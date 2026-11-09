import AppKit
import Combine
import Darwin
import Foundation

@MainActor
protocol MemoryApplicationHandling: AnyObject {
    var metadata: MemoryAppMetadata { get }
    var isTerminated: Bool { get }
    func request(_ action: MemoryAction) -> Bool
}

@MainActor
protocol MemoryApplicationControlling {
    func application(pid: Int32) -> (any MemoryApplicationHandling)?
}

@MainActor
private final class MemoryRunningApplication: MemoryApplicationHandling {
    let app: NSRunningApplication
    init(_ app: NSRunningApplication) { self.app = app }
    var metadata: MemoryAppMetadata { MemoryApplications.metadata(app) }
    var isTerminated: Bool { app.isTerminated }
    func request(_ action: MemoryAction) -> Bool {
        switch action {
        case .quit: app.terminate()
        case .forceQuit: app.forceTerminate()
        }
    }
}

@MainActor
struct MemoryApplicationController: MemoryApplicationControlling {
    func application(pid: Int32) -> (any MemoryApplicationHandling)? {
        NSRunningApplication(processIdentifier: pid).map { MemoryRunningApplication($0) }
    }
}

@MainActor
protocol MemoryActionClock {
    var now: Double { get }
    func sleep(seconds: Double) async throws
}

@MainActor
final class MemoryContinuousClock: MemoryActionClock {
    private let origin = ContinuousClock.now
    var now: Double {
        let parts = origin.duration(to: .now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
    func sleep(seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
}

@MainActor
final class MemoryResultRace<Value: Sendable> {
    var continuation: CheckedContinuation<Value?, Never>?
    var timeout: Task<Void, Never>?
    init(_ continuation: CheckedContinuation<Value?, Never>) { self.continuation = continuation }
    func finish(_ sample: Value?) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        continuation.resume(returning: sample)
    }
}

@MainActor
enum MemoryBoundedWork {
    static func run<Value: Sendable>(_ operation: @escaping @Sendable () async -> Value?) async -> Value? {
        await withCheckedContinuation { continuation in
            let race = MemoryResultRace(continuation)
            let work = Task { race.finish(await operation()) }
            race.timeout = Task {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                work.cancel()
                race.finish(nil)
            }
        }
    }
}

@MainActor
enum MemoryActionSampling {
    static func sample(_ provider: any MemoryStatsProviding) async -> MemorySnapshot? {
        await MemoryBoundedWork.run { await provider.sample() }
    }
}

@MainActor
final class MemoryActionService: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    let history: MemoryHistoryStore
    private let settings: MemorySettingsStore
    private let processes: any ProcessMemoryProviding
    private let stats: any MemoryStatsProviding
    private let applications: any MemoryApplicationControlling
    private let clock: any MemoryActionClock
    let policy: MemorySafetyPolicy
    private var pending: (MemoryConfirmation, Int)?
    private var generation = 0
    private var observationGeneration = 0
    private var exiting = false

    init(settings: MemorySettingsStore, history: MemoryHistoryStore, processes: any ProcessMemoryProviding,
         stats: any MemoryStatsProviding, policy: MemorySafetyPolicy,
         applications: any MemoryApplicationControlling = MemoryApplicationController(),
         clock: any MemoryActionClock = MemoryContinuousClock()) {
        self.settings = settings; self.history = history; self.processes = processes
        self.stats = stats; self.policy = policy; self.applications = applications; self.clock = clock
    }

    func canAct(_ group: MemoryProcessGroup, now: Date = Date()) -> Bool {
        !exiting && !isBusy && now.timeIntervalSince(group.sampledAt) >= 0 && now.timeIntervalSince(group.sampledAt) <= 10
            && group.footprint != nil && policy.classify(group.root, exclusions: settings.exclusions) != .protected
    }

    func confirmation(_ groups: [MemoryProcessGroup], action: MemoryAction) -> MemoryConfirmation? {
        guard !isBusy, !exiting else { return nil }
        var seen: Set<MemoryGroupIdentity> = []
        let targets = groups.filter { canAct($0) && seen.insert($0.id).inserted }
        guard !targets.isEmpty else { return nil }
        let confirmation = MemoryConfirmation(id: UUID(), action: action, targets: targets)
        pending = (confirmation, generation)
        return confirmation
    }

    func cancelConfirmation() { pending = nil }
    func foregroundEnded() { generation &+= 1; pending = nil }
    func observationInterrupted() { observationGeneration &+= 1; foregroundEnded() }
    func beginExit() { exiting = true; observationInterrupted() }

    private enum Validation {
        case allowed(any MemoryApplicationHandling)
        case denied(MemoryActionOutcome, MemoryActionReason)
    }
    private func validated(_ target: MemoryProcessGroup) async -> Validation {
        let age = Date().timeIntervalSince(target.sampledAt)
        guard age >= 0, age <= 10, target.footprint != nil else {
            return .denied(.policySkipped, .staleSample)
        }
        guard let app = applications.application(pid: target.root.identity.pid), !app.isTerminated else {
            return .denied(.alreadyExited, .targetGone)
        }
        let metadata = app.metadata
        guard metadata.bundleID == target.bundleID, metadata.executablePath == target.root.app?.executablePath,
              metadata.bundlePath == target.root.app?.bundlePath else { return .denied(.identityChanged, .identityChanged) }
        guard let fresh = await processes.record(pid: target.root.identity.pid, app: metadata) else {
            return .denied(.policySkipped, .policyDenied)
        }
        guard fresh.identity == target.root.identity else { return .denied(.identityChanged, .identityChanged) }
        guard fresh.uid == target.root.uid, policy.classify(fresh, exclusions: settings.exclusions) != .protected else {
            return .denied(.policySkipped, .policyDenied)
        }
        // Metadata and identity are rechecked again adjacent to the request, after measurement awaits.
        return .allowed(app)
    }

    /// Returns a new confirmation if the target set changed. No request is sent on a partial preflight.
    func execute(token: UUID) async -> MemoryConfirmation? {
        guard !isBusy, !exiting, let (confirmation, approvedGeneration) = pending,
              confirmation.id == token, approvedGeneration == generation else {
            message = memoryText("The confirmation expired. Review the applications again.")
            return nil
        }
        pending = nil // Single use, before the first await; actor reentrancy cannot replay it.
        isBusy = true; message = nil
        defer { isBusy = false }
        var valid: [MemoryProcessGroup] = []
        for target in confirmation.targets {
            guard approvedGeneration == generation, !exiting else { break }
            switch await validated(target) {
            case .allowed: valid.append(target)
            case .denied(let outcome, let reason):
                await record(target, action: confirmation.action, outcome: outcome, reason: reason)
            }
        }
        guard approvedGeneration == generation else { message = memoryText("Remaining applications were not attempted."); return nil }
        if valid.count != confirmation.targets.count {
            message = memoryText("Targets changed. Confirm the remaining applications again.")
            guard !valid.isEmpty else { return nil }
            let revised = MemoryConfirmation(id: UUID(), action: confirmation.action, targets: valid)
            pending = (revised, generation)
            return revised
        }
        for (index, target) in valid.enumerated() {
            guard approvedGeneration == generation, !exiting else {
                message = memoryText("Remaining applications were not attempted."); break
            }
            let before = await MemoryActionSampling.sample(stats)
            let baselineTime = clock.now
            let validation = await validated(target)
            guard approvedGeneration == generation, !exiting else {
                message = memoryText("Remaining applications were not attempted."); break
            }
            let app: any MemoryApplicationHandling
            switch validation {
            case .allowed(let current): app = current
            case .denied(let outcome, let reason):
                await record(target, action: confirmation.action, outcome: outcome, reason: reason)
                message = memoryText("Targets changed. Confirm the remaining applications again.")
                let remaining = Array(valid.dropFirst(index + 1))
                if !remaining.isEmpty, approvedGeneration == generation {
                    let revised = MemoryConfirmation(id: UUID(), action: confirmation.action, targets: remaining)
                    pending = (revised, generation)
                    return revised
                }
                return nil
            }
            let observedGeneration = observationGeneration
            // No await between this final state check and the NSRunningApplication request.
            guard policy.classify(target.root, exclusions: settings.exclusions) != .protected else {
                await record(target, action: confirmation.action, outcome: .policySkipped); break
            }
            if app.isTerminated { await record(target, action: confirmation.action, outcome: .alreadyExited); continue }
            let requestTime = clock.now
            let requestDate = Date()
            guard app.request(confirmation.action) else {
                await record(target, action: confirmation.action, outcome: .requestRefused); continue
            }
            let deadline = clock.now + 5
            var observedTermination = false
            while clock.now <= deadline {
                if app.isTerminated { observedTermination = true; break }
                if clock.now >= deadline { break }
                do { try await clock.sleep(seconds: 0.1) } catch { break }
            }
            let outcome: MemoryActionOutcome = observedTermination ? .terminated : .timedOut
            var after: MemorySnapshot?
            if outcome == .terminated, observedGeneration == observationGeneration, !exiting {
                try? await clock.sleep(seconds: 1)
                if observedGeneration == observationGeneration, !exiting { after = await MemoryActionSampling.sample(stats) }
            }
            let baselineAge = before.map { requestDate.timeIntervalSince($0.sampledAt) }
            let baseline = requestTime - baselineTime <= 1 && baselineAge.map({ $0 >= 0 && $0 <= 1 }) == true ? before : nil
            await record(target, action: confirmation.action, outcome: outcome,
                         before: baseline, after: observedGeneration == observationGeneration && !exiting ? after : nil,
                         reason: exiting ? .appExiting : (observedGeneration != observationGeneration ? .observationInterrupted : nil))
        }
        if message == nil { message = memoryText("Actions finished. Review the individual results in Memory history.") }
        return nil
    }

    private func record(_ target: MemoryProcessGroup, action: MemoryAction, outcome: MemoryActionOutcome,
                        before: MemorySnapshot? = nil, after: MemorySnapshot? = nil,
                        reason: MemoryActionReason? = nil) async {
        var delta: Int64?
        var measurement: MemoryMeasurement = .unmeasured
        if outcome == .terminated, let before, let after, before.total == after.total,
           after.sampledAt >= before.sampledAt, let a = before.used, let b = after.used {
            let difference = a.subtractingReportingOverflow(b)
            if !difference.overflow {
                let value = difference.partialValue
                if value > -16 * 1024 * 1024 && value < 16 * 1024 * 1024 { measurement = .belowThreshold }
                else { measurement = .observed; delta = value }
            }
        }
        await history.append(MemoryHistoryEntry(id: UUID(), date: Date(), bundleID: target.bundleID,
            name: target.title, action: action, outcome: outcome, measurement: measurement, delta: delta,
            beforeDate: before?.sampledAt, afterDate: after?.sampledAt, accountingVersion: 1,
            reason: reason ?? (measurement == .unmeasured ? (outcome == .terminated ? .samplingUnavailable : .terminationNotObserved) : nil)))
    }
}
