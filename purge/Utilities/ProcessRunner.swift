import Foundation

/// Runs helper binaries (`xcrun`, `du`, `git`) without the three ways `Process` hangs an app.
///
/// **1. The pipe deadlock.** A child blocks once it fills the 64 KB kernel pipe buffer, so a
/// parent that calls `waitUntilExit()` before draining can never make progress: the child cannot
/// finish writing, the parent cannot stop waiting. `simctl list devices --json` clears 64 KB on
/// any machine with a normal spread of runtimes, which froze Purge at launch for anyone with
/// Xcode installed (1.2.9).
///
/// **2. The thread-pool deadlock.** Draining looks like a job for two helper queues, and that is
/// the trap. Callers like `CacheScanner.runSizeJobs` invoke this from Swift concurrency tasks, so
/// the blocking wait sits on a *cooperative pool* thread — and that pool is only as wide as the
/// core count. Ten concurrent `du` chunks block all ten threads, the helper reads never get
/// scheduled, and the app wedges with the scan stuck at zero. So both pipes are drained by
/// `poll(2)` **on the calling thread**: no helper threads, no cross-queue dependency, nothing to
/// starve.
///
/// **3. The unkillable child.** The wait is bounded and escalates SIGTERM → SIGKILL. SIGTERM only
/// *queues* for a SIGSTOP'd process, so a child suspended by a throttler (App Tamer, in the
/// original report) needs SIGKILL to be reaped at all.
///
/// This is `nonisolated` and blocking: call it off the main actor, and prefer ``runAsync`` from
/// async code.
nonisolated enum ProcessRunner {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data
        /// `true` when the child overran its budget and was killed; `status` is then meaningless.
        let timedOut: Bool
        var cancelled: Bool = false

        var succeeded: Bool { !timedOut && !cancelled && status == 0 }

        var stdoutText: String { String(data: stdout, encoding: .utf8) ?? "" }
        var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }
    }

    /// Grace period allowed after each escalation step once a child has overrun its timeout.
    private static let terminationGrace: TimeInterval = 2

    /// Upper bound on a single `poll` wait, so the deadline is still noticed on a silent child.
    private static let pollSliceMilliseconds: Int32 = 250

    private static let readBufferSize = 64 * 1024

    /// Returns `nil` when the binary could not be launched or cancellation preceded launch.
    ///
    /// Blocks the calling thread for up to `timeout`. The debug precondition is the guardrail
    /// against reintroducing the launch freeze: this must never run on the main queue.
    ///
    /// `environment`, when given, replaces the inherited one whole. Read-only
    /// callers may opt into cancellation with a thread-safe `isCancelled` probe.
    static func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> Output? {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(.main))
        #endif
        // Cancellation is opt-in: interrupting a package-manager mutation can leave
        // it half applied. Read-only callers such as folder sizing supply a probe.
        guard !isCancelled() else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        // Without this a child that reads stdin inherits ours and waits on input that never comes.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        return withExtendedLifetime((outPipe, errPipe)) {
            let stdoutFD = outPipe.fileHandleForReading.fileDescriptor
            let stderrFD = errPipe.fileHandleForReading.fileDescriptor
            // Required: `drainReadable` keeps reading until EAGAIN, which a blocking descriptor
            // never reports — it would sit in `read` instead, defeating the point of polling.
            // Only the parent's read ends are affected; the child's write ends are separate.
            makeNonBlocking(stdoutFD)
            makeNonBlocking(stderrFD)

            let drain = drainPipes(
                process: process,
                stdoutFD: stdoutFD,
                stderrFD: stderrFD,
                timeout: timeout,
                isCancelled: isCancelled
            )

            guard drain.reachedEOF else {
                // Both pipes still open past SIGKILL — a surviving grandchild is holding them.
                // Abandon rather than hand the caller an unbounded wait.
                return Output(status: -1, stdout: drain.stdout, stderr: drain.stderr,
                              timedOut: drain.timedOut, cancelled: drain.cancelled)
            }

            process.waitUntilExit()
            return Output(
                status: process.terminationStatus,
                stdout: drain.stdout,
                stderr: drain.stderr,
                timedOut: drain.timedOut,
                cancelled: drain.cancelled
            )
        }
    }

    private static func makeNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else { return }
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    private struct DrainResult {
        var stdout = Data()
        var stderr = Data()
        var timedOut = false
        var cancelled = false
        /// `false` when we gave up with a pipe still open, which makes `waitUntilExit` unsafe.
        var reachedEOF = false
    }

    /// Reads both descriptors until EOF on the calling thread, escalating signals past `timeout`.
    private static func drainPipes(
        process: Process,
        stdoutFD: Int32,
        stderrFD: Int32,
        timeout: TimeInterval,
        isCancelled: @Sendable () -> Bool
    ) -> DrainResult {
        var result = DrainResult()
        var openOut = true
        var openErr = true
        var deadline = Date().addingTimeInterval(timeout)
        var sentTerm = false
        var sentKill = false
        var buffer = [UInt8](repeating: 0, count: readBufferSize)

        // A child can close both pipes and keep running. Keep the deadline and
        // cancellation checks alive until it exits instead of blocking in waitUntilExit.
        while openOut || openErr || process.isRunning {
            let cancelling = !sentTerm && isCancelled()
            if cancelling || Date() >= deadline {
                if cancelling { result.cancelled = true }
                else if !sentTerm { result.timedOut = true }
                if !sentTerm {
                    sentTerm = true
                    process.terminate()
                } else if !sentKill {
                    sentKill = true
                    // SIGTERM is only queued for a stopped process; SIGKILL always lands.
                    kill(process.processIdentifier, SIGKILL)
                } else {
                    return result
                }
                deadline = Date().addingTimeInterval(terminationGrace)
                continue
            }

            var pollFDs: [pollfd] = []
            if openOut { pollFDs.append(pollfd(fd: stdoutFD, events: Int16(POLLIN), revents: 0)) }
            if openErr { pollFDs.append(pollfd(fd: stderrFD, events: Int16(POLLIN), revents: 0)) }

            let ready = poll(&pollFDs, nfds_t(pollFDs.count), pollSliceMilliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                return result
            }
            if ready == 0 { continue }

            for entry in pollFDs where entry.revents != 0 {
                // POLLHUP can arrive with data still buffered, so always read to EOF or EAGAIN
                // rather than trusting the flag.
                let hitEOF = drainReadable(fd: entry.fd, into: &buffer) { bytes in
                    guard let base = bytes.baseAddress else { return }
                    if entry.fd == stdoutFD {
                        result.stdout.append(base, count: bytes.count)
                    } else {
                        result.stderr.append(base, count: bytes.count)
                    }
                }
                if hitEOF {
                    if entry.fd == stdoutFD { openOut = false } else { openErr = false }
                }
            }
        }

        result.reachedEOF = true
        return result
    }

    /// Reads everything currently available on `fd`. Returns `true` once the descriptor is done.
    private static func drainReadable(
        fd: Int32,
        into buffer: inout [UInt8],
        append: (UnsafeMutableBufferPointer<UInt8>) -> Void
    ) -> Bool {
        while true {
            let count = buffer.withUnsafeMutableBytes { raw in
                read(fd, raw.baseAddress, raw.count)
            }
            if count > 0 {
                buffer.withUnsafeMutableBufferPointer { pointer in
                    append(UnsafeMutableBufferPointer(rebasing: pointer[0..<count]))
                }
                continue
            }
            if count == 0 { return true }
            switch errno {
            case EINTR: continue
            case EAGAIN: return false
            default: return true
            }
        }
    }

    /// Async wrapper that keeps the blocking drain off whatever actor or cooperative thread the
    /// caller is running on.
    static func runAsync(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil
    ) async -> Output? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(
                    returning: run(
                        executablePath: executablePath,
                        arguments: arguments,
                        timeout: timeout,
                        environment: environment
                    )
                )
            }
        }
    }
}
