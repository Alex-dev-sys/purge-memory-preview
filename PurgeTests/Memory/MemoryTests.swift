import Foundation
import Testing
@testable import Purge

@MainActor
private enum MemoryFixtures {
    static let policy = MemorySafetyPolicy(currentUID: 501, ownPID: 999, ownBundleID: "test.purge",
                                           ownBundlePath: "/Applications/Purge.app")
    static func record(pid: Int32 = 42, uid: UInt32 = 501, parent: Int32 = 1, start: UInt64 = 10,
                       bundle: String? = "com.apple.calculator", regular: Bool = true, recognized: Bool = true,
                       path: String = "/Applications/Test.app/Contents/MacOS/Test", footprint: Int64? = 1024,
                       name: String = "Test") -> MemoryProcessRecord {
        let app = MemoryAppMetadata(pid: pid, bundleID: bundle, name: name,
                                   bundlePath: "/Applications/Test.app", executablePath: path, isRegular: regular)
        return MemoryProcessRecord(identity: MemoryProcessIdentity(pid: pid, seconds: start, microseconds: 0),
            uid: uid, parentPID: parent, name: name, executablePath: path, footprint: footprint, app: recognized ? app : nil)
    }
    static func group(_ record: MemoryProcessRecord) -> MemoryProcessGroup {
        MemoryProcessGroup(root: record, members: [record], sampledAt: Date())
    }
}

@MainActor
@Suite("Memory counter semantics and action safety")
struct MemoryTests {
    @Test("Speculative and purgeable pages are moved rather than counted twice")
    func accounting() throws {
        let value = try #require(MemoryAccounting.snapshot(total: 1000 * 4096, pageSize: 4096,
            free: 100, speculative: 10, internalPages: 500, externalPages: 100, purgeable: 20,
            wired: 200, compressed: 50, swap: 8192))
        #expect(value.app == 480 * 4096)
        #expect(value.free == 90 * 4096)
        #expect(value.cached == 130 * 4096)
        #expect(value.used == 730 * 4096)
        #expect(value.breakdownRemainder == 50 * 4096)
        #expect(value.swap == 8192)
    }

    @Test("Impossible subtraction, overflow and inconsistent totals are unavailable")
    func unavailableCounters() throws {
        let value = try #require(MemoryAccounting.snapshot(total: 1000, pageSize: 1,
            free: 1, speculative: 2, internalPages: 1, externalPages: UInt64.max,
            purgeable: 2, wired: 900, compressed: 900, swap: nil))
        #expect(value.free == nil)
        #expect(value.app == nil)
        #expect(value.cached == nil)
        #expect(value.used == nil)
        #expect(value.breakdownRemainder == nil)
        #expect(value.unavailableReasons["free"] == .invalidCounter)
        #expect(MemoryAccounting.snapshot(total: UInt64.max, pageSize: 4096, free: 0, speculative: 0,
            internalPages: 0, externalPages: 0, purgeable: 0, wired: 0, compressed: 0, swap: nil) == nil)
    }

    @Test("Only recognized current-user regular apps may be actionable")
    func denies() {
        let records = [MemoryFixtures.record(uid: 0), MemoryFixtures.record(uid: 502),
            MemoryFixtures.record(pid: 999), MemoryFixtures.record(start: 0),
            MemoryFixtures.record(bundle: nil), MemoryFixtures.record(regular: false),
            MemoryFixtures.record(recognized: false), MemoryFixtures.record(footprint: nil), MemoryFixtures.record(footprint: -1),
            MemoryFixtures.record(bundle: "com.apple.finder"), MemoryFixtures.record(bundle: "test.purge"),
            MemoryFixtures.record(path: "/usr/bin/Test"), MemoryFixtures.record(path: "/System/Library/Test"),
            MemoryFixtures.record(path: "/Applications/Purge.app/Contents/MacOS/Child"),
            MemoryFixtures.record(name: "PurgeWatch")]
        for record in records { #expect(MemoryFixtures.policy.classify(record, exclusions: []) == .protected) }
        var descendant = MemoryFixtures.record()
        descendant.isPurgeDescendant = true
        #expect(MemoryFixtures.policy.classify(descendant, exclusions: []) == .protected)
        #expect(MemoryFixtures.policy.classify(MemoryFixtures.record(), exclusions: ["com.apple.calculator"]) == .protected)
        #expect(MemoryFixtures.policy.classify(MemoryFixtures.record(), exclusions: []) == .safe)
        #expect(MemoryFixtures.policy.classify(MemoryFixtures.record(bundle: "test.editor"), exclusions: []) == .checkFirst)
    }

    @Test("Only positive same-bundle ancestry groups helpers; cycles and similar names do not")
    func grouping() throws {
        let root = MemoryFixtures.record()
        let child = MemoryFixtures.record(pid: 43, parent: 42, recognized: false,
            path: "/Applications/Test.app/Contents/Helpers/Child", footprint: 2048)
        let unrelated = MemoryFixtures.record(pid: 44, parent: 42, recognized: false,
            path: "/Applications/TestOther.app/Child")
        let cyclic = MemoryFixtures.record(pid: 45, parent: 45, recognized: false)
        let groups = MemoryGrouping.groups([root, child, unrelated, cyclic], date: Date())
        let app = try #require(groups.first { $0.root.id == root.id })
        #expect(app.members.count == 2)
        #expect(app.footprint == 3072)
        #expect(groups.count == 3)
    }

    @Test("One notification per continuous episode, reset on recovery or unknown")
    func episodes() {
        var episode = MemoryPressureEpisode()
        episode.update(level: .warning, threshold: .warning, enabled: true, now: 0)
        episode.update(level: .critical, threshold: .warning, enabled: true, now: 30)
        #expect(!episode.due(now: 59.99))
        #expect(episode.due(now: 60))
        episode.markDelivered()
        #expect(!episode.due(now: 120))
        episode.update(level: .normal, threshold: .warning, enabled: true, now: 121)
        episode.update(level: .critical, threshold: .warning, enabled: true, now: 122)
        #expect(!episode.due(now: 181))
        #expect(episode.due(now: 182))
        episode.update(level: .unknown, threshold: .warning, enabled: true, now: 183)
        #expect(!episode.due(now: 1000))
        episode.update(level: .critical, threshold: .critical, enabled: false, now: 1001)
        #expect(!episode.due(now: 2000))
    }

    @Test("Chart data expires and stays bounded")
    func chartBounds() throws {
        var chart = MemoryChartBuffer()
        for index in 0..<4000 {
            chart.append(try #require(MemoryAccounting.snapshot(total: 4096, pageSize: 1,
                free: 0, speculative: 0, internalPages: 0, externalPages: 0, purgeable: 0,
                wired: 0, compressed: 0, swap: nil, date: Date(timeIntervalSince1970: Double(index)))))
        }
        #expect(chart.samples.count <= 3601)
        #expect(chart.samples.first?.sampledAt.timeIntervalSince1970 == 399)
    }

    @Test("Memory preferences are isolated and optional integrations start off")
    func defaults() {
        let defaults = ThrowawayDefaults()
        let settings = MemorySettingsStore(defaults: defaults.defaults)
        #expect(!settings.showsMenuBar)
        #expect(!settings.notifications)
        #expect(settings.threshold == .critical)
        #expect(settings.interval == 2)
        settings.exclude("test.editor")
        #expect(MemorySettingsStore(defaults: defaults.defaults).exclusions == ["test.editor"])
        settings.include("test.editor")
        #expect(settings.exclusions.isEmpty)
    }

    @Test("Corrupt history is preserved and bounded history never stores process paths")
    func history() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("memory.json")
        let corrupt = Data("future-or-corrupt".utf8)
        try corrupt.write(to: url)
        let store = MemoryHistoryStore(url: url)
        await store.load()
        #expect(store.isUnavailable)
        let entry = MemoryHistoryEntry(id: UUID(), date: Date(), bundleID: "test.editor", name: "Editor",
            action: .quit, outcome: .timedOut, measurement: .unmeasured, delta: nil,
            beforeDate: nil, afterDate: nil, accountingVersion: 1)
        await store.append(entry)
        #expect(try Data(contentsOf: url) == corrupt)
        await store.clear()
        for _ in 0..<102 { await store.append(entry) }
        #expect(store.entries.count == 100)
        let decoded = try JSONDecoder().decode(MemoryHistoryArchive.self, from: Data(contentsOf: url))
        #expect(decoded.entries.count == 100)
        #expect(decoded.entries.first?.outcome == .timedOut)
    }

    @Test("All three Memory resource tables have the same nonempty keys")
    func localization() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let tables = try ["en", "zh-Hans", "ru"].map { locale in
            let data = try Data(contentsOf: repo.appendingPathComponent("purge/\(locale).lproj/Memory.strings"))
            // A strings table is the body of an OpenStep property-list dictionary.
            let wrapped = Data(("{\n" + String(decoding: data, as: UTF8.self) + "\n}").utf8)
            return try #require(PropertyListSerialization.propertyList(from: wrapped, format: nil) as? [String: String])
        }
        #expect(!tables[0].isEmpty)
        for table in tables {
            #expect(Set(table.keys) == Set(tables[0].keys))
            #expect(table.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
    }
}
