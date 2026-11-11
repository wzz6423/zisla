import AppKit
import Testing

@testable import Zisla
import ZislaKit

struct SettingsWindowLevelTests {
    @Test @MainActor
    func standaloneWindowsStayBelowTheIslandWhenKeyStatusChanges() throws {
        let contentRect = CGRect(x: 0, y: 0, width: 548, height: 560)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        let previewController = DailyBriefingPreviewWindowController()
        let windows: [(String, NSWindow)] = [
            ("Settings", SettingsWindow(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)),
            ("System history", SystemMetricsHistoryPanel(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)),
            ("Daily briefing preview", try #require(previewController.window)),
            ("Disk cleanup", SystemCleanupPanel(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)),
        ]
        defer {
            for (_, window) in windows {
                window.contentView = nil
                window.close()
            }
        }
        WindowPlacement.installTransientWindowPromotion()

        for (name, window) in windows {
            window.isReleasedWhenClosed = false
            #expect(!(window is NSPanel), "\(name) must use a regular window")
            #expect(window.sheetParent == nil, "\(name) must be standalone")
            #expect(window.level == .normal, "\(name) must open at the normal level")

            for _ in 0..<2 {
                window.becomeKey()
                NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
                #expect(window.level == .normal, "\(name) must keep the normal level while key")
                #expect(window.level.rawValue < IslandPanel.onTopLevel.rawValue, "The expanded island must stay above \(name)")

                window.resignKey()
                #expect(window.level == .normal, "\(name) must keep the normal level after losing focus")
            }
        }
    }
}
