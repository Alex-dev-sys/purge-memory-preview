import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class MemoryProcessStore: ObservableObject {
    @Published var sample: MemoryProcessSample?
    @Published var unavailable = false
}

@MainActor
final class MemoryCoordinator: ObservableObject {
    let settings: MemorySettingsStore
    let history: MemoryHistoryStore
    let actions: MemoryActionService
    let notifications: MemoryNotificationController
    let cleanup: MemoryCleanupService
    var isBusy: Bool { actions.isBusy || cleanup.isBusy || cleanup.isAuthorizing }
    let processStore = MemoryProcessStore()
    @Published private(set) var snapshot: MemorySnapshot?
    @Published private(set) var statsUnavailable = false
    @Published private(set) var pressure: MemoryPressure = .unknown
    private let stats: any MemoryStatsProviding
    private let processes: any ProcessMemoryProviding
    private var pages: [UUID: NSWindow] = [:]
    private var expandedPages: Set<UUID> = []
    private var foreground = false
    private var sleeping = false
    private var started = false
    private var samplingInterval: Double?
    private var aggregateTask: Task<Void, Never>?
    private var processTask: Task<Void, Never>?
    private var scan: (UUID, Task<MemoryProcessSample?, Never>)?
    private var source: DispatchSourceMemoryPressure?
    private var pressureGeneration = UUID()
    private var subscriptions: [AnyCancellable] = []

    init(settings: MemorySettingsStore? = nil, history: MemoryHistoryStore? = nil,
         stats: (any MemoryStatsProviding)? = nil, processes: (any ProcessMemoryProviding)? = nil) {
        let settings = settings ?? MemorySettingsStore()
        let history = history ?? MemoryHistoryStore()
        let stats = stats ?? MemoryStatsProvider()
        let processes = processes ?? ProcessMemoryProvider()
        self.settings = settings; self.history = history; self.stats = stats; self.processes = processes
        let policy = MemorySafetyPolicy(currentUID: getuid(), ownPID: getpid(), ownBundleID: Bundle.main.bundleIdentifier,
                                        ownBundlePath: Bundle.main.bundleURL.resolvingSymlinksInPath().path)
        actions = MemoryActionService(settings: settings, history: history, processes: processes, stats: stats, policy: policy)
        notifications = MemoryNotificationController(settings: settings)
        cleanup = MemoryCleanupService(settings: settings, history: history, stats: stats)
        cleanup.isBlocked = { [weak actions] in actions?.isBusy == true || AppEnvironment.store.isAnyCleanInProgress }
        cleanup.currentSnapshot = { [weak self] in self?.statsUnavailable == false ? self?.snapshot : nil }
        cleanup.didSample = { [weak self] value in
            guard let self else { return }
            self.snapshot = value; self.statsUnavailable = false
        }
        actions.cleaningIsBusy = { [weak cleanup] in cleanup?.isBusy == true || cleanup?.isAuthorizing == true }
        settings.onChange = { [weak self] in
            guard let self else { return }
            self.notifications.update(self.pressure)
            self.cleanup.configure()
            self.reconcile()
        }
        notifications.permissionChanged = { [weak self] in self?.reconcile() }
        notifications.processSample = { [weak self] in await self?.processSample() }
    }

    func start() {
        guard !started, !TestHost.isActive() else { return }
        started = true
        cleanup.start()
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor in
                    self?.reconcile()
                    if name == NSApplication.didBecomeActiveNotification { await self?.notifications.refreshPermission() }
                }
            }.store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification).sink { [weak self] event in
            guard let window = event.object as? NSWindow else { return }
            Task { @MainActor in
                if self?.pages.values.contains(where: { $0 === window }) == true { self?.actions.foregroundEnded() }
                self?.pages = self?.pages.filter { $0.value !== window } ?? [:]
                if let self { self.expandedPages.formIntersection(self.pages.keys) }
                self?.reconcile()
            }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = true; self?.cleanup.setSleeping(true); self?.actions.observationInterrupted(); self?.stopPressure(); self?.reconcile()
            }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; self?.cleanup.setSleeping(false); self?.reconcile() }
        }.store(in: &subscriptions)
        Task { [weak self] in
            await self?.history.load()
            await self?.notifications.refreshPermission()
        }
        reconcile()
    }

    func page(_ id: UUID, window: NSWindow?, processesVisible: Bool = true) {
        if window == nil, pages[id] != nil { actions.foregroundEnded() }
        pages[id] = window
        if window != nil && processesVisible { expandedPages.insert(id) }
        else { expandedPages.remove(id) }
        start(); reconcile()
    }

    func processDetails(_ id: UUID, visible: Bool) {
        if visible { expandedPages.insert(id) }
        else { expandedPages.remove(id) }
        reconcile()
    }

    private func reconcile() {
        guard started, !TestHost.isActive() else { return }
        let active = !sleeping && NSApp.isActive && pages.values.contains {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        }
        if foreground != active {
            foreground = active
            if !active { actions.foregroundEnded(); scan?.1.cancel() }
        }
        let needsProcesses = active && pages.contains { id, window in
            expandedPages.contains(id) && window.isVisible && !window.isMiniaturized
                && window.occlusionState.contains(.visible)
        }
        if needsProcesses != (processTask != nil) {
            processTask?.cancel(); processTask = nil
            if needsProcesses {
                processTask = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self else { return }
                        let sample = await self.processSample()
                        guard !Task.isCancelled, self.foreground else { return }
                        self.processStore.unavailable = sample == nil
                        if let sample { self.processStore.sample = sample }
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    }
                }
            }
        }
        let interval: Double? = sleeping ? nil : (active ? settings.interval : (settings.showsMenuBar || settings.automaticCleaning ? 10 : nil))
        if samplingInterval != interval {
            aggregateTask?.cancel(); samplingInterval = interval
            if let interval {
                aggregateTask = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self else { return }
                        let value = await self.stats.sample()
                        guard !Task.isCancelled else { return }
                        self.statsUnavailable = value == nil
                        if let value {
                            self.snapshot = value
                        }
                        do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                    }
                }
            }
        }
        let needsPressure = !sleeping && (active || settings.showsMenuBar || (settings.notifications && notifications.authorized))
        if needsPressure && source == nil {
            let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
            self.source = source
            let generation = UUID()
            pressureGeneration = generation
            source.setEventHandler { [weak self] in
                // Dispatch data is read inside its handler; this source is explicitly on .main.
                MainActor.assumeIsolated {
                    guard self?.pressureGeneration == generation else { return }
                    self?.pressureEvent()
                }
            }
            source.resume()
        } else if !needsPressure { stopPressure() }
    }

    private func pressureEvent() {
        guard let data = source?.data else { return }
        if data == .normal { pressure = .normal }
        else if data == .warning { pressure = .warning }
        else if data == .critical { pressure = .critical }
        else { pressure = .unknown }
        notifications.update(pressure)
    }
    private func stopPressure() {
        pressureGeneration = UUID()
        source?.cancel(); source = nil; pressure = .unknown; notifications.interrupt()
    }

    private func processSample() async -> MemoryProcessSample? {
        if let scan { return await scan.1.value }
        let apps = MemoryApplications.current()
        let provider = processes
        let id = UUID()
        let task = Task { await provider.sample(apps: apps) }
        scan = (id, task)
        let value = await task.value
        if scan?.0 == id { scan = nil }
        return value
    }

    func enableNotifications(_ enabled: Bool) {
        settings.notifications = enabled
        Task { await notifications.refreshPermission(request: enabled) }
    }
    func openMemory() {
        AppEnvironment.store.selectedTab = .memory
        AppWindowPresenter.reveal()
    }
    func prepareForExit() async {
        actions.beginExit()
        cleanup.shutdown()
        let clock = MemoryContinuousClock()
        let deadline = clock.now + 8
        while isBusy && clock.now < deadline { try? await clock.sleep(seconds: 0.1) }
        shutdown()
    }
    func shutdown() {
        aggregateTask?.cancel(); processTask?.cancel(); scan?.1.cancel(); stopPressure()
        cleanup.shutdown()
        subscriptions.removeAll(); started = false
    }
}
