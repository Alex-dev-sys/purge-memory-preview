import Foundation
import Testing
@testable import Purge

@Suite("Application language preferences")
struct AppLanguageTests {
    private let suite = ThrowawayDefaults()

    @Test func followsTheSystemUntilExplicitlySelected() {
        #expect(AppLanguage.selected(in: suite.defaults) == .system)
        suite.defaults.set("unsupported", forKey: AppLanguage.userDefaultsKey)
        #expect(AppLanguage.selected(in: suite.defaults) == .system)
    }

    @Test func selectingRussianAndEnglishSetsTheAppLanguageOverride() {
        for language in [AppLanguage.russian, .english] {
            language.save(in: suite.defaults)
            #expect(AppLanguage.selected(in: suite.defaults) == language)
            // Xcode forces English via the argument domain. Inspect the app's
            // persisted override, which takes effect in a normal relaunch.
            let saved = suite.defaults.persistentDomain(forName: suite.name)?["AppleLanguages"] as? [String]
            #expect(saved == [language.rawValue])
        }
    }

    @Test func returningToSystemRemovesTheOverride() {
        AppLanguage.russian.save(in: suite.defaults)
        AppLanguage.system.save(in: suite.defaults)
        #expect(AppLanguage.selected(in: suite.defaults) == .system)
        #expect(suite.defaults.persistentDomain(forName: suite.name)?["AppleLanguages"] == nil)
    }

    @Test func russianAndEnglishHaveSeparateUsableResources() throws {
        let russianPath = try #require(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let russian = try #require(Bundle(path: russianPath))
        #expect(russian.localizedString(forKey: "Settings", value: nil, table: nil) == "Настройки")
        #expect(russian.localizedString(forKey: "Cancel", value: nil, table: nil) == "Отмена")
        #expect(russian.localizedString(forKey: "Uninstall with Purge", value: nil, table: "ServicesMenu") == "Удалить с помощью Purge")
        let englishPath = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try #require(Bundle(path: englishPath))
        #expect(english.localizedString(forKey: "Settings", value: "Settings", table: nil) == "Settings")
    }

    @Test func russianCountsUseOneFewAndManyForms() throws {
        let path = try #require(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let russian = try #require(Bundle(path: path))
        for (count, expected) in [(0, "0 элементов"), (1, "1 элемент"), (2, "2 элемента"),
                                  (5, "5 элементов"), (11, "11 элементов"), (21, "21 элемент")] {
            let actual = String(localized: "\(count) items", bundle: russian, locale: Locale(identifier: "ru"))
            #expect(actual == expected)
        }
    }
}
