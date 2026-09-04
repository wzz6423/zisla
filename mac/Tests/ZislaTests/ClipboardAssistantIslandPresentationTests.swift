import AppKit
import Foundation
import Testing
import ZislaCore

@testable import Zisla

struct ClipboardAssistantIslandPresentationTests {
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
    func clipboardAssistantSharesEveryCapturedPayload() throws {
        let appModelSource = try String(contentsOf: appModelSourceURL, encoding: .utf8)
        #expect(appModelSource.contains("detection.actions.append(.share)"))
        #expect(appModelSource.contains("case .share:"))
        #expect(appModelSource.contains("[.image(data)]"))
        #expect(appModelSource.contains("guard let anchor = clipboardAssistant.sharingAnchorView"))
        #expect(appModelSource.contains("share(items, from: anchor)"))
        #expect(appModelSource.contains("isSharingPickerVisible = anchor.window is IslandPanel"))
        #expect(appModelSource.contains("if dismissesClipboardAssistant { clipboardAssistant.dismiss() }"))

        let pngData = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        ))
        #expect(TransferDropItem.image(pngData).shareValue is NSImage)
    }

    @Test
    func sharingDefersAssistantDismissalToTheSystemPicker() throws {
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let actionStart = try #require(source.range(of: "func perform(_ action: ClipboardAssistantAction)"))
        let actionEnd = try #require(source[actionStart.upperBound...].range(of: "func performCurrentAction"))
        let actionSource = source[actionStart.lowerBound..<actionEnd.lowerBound]

        #expect(actionSource.contains("if case .share = action"))
        #expect(actionSource.contains("isSharingAnchorHeld = true"))
        #expect(actionSource.contains("cancelDismissTask()"))
        #expect(actionSource.contains("guard !isSharingAnchorHeld else { return }"))
        #expect(source.contains("guard !isSharingAnchorHeld else { return }"))
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

        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let phaseStart = try #require(source.range(of: "private func applyScreenshotPhase()"))
        let phaseSource = source[phaseStart.lowerBound...]
        // Keep visible during capturing so it appears in the frozen screenshot.
        // Hide only when the selection overlay renders the frozen capture.
        #expect(phaseSource.contains("let hidesLiveWindow = screenshotPhase == .selecting || isSystemScreenshotActive"))
        #expect(phaseSource.contains("window.ignoresMouseEvents = hidesLiveWindow"))
        #expect(phaseSource.contains("window.level = ClipboardAssistantWindow.defaultWindowLevel"))
        #expect(phaseSource.contains("if hidesLiveWindow {"))
        #expect(phaseSource.contains("window.orderOut(nil)"))
        #expect(phaseSource.contains("screenshotPhase == .restored || screenshotPhase == .inactive"))
        #expect(!source.contains("aboveScreenshotSelectionLevel"))
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
    func capturingPhaseKeepsWindowVisibleForFrozenScreenshot() throws {
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let phaseStart = try #require(source.range(of: "private func applyScreenshotPhase()"))
        let phaseEnd = try #require(source[phaseStart.upperBound...].range(of: "\n    }"))
        let phaseImpl = source[phaseStart.lowerBound..<phaseEnd.upperBound]

        // Capturing phase should NOT hide the window - it stays visible for the frozen capture
        #expect(!phaseImpl.contains("screenshotPhase == .capturing"))
        #expect(phaseImpl.contains("let hidesLiveWindow = screenshotPhase == .selecting || isSystemScreenshotActive"))

        let enumStart = try #require(source.range(of: "private enum ScreenshotPhase"))
        let enumSource = source[enumStart.lowerBound...]
        #expect(enumSource.contains("/// The display is about to be frozen; the row stays visible"))
        #expect(enumSource.contains("case capturing"))
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
    func systemScreenshotMonitorUsesVisibleWindowsBeforeRestoringTheIsland() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Zisla/SystemScreenshotMonitor.swift"),
            encoding: .utf8
        )

        #expect(source.contains("NSWorkspace.didActivateApplicationNotification"))
        #expect(source.contains("publishIfNeeded(session.applicationStarted"))
        #expect(source.contains("CGWindowListCopyWindowInfo"))
        #expect(source.contains("[.optionOnScreenOnly, .excludeDesktopElements]"))
        #expect(source.contains("kCGWindowOwnerPID"))
        #expect(source.contains("SystemScreenshotWindowDetector.hasVisibleSystemScreenshotWindow"))
        #expect(source.contains("let hasVisibleWindow = !hasRunningProcess"))
        #expect(source.contains("onScreenWindowCandidates(ownedBy: processIdentifiers)"))
        #expect(source.contains("SystemScreenshotWindowDetector.isEligibleOwner("))
        #expect(source.contains("currentBundleIdentifier: application?.bundleIdentifier"))
        #expect(!source.contains("layer == 0"))
        #expect(source.contains("private var windowPollingTask: Task<Void, Never>?"))
        #expect(source.contains("windowPollingTask?.cancel()"))
        #expect(source.contains("Task.detached(priority: .utility)"))

        let refreshStart = try #require(source.range(of: "private func refreshWindowVisibility"))
        let refreshSource = source[refreshStart.lowerBound...]
        #expect(!refreshSource.contains("workspace.runningApplications"))
    }

    @Test
    func clipboardAssistantReusesTheIslandSurfaceWithoutWindowChrome() throws {
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let toastStart = try #require(source.range(of: "struct ClipboardAssistantToastView: View"))
        let toastSource = source[toastStart.lowerBound...]

        #expect(toastSource.contains("IslandSurface("))
        #expect(toastSource.contains("isCollapsed: !isExpanded"))
        #expect(toastSource.contains("visualStyle: presentation.visualStyle"))
        #expect(toastSource.contains("collapsedTopCornerRadius: 0"))
        #expect(toastSource.contains("bottomCornerRadius: VoiceRecordingIslandGeometry.bottomCornerRadius"))
        #expect(!toastSource.contains("usesCompactGlassSurface: true"))
        #expect(!toastSource.contains("Color.black.opacity(0.86)"))
        #expect(toastSource.contains(".popover(isPresented: Binding("))
        #expect(toastSource.contains("moreActionsPopover(for: detection)"))
        #expect(toastSource.contains("controller.setMoreActionsPresented("))
        #expect(!toastSource.contains("showActionsMenu(for: detection)"))
        #expect(!toastSource.contains("Menu {\n                        actionMenuItems(menuActions(for: detection))"))
        #expect(toastSource.contains("if detection.action != nil"))
        #expect(toastSource.contains("private func menuActions(for detection"))
        #expect(toastSource.contains("private func moreActionsPopover(for detection"))
        #expect(toastSource.contains("if case .blockSourceApp = action"))
        #expect(toastSource.contains("Image(systemName: \"chevron.down.circle\")"))
        #expect(!toastSource.contains("Image(systemName: \"ellipsis.circle\")"))
        #expect(toastSource.contains("guard ![.url, .text, .nonSystemLanguageText, .code, .math].contains(detection.kind)"))
        #expect(toastSource.contains(".onDrag { NSItemProvider(object: dragText as NSString) }"))
        #expect(toastSource.contains("private func dragText(for detection"))
        let headerContentStart = try #require(toastSource.range(of: "private func headerContent"))
        let headerContentEnd = try #require(toastSource[headerContentStart.upperBound...]
            .range(of: "private func leadingAccessory"))
        let headerContentSource = toastSource[headerContentStart.lowerBound..<headerContentEnd.lowerBound]
        #expect(headerContentSource.contains("guard controller.isLightweightMode else { return }"))
        #expect(!headerContentSource.contains("toggleExpansion(detection)"))
        #expect(source.contains("hasShadow = false"))
        #expect(source.contains("hostingView.layer?.backgroundColor = NSColor.clear.cgColor"))
        #expect(source.contains("let layout = screenSnapshot.map { ScreenLayoutEngine().layout(for: $0) }"))
        #expect(source.contains("let collapsedFrame = layout?.collapsedFrame"))
        #expect(source.contains("presentation.islandTopHeight = collapsedFrame.height"))
        #expect(source.contains("y: collapsedFrame.minY"))
        #expect(source.contains("ClipboardAssistantToastView.requiredRowWidth("))
        #expect(toastSource.contains(".fixedSize(horizontal: true, vertical: false)"))
        #expect(!source.contains("SideNoticeLayoutEngine().compactBarFrame"))
        #expect(source.contains("presentation.physicalNotchWidth = topology.hasPhysicalNotch ? topology.anchorFrame.width : 0"))
        #expect(toastSource.contains("physicalNotchHeader(detection)"))
        #expect(toastSource.contains("Spacer(minLength: 0)"))
        #expect(source.contains("onPresentationChanged?(true)"))
        #expect(source.contains("onPresentationChanged?(false)"))
        #expect(source.contains("guard !isScreenshotActive else { return }"))
        #expect(source.contains("setScreenshotActive(_ active: Bool)"))
        #expect(source.contains("setScreenshotSelectionActive(_ active: Bool)"))
        #expect(source.contains("guard presentationGeneration == generation else { return }"))
        #expect(!source.contains("guard displayDuration != .never"))
        #expect(source.contains("guard self.presentationGeneration == generation else { return }"))
        #expect(source.contains("self.dismissalGeneration == dismissalGeneration"))
        let appModelSource = try String(contentsOf: appModelSourceURL, encoding: .utf8)
        #expect(appModelSource.contains("clipboardAssistant.present(detection, visualStyle: settings.islandVisualStyle)"))
        #expect(appModelSource.contains("detection.actions.append(.addToQuickNote)"))
        #expect(appModelSource.contains("detection.actions.append(.sendToTeleprompter)"))
        #expect(appModelSource.contains("case .addToQuickNote:"))
        #expect(appModelSource.contains("case .sendToTeleprompter:"))
        #expect(appModelSource.contains("transientMessage = AppLocalization.text(\"已发送到提词器\")"))
        #expect(appModelSource.contains("presentTeleprompter()"))
        let downloadActionStart = try #require(appModelSource.range(of: "case .openDownload(let url):"))
        let downloadActionEnd = try #require(appModelSource[downloadActionStart.upperBound...]
            .range(of: "case .revealInFinder"))
        let downloadAction = appModelSource[downloadActionStart.lowerBound..<downloadActionEnd.lowerBound]
        #expect(!downloadAction.contains("guard !downloadState.isRunning else { return }"))
        #expect(downloadAction.contains("downloadURL = url.absoluteString"))
        #expect(!downloadAction.contains("startDownload()"))
        #expect(downloadAction.contains("selectModule(.download)"))
        let linkHandlerStart = try #require(appModelSource.range(of: "clipboardMonitor.onLinkDetected"))
        let linkHandlerEnd = appModelSource[linkHandlerStart.upperBound...]
            .range(of: "voiceInput.onRecordingWillStart")
        let linkHandler = appModelSource[linkHandlerStart.lowerBound..<(linkHandlerEnd?.lowerBound ?? appModelSource.endIndex)]
        #expect(!linkHandler.contains("selectModule(.download)"))
        #expect(linkHandler.contains("routeCapturedClipboardContent(.text(url.absoluteString), downloadableURL: url)"))
        #expect(!linkHandler.contains("notices.enqueue("))

        let downloadCompletionStart = try #require(appModelSource.range(of: "state: .completed(result.fileURL)"))
        let downloadCompletionEnd = try #require(appModelSource[downloadCompletionStart.upperBound...]
            .range(of: "} catch is CancellationError"))
        let downloadCompletion = appModelSource[downloadCompletionStart.lowerBound..<downloadCompletionEnd.lowerBound]
        #expect(downloadCompletion.contains("showsCompletion: true"))
        #expect(!downloadCompletion.contains("notices.enqueue("))

        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)
        #expect(!appSource.contains("model.$detectedLink.map { $0 != nil }"))
        #expect(appSource.contains("setHoverActivationSuspended(visible)"))
        #expect(appSource.contains("if isTeleprompterPresented {"))
        #expect(appSource.contains("model.teleprompterPresentationPoint ?? NSEvent.mouseLocation"))
        #expect(appModelSource.contains("teleprompterPresentationPoint = NSEvent.mouseLocation"))
    }

    @Test
    func teleprompterAcceptsTransferredText() throws {
        let source = try String(
            contentsOf: sourcesDirectoryURL.appendingPathComponent("Zisla/TeleprompterView.swift"),
            encoding: .utf8
        )
        #expect(source.contains("TransferDropDelegate.supportedTypes"))
        #expect(source.contains(".onDrop("))
        #expect(source.contains("script = droppedText"))
        #expect(source.contains("private static func text(from items: [TransferDropItem])"))
    }

    @Test
    func downloadModuleRendersEveryActiveDownload() throws {
        let source = try String(
            contentsOf: sourcesDirectoryURL.appendingPathComponent("Zisla/DownloadModuleView.swift"),
            encoding: .utf8
        )
        #expect(source.contains("ForEach(model.activeDownloads)"))
        #expect(source.contains("downloadTaskRow(task)"))
        #expect(source.contains("task.urlString"))
        #expect(source.contains("speed"))
        #expect(source.contains("eta"))
        #expect(source.contains("model.cancelDownload(taskID: task.id)"))
        #expect(source.contains("model.cancelAllDownloads()"))
        #expect(source.contains("IconButton(symbol: \"xmark\", help: AppLocalization.text(\"取消此下载\")"))
        #expect(!source.contains("Button(\"取消此下载\""))

        let appModelSource = try String(contentsOf: appModelSourceURL, encoding: .utf8)
        #expect(appModelSource.contains("@Published private(set) var activeDownloads: [DownloadTaskSnapshot] = []"))
        #expect(appModelSource.contains("private func refreshActiveDownloads()"))
        #expect(appModelSource.contains("func cancelDownload(taskID: UUID)"))
        #expect(appModelSource.contains("func cancelAllDownloads()"))
    }

    @Test
    func composingMailFromTheAssistantExpandsTheIslandItself() throws {
        let appModelSource = try String(contentsOf: appModelSourceURL, encoding: .utf8)
        #expect(appModelSource.contains("@Published var islandExpansionRequested = false"))
        let composeStart = try #require(appModelSource.range(of: "case .composeMail(let address):"))
        let composeEnd = try #require(appModelSource[composeStart.upperBound...].range(of: "case .copyText"))
        let composeAction = appModelSource[composeStart.lowerBound..<composeEnd.lowerBound]
        #expect(composeAction.contains("mailComposeRequest = MailComposeRequest(recipient: address)"))
        #expect(composeAction.contains("selectModule(.mail)"))
        #expect(composeAction.contains("islandExpansionRequested = true"))

        // The system-mail fallback hands off to another app, so it must not open the island.
        let fallbackStart = try #require(composeAction.range(of: "} else {"))
        let fallback = composeAction[fallbackStart.lowerBound...]
        #expect(fallback.contains("openSystemMail(to: address)"))
        #expect(!fallback.contains("islandExpansionRequested"))

        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)
        let sinkStart = try #require(appSource.range(of: "model.$islandExpansionRequested"))
        let sinkEnd = try #require(appSource[sinkStart.upperBound...].range(of: ".store(in: &cancellables)"))
        let sink = appSource[sinkStart.lowerBound..<sinkEnd.lowerBound]
        #expect(sink.contains(".filter { $0 }"))
        #expect(sink.contains("coordinator?.showExpanded(at: NSEvent.mouseLocation)"))
        #expect(sink.contains("AppModel.shared.islandExpansionRequested = false"))

        // The composer lives in @State, so a collapse would drop the draft mid-write.
        let mailSource = try String(
            contentsOf: sourcesDirectoryURL.appendingPathComponent("Zisla/MailModuleView.swift"),
            encoding: .utf8
        )
        #expect(mailSource.contains("var onTransientInteractionChanged: (Bool) -> Void = { _ in }"))
        #expect(mailSource.contains("onTransientInteractionChanged(composing)"))
        #expect(mailSource.contains("onTransientInteractionChanged(false)"))

        let rootSource = try String(
            contentsOf: sourcesDirectoryURL.appendingPathComponent("Zisla/IslandRootView.swift"),
            encoding: .utf8
        )
        let mailCaseStart = try #require(rootSource.range(of: "case .mail:"))
        let mailCaseEnd = try #require(rootSource[mailCaseStart.upperBound...].range(of: "case .quickNotes:"))
        #expect(rootSource[mailCaseStart.lowerBound..<mailCaseEnd.lowerBound]
            .contains("onTransientInteractionChanged: onTransientInteractionChanged"))
    }

    /// Expanding the island dismisses the clipboard assistant. Routing that dismissal through
    /// `setIslandExpanded` cleared the presenter's hidden state, so the collapsed status bar
    /// re-appeared on top of the open panel.
    @Test
    func clipboardAssistantDismissalKeepsTheCollapsedStatusBarHidden() throws {
        let appSource = try String(contentsOf: appSourceURL, encoding: .utf8)
        let handlerStart = try #require(
            appSource.range(of: "model.clipboardAssistant.onPresentationChanged")
        )
        let handlerEnd = try #require(
            appSource[handlerStart.upperBound...].range(of: "coordinator.setPersistentContentVisible")
        )
        let handler = appSource[handlerStart.lowerBound..<handlerEnd.lowerBound]
        #expect(handler.contains("setClipboardAssistantVisible(visible)"))
        #expect(!handler.contains("setIslandExpanded"))

        let presenterSource = try String(contentsOf: presenterSourceURL, encoding: .utf8)
        #expect(presenterSource.contains("func setClipboardAssistantVisible(_ visible: Bool)"))
        #expect(presenterSource.contains("guard !suppression.hidesNotices else {"))
    }

    private var sourceURL: URL {
        sourcesDirectoryURL.appendingPathComponent("Zisla/ClipboardAssistantWindowController.swift")
    }

    private var presenterSourceURL: URL {
        sourcesDirectoryURL.appendingPathComponent("Zisla/SideNoticePresenter.swift")
    }

    private var appModelSourceURL: URL {
        sourcesDirectoryURL.appendingPathComponent("Zisla/AppModel.swift")
    }

    private var appSourceURL: URL {
        sourcesDirectoryURL.appendingPathComponent("Zisla/ZislaApp.swift")
    }

    private var sourcesDirectoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }
}
