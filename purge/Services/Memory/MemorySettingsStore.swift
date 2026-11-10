import Combine
import Foundation

@MainActor
final class MemorySettingsStore: ObservableObject {
    static let menuKey = "memory.menuBar"
    private let defaults: UserDefaults
    var onChange: (() -> Void)?
    @Published var interval: Double { didSet { defaults.set(interval == 1 ? 1 : 2, forKey: "memory.interval"); onChange?() } }
    @Published var showsMenuBar: Bool { didSet { defaults.set(showsMenuBar, forKey: Self.menuKey); onChange?() } }
    @Published var notifications: Bool { didSet { defaults.set(notifications, forKey: "memory.notifications"); onChange?() } }
    @Published var threshold: MemoryPressure { didSet { defaults.set(threshold.rawValue, forKey: "memory.threshold"); onChange?() } }
    @Published private(set) var exclusions: Set<String>
    static let cleanupIntervals = [5, 15, 30, 60]
    static let cleanupThresholds = [70, 80, 85, 90, 95]
    @Published var automaticCleaning: Bool { didSet { defaults.set(automaticCleaning, forKey: "memory.autoClean"); onChange?() } }
    @Published var cleaningMode: MemoryCleanupMode { didSet { defaults.set(cleaningMode.rawValue, forKey: "memory.cleanMode"); onChange?() } }
    @Published var cleaningInterval: Int { didSet { defaults.set(cleaningInterval, forKey: "memory.cleanMinutes"); onChange?() } }
    @Published var cleaningThreshold: Int { didSet { defaults.set(cleaningThreshold, forKey: "memory.cleanPercent"); onChange?() } }
    var lastCleaningAttempt: Date? {
        get { defaults.object(forKey: "memory.lastCleanAttempt") as? Date }
        set { defaults.set(newValue, forKey: "memory.lastCleanAttempt") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.menuKey: false, "memory.notifications": false, "memory.interval": 2,
            "memory.threshold": MemoryPressure.critical.rawValue, "memory.exclusions": [String]()])
        interval = defaults.double(forKey: "memory.interval") == 1 ? 1 : 2
        showsMenuBar = defaults.bool(forKey: Self.menuKey)
        notifications = defaults.bool(forKey: "memory.notifications")
        threshold = defaults.integer(forKey: "memory.threshold") == MemoryPressure.warning.rawValue ? .warning : .critical
        exclusions = Set(defaults.stringArray(forKey: "memory.exclusions") ?? [])
        automaticCleaning = defaults.bool(forKey: "memory.autoClean")
        cleaningMode = MemoryCleanupMode(rawValue: defaults.string(forKey: "memory.cleanMode") ?? "") ?? .timer
        let minutes = defaults.integer(forKey: "memory.cleanMinutes")
        cleaningInterval = Self.cleanupIntervals.contains(minutes) ? minutes : 30
        let percent = defaults.integer(forKey: "memory.cleanPercent")
        cleaningThreshold = Self.cleanupThresholds.contains(percent) ? percent : 85
    }

    func exclude(_ bundle: String) {
        guard !bundle.isEmpty else { return }
        exclusions.insert(bundle)
        persistExclusions()
    }
    func include(_ bundle: String) { exclusions.remove(bundle); persistExclusions() }
    private func persistExclusions() {
        defaults.set(exclusions.sorted(), forKey: "memory.exclusions")
        onChange?()
    }
}
