import Combine
import Foundation
import Testing
import XCTest

@testable import KeyboardKit
import ZislaCore
import ZislaKit

@MainActor
struct KeyboardSoundProfileTests {
    @Test(arguments: [true, false])
    func settingsProfilesFollowAvailableLibraryWhileKeyboardServicesAreDisabled(hasBundledRecordings: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardSoundProfileTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "KeyboardSoundProfileTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "enabled")
        defaults.set(false, forKey: "typingStatsEnabled")
        let library = hasBundledRecordings
            ? SoundPackLibrary(rootURL: directory.appendingPathComponent("packs"))
            : SoundPackLibrary(rootURL: directory.appendingPathComponent("packs"), bundledPackRootURL: nil)
        let expected = try await library.descriptors()
        let model = KeyboardAppModel(
            settings: AppSettings(defaults: defaults),
            permission: InputMonitoringPermissionManager(defaults: defaults),
            soundPackLibrary: library,
            typingStats: TypingStatsModel(persistence: TypingStatsStore(
                databaseURL: directory.appendingPathComponent("stats.sqlite3")
            )),
            startsServices: false
        )
        defer { model.stop() }
        let controller = KeyboardSoundController(model: model)
        let loaded = XCTestExpectation(description: "The settings picker publishes the complete sound library")
        let subscription = controller.$keyboardProfiles
            .filter { $0.count == expected.count }
            .prefix(1)
            .sink { _ in loaded.fulfill() }
        defer { subscription.cancel() }
        let result = await XCTWaiter.fulfillment(of: [loaded], timeout: 5)
        #expect(result == .completed)
        #expect(controller.keyboardProfiles.map(\.id) == expected.map(\.id))
        #expect(controller.keyboardProfiles.count == (hasBundledRecordings ? 23 : 20))
        #expect(controller.keyboardProfiles.contains { $0.name == "WhiteFox Hako Violet" } == hasBundledRecordings)
        #expect(controller.keyboardProfiles.contains { $0.name == "Apple M0118 ALPS SKCM Orange" } == hasBundledRecordings)
        #expect(controller.keyboardProfiles.contains { $0.name == "BCP (Suit80)" } == hasBundledRecordings)
        #expect(model.monitoringState == .stopped)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("stats.sqlite3").path))
    }

    @Test(arguments: AppLanguage.allCases)
    func soundPickerDescriptionDoesNotPromiseAnObsoleteCount(language: AppLanguage) throws {
        let key = "选择机械键盘音色"
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
        let translation = try #require(table[key])
        #expect(!translation.isEmpty)
        #expect(AppLocalization.string(key, language: language) == translation)
        #expect(!translation.contains("20"))
        if language != .simplifiedChinese {
            #expect(translation != key)
        }
    }
}
