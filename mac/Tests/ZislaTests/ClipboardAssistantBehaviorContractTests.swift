import Foundation
import Testing

@testable import Zisla

struct ClipboardAssistantBehaviorContractTests {
    @Test
    func downloadableLinksAreRoutedOncePerPasteboardChange() throws {
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

        #expect(linkHandler.contains("routeCapturedClipboardContent(.text(url.absoluteString), downloadableURL: url)"))
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
        #expect(fallback.contains("downloadURL = url.absoluteString"))
        #expect(fallback.contains("selectModule(.download)"))
        #expect(fallback.contains("detectedLink = url"))
    }

    @Test
    func actionsPreserveDownloadAndSystemMailConfirmationPaths() throws {
        let source = try String(contentsOf: appModelSourceURL, encoding: .utf8)

        let downloadAction = try sourceSlice(
            in: source,
            from: "case .openDownload(let url):",
            to: "case .revealInFinder"
        )
        #expect(downloadAction.contains("downloadURL = url.absoluteString"))
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
}
