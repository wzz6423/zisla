import AppKit
import Combine
import Testing
import XCTest
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct IslandPetControllerTests {
    @Test
    func islandUsesTheDailyPetAcrossLifecycleAndLibraryChanges() async throws {
        let suite = "IslandPetControllerTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pets = root.appendingPathComponent("pets", isDirectory: true)
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let imported = try await PetMediaImporter.importPet(
            from: package.appendingPathComponent("Resources/Pets/bear/sprite.png"), name: "Test pet", directory: pets
        )
        let notifications = NotificationCenter()
        let workspace = NotificationCenter()
        let monitor = AIStateMonitor(directoryURL: root, activityDetectors: [])
        let store = FeatureSettingsStore(defaults: defaults)
        let fixedID = "kirby"
        store.settings = FeatureSettings(petID: fixedID, petSelectionMode: .randomRotation, petRandomPool: [imported.id])
        var now = Date()
        var dateReads = 0
        let controller = IslandPetController(settingsStore: store, aiMonitor: monitor, userPetsDirectory: pets) {
            dateReads += 1
            return now
        }
        controller.start(notificationCenter: notifications, workspaceNotificationCenter: workspace)
        defer { controller.stop() }

        let initial = try #require(store.petRotationSelection)
        #expect(initial.petID == imported.id)
        #expect(controller.sprite?.frames == 1)
        #expect(controller.currentPetID == imported.id)
        store.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: defaults).petRotationSelection == initial)
        let readsAtStart = dateReads
        store.settings.petSide = .right
        await deliverNotifications()
        #expect(dateReads == readsAtStart)
        store.settings.petRandomPool = [imported.id, fixedID]
        await deliverNotifications()
        #expect(store.petRotationSelection == initial)

        for (center, name) in [
            (workspace, NSWorkspace.didWakeNotification), (notifications, .NSCalendarDayChanged),
            (notifications, .NSSystemClockDidChange), (notifications, .NSSystemTimeZoneDidChange),
        ] {
            let previous = try #require(store.petRotationSelection?.petID)
            now.addTimeInterval(2 * 86_400)
            center.post(name: name, object: nil)
            await deliverNotifications()
            let today = try #require(store.petRotationSelection?.petID)
            #expect(today == (previous == imported.id ? fixedID : imported.id))
            let sprite = try #require(PetLibrary.loadSprite(for: today, userPetsDirectory: pets))
            #expect(controller.sprite?.image.tiffRepresentation == sprite.image.tiffRepresentation)
        }

        try FileManager.default.removeItem(at: pets.appendingPathComponent(imported.id))
        notifications.post(name: .petLibraryDidChange, object: nil)
        await deliverNotifications()
        #expect(store.settings.petRandomPool == [fixedID])
        #expect(store.petRotationSelection?.petID == fixedID)

        store.settings.petSelectionMode = .fixed
        store.settings.petID = "bear"
        await deliverNotifications()
        #expect(controller.sprite?.frames == 1)
        #expect(store.petRotationSelection?.petID == fixedID)
        store.reset()
        await deliverNotifications()
        #expect(store.petRotationSelection == nil)
        store.settings.petSelectionMode = .randomRotation
        await deliverNotifications()
        let resetWinner = try #require(store.petRotationSelection)
        #expect(controller.currentPetID == resetWinner.petID)
        #expect(FeatureSettingsStore(defaults: defaults).petRotationSelection == resetWinner)
        store.settings.petSelectionMode = .fixed
        controller.stop()
        await deliverNotifications()
        #expect(controller.sprite == nil)
        #expect(store.settings.petID == FeatureSettings.default.petID)
    }

    @Test
    func debugSecondsAcceptPositiveIntegersOnlyInTheDebugApp() {
        for value in ["1", "2", "5"] {
            let env = ["ZISLA_DEBUG_PET_ROTATION_SECONDS": value]
            #expect(IslandPetController.debugRotationInterval(environment: env, isDebugBuild: true) == Double(value))
            #expect(IslandPetController.debugRotationInterval(environment: env, isDebugBuild: false) == nil)
        }
        for value in ["", "0", "-1", "2.5", "nan", "1s", "18446744074", "9223372036854775808", "18446744073709551616"] {
            #expect(IslandPetController.debugRotationInterval(
                environment: ["ZISLA_DEBUG_PET_ROTATION_SECONDS": value], isDebugBuild: true
            ) == nil)
        }
        #expect(IslandPetController.debugRotationInterval(environment: [:], isDebugBuild: true) == nil)
    }

    @Test(arguments: [false, true])
    func timerRotatesWithoutNotificationsAndCancelsForFixedModeOrOnePet(debug: Bool) async throws {
        let suite = "IslandPetTimerTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60))
        let reference = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let clock = ContinuousClock()
        var startedAt: ContinuousClock.Instant?
        let original = try #require(PetRotationSelection.resolve(previous: nil, candidates: ["bear"],
                                                                 interval: debug ? nil : 1, at: reference))
        store.petRotationSelection = original
        store.settings = FeatureSettings(petID: "chiikawa", petSelectionMode: .randomRotation,
                                         petRandomPool: ["bear", "kirby"], petRotationInterval: debug ? 3_661 : 1)
        store.flushPendingChanges()
        let savedSettings = try #require(defaults.data(forKey: "feature-settings-v1"))
        var reads = 0
        let controller = IslandPetController(
            settingsStore: store, aiMonitor: AIStateMonitor(directoryURL: root, activityDetectors: []),
            userPetsDirectory: root, environment: ["ZISLA_DEBUG_PET_ROTATION_SECONDS": debug ? "1" : "invalid"],
            isDebugBuild: true
        ) {
            reads += 1
            guard let startedAt else {
                startedAt = clock.now
                return reference
            }
            let elapsed = startedAt.duration(to: clock.now).components
            return reference.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        }
        controller.start(notificationCenter: NotificationCenter(), workspaceNotificationCenter: NotificationCenter())
        defer { controller.stop() }
        #expect(controller.currentPetID == "bear")

        var changedTo: String?
        let didRotate = XCTestExpectation(description: "The island publishes the next pet")
        var settingsPublications = 0
        let writes = store.$settings.dropFirst().sink { _ in settingsPublications += 1 }
        defer { writes.cancel() }
        let change = controller.$currentPetID.compactMap { $0 }.first { $0 != "bear" }.sink { id in
            #expect(settingsPublications == 0)
            changedTo = id
            if debug {
                store.settings.petSelectionMode = .fixed
            } else {
                store.settings.petRandomPool = [id]
            }
            didRotate.fulfill()
        }
        defer { change.cancel() }
        #expect(await XCTWaiter.fulfillment(of: [didRotate], timeout: 30) == .completed)
        #expect(changedTo == "kirby")
        await deliverNotifications()
        #expect(store.petRotationSelection?.petID == (debug ? "bear" : "kirby"))
        if debug { #expect(store.petRotationSelection == original) }
        #expect(defaults.data(forKey: "feature-settings-v1") == savedSettings)
        #expect(FeatureSettingsStore(defaults: defaults).petRotationSelection == store.petRotationSelection)

        let expectedID = debug ? "chiikawa" : "kirby"
        #expect(controller.currentPetID == expectedID)
        let readsBeforeWait = reads
        try await Task.sleep(for: .milliseconds(1_150))
        #expect(reads == readsBeforeWait)
        #expect(controller.currentPetID == expectedID)

        store.settings.petSelectionMode = .randomRotation
        store.settings.petRandomPool = ["bear", "kirby"]
        await deliverNotifications()
        controller.stop()
        let readsAfterStop = reads
        try await Task.sleep(for: .milliseconds(1_150))
        #expect(reads == readsAfterStop)
        #expect(controller.currentPetID == nil)
        #expect(controller.sprite == nil)
    }

    private func deliverNotifications() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
