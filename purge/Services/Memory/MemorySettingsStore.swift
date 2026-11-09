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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.menuKey: false, "memory.notifications": false, "memory.interval": 2,
            "memory.threshold": MemoryPressure.critical.rawValue, "memory.exclusions": [String]()])
        interval = defaults.double(forKey: "memory.interval") == 1 ? 1 : 2
        showsMenuBar = defaults.bool(forKey: Self.menuKey)
        notifications = defaults.bool(forKey: "memory.notifications")
        threshold = defaults.integer(forKey: "memory.threshold") == MemoryPressure.warning.rawValue ? .warning : .critical
        exclusions = Set(defaults.stringArray(forKey: "memory.exclusions") ?? [])
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
