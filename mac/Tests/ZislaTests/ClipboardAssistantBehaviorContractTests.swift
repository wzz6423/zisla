import Foundation
import Testing

@testable import Zisla

struct ClipboardAssistantBehaviorContractTests {
    @Test
    func linksAreRoutedOncePerPasteboardChange() throws {
        let source = try String(contentsOf: appModelSourceURL, encoding: .utf8)
        let linkHandler = try sourceSlice(
            in: source,
            from: "clipboardMonitor.onLinkDetected",
            to: "voiceInput.onRecordingWillStart"
        )
        let router = try sourceSlice(
            in: source,
            from: "private func routeCapturedClipboardContent(",
            to: "private func presentClipboardAssistant("
        )

        #expect(linkHandler.contains(
            "let downloadableURL = DownloadURLClassifier.isLikelyDownloadable(url.absoluteString) ? url : nil"
        ))
        #expect(linkHandler.contains(
            "routeCapturedClipboardContent(.text(url.absoluteString), downloadableURL: downloadableURL)"
        ))
        #expect(router.contains("lastClipboardAssistantRoutingChangeCount != changeCount"))
        #expect(router.contains("lastClipboardAssistantRoutingChangeCount = changeCount"))
        #expect(router.contains("case .presented, .ignored:"))
        #expect(router.contains("case .unavailable:"))
        #expect(router.contains("presentDetectedLink(downloadableURL)"))

        let fallback = try sourceSlice(
            in: source,
            from: "private func presentDetectedLink(_ url: URL)",
            to: "private func performClipboardAssistantAction"
        )
        #expect(fallback.contains("setDownloadURL(url.absoluteString)"))
        #expect(fallback.contains("selectModule(.download)"))
        #expect(fallback.contains("detectedLink = url"))
    }

    @Test
    func clipboardLinkDetectionIsIndependentOfDownloader() throws {
        let source = try String(contentsOf: appModelSourceURL, encoding: .utf8)
        let configuration = try sourceSlice(
            in: source,
            from: "if selectedModule == .agenda { refreshAgendaIfEnabled() }",
            to: "// The shared pasteboard monitor"
        )

        #expect(configuration.contains("settings.clipboardDetectionEnabled"))
        #expect(!configuration.contains("settings.downloaderEnabled"))
    }

    @Test
    func actionsPreserveDownloadAndSystemMailConfirmationPaths() throws {
        let source = try String(contentsOf: appModelSourceURL, encoding: .utf8)

        let downloadAction = try sourceSlice(
            in: source,
            from: "case .openDownload(let url):",
            to: "case .revealInFinder"
        )
        #expect(downloadAction.contains("setDownloadURL(url.absoluteString)"))
        #expect(downloadAction.contains("selectModule(.download)"))
        #expect(!downloadAction.contains("startDownload()"))

        let mailFallback = try sourceSlice(
            in: source,
            from: "private func openSystemMail(to address: String)",
            to: "private func compressAssistantFile"
        )
        #expect(mailFallback.contains("NSWorkspace.shared.open(url)"))
        #expect(!mailFallback.contains("com.apple.Mail"))
        #expect(!mailFallback.contains("withApplicationAt"))
    }

    @Test
    func voiceRecordingStartCapturesTheExternalTargetWithoutChangingFocus() throws {
        let source = try String(contentsOf: appModelSourceURL, encoding: .utf8)
        let handler = try sourceSlice(
            in: source,
            from: "voiceInput.onRecordingWillStart = {",
            to: "voiceInput.onTranscriptCompleted = {"
        )

        #expect(handler.contains("let processIdentifier = Self.frontmostVoiceInputTargetProcessIdentifier()"))
        #expect(handler.contains("voiceInputTargetProcessIdentifier = processIdentifier"))
        #expect(handler.contains("voiceInputTarget = processIdentifier.flatMap(VoiceTranscriptDelivery.captureTarget(for:))"))
        #expect(handler.contains("voiceInputTargetMouseLocation = CGEvent(source: nil)?.location"))
        #expect(!handler.contains("requestVoiceInputPostEventAccessIfNeeded"))
        #expect(!handler.contains("WindowPlacement.authorizationPromptHost"))
        #expect(!handler.contains("CGRequestPostEventAccess"))
    }

    @Test
    func voiceRecordingArmsOverlayProtectionBeforeDismissingTheAssistant() throws {
        let appModel = try String(contentsOf: appModelSourceURL, encoding: .utf8)
        let handler = try sourceSlice(
            in: appModel,
            from: "voiceInput.onRecordingWillStart = {",
            to: "voiceInput.onTranscriptCompleted = {"
        )
        let protection = try #require(handler.range(of: "onVoiceInputWillStart?()"))
        let dismissal = try #require(handler.range(of: "clipboardAssistant.dismiss(animated: false)"))

        #expect(protection.lowerBound < dismissal.lowerBound)

        let controller = try String(contentsOf: voiceInputControllerSourceURL, encoding: .utf8)
        let start = try #require(controller.range(of: "func start() {"))
        let stop = try #require(controller[start.upperBound...].range(of: "func stop() {"))
        let startBody = controller[start.lowerBound..<stop.lowerBound]
        let preparing = try #require(startBody.range(of: "isPreparing = true"))
        let callback = try #require(startBody.range(of: "onRecordingWillStart?()"))
        #expect(preparing.lowerBound < callback.lowerBound)
    }

    @Test
    func mouseGestureCancelsDeferredCopyWhenStopped() throws {
        let source = try String(contentsOf: clipboardAssistantSourceURL, encoding: .utf8)
        let monitor = try sourceSlice(
            in: source,
            from: "final class ClipboardAssistantMouseGestureMonitor",
            to: "private func postCommandC()"
        )
        let postCommandCStart = try #require(source.range(of: "private func postCommandC()"))
        let postCommandC = source[postCommandCStart.lowerBound...]

        #expect(monitor.contains("private var commandCCopyTask: Task<Void, Never>?"))
        #expect(monitor.contains("commandCCopyTask?.cancel()"))
        #expect(monitor.contains("copyGeneration &+= 1"))
        #expect(postCommandC.contains("Task.sleep(for: .milliseconds(50))"))
        #expect(postCommandC.contains("self.copyGeneration == generation"))
        #expect(!postCommandC.contains("DispatchQueue.global().asyncAfter"))
        #expect(!postCommandC.contains("usleep("))
    }

    @Test
    func openAppActionLaunchesThroughTheWorkspaceAPI() throws {
        let source = try String(contentsOf: appModelSourceURL, encoding: .utf8)

        let action = try sourceSlice(
            in: source,
            from: "case .openApp(let bundleIdentifier, _):",
            to: "case .revealInFinder"
        )
        #expect(action.contains("openInstalledApplication(bundleIdentifier: bundleIdentifier)"))

        let launcher = try sourceSlice(
            in: source,
            from: "private func openInstalledApplication(bundleIdentifier: String)",
            to: "private func openSystemMail"
        )
        #expect(launcher.contains("NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)"))
        #expect(launcher.contains("NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)"))
        #expect(launcher.contains(#"transientMessage = clipboardAssistantMessage("无法打开应用")"#))

        // The detector only matches names against a published snapshot, so a cold
        // start without the catalog yet must never crash or misclassify.
        #expect(source.contains("installedApplications: installedApplications"))
        #expect(source.contains("startInstalledApplicationCatalog()"))
    }

    private func sourceSlice(in source: String, from start: String, to end: String) throws -> Substring {
        let startRange = try #require(source.range(of: start))
        let endRange = try #require(source[startRange.upperBound...].range(of: end))
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private var appModelSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/AppModel.swift")
    }

    private var voiceInputControllerSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/VoiceInputController.swift")
    }

    private var clipboardAssistantSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/ClipboardAssistantWindowController.swift")
    }
}
