import Foundation

nonisolated struct MemoryProcessIdentity: Hashable, Codable, Sendable {
    let pid: Int32
    let seconds: UInt64
    let microseconds: UInt64
}

nonisolated struct MemoryAppMetadata: Sendable {
    let pid: Int32
    let bundleID: String?
    let name: String
    let bundlePath: String?
    let executablePath: String?
    let isRegular: Bool
}

nonisolated struct MemoryProcessRecord: Sendable, Identifiable {
    var id: MemoryProcessIdentity { identity }
    let identity: MemoryProcessIdentity
    let uid: UInt32
    let parentPID: Int32
    let name: String
    let executablePath: String?
    let footprint: Int64?
    let app: MemoryAppMetadata?
    var isPurgeDescendant = false
}

nonisolated enum MemorySafety: Sendable, Equatable {
    case safe, checkFirst, protected
    var title: String {
        switch self {
        case .safe: memoryText("Safe to Quit")
        case .checkFirst: memoryText("Check First")
        case .protected: memoryText("Protected")
        }
    }
}

nonisolated struct MemoryGroupIdentity: Hashable, Sendable {
    let process: MemoryProcessIdentity
    let bundleID: String?
}

nonisolated struct MemoryProcessGroup: Sendable, Identifiable {
    var id: MemoryGroupIdentity { MemoryGroupIdentity(process: root.identity, bundleID: bundleID) }
    let root: MemoryProcessRecord
    let members: [MemoryProcessRecord]
    let sampledAt: Date
    let footprint: Int64?
    init(root: MemoryProcessRecord, members: [MemoryProcessRecord], sampledAt: Date) {
        self.root = root; self.members = members; self.sampledAt = sampledAt
        footprint = MemorySnapshot.sum(members.map(\.footprint))
    }
    var bundleID: String? { root.app?.bundleID }
    var title: String { root.app?.name ?? root.name }
    var explanation: String {
        switch bundleID {
        case "com.apple.Safari": memoryText("Web browser. Tabs and extensions may use helper processes.")
        case "com.apple.dt.Xcode": memoryText("Development environment. Check builds and unsaved projects before quitting.")
        case "com.apple.calculator": memoryText("Calculator application. Review any work before quitting.")
        case "com.apple.weather": memoryText("Weather application. The safety label does not guarantee absence of work.")
        default: root.app?.isRegular == true
            ? memoryText("User application. Check documents and background tasks before quitting.")
            : memoryText("Process counters only. Unrecognized processes cannot be closed here.")
        }
    }
}

nonisolated struct MemoryProcessSample: Sendable {
    let groups: [MemoryProcessGroup]
    let sampledAt: Date
    let isPartial: Bool
}

/// Requestable applications always precede protected or unmeasured groups;
/// the user's selected sort applies independently inside those two sections.
nonisolated enum MemoryProcessOrdering {
    static func isRequestable(_ group: MemoryProcessGroup, policy: MemorySafetyPolicy, exclusions: Set<String>) -> Bool {
        group.footprint != nil && policy.classify(group.root, exclusions: exclusions) != .protected
    }

    static func sorted(_ groups: [MemoryProcessGroup], policy: MemorySafetyPolicy,
                       exclusions: Set<String>, byName: Bool) -> [MemoryProcessGroup] {
        let ranked = groups.map { group in
            (group: group, requestable: isRequestable(group, policy: policy, exclusions: exclusions), footprint: group.footprint)
        }
        return ranked.sorted { lhs, rhs in
            if lhs.requestable != rhs.requestable { return lhs.requestable }
            if !byName, lhs.footprint != rhs.footprint { return (lhs.footprint ?? -1) > (rhs.footprint ?? -1) }
            let names = lhs.group.title.localizedStandardCompare(rhs.group.title)
            if names != .orderedSame { return names == .orderedAscending }
            return lhs.group.root.identity.pid < rhs.group.root.identity.pid
        }.map { $0.group }
    }
}
