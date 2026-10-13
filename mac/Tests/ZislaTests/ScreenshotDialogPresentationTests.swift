import AppKit
import Testing
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenshotDialogMainQueueTests {
    @Test(arguments: [0, 1])
    func ocrResultAllowsMainQueueProgressBeforeItCloses(buttonIndex: Int) async {
        _ = NSApplication.shared
        let alert = NSAlert()
        alert.messageText = "Synthetic OCR result"
        alert.window.alphaValue = 0
        alert.window.isReleasedWhenClosed = false
        let progress = ModalProgress()
        let probe = Timer(timeInterval: 0.01, repeats: true) { timer in
            let observedModal = MainActor.assumeIsolated {
                guard NSApp.modalWindow === alert.window else { return false }
                progress.observedModal = true
                DispatchQueue.main.async {
                    guard NSApp.modalWindow === alert.window else { return }
                    progress.mainQueueRanWhileModal = true
                    alert.buttons[buttonIndex].performClick(nil)
                }
                return true
            }
            if observedModal { timer.invalidate() }
        }
        let watchdog = Timer(timeInterval: 1, repeats: false) { _ in
            MainActor.assumeIsolated {
                NSApp.stopModal(withCode: .abort)
                if let event = NSEvent.otherEvent(
                    with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0
                ) {
                    NSApp.postEvent(event, atStart: true)
                }
            }
        }
        defer {
            probe.invalidate()
            watchdog.invalidate()
            alert.window.close()
        }

        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                RunLoop.main.add(probe, forMode: .modalPanel)
                RunLoop.main.add(watchdog, forMode: .modalPanel)
                ScreenshotDialogPresentation.present(alert) { response in
                    progress.mainQueueRanBeforeCompletion = progress.mainQueueRanWhileModal
                    continuation.resume(returning: response)
                }
            }
        }
        #expect(progress.observedModal, "The probe must reach the real AppKit modal loop")
        #expect(progress.mainQueueRanBeforeCompletion,
                "An OCR result must not prevent the next screenshot's main-queue work from running")
        #expect(response.rawValue == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + buttonIndex)
        #expect(NSApp.modalWindow == nil)
        #expect(!alert.window.isVisible)
    }

    @MainActor
    private final class ModalProgress {
        var observedModal = false
        var mainQueueRanWhileModal = false
        var mainQueueRanBeforeCompletion = false
    }
}

@MainActor
@Suite(.serialized)
struct ScreenshotDialogPresentationTests {
    @Test(arguments: [false, true], [false, true])
    func dialogsAppearBeforeClosingScreenshots(unrelatedWindowIsKey: Bool, accepts: Bool) async throws {
        _ = NSApplication.shared
        let screenshot = makeWindow(screenshot: true, level: .screenSaver)
        let lowerScreenshot = makeWindow(screenshot: true, level: .floating)
        let otherWindow = IslandPanel(contentView: NSView(), frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        otherWindow.allowsKeyWindow = true
        otherWindow.alphaValue = 0
        otherWindow.orderFrontRegardless()
        defer {
            screenshot.close()
            lowerScreenshot.close()
            otherWindow.close()
        }
        if unrelatedWindowIsKey {
            otherWindow.makeKey()
            #expect(NSApp.keyWindow === otherWindow)
        } else {
            #expect(NSApp.keyWindow == nil)
        }

        let panel = SavePanel()
        let alert = Alert()
        panel.isReleasedWhenClosed = false
        alert.window.isReleasedWhenClosed = false
        defer {
            panel.close()
            alert.window.close()
        }
        let screen = try #require(WindowPlacement.screenUnderMouse())
        var saveResponses: [NSApplication.ModalResponse] = []
        ScreenshotDialogPresentation.present(panel) { saveResponses.append($0) }
        #expect(panel.presentedStandalone)
        #expect(panel.levelWhenPresented > screenshot.level.rawValue)
        #expect(panel.sheetParent == nil)
        #expect(abs(panel.frame.midX - screen.visibleFrame.midX) <= 1)
        #expect(abs(panel.frame.midY - screen.visibleFrame.midY) <= 1)
        #expect(saveResponses.isEmpty)
        let saveResponse: NSApplication.ModalResponse = accepts ? .OK : .cancel
        panel.respond(saveResponse)
        #expect(saveResponses == [saveResponse])

        alert.response = accepts ? .alertFirstButtonReturn : .alertSecondButtonReturn
        var alertResponses: [NSApplication.ModalResponse] = []
        await withCheckedContinuation { continuation in
            ScreenshotDialogPresentation.present(alert) {
                alertResponses.append($0)
                continuation.resume()
            }
            #expect(alertResponses.isEmpty)
        }
        #expect(alert.presentedStandalone)
        #expect(alert.levelWhenPresented > screenshot.level.rawValue)
        #expect(alert.window.sheetParent == nil)
        #expect(abs(alert.window.frame.midX - screen.visibleFrame.midX) <= 1)
        #expect(abs(alert.window.frame.midY - screen.visibleFrame.midY) <= 1)
        #expect(alertResponses == [alert.response])

        alert.window.level = .normal
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: alert.window)
        #expect(alert.window.level == .normal, "A completed result must not retain its level observer")

        #expect(screenshot.isVisible)
        #expect(screenshot.level == .screenSaver)
        #expect(lowerScreenshot.isVisible)
        #expect(lowerScreenshot.level == .floating)
        #expect(otherWindow.attachedSheet == nil)
        #expect(screenshot.attachedSheet == nil)
    }

    @Test(arguments: ["no screenshot", "hidden screenshot", "unrelated window", "normal-level screenshot"])
    func dialogsKeepTheNormalModalLevelWhenNoOverlayNeedsIt(scenario: String) async {
        _ = NSApplication.shared
        let window: NSWindow? = scenario == "no screenshot" ? nil : makeWindow(
            screenshot: scenario != "unrelated window",
            level: scenario == "normal-level screenshot" ? .normal : .screenSaver,
            visible: scenario != "hidden screenshot"
        )
        defer { window?.close() }
        let panel = SavePanel()
        let alert = Alert()
        panel.isReleasedWhenClosed = false
        alert.window.isReleasedWhenClosed = false
        defer {
            panel.close()
            alert.window.close()
        }

        ScreenshotDialogPresentation.present(panel) { _ in }
        #expect(panel.levelWhenPresented == WindowPlacement.modalWindowLevel.rawValue)
        panel.respond(.cancel)
        await withCheckedContinuation { continuation in
            ScreenshotDialogPresentation.present(alert) { _ in continuation.resume() }
        }
        #expect(alert.levelWhenPresented == WindowPlacement.modalWindowLevel.rawValue)
    }

    @Test
    func dialogLevelTracksScreenshotChangesBeforePresentation() async {
        _ = NSApplication.shared
        let screenshot = makeWindow(screenshot: true, level: .floating)
        let alert = Alert()
        alert.window.isReleasedWhenClosed = false
        defer {
            screenshot.close()
            alert.window.close()
        }
        await withCheckedContinuation { continuation in
            ScreenshotDialogPresentation.present(alert) { _ in continuation.resume() }
            screenshot.level = .screenSaver
        }
        #expect(alert.levelWhenPresented > screenshot.level.rawValue,
                "The dialog must use the screenshot level at presentation time")
    }

    private func makeWindow(screenshot: Bool, level: NSWindow.Level, visible: Bool = true) -> NSWindow {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        let window = screenshot
            ? ScreenshotEditorWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            : NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.level = level
        if visible { window.orderFrontRegardless() }
        return window
    }

    private final class SavePanel: NSSavePanel {
        var presentedStandalone = false
        var levelWhenPresented = 0
        private var completion: ((NSApplication.ModalResponse) -> Void)?

        override func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
            presentedStandalone = true
            levelWhenPresented = level.rawValue
            completion = handler
        }

        override func beginSheetModal(for window: NSWindow, completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
            levelWhenPresented = level.rawValue
            completion = handler
        }

        func respond(_ response: NSApplication.ModalResponse) {
            let handler = completion
            completion = nil
            handler?(response)
        }
    }

    private final class Alert: NSAlert {
        var presentedStandalone = false
        var levelWhenPresented = 0
        var response = NSApplication.ModalResponse.alertSecondButtonReturn

        override func runModal() -> NSApplication.ModalResponse {
            presentedStandalone = true
            levelWhenPresented = window.level.rawValue
            return response
        }

        override func beginSheetModal(for window: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
            levelWhenPresented = self.window.level.rawValue
            handler?(response)
        }
    }
}
