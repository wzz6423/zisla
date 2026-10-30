 import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct IslandDashboardViewLayoutTests {
    @Test
    func dashboardCapsHeightAtKeyboardSurfaceHeight() {
        let layout = IslandModuleLayout.resolved(for: .dashboard, dashboardCardCount: 100)

        #expect(layout.islandSize.height == IslandModuleLayout.keyboardSound.islandSize.height)
        #expect(layout.panelSize.height == IslandModuleLayout.keyboardSound.panelSize.height)
    }

    @Test @MainActor
    func recordingOperationsAddAndRemoveDashboardRows() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        queue.enqueue(IslandNotice(id: "browser-download-left", title: "Download"), expiresAfter: nil)
        #expect(queue.screenRecordingOperations.count == 0)
        queue.enqueue(IslandNotice(id: "screen-recording-operation-save", title: "Save"), expiresAfter: nil)
        #expect(queue.screenRecordingOperations.count == 1)
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: 2 + queue.screenRecordingOperations.count) == 2)
        queue.remove(id: "screen-recording-operation-save")
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: 2 + queue.screenRecordingOperations.count) == 1)
    }

}
