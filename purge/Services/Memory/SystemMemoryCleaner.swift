import Darwin
import Foundation

nonisolated protocol MemoryCleaningBackend: Sendable {
    func isEnabled() async -> Bool
    func enable() async throws
    func disable() async throws
    func clean() async throws
}

nonisolated enum MemoryCleaningError: Error, Equatable {
    case authorization, unavailable, timedOut, failed, rateLimited

    var message: String {
        switch self {
        case .authorization: memoryText("Administrator approval was cancelled or unavailable.")
        case .unavailable: memoryText("Enable memory cleaning first. Administrator approval is required once.")
        case .timedOut: memoryText("Memory cleaning timed out. Try again later.")
        case .failed: memoryText("macOS could not release its file cache. No applications were closed.")
        case .rateLimited: memoryText("Wait a minute before cleaning memory again.")
        }
    }
}

/// A root-owned launchd job watches a single user-writable request file. The
/// approved script accepts only a request UUID and executes Apple's fixed purge
/// command. No sudoers changes, stored passwords, arbitrary commands or app code
/// run as root. Installation/removal alone use the native administrator dialog.
nonisolated struct MemoryCleaningInstallation: Sendable {
    let uid: uid_t
    let bundleID: String
    static let base = "/Library/Application Support/PurgeMemoryCleaning"
    var label: String { "\(bundleID).memory-cleaning.\(uid)" }
    var directory: String { "\(Self.base)/\(bundleID)/\(uid)" }
    var scriptPath: String { directory + "/clean.sh" }
    var requestPath: String { directory + "/request" }
    var resultPath: String { directory + "/result" }
    var plistPath: String { "/Library/LaunchDaemons/\(label).plist" }

    init(bundleID: String, uid: uid_t) {
        precondition(uid > 0 && !bundleID.isEmpty && bundleID.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 46 || $0 == 45
        } && !bundleID.contains("..") && !bundleID.hasPrefix("."))
        self.bundleID = bundleID; self.uid = uid
    }

    static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }

    var workerScript: String {
        """
        #!/bin/sh
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        export PATH
        request_id=$(/usr/bin/head -c 64 \(Self.quote(requestPath)))
        [ "${#request_id}" -eq 36 ] || exit 0
        case "$request_id" in *[!0123456789abcdefABCDEF-]*) exit 0 ;; esac
        [ "$request_id" != '00000000-0000-0000-0000-000000000000' ] || exit 0
        previous=$(/usr/bin/head -n 1 \(Self.quote(resultPath)) 2>/dev/null)
        [ "$request_id" != "$previous" ] || exit 0
        now=$(/bin/date +%s)
        last=$(/bin/cat \(Self.quote(directory + "/last-run")) 2>/dev/null)
        case "$last" in ''|*[!0123456789]*) last=0 ;; esac
        if [ "$((now - last))" -lt 60 ]; then
          status=75
        else
          printf '%s' "$now" > \(Self.quote(directory + "/last-run"))
          /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/perl -e 'alarm 45; exec {"/usr/sbin/purge"} "/usr/sbin/purge"; exit 127;'
          status=$?
        fi
        printf '%s\\n%s\\n' "$request_id" "$status" > \(Self.quote(resultPath + ".next"))
        /bin/chmod 644 \(Self.quote(resultPath + ".next"))
        /bin/mv -f \(Self.quote(resultPath + ".next")) \(Self.quote(resultPath))
        """ + "\n"
    }

    var plistData: Data {
        // Only fixed Apple binaries; launchd never executes the user-writable app.
        try! PropertyListSerialization.data(fromPropertyList: [
            "Label": label, "ProgramArguments": ["/bin/sh", scriptPath],
            "WatchPaths": [requestPath], "RunAtLoad": false,
            "ThrottleInterval": 1, "ProcessType": "Background", "AssociatedBundleIdentifiers": [bundleID]
        ], format: .xml, options: 0)
    }

    private func writeRootFile(_ data: Data, to path: String, mode: String) -> String {
        let temp = path + ".install"
        return """
        /bin/rm -f \(Self.quote(temp))
        printf '%s' \(Self.quote(data.base64EncodedString())) | /usr/bin/base64 -D > \(Self.quote(temp))
        /usr/sbin/chown root:wheel \(Self.quote(temp))
        /bin/chmod -N \(Self.quote(temp))
        /bin/chmod \(mode) \(Self.quote(temp))
        /bin/mv -f \(Self.quote(temp)) \(Self.quote(path))
        """
    }

    var installScript: String {
        let directories = [Self.base, Self.base + "/" + bundleID, directory]
        return "set -eu\n" + directories.map { path in
            """
            [ ! -L \(Self.quote(path)) ] || exit 1
            if [ -e \(Self.quote(path)) ]; then
              [ -d \(Self.quote(path)) ] && [ "$(/usr/bin/stat -f %u \(Self.quote(path)))" = 0 ] || exit 1
            fi
            /usr/bin/install -d -o root -g wheel -m 755 \(Self.quote(path))
            /bin/chmod -N \(Self.quote(path))
            """
        }.joined(separator: "\n") + "\n" + """
        /bin/launchctl bootout \(Self.quote("system/" + label)) >/dev/null 2>&1 || true
        \(writeRootFile(Data(workerScript.utf8), to: scriptPath, mode: "755"))
        \(writeRootFile(plistData, to: plistPath, mode: "644"))
        \(writeRootFile(Data("00000000-0000-0000-0000-000000000000".utf8), to: requestPath, mode: "600"))
        /usr/sbin/chown \(uid):wheel \(Self.quote(requestPath))
        /bin/launchctl bootstrap system \(Self.quote(plistPath))
        """
    }

    var uninstallScript: String {
        """
        set -eu
        /bin/launchctl bootout \(Self.quote("system/" + label)) >/dev/null 2>&1 || true
        /bin/rm -f \([plistPath, scriptPath, requestPath, resultPath, resultPath + ".next", directory + "/last-run"].map(Self.quote).joined(separator: " "))
        /bin/rmdir \(Self.quote(directory)) 2>/dev/null || true
        """
    }

    static func trusted(_ path: String, directory: Bool = false) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_uid == 0, info.st_mode & 0o022 == 0 else { return false }
        return directory ? info.st_mode & S_IFMT == S_IFDIR : info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1
    }

    var filesAreTrusted: Bool {
        [Self.base, Self.base + "/" + bundleID, directory].allSatisfy { Self.trusted($0, directory: true) }
            && Self.trusted(plistPath) && Self.trusted(scriptPath)
            && (try? Data(contentsOf: URL(fileURLWithPath: scriptPath))) == Data(workerScript.utf8)
            && (try? PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: plistPath)), format: nil) as? NSDictionary)
                == (try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? NSDictionary)
    }
}

actor SystemMemoryCleaner: MemoryCleaningBackend {
    let installation: MemoryCleaningInstallation
    init(bundleID: String = Bundle.main.bundleIdentifier ?? "io.getpurge.app", uid: uid_t = getuid()) {
        installation = MemoryCleaningInstallation(bundleID: bundleID, uid: uid)
    }

    func isEnabled() async -> Bool {
        guard installation.filesAreTrusted else { return false }
        let output = await ProcessRunner.runAsync(executablePath: "/bin/launchctl",
            arguments: ["print", "system/" + installation.label], timeout: 3)
        return output?.succeeded == true
    }

    private func authorize(_ script: String) async throws {
        guard !TestHost.isActive() else { throw MemoryCleaningError.unavailable }
        let output = await ProcessRunner.runAsync(executablePath: "/usr/bin/osascript", arguments: [
            "-e", "on run argv\ndo shell script (item 1 of argv) with administrator privileges\nend run", script
        ], timeout: 120)
        guard output?.succeeded == true else { throw MemoryCleaningError.authorization }
    }

    func enable() async throws {
        guard !TestHost.isActive() else { throw MemoryCleaningError.unavailable }
        guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/purge"),
              FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else { throw MemoryCleaningError.unavailable }
        try await authorize(installation.installScript)
        guard await isEnabled() else { throw MemoryCleaningError.unavailable }
    }

    func disable() async throws { try await authorize(installation.uninstallScript) }

    func clean() async throws {
        guard !TestHost.isActive() else { throw MemoryCleaningError.unavailable }
        guard await isEnabled() else { throw MemoryCleaningError.unavailable }
        let request = UUID()
        let descriptor = open(installation.requestPath, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw MemoryCleaningError.unavailable }
        var info = stat()
        let valid = fstat(descriptor, &info) == 0 && info.st_uid == installation.uid
            && info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1 && info.st_size == 36
        let data = Array(request.uuidString.utf8)
        let written = valid ? data.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, $0.count, 0) } : -1
        close(descriptor)
        guard written == 36 else { throw MemoryCleaningError.unavailable }
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if MemoryCleaningInstallation.trusted(installation.resultPath),
               let text = try? String(contentsOfFile: installation.resultPath, encoding: .utf8) {
                let parts = text.split(separator: "\n")
                if parts.count == 2, UUID(uuidString: String(parts[0])) == request, let status = Int(parts[1]) {
                    guard status == 0 else {
                        if status == 75 { throw MemoryCleaningError.rateLimited }
                        if status == 142 { throw MemoryCleaningError.timedOut }
                        throw MemoryCleaningError.failed
                    }
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw MemoryCleaningError.timedOut
    }
}
