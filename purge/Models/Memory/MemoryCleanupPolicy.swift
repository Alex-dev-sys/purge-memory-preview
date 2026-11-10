import Foundation

nonisolated enum MemoryCleanupMode: String, CaseIterable, Sendable {
    case timer, usage
    var title: String {
        switch self {
        case .timer: memoryText("Timer")
        case .usage: memoryText("RAM usage")
        }
    }
}

nonisolated enum MemoryCleanupTrigger: String, Codable, Sendable {
    case manual, timer, usage
    var title: String {
        switch self {
        case .manual: memoryText("Manual")
        case .timer: memoryText("Timer")
        case .usage: memoryText("RAM usage")
        }
    }
}

nonisolated struct MemoryCleanupPolicy {
    static let cooldown: TimeInterval = 5 * 60
    static let sustainedThreshold: TimeInterval = 30
    var nextDate: Date?
    var aboveSince: Date?
    var usageLatched = false

    mutating func reset(now: Date, intervalMinutes: Int) {
        nextDate = now.addingTimeInterval(Double(intervalMinutes) * 60)
        aboveSince = nil; usageLatched = false
    }

    mutating func due(mode: MemoryCleanupMode, threshold: Int, snapshot: MemorySnapshot?,
                      lastAttempt: Date?, now: Date, blocked: Bool) -> MemoryCleanupTrigger? {
        let age = snapshot.map { now.timeIntervalSince($0.sampledAt) }
        let percent: Double? = snapshot.flatMap { value in
            guard let used = value.used, value.total > 0, let age, age >= 0, age <= 30 else { return nil }
            return Double(used) / Double(value.total) * 100
        }
        if let percent, percent <= Double(threshold - 5) { usageLatched = false }
        if blocked { aboveSince = nil; return nil }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.cooldown { aboveSince = nil; return nil }
        if mode == .timer { return nextDate.map { now >= $0 } == true ? .timer : nil }
        guard let percent, percent >= Double(threshold), !usageLatched else { aboveSince = nil; return nil }
        if aboveSince == nil { aboveSince = now }
        return now.timeIntervalSince(aboveSince!) >= Self.sustainedThreshold ? .usage : nil
    }

    mutating func attempted(now: Date, intervalMinutes: Int) {
        nextDate = now.addingTimeInterval(Double(intervalMinutes) * 60)
        aboveSince = nil; usageLatched = true
    }
}
