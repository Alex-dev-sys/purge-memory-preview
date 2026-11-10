import AppKit
import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    static let userDefaultsKey = "app.language"
    static let launchSelection = selected(in: .standard)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: String(localized: "System language")
        case .english: "English"
        case .russian: "Русский"
        }
    }

    static func selected(in defaults: UserDefaults) -> AppLanguage {
        defaults.string(forKey: userDefaultsKey).flatMap(Self.init(rawValue:)) ?? .system
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }

    @MainActor
    static func relaunch() throws {
        UserDefaults.standard.synchronize()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The app path is an argument, never interpolated into shell code.
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$1\"", "purge-relaunch", Bundle.main.bundlePath]
        try process.run()
        NSApp.terminate(nil)
    }
}
