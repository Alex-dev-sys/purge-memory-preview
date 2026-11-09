import Foundation

nonisolated struct MemorySafetyPolicy: Sendable {
    let currentUID: UInt32
    let ownPID: Int32
    let ownBundleID: String?
    let ownBundlePath: String?

    func classify(_ record: MemoryProcessRecord, exclusions: Set<String>) -> MemorySafety {
        guard record.uid != 0, record.uid == currentUID, record.identity.pid != ownPID, !record.isPurgeDescendant,
              record.identity.seconds > 0, let app = record.app, app.pid == record.identity.pid, app.isRegular,
              let bundle = app.bundleID, !bundle.isEmpty, bundle != ownBundleID,
              !exclusions.contains(bundle), let path = record.executablePath,
              let appPath = app.executablePath, path == appPath, app.bundlePath != nil,
              let footprint = record.footprint, footprint >= 0 else { return .protected }
        let protectedIDs: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
            "com.apple.SystemUIServer", "com.apple.controlcenter"]
        let protectedNames: Set<String> = ["kernel_task", "launchd", "WindowServer", "PurgeHelper", "PurgeWatch", "PurgeAssetWorker"]
        guard !protectedIDs.contains(bundle), !protectedNames.contains(record.name),
              !Self.isInside(path, root: "/System/Library"), !Self.isInside(path, root: "/usr"),
              ownBundlePath.map({ !Self.isInside(path, root: $0) }) ?? true else { return .protected }
        return ["com.apple.calculator", "com.apple.weather"].contains(bundle) ? .safe : .checkFirst
    }

    static func isInside(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
