import AppKit
import Darwin
import Foundation

nonisolated protocol ProcessMemoryProviding: Sendable {
    func sample(apps: [MemoryAppMetadata]) async -> MemoryProcessSample?
    func record(pid: Int32, app: MemoryAppMetadata?) async -> MemoryProcessRecord?
}

actor ProcessMemoryProvider: ProcessMemoryProviding {
    func record(pid: Int32, app: MemoryAppMetadata?) async -> MemoryProcessRecord? {
        guard var record = Self.read(pid: pid, app: app) else { return nil }
        var parent = record.parentPID
        var visited: Set<Int32> = [pid]
        while parent > 1, visited.insert(parent).inserted {
            if parent == getpid() { record.isPurgeDescendant = true; break }
            guard let info = Self.bsdInfo(parent) else { return nil }
            parent = Int32(info.pbi_ppid)
        }
        return record
    }

    func sample(apps: [MemoryAppMetadata]) async -> MemoryProcessSample? {
        guard let pids = ProcessWorkingDirectories.allProcessIDs() else { return nil }
        let metadata = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var records: [MemoryProcessRecord] = []
        var partial = false
        for pid in pids {
            guard !Task.isCancelled else { return nil }
            if let record = Self.read(pid: pid, app: metadata[pid]) {
                records.append(record)
                if record.footprint == nil { partial = true }
            } else { partial = true }
        }
        // Revalidate after enumeration: never publish membership based on a reused PID.
        records = records.filter { record in
            guard !Task.isCancelled, let fresh = Self.bsdInfo(record.identity.pid),
                  fresh.pbi_start_tvsec == record.identity.seconds,
                  fresh.pbi_start_tvusec == record.identity.microseconds,
                  fresh.pbi_uid == record.uid, Int32(fresh.pbi_ppid) == record.parentPID else {
                partial = true
                return false
            }
            return true
        }
        let byPID = Dictionary(records.map { ($0.identity.pid, $0) }, uniquingKeysWith: { first, _ in first })
        records = records.map { original in
            var record = original
            var parent = record.parentPID
            var visited: Set<Int32> = [record.identity.pid]
            while parent > 1, visited.insert(parent).inserted {
                if parent == getpid() { record.isPurgeDescendant = true; break }
                guard let ancestor = byPID[parent] else { break }
                parent = ancestor.parentPID
            }
            return record
        }
        let date = Date()
        return MemoryProcessSample(groups: MemoryGrouping.groups(records, date: date), sampledAt: date, isPartial: partial)
    }

    private static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == Int32(size) else { return nil }
        return info
    }

    static func identity(_ pid: Int32) -> MemoryProcessIdentity? {
        guard let info = bsdInfo(pid) else { return nil }
        return MemoryProcessIdentity(pid: pid, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }

    private static func read(pid: Int32, app: MemoryAppMetadata?) -> MemoryProcessRecord? {
        guard let before = bsdInfo(pid) else { return nil }
        let id = MemoryProcessIdentity(pid: pid, seconds: before.pbi_start_tvsec, microseconds: before.pbi_start_tvusec)
        var usage = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        let path = ProcessWorkingDirectories.executablePath(of: pid).map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
        }
        guard identity(pid) == id else { return nil }
        let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? app?.name ?? memoryText("Unknown process")
        return MemoryProcessRecord(identity: id, uid: before.pbi_uid, parentPID: Int32(before.pbi_ppid),
            name: name, executablePath: path, footprint: status == 0 ? Int64(exactly: usage.ri_phys_footprint) : nil, app: app)
    }
}

nonisolated enum MemoryGrouping {
    static func groups(_ records: [MemoryProcessRecord], date: Date) -> [MemoryProcessGroup] {
        let byPID = Dictionary(records.map { ($0.identity.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let roots = records.filter { $0.app?.isRegular == true }
        var owner: [MemoryProcessIdentity: MemoryProcessIdentity] = [:]
        for root in roots { owner[root.identity] = root.identity }
        for record in records where record.app?.isRegular != true {
            guard let path = record.executablePath, record.uid != 0 else { continue }
            var matches: [MemoryProcessIdentity] = []
            for root in roots {
                guard root.uid == record.uid, let bundle = root.app?.bundlePath,
                      MemorySafetyPolicy.isInside(path, root: bundle) else { continue }
                var parent = record.parentPID
                var visited: Set<Int32> = [record.identity.pid]
                while let ancestor = byPID[parent], visited.insert(parent).inserted {
                    guard ancestor.uid == root.uid else { break }
                    if ancestor.identity == root.identity { matches.append(root.identity); break }
                    guard ancestor.app?.isRegular != true, let ancestorPath = ancestor.executablePath,
                          MemorySafetyPolicy.isInside(ancestorPath, root: bundle) else { break }
                    parent = ancestor.parentPID
                }
            }
            if matches.count == 1 { owner[record.identity] = matches[0] }
        }
        let members = Dictionary(grouping: records) { owner[$0.identity] ?? $0.identity }
        return members.compactMap { id, rows in
            guard let root = rows.first(where: { $0.identity == id }) else { return nil }
            return MemoryProcessGroup(root: root, members: rows, sampledAt: date)
        }.sorted { ($0.footprint ?? -1) > ($1.footprint ?? -1) }
    }
}

@MainActor
enum MemoryApplications {
    static func metadata(_ app: NSRunningApplication) -> MemoryAppMetadata {
        MemoryAppMetadata(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
            name: app.localizedName ?? memoryText("Unknown application"),
            bundlePath: app.bundleURL?.resolvingSymlinksInPath().path,
            executablePath: app.executableURL?.resolvingSymlinksInPath().path,
            isRegular: app.activationPolicy == .regular)
    }
    static func current() -> [MemoryAppMetadata] { NSWorkspace.shared.runningApplications.map { metadata($0) } }
}
