import Foundation
import Testing
@testable import Purge

nonisolated private struct EmptyMemoryStats: MemoryStatsProviding {
    func sample() async -> MemorySnapshot? { nil }
}

private actor GatedMemoryStats: MemoryStatsProviding {
    private var continuation: CheckedContinuation<MemorySnapshot?, Never>?
    private var released = false
    var isWaiting: Bool { continuation != nil }
    func sample() async -> MemorySnapshot? {
        if released { return nil }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

private actor FakeMemoryProcesses: ProcessMemoryProviding {
    var records: [Int32: MemoryProcessRecord]
    init(_ records: [MemoryProcessRecord]) { self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id.pid, $0) }) }
    func record(pid: Int32, app: MemoryAppMetadata?) async -> MemoryProcessRecord? { records[pid] }
    func sample(apps: [MemoryAppMetadata]) async -> MemoryProcessSample? { nil }
    func replace(_ value: MemoryProcessRecord) { records[value.id.pid] = value }
}

@MainActor
private final class FakeMemoryApp: MemoryApplicationHandling {
    let metadata: MemoryAppMetadata
    var isTerminated = false
    var calls: [MemoryAction] = []
    var onRequest: (() -> Void)?
    var exitsOnRequest = false
    init(_ metadata: MemoryAppMetadata) { self.metadata = metadata }
    func request(_ action: MemoryAction) -> Bool {
        calls.append(action)
        isTerminated = exitsOnRequest
        onRequest?()
        return true
    }
}

@MainActor
private struct FakeMemoryApps: MemoryApplicationControlling {
    let apps: [Int32: FakeMemoryApp]
    func application(pid: Int32) -> (any MemoryApplicationHandling)? { apps[pid] }
}

@MainActor
private final class FakeMemoryClock: MemoryActionClock {
    var now: Double = 0
    func sleep(seconds: Double) async throws { now += seconds; await Task.yield() }
}

@MainActor
private final class MemoryActionRig {
    let defaults = ThrowawayDefaults()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let settings: MemorySettingsStore
    let history: MemoryHistoryStore
    let processes: FakeMemoryProcesses
    let apps: [Int32: FakeMemoryApp]
    let service: MemoryActionService
    init(records: [MemoryProcessRecord], stats: any MemoryStatsProviding = EmptyMemoryStats()) {
        settings = MemorySettingsStore(defaults: defaults.defaults)
        history = MemoryHistoryStore(url: folder.appendingPathComponent("history.json"))
        processes = FakeMemoryProcesses(records)
        apps = Dictionary(uniqueKeysWithValues: records.compactMap { record in record.app.map { (record.id.pid, FakeMemoryApp($0)) } })
        service = MemoryActionService(settings: settings, history: history, processes: processes,
            stats: stats, policy: MemorySafetyPolicy(currentUID: 501, ownPID: 999,
                ownBundleID: "test.purge", ownBundlePath: "/Applications/Purge.app"),
            applications: FakeMemoryApps(apps: apps), clock: FakeMemoryClock())
    }
    deinit { try? FileManager.default.removeItem(at: folder) }
}

@MainActor
@Suite("Memory actions never target live test-host apps")
struct MemoryActionTests {
    private func record(pid: Int32 = 42, start: UInt64 = 10) -> MemoryProcessRecord {
        let app = MemoryAppMetadata(pid: pid, bundleID: "test.editor", name: "Editor",
            bundlePath: "/Applications/Test.app", executablePath: "/Applications/Test.app/Contents/MacOS/Test", isRegular: true)
        return MemoryProcessRecord(identity: MemoryProcessIdentity(pid: pid, seconds: start, microseconds: 0),
            uid: 501, parentPID: 1, name: "Editor", executablePath: app.executablePath, footprint: 4096, app: app)
    }
    private func group(_ value: MemoryProcessRecord) -> MemoryProcessGroup {
        MemoryProcessGroup(root: value, members: [value], sampledAt: Date())
    }

    @Test("Changed PID identity cannot execute and a token cannot be replayed")
    func pidReuseAndReplay() async throws {
        let original = record()
        let rig = MemoryActionRig(records: [original])
        let confirmation = try #require(rig.service.confirmation([group(original)], action: .quit))
        await rig.processes.replace(record(start: 11))
        _ = await rig.service.execute(token: confirmation.id)
        _ = await rig.service.execute(token: confirmation.id)
        #expect(rig.apps[42]?.calls.isEmpty == true)
        #expect(rig.history.entries.count == 1)
        #expect(rig.history.entries.first?.outcome == .identityChanged)
    }

    @Test("Quit timeout never calls Force Quit and records an unmeasured outcome")
    func timeoutDoesNotEscalate() async throws {
        let target = record()
        let rig = MemoryActionRig(records: [target])
        let confirmation = try #require(rig.service.confirmation([group(target)], action: .quit))
        _ = await rig.service.execute(token: confirmation.id)
        #expect(rig.apps[42]?.calls == [.quit])
        #expect(rig.history.entries.first?.outcome == .timedOut)
        #expect(rig.history.entries.first?.measurement == .unmeasured)
    }

    @Test("Deactivation after an issued request retains its result but stops the remaining batch")
    func savePromptLifecycle() async throws {
        let one = record(), two = record(pid: 43)
        let rig = MemoryActionRig(records: [one, two])
        rig.apps[42]?.exitsOnRequest = true
        rig.apps[42]?.onRequest = { [weak service = rig.service] in service?.foregroundEnded() }
        let confirmation = try #require(rig.service.confirmation([group(one), group(two)], action: .quit))
        _ = await rig.service.execute(token: confirmation.id)
        #expect(rig.apps[42]?.calls == [.quit])
        #expect(rig.apps[43]?.calls.isEmpty == true)
        #expect(rig.history.entries.count == 1)
        #expect(rig.history.entries.first?.outcome == .terminated)
    }

    @Test("Exclusion changes invalidate an already-open confirmation; duplicate targets are removed")
    func exclusionsAndDuplicates() async throws {
        let target = record()
        let rig = MemoryActionRig(records: [target])
        let confirmation = try #require(rig.service.confirmation([group(target), group(target)], action: .forceQuit))
        #expect(confirmation.targets.count == 1)
        rig.settings.exclude("test.editor")
        _ = await rig.service.execute(token: confirmation.id)
        #expect(rig.apps[42]?.calls.isEmpty == true)
    }

    @Test("Concurrent/replayed submissions are rejected even across a suspended baseline read")
    func concurrentSubmissions() async throws {
        let target = record()
        let stats = GatedMemoryStats()
        let rig = MemoryActionRig(records: [target], stats: stats)
        let confirmation = try #require(rig.service.confirmation([group(target)], action: .quit))
        let running = Task { await rig.service.execute(token: confirmation.id) }
        for _ in 0..<1000 {
            if await stats.isWaiting { break }
            await Task.yield()
        }
        #expect(rig.service.isBusy)
        #expect(rig.service.confirmation([group(target)], action: .forceQuit) == nil)
        _ = await rig.service.execute(token: confirmation.id)
        await stats.release()
        _ = await running.value
        #expect(rig.apps[42]?.calls == [.quit])
        #expect(!rig.service.isBusy)
    }

    @Test("Observation interruption retains termination outcome but never claims a measured delta")
    func interruptedMeasurement() async throws {
        let target = record()
        let rig = MemoryActionRig(records: [target])
        rig.apps[42]?.exitsOnRequest = true
        rig.apps[42]?.onRequest = { [weak service = rig.service] in service?.observationInterrupted() }
        let confirmation = try #require(rig.service.confirmation([group(target)], action: .forceQuit))
        _ = await rig.service.execute(token: confirmation.id)
        #expect(rig.apps[42]?.calls == [.forceQuit])
        #expect(rig.history.entries.first?.outcome == .terminated)
        #expect(rig.history.entries.first?.measurement == .unmeasured)
        #expect(rig.history.entries.first?.reason == .observationInterrupted)
    }
}
