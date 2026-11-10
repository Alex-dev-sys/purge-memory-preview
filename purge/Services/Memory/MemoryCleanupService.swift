import Combine
import Foundation

@MainActor
final class MemoryCleanupService: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var message: String?
    @Published private(set) var lastBeforeFree: Int64?
    @Published private(set) var lastAfterFree: Int64?
    @Published private(set) var nextDate: Date?
    let settings: MemorySettingsStore
    private let history: MemoryHistoryStore
    private let backend: any MemoryCleaningBackend
    private let stats: any MemoryStatsProviding
    private let now: () -> Date
    private let settle: () async -> Void
    var isBlocked: () -> Bool = { false }
    var currentSnapshot: () -> MemorySnapshot? = { nil }
    var didSample: (MemorySnapshot) -> Void = { _ in }
    private var policy = MemoryCleanupPolicy()
    private var configuration = ""
    private var monitor: Task<Void, Never>?
    private var sleeping = false
    private var exiting = false

    init(settings: MemorySettingsStore, history: MemoryHistoryStore, stats: any MemoryStatsProviding,
         backend: any MemoryCleaningBackend = SystemMemoryCleaner(), now: @escaping () -> Date = Date.init,
         settle: @escaping () async -> Void = { try? await Task.sleep(for: .seconds(1)) }) {
        self.settings = settings; self.history = history; self.stats = stats
        self.backend = backend; self.now = now; self.settle = settle
    }

    func refreshPermission() async {
        isEnabled = await backend.isEnabled()
        if !isEnabled, !isAuthorizing, settings.automaticCleaning {
            settings.automaticCleaning = false; nextDate = nil
            message = MemoryCleaningError.unavailable.message
        }
    }

    @discardableResult
    func enable() async -> Bool {
        guard !isBusy, !isAuthorizing, !exiting, !isBlocked() else { return false }
        isAuthorizing = true; message = nil
        defer { isAuthorizing = false }
        do {
            try await backend.enable()
            isEnabled = await backend.isEnabled()
            return isEnabled
        } catch {
            message = (error as? MemoryCleaningError)?.message ?? MemoryCleaningError.authorization.message
            return false
        }
    }

    func disable() async {
        guard !isBusy, !isAuthorizing, !exiting, !isBlocked() else { return }
        isAuthorizing = true
        defer { isAuthorizing = false }
        do {
            try await backend.disable()
            settings.automaticCleaning = false; isEnabled = false
            message = memoryText("Memory cleaning permission was removed.")
        } catch { message = MemoryCleaningError.authorization.message }
    }

    func setAutomatic(_ enabled: Bool) async {
        if enabled {
            if !isEnabled, !(await enable()) { return }
            guard !exiting else { return }
        }
        settings.automaticCleaning = enabled
        configure()
    }

    func configure() {
        let key = "\(settings.automaticCleaning):\(settings.cleaningMode):\(settings.cleaningInterval):\(settings.cleaningThreshold)"
        guard key != configuration else { return }
        configuration = key
        policy.reset(now: now(), intervalMinutes: settings.cleaningInterval)
        nextDate = settings.automaticCleaning && settings.cleaningMode == .timer ? policy.nextDate : nil
    }

    func start() {
        guard monitor == nil, !TestHost.isActive() else { return }
        exiting = false; configure()
        monitor = Task { [weak self] in
            await self?.refreshPermission()
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
    }

    func tick() async {
        configure()
        guard settings.automaticCleaning, !exiting else { return }
        let blocked = sleeping || isBusy || isAuthorizing || isBlocked() || !isEnabled
        if let trigger = policy.due(mode: settings.cleaningMode, threshold: settings.cleaningThreshold,
                                    snapshot: currentSnapshot(), lastAttempt: settings.lastCleaningAttempt,
                                    now: now(), blocked: blocked) {
            await clean(trigger: trigger)
        }
    }

    func setSleeping(_ value: Bool) {
        sleeping = value
        let latched = policy.usageLatched
        policy.reset(now: now(), intervalMinutes: settings.cleaningInterval)
        policy.usageLatched = latched
        nextDate = settings.automaticCleaning && settings.cleaningMode == .timer ? policy.nextDate : nil
    }

    func clean(trigger: MemoryCleanupTrigger = .manual) async {
        guard !isBusy, !isAuthorizing, !exiting, !sleeping, !isBlocked() else { return }
        if let last = settings.lastCleaningAttempt, now().timeIntervalSince(last) < 60 {
            if trigger == .manual { message = MemoryCleaningError.rateLimited.message }
            return
        }
        if !isEnabled {
            guard trigger == .manual, await enable(), !exiting, !isBlocked() else { return }
        }
        // Lock before the first sample await; both manual and scheduled requests
        // share this gate, and process termination actions consult it too.
        guard !isBusy, !exiting, !isBlocked() else { return }
        isBusy = true; message = nil; lastBeforeFree = nil; lastAfterFree = nil
        defer { isBusy = false }
        let date = now()
        settings.lastCleaningAttempt = date
        policy.attempted(now: date, intervalMinutes: settings.cleaningInterval)
        nextDate = settings.automaticCleaning && settings.cleaningMode == .timer ? policy.nextDate : nil
        let before = await MemoryActionSampling.sample(stats)
        let baselineDate = now()
        do {
            try Task.checkCancellation()
            guard !exiting, !sleeping else { return }
            try await backend.clean()
            await settle()
            let after = await MemoryActionSampling.sample(stats)
            let measuredDate = now()
            if let after { didSample(after) }
            let comparable = before != nil && after != nil && before!.total == after!.total
                && after!.sampledAt >= before!.sampledAt
                && baselineDate.timeIntervalSince(before!.sampledAt) >= 0
                && baselineDate.timeIntervalSince(before!.sampledAt) <= 2
                && measuredDate.timeIntervalSince(after!.sampledAt) >= 0
                && measuredDate.timeIntervalSince(after!.sampledAt) <= 2
            let beforeFree = comparable ? before?.free : nil
            let afterFree = comparable ? after?.free : nil
            lastBeforeFree = beforeFree; lastAfterFree = afterFree
            let delta = beforeFree.flatMap { a in afterFree.map { $0 - a } }
            if let delta, delta > 0 {
                message = memoryText("Observed free RAM increase: \(MemoryFormat.bytes(delta)).")
            } else if delta != nil {
                message = memoryText("Cleaning finished. No measurable increase in free RAM was observed.")
            } else {
                message = memoryText("Cleaning finished. The change in free RAM could not be measured.")
            }
            await history.append(MemoryHistoryEntry(id: UUID(), date: date, bundleID: nil,
                name: memoryText("System file cache"), action: .clean, outcome: .cleaned,
                measurement: delta == nil ? .unmeasured : .observed, delta: delta,
                beforeDate: before?.sampledAt, afterDate: after?.sampledAt, accountingVersion: 1,
                cleanupTrigger: trigger, beforeFree: beforeFree, afterFree: afterFree))
        } catch {
            message = (error as? MemoryCleaningError)?.message ?? MemoryCleaningError.failed.message
            if error as? MemoryCleaningError == .unavailable {
                isEnabled = false; settings.automaticCleaning = false; nextDate = nil
            }
            await history.append(MemoryHistoryEntry(id: UUID(), date: date, bundleID: nil,
                name: memoryText("System file cache"), action: .clean, outcome: .cleanFailed,
                measurement: .unmeasured, delta: nil, beforeDate: before?.sampledAt,
                afterDate: nil, accountingVersion: 1, cleanupTrigger: trigger, cleanupError: message))
        }
    }

    func shutdown() {
        exiting = true; monitor?.cancel(); monitor = nil
    }
}
