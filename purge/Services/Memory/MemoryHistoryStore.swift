import Combine
import Foundation

nonisolated struct MemoryHistoryArchive: Codable, Sendable {
    var version = 1
    var entries: [MemoryHistoryEntry] = []
}

actor MemoryHistoryDisk {
    private let url: URL
    private var archive = MemoryHistoryArchive()
    private var loaded = false
    private var unavailable = false
    init(url: URL) { self.url = url }

    func read() -> MemoryHistoryArchive? {
        if !loaded {
            loaded = true
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    archive = try JSONDecoder().decode(MemoryHistoryArchive.self, from: Data(contentsOf: url))
                    guard archive.version == 1 else { unavailable = true; return nil }
                    archive.entries = Array(archive.entries.prefix(100))
                } catch { unavailable = true }
            }
        }
        return unavailable ? nil : archive
    }

    func append(_ entry: MemoryHistoryEntry) -> MemoryHistoryArchive? {
        guard read() != nil else { return nil } // Preserve corrupt/future files until confirmed reset.
        archive.entries.insert(entry, at: 0)
        archive.entries = Array(archive.entries.prefix(100))
        return write()
    }
    func clear() -> MemoryHistoryArchive? {
        archive = MemoryHistoryArchive(); loaded = true; unavailable = false
        return write()
    }
    private func write() -> MemoryHistoryArchive? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
            return archive
        } catch { unavailable = true; return nil }
    }
}

@MainActor
final class MemoryHistoryStore: ObservableObject {
    @Published private(set) var entries: [MemoryHistoryEntry] = []
    @Published private(set) var isUnavailable = false
    private let disk: MemoryHistoryDisk?
    private let protectsAppStorage: Bool
    private var revision = 0
    init(url: URL? = nil) {
        protectsAppStorage = url == nil && !TestHost.isActive()
        if let url { disk = MemoryHistoryDisk(url: url) }
        else if TestHost.isActive() { disk = nil }
        else { disk = MemoryHistoryDisk(url: AppSupportFolder.url().appendingPathComponent("memory-history.json")) }
    }
    func load() async {
        let revision = revision
        if let disk {
            let result = await MemoryBoundedWork.run { await disk.read() }
            if revision == self.revision { receive(result) }
        }
    }
    func append(_ entry: MemoryHistoryEntry) async {
        guard !protectsAppStorage || !SelfUninstallState.clearsDefaultsOnQuit else { isUnavailable = true; return }
        revision &+= 1
        let revision = revision
        if let disk {
            let result = await MemoryBoundedWork.run { await disk.append(entry) }
            if revision == self.revision { receive(result) }
        }
    }
    func clear() async {
        guard !protectsAppStorage || !SelfUninstallState.clearsDefaultsOnQuit else { return }
        revision &+= 1
        let revision = revision
        if let disk {
            let result = await MemoryBoundedWork.run { await disk.clear() }
            if revision == self.revision { receive(result) }
        }
    }
    private func receive(_ archive: MemoryHistoryArchive?) {
        isUnavailable = archive == nil
        if let archive { entries = archive.entries }
    }
}
