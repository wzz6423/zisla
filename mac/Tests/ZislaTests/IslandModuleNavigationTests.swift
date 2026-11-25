import Testing
import ZislaCore

@testable import Zisla

struct IslandModuleNavigationTests {
    @Test(arguments: [false, true])
    func adjacentPagesFollowTheEnabledConfiguredOrderAndWrap(isRightToLeft: Bool) throws {
        var settings = FeatureSettings.default
        settings.moduleOrder = [.mail, .battery, .dashboard, .shelf]
        settings.mailEnabled = false
        settings.systemMonitorEnabled = true
        let order = IslandModule.enabledOrder(settings)
        #expect(order.prefix(3) == [.system, .dashboard, .shelf])
        let last = try #require(order.last)
        var navigation = IslandModuleNavigation()
        let rightmost: IslandModule = isRightToLeft ? .system : last
        let leftmost: IslandModule = isRightToLeft ? last : .system

        #expect(navigation.adjacentTarget(in: .previous, selectedModule: leftmost, settings: settings, isRightToLeft: isRightToLeft) == rightmost)
        #expect(navigation.adjacentTarget(in: .next, selectedModule: rightmost, settings: settings, isRightToLeft: isRightToLeft) == leftmost)
        let expectedAfterFirst: IslandModule = isRightToLeft ? last : .dashboard
        #expect(navigation.adjacentTarget(in: .next, selectedModule: .battery, settings: settings, isRightToLeft: isRightToLeft) == expectedAfterFirst)
        #expect(navigation.adjacentTarget(in: .next, selectedModule: .mail, settings: settings, isRightToLeft: isRightToLeft) == expectedAfterFirst,
                "A disabled selection must navigate from the displayed fallback page")
        let selectedLast = navigation.select(rightmost, selectedModule: leftmost, settings: settings, direction: .previous)
        #expect(selectedLast)
        #expect(navigation.direction == -1, "Wrapping left must keep the leftward transition")
        let pendingLast = navigation.takePendingSelection()
        #expect(pendingLast == rightmost)
        let selectedFirst = navigation.select(leftmost, selectedModule: rightmost, settings: settings, direction: .next)
        #expect(selectedFirst)
        #expect(navigation.direction == 1, "Wrapping right must keep the rightward transition")
    }

    @Test
    func rapidCommandsAdvanceFromThePendingPageAndCanReturnToTheCurrentPage() throws {
        let settings = FeatureSettings.default
        let order = IslandModule.enabledOrder(settings)
        let first = try #require(order.first)
        var navigation = IslandModuleNavigation()

        for expected in order.dropFirst().prefix(3) {
            let target = navigation.adjacentTarget(in: .next, selectedModule: first, settings: settings)
            #expect(target == expected, "Each command must advance even before the previous page mounts")
            let selected = navigation.select(target, selectedModule: first, settings: settings, direction: .next)
            #expect(selected)
        }
        let pending = navigation.takePendingSelection()
        #expect(pending == order[3])
        let replay = navigation.takePendingSelection()
        #expect(replay == nil, "A committed selection must not replay")

        let next = navigation.adjacentTarget(in: .next, selectedModule: first, settings: settings)
        let selectedNext = navigation.select(next, selectedModule: first, settings: settings, direction: .next)
        #expect(selectedNext)
        let previous = navigation.adjacentTarget(in: .previous, selectedModule: first, settings: settings)
        #expect(previous == first)
        let selectedPrevious = navigation.select(previous, selectedModule: first, settings: settings, direction: .previous)
        #expect(selectedPrevious)
        let cancelled = navigation.takePendingSelection()
        #expect(cancelled == first, "Opposite commands must cancel the queued page")
    }

    @Test
    func directSelectionKeepsMouseDirectionAndLegacyTargets() {
        let settings = FeatureSettings.default
        var navigation = IslandModuleNavigation()
        let selectedShelf = navigation.select(.shelf, selectedModule: .dashboard, settings: settings)
        #expect(selectedShelf)
        #expect(navigation.direction == 1)
        let repeatedShelf = navigation.select(.shelf, selectedModule: .dashboard, settings: settings)
        #expect(!repeatedShelf)
        let pendingShelf = navigation.takePendingSelection()
        #expect(pendingShelf == .shelf)
        let selectedDashboard = navigation.select(.dashboard, selectedModule: .shelf, settings: settings)
        #expect(selectedDashboard)
        #expect(navigation.direction == -1)
        let pendingDashboard = navigation.takePendingSelection()
        #expect(pendingDashboard == .dashboard)
        let selectedBattery = navigation.select(.battery, selectedModule: .dashboard, settings: settings)
        #expect(selectedBattery)
        let pendingSystem = navigation.takePendingSelection()
        #expect(pendingSystem == .system)
        let repeatedBattery = navigation.select(.battery, selectedModule: .system, settings: settings)
        #expect(!repeatedBattery)
        #expect(navigation.pendingSelection == nil)
        let selectedLockScreen = navigation.select(.lockScreen, selectedModule: .system, settings: settings)
        #expect(selectedLockScreen)
        #expect(navigation.direction == 1, "A direct target outside the configured order must keep the previous direction")
        let pendingLockScreen = navigation.takePendingSelection()
        #expect(pendingLockScreen == .lockScreen)
    }

    @Test
    func singlePageNavigationDoesNotQueueAChange() {
        var settings = FeatureSettings.default
        settings.fileShelfEnabled = false
        settings.contextNotesEnabled = false
        settings.clipboardHistoryEnabled = false
        settings.aiProgressEnabled = false
        settings.downloaderEnabled = false
        settings.calendarEnabled = false
        settings.weatherEnabled = false
        settings.mailEnabled = false
        settings.quickNotesEnabled = false
        settings.volumeMixerEnabled = false
        settings.toolboxEnabled = false
        settings.systemMonitorEnabled = false
        settings.lockScreenInfoEnabled = false
        settings.keyboardEnabled = false
        #expect(IslandModule.enabledOrder(settings) == [.dashboard])
        var navigation = IslandModuleNavigation()
        for direction in [IslandModuleNavigation.Direction.previous, .next] {
            let target = navigation.adjacentTarget(in: direction, selectedModule: .dashboard, settings: settings)
            #expect(target == .dashboard)
            let selected = navigation.select(target, selectedModule: .dashboard, settings: settings, direction: direction)
            #expect(!selected)
            #expect(navigation.pendingSelection == nil)
            #expect(navigation.direction == 1)
        }
    }
}
