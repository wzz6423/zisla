import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct ClipboardAssistantIslandPresentationTests {
    @MainActor
    @Test
    func promptLayoutKeepsItsOriginUntilTheNextPresentation() throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        let screen = try #require(NSScreen.screens.first)
        var requests: [CGPoint] = []
        controller.screenAtPoint = { requests.append($0); return screen }
        let detection = ClipboardAssistantDetection(kind: .text, title: "saved note")
        let first = CGPoint(x: -100_000, y: -100_000)
        let second = CGPoint(x: -102_000, y: -101_000)
        controller.present(detection, visualStyle: .frosted, at: first)
        let initial = try #require(controller.rowLayout(for: detection))
        #expect(initial.frame.maxY == screen.frame.maxY)
        #expect(controller.rowLayout(for: detection)?.frame == initial.frame)
        #expect(requests == [first, first])
        controller.setScreenLocked(true)
        #expect(controller.present(detection, visualStyle: .frosted, at: second) == nil)
        #expect(controller.rowLayout(for: detection)?.frame == initial.frame)
        #expect(requests.last == first)
        controller.setScreenLocked(false)
        controller.present(detection, visualStyle: .frosted, at: second)
        _ = controller.rowLayout(for: detection)
        #expect(requests.last == second)
        controller.screenAtPoint = { _ in nil }
        #expect(controller.rowLayout(for: detection) == nil)
    }

    @MainActor
    @Test(arguments: [IslandVisualStyle.transparent, .frosted])
    func quickActionBackgroundUpdatesWithoutReplacingThePrompt(
        visualStyle: IslandVisualStyle
    ) async throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        let detection = ClipboardAssistantDetection(kind: .text, title: "copied text")
        controller.present(detection, visualStyle: visualStyle)
        let host = NSHostingView(rootView: ClipboardAssistantToastView(
            presentation: controller.presentation,
            controller: controller
        ).transaction { $0.disablesAnimations = true })
        host.sizingOptions = []
        let panel = ClipboardAssistantController.makeWindow(
            contentView: host,
            frame: CGRect(x: -100_000, y: -100_000, width: 533, height: 37)
        )
        defer { panel.close() }

        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        for background in [IslandNotchBackground.black, .frosted, .black, .frosted] {
            controller.presentation.notchBackground = background
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            var effects: [NSVisualEffectView] = []
            var pending = [host as NSView]
            while let view = pending.popLast() {
                if let effect = view as? NSVisualEffectView { effects.append(effect) }
                pending.append(contentsOf: view.subviews)
            }
            if background == .frosted && !reduceTransparency {
                let effect = try #require(effects.first, "磨砂背景应随设置切换立即出现")
                #expect(effect.material == .popover)
                #expect(effect.blendingMode == .behindWindow)
                #expect(effect.alphaValue == 0.92)
            } else {
                #expect(effects.isEmpty, "刘海纯色或降低透明度时不应使用磨砂材质")
            }
            #expect(controller.presentation.detection == detection)
            #expect(controller.presentation.visualStyle == visualStyle)
            #expect(!panel.isVisible)
        }
    }

    @MainActor
    @Test(arguments: [false, true])
    func quickNoteCopyIsCapturedBeforeTheFoldFinishes(alreadyCollapsing: Bool) throws {
        let pasteboard = NSPasteboard(name: .init("dev.wzz.zisla.tests.quick-note-handoff.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var handoff = IslandClipboardHandoff()
        var captures = 0
        let monitor = ClipboardHistoryMonitor(pasteboard: pasteboard, pollInterval: 3600) { content in
            #expect(handoff.shouldDefer, "The capture must stay queued until the island finishes folding")
            captures += 1
            handoff.hold(.init(content: content, downloadableURL: nil, changeCount: pasteboard.changeCount))
        }
        monitor.setEnabled(true)
        defer { monitor.setEnabled(false) }
        if alreadyCollapsing {
            handoff.beginRecycle()
        } else {
            handoff.noteDidCopy()
        }
        #expect(ClipboardHistoryPasteboard.write(.text("copied note"), to: pasteboard))

        monitor.pollNow()

        let result = handoff.finishRecycle(currentChangeCount: pasteboard.changeCount)
        let pending = try #require(result)
        #expect(pending.content == .text("copied note"), "The fold must not finish waiting for the next periodic clipboard poll")
        monitor.pollNow()
        #expect(captures == 1, "The next periodic poll must not present the same copy again")
    }

    @Test
    func quickNoteCopyWaitsForTheFoldAndKeepsTheNewestCapture() {
        var handoff = IslandClipboardHandoff()
        handoff.noteDidCopy()
        #expect(handoff.shouldDefer)

        handoff.hold(.init(content: .text("first"), downloadableURL: nil, changeCount: 10))
        handoff.beginRecycle()
        handoff.hold(.init(content: .text("latest"), downloadableURL: nil, changeCount: 11))

        let pending = handoff.finishRecycle(currentChangeCount: 11)
        #expect(pending?.content == .text("latest"))
        #expect(!handoff.shouldDefer)
    }

    @Test
    func reExpansionAndNewPasteboardChangesDiscardStaleHandoffs() {
        var handoff = IslandClipboardHandoff()
        handoff.beginRecycle()
        #expect(handoff.shouldDefer)
        handoff.hold(.init(content: .text("old"), downloadableURL: nil, changeCount: 3))
        #expect(handoff.finishRecycle(currentChangeCount: 4) == nil)

        handoff.noteDidCopy()
        handoff.hold(.init(content: .text("cancelled"), downloadableURL: nil, changeCount: 5))
        handoff.cancel()
        #expect(!handoff.shouldDefer)
        #expect(handoff.finishRecycle(currentChangeCount: 5) == nil)
    }

    @MainActor
    @Test(.serialized, arguments: [false, true], [
        (hasPhysicalNotch: false, progressGlowEnabled: false),
        (hasPhysicalNotch: false, progressGlowEnabled: true),
        (hasPhysicalNotch: true, progressGlowEnabled: false),
        (hasPhysicalNotch: true, progressGlowEnabled: true),
    ])
    func buttonsDismissThePromptWithoutTakingFocus(
        performsPrimaryAction: Bool,
        configuration: (hasPhysicalNotch: Bool, progressGlowEnabled: Bool)
    ) throws {
        _ = NSApplication.shared
        let wasActive = NSApp.isActive
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = configuration.progressGlowEnabled ? .fiveSeconds : .never
        controller.presentation.islandTopHeight = 37
        controller.presentation.physicalNotchWidth = configuration.hasPhysicalNotch ? 185 : 0
        controller.presentation.progressGlowEnabled = configuration.progressGlowEnabled
        controller.present(ClipboardAssistantDetection(
            kind: .nonSystemLanguageText,
            title: "copied text",
            detail: .characterAndWordCount(characters: 1726, words: 27),
            actions: [.translate("copied text")]
        ), visualStyle: .transparent)
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        let host = NSHostingView(rootView: ClipboardAssistantToastView(
            presentation: controller.presentation,
            controller: controller
        ).environment(\.locale, Locale(identifier: "zh-Hans")))
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        let panel = ClipboardAssistantController.makeWindow(
            contentView: host,
            frame: CGRect(x: -100_000, y: -100_000, width: 533, height: 37)
        )
        defer { panel.close() }
        #expect(!panel.hasShadow)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(panel.frame) })
        // SwiftUI installs its event graph only after the window is ordered in.
        panel.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let point = CGPoint(x: performsPrimaryAction ? 443 : 509, y: 18.5)
        let down = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: down.timestamp + 0.1,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ))
        panel.sendEvent(down)
        panel.sendEvent(up)

        #expect(controller.presentation.detection == nil)
        #expect(actions == (performsPrimaryAction ? [.translate("copied text")] : []))
        #expect(!panel.isKeyWindow)
        #expect(!panel.canBecomeKey)
        #expect(NSApp.isActive == wasActive)
    }

    @Test
    func physicalNotchHeaderReservesTheHardwareCutout() {
        #expect(ClipboardAssistantToastView.physicalNotchSideWidth(totalWidth: 480, notchWidth: 185) == 147.5)
        #expect(ClipboardAssistantToastView.physicalNotchSideWidth(totalWidth: 480, notchWidth: 640) == 0)
    }

    @Test
    func physicalNotchRowExpandsForTrailingControls() {
        let width = ClipboardAssistantToastView.requiredRowWidth(
            baseWidth: 480,
            maximumWidth: 900,
            notchWidth: 185,
            trailingControlsWidth: 174
        )
        #expect(width == 533)
        #expect(ClipboardAssistantToastView.physicalNotchSideWidth(totalWidth: width, notchWidth: 185) == 174)
        #expect(ClipboardAssistantToastView.requiredRowWidth(
            baseWidth: 480,
            maximumWidth: 900,
            notchWidth: 0,
            trailingControlsWidth: 174
        ) == 480)
    }

    @Test
    func assistantCompressionCreatesAZIPArchive() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-archive-\(UUID().uuidString)", isDirectory: true)
        let source = directory.appendingPathComponent("example.txt")
        let archive = directory.appendingPathComponent("example.zip")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("archive me".utf8).write(to: source)
        #expect(await AppModel.zipArchiveError(source: source, destination: archive) == nil)
        #expect(FileManager.default.fileExists(atPath: archive.path))
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, source.lastPathComponent]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "archive me")

        let folder = directory.appendingPathComponent("folder", isDirectory: true)
        let nestedFile = folder.appendingPathComponent("nested.txt")
        let folderArchive = directory.appendingPathComponent("folder.zip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: nestedFile)
        #expect(await AppModel.zipArchiveError(source: folder, destination: folderArchive) == nil)
        let folderProcess = Process()
        let folderOutput = Pipe()
        folderProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        folderProcess.arguments = ["-p", folderArchive.path, "folder/nested.txt"]
        folderProcess.standardOutput = folderOutput
        try folderProcess.run()
        folderProcess.waitUntilExit()
        #expect(folderProcess.terminationStatus == 0)
        #expect(String(decoding: folderOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "nested")
    }

    @Test
    func capturedImagePayloadProducesASharingImage() throws {
        let pngData = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        ))
        #expect(TransferDropItem.image(pngData).shareValue is NSImage)
    }

    @MainActor
    @Test
    func sharingKeepsTheClipboardAssistantAnchorAlive() {
        let controller = ClipboardAssistantController()
        controller.presentation.detection = ClipboardAssistantDetection(
            kind: .file,
            title: "folder",
            actions: [.share]
        )

        controller.perform(.share)
        controller.setHovered(false)

        #expect(controller.presentation.detection != nil)
    }

    @MainActor
    @Test
    func actionsDismissEvenWhenAutomaticDismissalIsDisabled() {
        let controller = ClipboardAssistantController()
        controller.displayDuration = .never
        controller.presentation.detection = ClipboardAssistantDetection(
            kind: .text,
            title: "text",
            actions: [.copyText("text")]
        )

        controller.perform(.copyText("text"))

        #expect(controller.presentation.detection == nil)
    }

    @MainActor
    @Test
    func screenshotSessionsKeepThePromptInsteadOfCancellingIt() throws {
        let controller = ClipboardAssistantController()
        controller.displayDuration = .never
        controller.presentation.detection = ClipboardAssistantDetection(
            kind: .text,
            title: "text",
            actions: [.copyText("text")]
        )

        controller.setScreenshotActive(true)
        controller.setScreenshotSelectionActive(true)
        #expect(controller.presentation.detection != nil)

        controller.setScreenshotSelectionActive(false)
        controller.setScreenshotActive(false)
        #expect(controller.presentation.detection != nil)
    }

    @MainActor
    @Test
    func screenshotSessionDoesNotRestartDismissalAfterTheHiddenWindowReportsHoverExit() async throws {
        let controller = ClipboardAssistantController()
        controller.displayDuration = .threeSeconds
        controller.presentation.detection = ClipboardAssistantDetection(
            kind: .text,
            title: "text",
            actions: [.copyText("text")]
        )

        controller.setScreenshotActive(true)
        controller.setHovered(false)
        try await Task.sleep(for: .milliseconds(3_200))

        #expect(controller.presentation.detection != nil)
        controller.displayDuration = .never
        controller.setScreenshotActive(false)
    }

    @MainActor
    @Test
    func imageThumbnailUsesImageActionEvenWhenItIsNotPrimary() throws {
        let pngData = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        ))
        let detection = ClipboardAssistantDetection(
            kind: .image,
            title: "image",
            actions: [.copyText("metadata"), .saveImage(pngData)]
        )

        #expect(ClipboardAssistantController.thumbnail(for: detection) != nil)
    }

    @MainActor
    @Test
    func screenshotPhasesCloseMoreActionsOnlyWhenTheLiveWindowLeaves() {
        let controller = ClipboardAssistantController()

        controller.setMoreActionsPresented(true)
        #expect(controller.isMoreActionsPresented)

        controller.setScreenshotActive(true)
        #expect(controller.isMoreActionsPresented)

        controller.setScreenshotSelectionActive(true)
        #expect(!controller.isMoreActionsPresented)

        controller.setScreenshotSelectionActive(false)
        controller.setScreenshotActive(false)
        controller.setMoreActionsPresented(true)
        controller.setSystemScreenshotActive(true)
        #expect(!controller.isMoreActionsPresented)
        controller.setSystemScreenshotActive(false)
    }

    @Test
    func systemScreenshotSessionTracksTheLauncherAndCaptureUI() {
        #expect(SystemScreenshotSession.matches(bundleIdentifier: "com.apple.screencaptureui"))
        #expect(SystemScreenshotSession.matches(bundleIdentifier: "com.apple.screenshot.launcher"))
        #expect(!SystemScreenshotSession.matches(bundleIdentifier: "com.apple.ScreenCapture"))

        var session = SystemScreenshotSession(missingWindowPollLimit: 2)
        var result = session.applicationStarted(processIdentifier: 101)
        #expect(result)
        #expect(session.isActive)

        result = session.applicationStarted(processIdentifier: 101)
        #expect(!result)
        result = session.updateWindowVisibility(false, hasRunningProcess: true)
        #expect(!result)
        #expect(session.isActive)
        result = session.updateWindowVisibility(false, hasRunningProcess: true)
        #expect(!result)
        #expect(session.isActive)
        result = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(!result)
        #expect(session.isActive)
        result = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(result)
        #expect(!session.isActive)
    }

    @Test @MainActor
    func systemScreenshotPollingReducesWakeupsWithoutExtendingDismissalGracePeriod() {
        #expect(SystemScreenshotMonitor.pollInterval == .milliseconds(100))
        #expect(SystemScreenshotSession.defaultMissingWindowPollLimit == 3)
    }

    @Test
    func systemScreenshotSessionDropsStaleProcessIdentifiersAfterTheWindowGracePeriod() {
        var session = SystemScreenshotSession(missingWindowPollLimit: 2)
        _ = session.applicationStarted(processIdentifier: 606)

        #expect(session.activeProcessIdentifiers == [606])
        let firstUpdate = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(!firstUpdate)
        let secondUpdate = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(secondUpdate)

        #expect(!session.isActive)
        #expect(session.activeProcessIdentifiers.isEmpty)
    }

    @Test
    func systemScreenshotSessionStaysActiveAcrossLauncherToCaptureUIHandoff() {
        var session = SystemScreenshotSession(missingWindowPollLimit: 2)
        var result = session.applicationStarted(processIdentifier: 101)
        #expect(result)

        session.applicationTerminated(processIdentifier: 101)
        result = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(!result)
        #expect(session.isActive)

        result = session.applicationStarted(processIdentifier: 202)
        #expect(!result)
        #expect(session.isActive)

        session.applicationTerminated(processIdentifier: 202)
        result = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(!result)
        result = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(result)
        #expect(!session.isActive)
    }

    @Test
    func systemScreenshotSessionKeepsActiveWhileProcessRunsEvenWithoutVisibleWindow() {
        var session = SystemScreenshotSession(missingWindowPollLimit: 3)
        var result = session.applicationStarted(processIdentifier: 303)
        #expect(result)
        #expect(session.isActive)

        for _ in 0..<10 {
            result = session.updateWindowVisibility(false, hasRunningProcess: true)
            #expect(!result)
            #expect(session.isActive)
        }

        result = session.updateWindowVisibility(true, hasRunningProcess: true)
        #expect(!result)
        #expect(session.isActive)

        session.applicationTerminated(processIdentifier: 303)
        result = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(!result)
        result = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(!result)
        result = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(result)
        #expect(!session.isActive)
    }

    @Test
    func systemScreenshotSessionWaitsForVisibleUIToDisappear() {
        var session = SystemScreenshotSession(missingWindowPollLimit: 2)
        var result = session.applicationStarted(processIdentifier: 202)
        #expect(result)
        result = session.updateWindowVisibility(true, hasRunningProcess: true)
        #expect(!result)
        #expect(session.isActive)

        session.applicationTerminated(processIdentifier: 202)
        #expect(session.activeProcessIdentifiers.isEmpty)
        result = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(!result)
        #expect(session.isActive)
        result = session.updateWindowVisibility(false, hasRunningProcess: false)
        #expect(result)
        #expect(!session.isActive)
    }

    @Test
    func systemScreenshotWindowDetectorAcceptsOverlayWindowsAtAnyLevel() {
        let candidates = [
            SystemScreenshotWindowCandidate(
                ownerProcessIdentifier: 404,
                alpha: 1,
                bounds: CGRect(x: 0, y: 0, width: 1_440, height: 900)
            ),
            SystemScreenshotWindowCandidate(
                ownerProcessIdentifier: 505,
                alpha: 0,
                bounds: CGRect(x: 20, y: 20, width: 200, height: 100)
            ),
        ]

        #expect(SystemScreenshotWindowDetector.hasVisibleSystemScreenshotWindow(
            candidates,
            ownedBy: [404]
        ))
        #expect(!SystemScreenshotWindowDetector.hasVisibleSystemScreenshotWindow(
            candidates,
            ownedBy: [505]
        ))
        #expect(!SystemScreenshotWindowDetector.isEligibleOwner(
            processIdentifier: 404,
            ownedBy: [404],
            currentBundleIdentifier: "com.apple.TextEdit",
            processIsRunning: true
        ))
        #expect(SystemScreenshotWindowDetector.isEligibleOwner(
            processIdentifier: 404,
            ownedBy: [404],
            currentBundleIdentifier: "com.apple.screencaptureui",
            processIsRunning: true
        ))
    }

    @Test
    func clipboardAssistantDismissalKeepsTheCollapsedStatusBarHidden() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/ZislaApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let handlerStart = try #require(source.range(of: "model.clipboardAssistant.onPresentationChanged"))
        let handlerEnd = try #require(
            source[handlerStart.upperBound...].range(of: "coordinator.setPersistentContentVisible")
        )
        let handler = source[handlerStart.lowerBound..<handlerEnd.lowerBound]
        // Dismissal must not clear the expanded island's suppression of the collapsed status bar.
        #expect(handler.contains("setClipboardAssistantVisible(visible)"))
        #expect(!handler.contains("setIslandExpanded"))
    }

}
