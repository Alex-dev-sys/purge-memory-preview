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
    let processStore = MemoryProcessStore()
    @Published private(set) var snapshot: MemorySnapshot?
    @Published private(set) var statsUnavailable = false
    @Published private(set) var pressure: MemoryPressure = .unknown
    @Published private(set) var chart = MemoryChartBuffer()
    private let stats: any MemoryStatsProviding
    private let processes: any ProcessMemoryProviding
    private var pages: [UUID: NSWindow] = [:]
    private var foreground = false
    private var sleeping = false
    private var started = false
    private var samplingInterval: Double?
    private var chartGeneration = 0
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
        settings.onChange = { [weak self] in
            guard let self else { return }
            self.notifications.update(self.pressure)
            self.reconcile()
        }
        notifications.permissionChanged = { [weak self] in self?.reconcile() }
        notifications.processSample = { [weak self] in await self?.processSample() }
    }

    func start() {
        guard !started, !TestHost.isActive() else { return }
        started = true
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
                self?.reconcile()
            }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = true; self?.actions.observationInterrupted(); self?.stopPressure(); self?.reconcile()
            }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; self?.reconcile() }
        }.store(in: &subscriptions)
        Task { [weak self] in
            await self?.history.load()
            await self?.notifications.refreshPermission()
        }
        reconcile()
    }

    func page(_ id: UUID, window: NSWindow?) {
        if window == nil, pages[id] != nil { actions.foregroundEnded() }
        pages[id] = window
        start(); reconcile()
    }

    private func reconcile() {
        guard started, !TestHost.isActive() else { return }
        let active = !sleeping && NSApp.isActive && pages.values.contains {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        }
        if foreground != active {
            foreground = active
            processTask?.cancel(); processTask = nil
            if !active { actions.foregroundEnded(); scan?.1.cancel() }
            if active {
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
        let interval: Double? = sleeping ? nil : (active ? settings.interval : (settings.showsMenuBar ? 10 : nil))
        if samplingInterval != interval {
            chartGeneration &+= 1
            aggregateTask?.cancel(); samplingInterval = interval
            if let interval {
                let generation = chartGeneration
                aggregateTask = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self else { return }
                        let value = await self.stats.sample()
                        guard !Task.isCancelled else { return }
                        self.statsUnavailable = value == nil
                        if let value {
                            self.snapshot = value
                            self.chart.append(value, generation: generation, interval: interval)
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
        let clock = MemoryContinuousClock()
        let deadline = clock.now + 8
        while actions.isBusy && clock.now < deadline { try? await clock.sleep(seconds: 0.1) }
        shutdown()
    }
    func shutdown() {
        aggregateTask?.cancel(); processTask?.cancel(); scan?.1.cancel(); stopPressure()
        subscriptions.removeAll(); started = false
    }
}
