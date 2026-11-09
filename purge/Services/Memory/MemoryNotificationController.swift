import Combine
import Foundation
import UserNotifications

/// Pure episode gate: no polling, one deadline/delivery per uninterrupted observed episode.
nonisolated struct MemoryPressureEpisode: Sendable {
    private(set) var beganAt: Double?
    private(set) var delivered = false
    private var threshold: MemoryPressure = .critical
    mutating func update(level: MemoryPressure, threshold: MemoryPressure, enabled: Bool, now: Double) {
        if self.threshold != threshold { reset(); self.threshold = threshold }
        guard enabled, level != .unknown, level.rawValue >= threshold.rawValue else { reset(); return }
        if beganAt == nil { beganAt = now }
    }
    func due(now: Double) -> Bool { !delivered && beganAt.map { now - $0 >= 60 } == true }
    mutating func markDelivered() { delivered = true }
    mutating func reset() { beganAt = nil; delivered = false }
}

@MainActor
final class MemoryNotificationController: ObservableObject {
    nonisolated static let categoryID = "purge.memory.pressure"
    nonisolated static let reviewID = "purge.memory.review"
    @Published private(set) var permissionDenied = false
    private(set) var authorized = false
    private let settings: MemorySettingsStore
    private var timer: Task<Void, Never>?
    private var generation = UUID()
    private var episode = MemoryPressureEpisode()
    private let clock = MemoryContinuousClock()
    private var pressure: MemoryPressure = .unknown
    var processSample: (() async -> MemoryProcessSample?)?
    var permissionChanged: (() -> Void)?

    init(settings: MemorySettingsStore) { self.settings = settings }
    static func category() -> UNNotificationCategory {
        UNNotificationCategory(identifier: categoryID,
            actions: [UNNotificationAction(identifier: reviewID, title: memoryText("Review"), options: .foreground)],
            intentIdentifiers: [], options: [])
    }
    func refreshPermission(request: Bool = false) async {
        guard !TestHost.isActive() else { return }
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if request && status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        authorized = status == .authorized || status == .provisional
        permissionDenied = status == .denied
        permissionChanged?()
        update(pressure)
    }

    func update(_ level: MemoryPressure) {
        pressure = level
        let old = episode.beganAt
        episode.update(level: level, threshold: settings.threshold,
                       enabled: settings.notifications && authorized, now: clock.now)
        if old != episode.beganAt || episode.beganAt == nil {
            timer?.cancel(); timer = nil; generation = UUID()
        }
        guard timer == nil, let began = episode.beganAt, !episode.delivered else { return }
        let token = generation
        timer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, 60 - (self?.clock.now ?? began) + began))) }
            catch { return }
            guard let self, token == self.generation, self.episode.due(now: self.clock.now),
                  self.settings.notifications, self.authorized else { return }
            let sample = await self.processSample?()
            guard token == self.generation, self.settings.notifications, self.authorized,
                  self.pressure != .unknown, self.pressure.rawValue >= self.settings.threshold.rawValue else { return }
            self.episode.markDelivered()
            let content = UNMutableNotificationContent()
            content.title = memoryText("Sustained memory pressure")
            let leader = sample?.groups.first(where: { $0.footprint != nil })?.title
            if let leader {
                content.body = memoryText("Review memory use. Largest readable consumer: \(leader).")
            } else { content.body = memoryText("Review memory use. No application will be closed automatically.") }
            content.categoryIdentifier = Self.categoryID
            content.sound = .default
            guard !TestHost.isActive() else { return }
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: "purge.memory.\(token.uuidString)", content: content, trigger: nil))
        }
    }

    func interrupt() {
        generation = UUID(); episode.reset(); pressure = .unknown
        timer?.cancel(); timer = nil
    }
}
