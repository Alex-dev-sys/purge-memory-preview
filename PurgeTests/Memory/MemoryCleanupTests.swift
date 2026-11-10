import Foundation
import Testing
@testable import Purge

private func cleanupSnapshot(_ date: Date, used: Int64 = 800, free: Int64 = 100) -> MemorySnapshot {
    MemorySnapshot(sampledAt: date, total: 1000, app: used, wired: 0, compressed: 0,
                   cached: 1000 - used - free, free: free, swap: 0)
}

@Suite("Memory cleanup scheduling")
struct MemoryCleanupPolicyTests {
    let start = Date(timeIntervalSince1970: 100_000)

    @Test func timerDoesNotRunImmediatelyOrDuringCooldown() {
        var policy = MemoryCleanupPolicy()
        policy.reset(now: start, intervalMinutes: 5)
        #expect(policy.due(mode: .timer, threshold: 85, snapshot: nil, lastAttempt: nil,
                           now: start, blocked: false) == nil)
        let due = start.addingTimeInterval(300)
        #expect(policy.due(mode: .timer, threshold: 85, snapshot: nil, lastAttempt: nil,
                           now: due, blocked: true) == nil)
        #expect(policy.due(mode: .timer, threshold: 85, snapshot: nil, lastAttempt: nil,
                           now: due, blocked: false) == .timer)
        policy.attempted(now: due, intervalMinutes: 5)
        #expect(policy.due(mode: .timer, threshold: 85, snapshot: nil, lastAttempt: due,
                           now: due.addingTimeInterval(299), blocked: false) == nil)
    }

    @Test func thresholdNeedsSustainedFreshSamplesAndRearmsOnlyAfterAHysteresisDrop() {
        var policy = MemoryCleanupPolicy()
        policy.reset(now: start, intervalMinutes: 30)
        func due(_ seconds: Double, _ used: Int64) -> MemoryCleanupTrigger? {
            let now = start.addingTimeInterval(seconds)
            return policy.due(mode: .usage, threshold: 85, snapshot: cleanupSnapshot(now, used: used, free: 0),
                              lastAttempt: nil, now: now, blocked: false)
        }
        #expect(due(0, 900) == nil)
        #expect(due(29, 900) == nil)
        #expect(due(30, 900) == .usage)
        policy.attempted(now: start.addingTimeInterval(30), intervalMinutes: 30)
        #expect(due(600, 900) == nil)
        #expect(due(610, 810) == nil)
        #expect(due(620, 800) == nil)
        #expect(due(630, 900) == nil)
        #expect(due(660, 900) == .usage)
    }

    @Test func staleMissingAndInterruptedReadingsCannotCompleteTheThresholdWindow() {
        var policy = MemoryCleanupPolicy()
        _ = policy.due(mode: .usage, threshold: 85, snapshot: cleanupSnapshot(start, used: 900, free: 0),
                       lastAttempt: nil, now: start, blocked: false)
        #expect(policy.due(mode: .usage, threshold: 85, snapshot: cleanupSnapshot(start, used: 900, free: 0),
                           lastAttempt: nil, now: start.addingTimeInterval(31), blocked: false) == nil)
        #expect(policy.aboveSince == nil)
        #expect(policy.due(mode: .usage, threshold: 85, snapshot: nil,
                           lastAttempt: nil, now: start.addingTimeInterval(60), blocked: false) == nil)
    }
}

private actor FakeMemoryCleaner: MemoryCleaningBackend {
    var enabled = true
    var calls = 0
    var failure: MemoryCleaningError?
    func isEnabled() -> Bool { enabled }
    func enable() { enabled = true }
    func disable() { enabled = false }
    func setFailure(_ error: MemoryCleaningError) { failure = error }
    func count() -> Int { calls }
    func clean() async throws {
        calls += 1
        try await Task.sleep(for: .milliseconds(10))
        if let failure { throw failure }
    }
}

private actor CleanupTestStats: MemoryStatsProviding {
    var values: [MemorySnapshot?]
    init(_ values: [MemorySnapshot?]) { self.values = values }
    func sample() -> MemorySnapshot? { values.isEmpty ? nil : values.removeFirst() }
}

@MainActor
private final class CleanupTestClock {
    var date = Date(timeIntervalSince1970: 100_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
@Suite("Memory cleaning service")
struct MemoryCleanupServiceTests {
    let suite = ThrowawayDefaults()

    @Test func measuresFreeRatherThanUsedAndSerializesConcurrentRequests() async throws {
        let now = Date()
        let backend = FakeMemoryCleaner()
        let stats = CleanupTestStats([cleanupSnapshot(now, free: 100), cleanupSnapshot(now, free: 200)])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = MemoryHistoryStore(url: folder.appendingPathComponent("history.json"))
        let settings = MemorySettingsStore(defaults: suite.defaults)
        let service = MemoryCleanupService(settings: settings, history: history, stats: stats,
            backend: backend, now: { now }, settle: {})
        await service.refreshPermission()
        let first = Task { await service.clean() }
        while !service.isBusy { await Task.yield() }
        await service.clean()
        await first.value
        #expect(await backend.count() == 1)
        #expect(service.lastBeforeFree == Int64(100))
        #expect(service.lastAfterFree == Int64(200))
        #expect(history.entries.first?.delta == Int64(100))
        #expect(history.entries.first?.action == .clean)
        #expect(history.entries.first?.cleanupTrigger == .manual)
        await service.clean()
        #expect(await backend.count() == 1) // Manual clicks also respect the minimum gap.
    }

    @Test func missingMeasurementsNeverInventAReclaimedAmountAndFailuresAreRecorded() async {
        let backend = FakeMemoryCleaner()
        let now = Date()
        let history = MemoryHistoryStore()
        let service = MemoryCleanupService(settings: MemorySettingsStore(defaults: suite.defaults),
            history: history, stats: CleanupTestStats([nil, nil]), backend: backend, now: { now }, settle: {})
        await service.refreshPermission()
        await service.clean()
        #expect(service.lastBeforeFree == nil)
        #expect(service.lastAfterFree == nil)
        #expect(service.message == memoryText("Cleaning finished. The change in free RAM could not be measured."))
    }

    @Test func zeroGainIsReportedAndUnavailablePermissionStopsAutomaticCleaning() async {
        let now = Date()
        let backend = FakeMemoryCleaner()
        let settings = MemorySettingsStore(defaults: suite.defaults)
        let service = MemoryCleanupService(settings: settings, history: MemoryHistoryStore(),
            stats: CleanupTestStats([cleanupSnapshot(now), cleanupSnapshot(now)]),
            backend: backend, now: { now }, settle: {})
        await service.refreshPermission()
        await service.clean()
        #expect(service.lastAfterFree == service.lastBeforeFree)
        #expect(service.message == memoryText("Cleaning finished. No measurable increase in free RAM was observed."))
        settings.automaticCleaning = true
        await backend.disable()
        await service.refreshPermission()
        #expect(!settings.automaticCleaning)
    }

    @Test func failedSystemRequestNeverShowsASuccessfulDelta() async {
        let now = Date()
        let backend = FakeMemoryCleaner()
        await backend.setFailure(.failed)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = MemoryHistoryStore(url: folder.appendingPathComponent("history.json"))
        let service = MemoryCleanupService(settings: MemorySettingsStore(defaults: suite.defaults),
            history: history, stats: CleanupTestStats([cleanupSnapshot(now)]),
            backend: backend, now: { now }, settle: {})
        await service.refreshPermission()
        await service.clean()
        #expect(history.entries.first?.outcome == .cleanFailed)
        #expect(history.entries.first?.delta == nil)
        #expect(!service.isBusy)
    }

    @Test func defaultSettingsAreOffAndInvalidPreferencesAreClamped() {
        suite.defaults.set(0, forKey: "memory.cleanMinutes")
        suite.defaults.set(101, forKey: "memory.cleanPercent")
        let settings = MemorySettingsStore(defaults: suite.defaults)
        #expect(!settings.automaticCleaning)
        #expect(settings.cleaningInterval == 30)
        #expect(settings.cleaningThreshold == 85)
    }

    @Test func sleepAndDiskActionsBlockCleanup() async {
        let backend = FakeMemoryCleaner()
        let service = MemoryCleanupService(settings: MemorySettingsStore(defaults: suite.defaults),
            history: MemoryHistoryStore(), stats: CleanupTestStats([]), backend: backend, settle: {})
        await service.refreshPermission()
        service.setSleeping(true)
        await service.clean()
        service.setSleeping(false)
        service.isBlocked = { true }
        await service.clean()
        #expect(await backend.count() == 0)
    }

    @Test func automaticTimerRunsOnlyWhenDueAndRestartsItsIntervalAfterSleep() async {
        let clock = CleanupTestClock()
        let backend = FakeMemoryCleaner()
        let settings = MemorySettingsStore(defaults: suite.defaults)
        settings.automaticCleaning = true; settings.cleaningInterval = 5
        let service = MemoryCleanupService(settings: settings, history: MemoryHistoryStore(),
            stats: CleanupTestStats([]), backend: backend, now: { clock.date }, settle: {})
        await service.refreshPermission()
        await service.tick()
        clock.advance(299); await service.tick()
        #expect(await backend.count() == 0)
        clock.advance(1); await service.tick()
        #expect(await backend.count() == 1)
        clock.advance(300); await service.tick()
        #expect(await backend.count() == 2)
        service.setSleeping(true)
        clock.advance(900); await service.tick()
        service.setSleeping(false)
        await service.tick()
        #expect(await backend.count() == 2)
        settings.automaticCleaning = false
        clock.advance(300); await service.tick()
        #expect(await backend.count() == 2)
    }

    @Test func automaticUsageDoesNotRepeatUntilUsageFallsEvenAcrossSleep() async {
        let clock = CleanupTestClock()
        let backend = FakeMemoryCleaner()
        let settings = MemorySettingsStore(defaults: suite.defaults)
        settings.automaticCleaning = true; settings.cleaningMode = .usage
        let service = MemoryCleanupService(settings: settings, history: MemoryHistoryStore(),
            stats: CleanupTestStats([]), backend: backend, now: { clock.date }, settle: {})
        var used: Int64 = 900
        service.currentSnapshot = { cleanupSnapshot(clock.date, used: used, free: 0) }
        await service.refreshPermission()
        await service.tick()
        clock.advance(29); await service.tick()
        #expect(await backend.count() == 0)
        clock.advance(1); await service.tick()
        #expect(await backend.count() == 1)
        clock.advance(600); await service.tick()
        service.setSleeping(true); service.setSleeping(false)
        clock.advance(30); await service.tick()
        #expect(await backend.count() == 1)
        used = 800; await service.tick()
        used = 900; clock.advance(1); await service.tick()
        clock.advance(30); await service.tick()
        #expect(await backend.count() == 2)
    }
}

@Suite("Memory cleaning permission boundary")
struct MemoryCleaningInstallationTests {
    @Test func daemonRunsOnlyTheRootOwnedScriptAndAcceptsNoAppProvidedCommands() throws {
        let plan = MemoryCleaningInstallation(bundleID: "io.getpurge.memorypreview.app", uid: 501)
        let plist = try #require(try PropertyListSerialization.propertyList(from: plan.plistData, format: nil) as? [String: Any])
        #expect(plist["ProgramArguments"] as? [String] == ["/bin/sh", plan.scriptPath])
        #expect(plist["WatchPaths"] as? [String] == [plan.requestPath])
        #expect(plan.workerScript.contains("/usr/sbin/purge"))
        #expect(!plan.workerScript.contains("eval"))
        #expect(!plan.installScript.contains("sudoers"))
        #expect(!plan.uninstallScript.contains("rm -rf"))
    }

    @Test func workerRejectsReplayAndEnforcesItsOwnRateLimit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("purge-memory-worker-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let plan = MemoryCleaningInstallation(bundleID: "io.getpurge.memorypreview.app", uid: 501)
        let fakePurge = folder.appendingPathComponent("fake-purge")
        try Data("#!/bin/sh\nprintf run >> '\(folder.path)/runs'\n".utf8).write(to: fakePurge)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakePurge.path)
        let script = folder.appendingPathComponent("clean.sh")
        let contents = plan.workerScript.replacingOccurrences(of: plan.directory, with: folder.path)
            .replacingOccurrences(of: "/usr/sbin/purge", with: fakePurge.path)
        try Data(contents.utf8).write(to: script)
        let syntax = await ProcessRunner.runAsync(executablePath: "/bin/sh", arguments: ["-n", script.path], timeout: 3)
        #expect(syntax?.succeeded == true)
        for text in [plan.installScript, plan.uninstallScript] {
            let check = folder.appendingPathComponent("syntax.sh")
            try Data(text.utf8).write(to: check)
            let result = await ProcessRunner.runAsync(executablePath: "/bin/sh", arguments: ["-n", check.path], timeout: 3)
            #expect(result?.succeeded == true)
        }
        let first = UUID().uuidString
        try Data(first.utf8).write(to: folder.appendingPathComponent("request"))
        let result = await ProcessRunner.runAsync(executablePath: "/bin/sh", arguments: [script.path], timeout: 5)
        #expect(result?.succeeded == true)
        #expect(try String(contentsOf: folder.appendingPathComponent("result"), encoding: .utf8) == first + "\n0\n")
        _ = await ProcessRunner.runAsync(executablePath: "/bin/sh", arguments: [script.path], timeout: 5)
        #expect(try String(contentsOf: folder.appendingPathComponent("result"), encoding: .utf8) == first + "\n0\n")
        let second = UUID().uuidString
        try Data(second.utf8).write(to: folder.appendingPathComponent("request"))
        _ = await ProcessRunner.runAsync(executablePath: "/bin/sh", arguments: [script.path], timeout: 5)
        #expect(try String(contentsOf: folder.appendingPathComponent("result"), encoding: .utf8) == second + "\n75\n")
        #expect(try String(contentsOf: folder.appendingPathComponent("runs"), encoding: .utf8) == "run")
        #expect(!MemoryCleaningInstallation.trusted(script.path)) // User files cannot impersonate the root service.
    }
}
