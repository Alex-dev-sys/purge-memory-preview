import Foundation

nonisolated func memoryText(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "Memory")
}

nonisolated enum MemoryPressure: Int, Codable, Sendable, CaseIterable {
    case unknown, normal, warning, critical

    var title: String {
        switch self {
        case .unknown: memoryText("Unknown")
        case .normal: memoryText("Normal")
        case .warning: memoryText("Warning")
        case .critical: memoryText("Critical")
        }
    }
}

nonisolated struct MemorySnapshot: Sendable, Identifiable {
    var id: Date { sampledAt }
    let sampledAt: Date
    let total: Int64
    let app: Int64?
    let wired: Int64?
    let compressed: Int64?
    let cached: Int64?
    let free: Int64?
    let swap: Int64?
    var unavailableReasons: [String: MemoryReadingFailure] {
        var result: [String: MemoryReadingFailure] = [:]
        for (name, value) in [("app", app), ("wired", wired), ("compressed", compressed), ("cached", cached), ("free", free)] {
            if value == nil { result[name] = .invalidCounter }
        }
        if swap == nil { result["swap"] = .sourceUnavailable }
        if used == nil { result["used"] = .invalidCounter }
        if breakdownRemainder == nil { result["breakdown"] = .inconsistentBreakdown }
        return result
    }

    var used: Int64? {
        guard let value = Self.sum([app, wired, compressed]), value <= total else { return nil }
        return value
    }
    var breakdownRemainder: Int64? {
        guard let sum = Self.sum([app, wired, compressed, cached, free]), sum <= total else { return nil }
        return total - sum
    }

    static func sum(_ values: [Int64?]) -> Int64? {
        var total: Int64 = 0
        for value in values {
            guard let value, value >= 0 else { return nil }
            let result = total.addingReportingOverflow(value)
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return total
    }
}

nonisolated enum MemoryReadingFailure: Sendable, Equatable {
    case sourceUnavailable, invalidCounter, inconsistentBreakdown
}

/// Proposed counter mapping; not Activity Monitor equivalence. All arithmetic is checked.
nonisolated enum MemoryAccounting {
    static func snapshot(total: UInt64, pageSize: UInt64, free: UInt64, speculative: UInt64,
                         internalPages: UInt64, externalPages: UInt64, purgeable: UInt64,
                         wired: UInt64, compressed: UInt64, swap: UInt64?, date: Date = Date()) -> MemorySnapshot? {
        guard total > 0, total <= UInt64(Int64.max), pageSize > 0 else { return nil }
        func bytes(_ count: UInt64?) -> Int64? {
            guard let count else { return nil }
            let product = count.multipliedReportingOverflow(by: pageSize)
            guard !product.overflow, product.partialValue <= total else { return nil }
            return Int64(product.partialValue)
        }
        let cache1 = externalPages.addingReportingOverflow(purgeable)
        let cache2 = cache1.partialValue.addingReportingOverflow(speculative)
        return MemorySnapshot(sampledAt: date, total: Int64(total),
                              app: bytes(internalPages >= purgeable ? internalPages - purgeable : nil),
                              wired: bytes(wired), compressed: bytes(compressed),
                              cached: bytes(cache1.overflow || cache2.overflow ? nil : cache2.partialValue),
                              free: bytes(free >= speculative ? free - speculative : nil),
                              swap: swap.flatMap { Int64(exactly: $0) })
    }
}

nonisolated struct MemoryChartEntry: Sendable {
    let snapshot: MemorySnapshot
    let generation: Int
    let interval: TimeInterval
}

nonisolated struct MemoryChartBuffer: Sendable {
    private var storage = [MemoryChartEntry?](repeating: nil, count: 3601)
    private var head = 0
    private var count = 0
    var entries: [MemoryChartEntry] {
        (0..<count).compactMap { storage[(head + $0) % storage.count] }
    }
    var samples: [MemorySnapshot] { entries.map(\.snapshot) }
    mutating func append(_ snapshot: MemorySnapshot, generation: Int = 0, interval: TimeInterval = 2) {
        let entry = MemoryChartEntry(snapshot: snapshot, generation: generation, interval: interval)
        let cutoff = snapshot.sampledAt.addingTimeInterval(-3600)
        while count > 0, let oldest = storage[head], oldest.snapshot.sampledAt < cutoff {
            storage[head] = nil
            head = (head + 1) % storage.count
            count -= 1
        }
        if count == storage.count {
            storage[head] = entry
            head = (head + 1) % storage.count
        } else {
            storage[(head + count) % storage.count] = entry
            count += 1
        }
    }
}

nonisolated enum MemoryFormat {
    static func bytes(_ value: Int64?) -> String {
        guard let value else { return memoryText("Unavailable") }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.includesActualByteCount = false
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: value)
    }
}
