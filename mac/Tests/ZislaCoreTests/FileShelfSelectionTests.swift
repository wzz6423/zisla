import Foundation
import Testing
@testable import ZislaCore

struct FileShelfSelectionTests {
    private let first = UUID()
    private let second = UUID()
    private let third = UUID()

    @Test func selectingPreservesClickOrderAndReselectingAppends() {
        var selection = FileShelfSelection()
        selection.toggleMode()
        selection.toggle(second)
        selection.toggle(first)
        #expect(selection.actionIDs(availableIDs: [first, second, third]) == [second, first])
        selection.toggle(second)
        selection.toggle(second)
        #expect(selection.ids == [first, second])
        selection.selectAll([second, third, first])
        #expect(selection.ids == [first, second, third])
    }

    @Test func emptySelectionNeverActsOnAllOrOnAnUnselectedContextItem() {
        var selection = FileShelfSelection()
        selection.toggleMode()
        #expect(selection.actionIDs(availableIDs: [first, second]).isEmpty)
        #expect(selection.actionIDs(availableIDs: [first, second], contextID: second).isEmpty)
        selection.toggle(first)
        #expect(selection.actionIDs(availableIDs: [first, second], contextID: second) == [first])
        selection.clear()
        #expect(selection.actionIDs(availableIDs: [first, second]).isEmpty)
    }

    @Test func changingFiltersOrRemovingFilesPrunesWithoutReordering() {
        var selection = FileShelfSelection()
        selection.toggleMode()
        selection.selectAll([third, first, second])
        selection.retainVisible([second, third])
        #expect(selection.ids == [third, second])
        #expect(selection.actionIDs(availableIDs: [second]) == [second])
        selection.retainVisible([])
        #expect(selection.ids.isEmpty)
    }

    @Test func leavingSelectionRestoresWholeShelfAndSingleContextActions() {
        var selection = FileShelfSelection()
        selection.toggle(first)
        selection.selectAll([first])
        #expect(selection.ids.isEmpty)
        #expect(selection.actionIDs(availableIDs: [first, second]) == [first, second])
        #expect(selection.actionIDs(availableIDs: [first, second], contextID: second) == [second])
        #expect(selection.actionIDs(availableIDs: [first], contextID: second).isEmpty)
        selection.toggleMode()
        selection.toggle(first)
        selection.toggleMode()
        #expect(!selection.isSelecting && selection.ids.isEmpty)
        #expect(selection.actionIDs(availableIDs: [first, second]) == [first, second])
    }
}
