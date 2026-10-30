import AppKit
import SwiftUI
import Testing
import XCTest
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct ClipboardAssistantPlacementTests {
    @Test(arguments: [IslandEdge.top, .bottom, .left, .right])
    func customPromptsUseTheirNaturalLengthAndNeverReserveTheCamera(edge: IslandEdge) {
        let controller = makeController(edge: edge)
        defer { controller.dismiss(animated: false) }
        let short = ClipboardAssistantDetection(kind: .text, title: "短", actions: [.copyText("短")])
        let long = ClipboardAssistantDetection(kind: .text, title: "稍长一点的提示", actions: [.copyText("长")])
        let first = controller.rowLayout(for: short, on: screen, locale: chinese)
        let second = controller.rowLayout(for: long, on: screen, locale: chinese)
        let firstLength = edge.isVertical ? first.frame.height : first.frame.width
        let secondLength = edge.isVertical ? second.frame.height : second.frame.width
        #expect(firstLength < secondLength)
        #expect(firstLength < 300, "Short custom prompts must not inherit the 480pt notch row")
        #expect(first.style == .pill && first.edge == edge)
        #expect(first.frame == first.collapsedFrame)
        #expect(controller.presentation.physicalNotchWidth == 0,
                "A custom pill must not retain a gap reserved for the camera")
        #expect(first.collapsedFrameInSurface == CGRect(origin: .zero, size: first.frame.size))
        #expect(screen.frame.contains(first.frame))
        if edge.isVertical { #expect(first.frame.width == 24) }
        else { #expect(first.frame.height == 24) }
    }

    @Test
    func theCustomPromptIncludesDetailControlsAndShortcutsInItsNaturalWidth() {
        let controller = makeController(edge: .bottom)
        defer { controller.dismiss(animated: false) }
        let title = "Fixture"
        let base = ClipboardAssistantDetection(kind: .file, title: title)
        let detail = ClipboardAssistantDetection(kind: .file, title: title, detail: .characterCount(999_999_999_999))
        let action = ClipboardAssistantDetection(kind: .file, title: title, actions: [.copyText("fixture")])
        let expandable = ClipboardAssistantDetection(kind: .file, title: title,
                                                     actions: [.copyText("fixture")], fullContent: "line\nline")
        let baseWidth = controller.rowLayout(for: base, on: screen, locale: chinese).frame.width
        #expect(controller.rowLayout(for: detail, on: screen, locale: chinese).frame.width == baseWidth,
                "The 24pt pill keeps the hidden subtitle out of its width budget")
        let tallBase = ClipboardAssistantToastView.compactLength(
            detection: base, thickness: 32, edge: .bottom, isLightweightMode: false,
            controlsWidth: 20, locale: chinese
        )
        let tallDetail = ClipboardAssistantToastView.compactLength(
            detection: detail, thickness: 32, edge: .bottom, isLightweightMode: false,
            controlsWidth: 20, locale: chinese
        )
        #expect(tallDetail > tallBase, "A row tall enough to show its subtitle must still reserve its width")
        let actionWidth = controller.rowLayout(for: action, on: screen, locale: chinese).frame.width
        #expect(actionWidth > baseWidth)
        #expect(controller.rowLayout(for: expandable, on: screen, locale: chinese).frame.width > actionWidth)
        controller.screenLayoutConfiguration.placement.edge = .left
        let baseLength = controller.rowLayout(for: base, on: screen, locale: chinese).frame.height
        let actionLength = controller.rowLayout(for: action, on: screen, locale: chinese).frame.height
        #expect(actionLength > baseLength)
        #expect(controller.rowLayout(for: expandable, on: screen, locale: chinese).frame.height > actionLength)
        controller.screenLayoutConfiguration.placement.edge = .bottom
        let withShortcut = ClipboardAssistantToastView.compactControlsWidth(
            action, isLightweightMode: false, shortcutHint: "⌘ 1", locale: chinese
        )
        let withoutShortcut = ClipboardAssistantToastView.compactControlsWidth(
            action, isLightweightMode: false, shortcutHint: nil, locale: chinese
        )
        #expect(withShortcut > withoutShortcut)
        controller.isLightweightMode = true
        #expect(controller.rowLayout(for: action, on: screen, locale: chinese).frame.width < actionWidth)
    }

    @Test(arguments: [IslandEdge.top, .bottom, .left, .right], [Double(0), 0.5, 1])
    func detailsExpandInwardFromTheActualPillAndReturnToExactlyTheSameFrame(
        edge: IslandEdge, offset: Double
    ) {
        let controller = makeController(edge: edge, offset: offset)
        defer { controller.dismiss(animated: false) }
        let detection = ClipboardAssistantDetection(
            kind: .file, title: "fixture file", actions: [.revealInFinder(URL(fileURLWithPath: "/fixture/file"))],
            fullContent: String(repeating: "Synthetic file description\n", count: 30)
        )
        controller.present(detection, visualStyle: .frosted)
        let compact = controller.rowLayout(for: detection, on: screen, locale: chinese)
        controller.toggleExpansion(detection)
        let expanded = controller.rowLayout(for: detection, on: screen, locale: chinese)
        #expect(controller.isExpanded)
        #expect(expanded.collapsedFrame == compact.frame)
        #expect(expanded.frame == expanded.expandedFrame)
        #expect(expanded.frame.width >= 480)
        #expect(screen.frame.contains(expanded.frame))
        let local = expanded.collapsedFrameInSurface
        #expect(local.minX >= 0 && local.maxX <= expanded.frame.width)
        #expect(local.minY >= 0 && local.maxY <= expanded.frame.height)
        switch edge {
        case .top:
            #expect(expanded.frame.maxY == compact.frame.maxY && local.minY == 0)
            #expect(local.midX + expanded.frame.minX == compact.frame.midX)
        case .bottom:
            #expect(expanded.frame.minY == compact.frame.minY && local.maxY == expanded.frame.height)
            #expect(local.midX + expanded.frame.minX == compact.frame.midX)
        case .left:
            #expect(expanded.frame.minX == compact.frame.minX && local.minX == 0)
            #expect(expanded.frame.maxY - local.midY == compact.frame.midY)
        case .right:
            #expect(expanded.frame.maxX == compact.frame.maxX && local.maxX == expanded.frame.width)
            #expect(expanded.frame.maxY - local.midY == compact.frame.midY)
        }
        controller.toggleExpansion(detection)
        #expect(!controller.isExpanded)
        #expect(controller.rowLayout(for: detection, on: screen, locale: chinese).frame == compact.frame)
    }

    @Test
    func defaultNotchKeepsItsExistingTopRowAndHardwareGap() {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        let detection = ClipboardAssistantDetection(kind: .text, title: "Fixture")
        let layout = controller.rowLayout(for: detection, on: screen, locale: chinese)
        let expected = ScreenLayoutEngine().layout(for: screen)
        #expect(layout.style == .notch && layout.edge == .top)
        #expect(layout.frame.width == 480)
        #expect(layout.frame.midX == screen.frame.midX)
        #expect(layout.frame.maxY == screen.frame.maxY)
        #expect(controller.presentation.physicalNotchWidth == expected.collapsedFrame.width)
        #expect(layout.rowHeight == SideNoticeLayoutEngine().compactWingHeight(
            for: screen, progressGlowEnabled: controller.presentation.progressGlowEnabled
        ))
    }

    @Test(arguments: [IslandLayoutStyle.notch, .pill])
    func missingDisplayMetadataKeepsTheExistingGeometryFallback(style: IslandLayoutStyle) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        let screen = MissingNumberScreen()
        controller.screenAtPoint = { _ in screen }
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: style, placement: IslandPlacement(mode: .custom, edge: .left)
        )
        let detection = ClipboardAssistantDetection(kind: .text, title: "Fixture")
        let layout = try #require(controller.rowLayout(for: detection))
        #expect(screen.frame.contains(layout.frame))
        #expect(controller.presentation.physicalNotchWidth == 0)
        #expect(layout.style == style)
        if style == .pill {
            #expect(layout.edge == .left && layout.frame.width == 24)
        } else {
            #expect(layout.frame.maxY == screen.frame.maxY && layout.frame.width == 480)
        }
    }

    @Test
    func cameraPillsKeepTheMenuBarCenterAndReserveOnlyTheRealCutout() {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(layoutStyle: .pill)
        let detection = ClipboardAssistantDetection(kind: .text, title: "Fixture", actions: [.copyText("Fixture")])
        let layout = controller.rowLayout(for: detection, on: screen, locale: chinese)
        #expect(layout.edge == .top && layout.placementMode == .camera)
        #expect(layout.frame.midX == screen.frame.midX)
        #expect(layout.frame.midY == screen.frame.maxY - screen.topBarHeight / 2)
        #expect(controller.presentation.physicalNotchWidth == 185)
        let wings = ClipboardAssistantToastView.physicalNotchSideWidth(
            totalWidth: layout.frame.width, notchWidth: controller.presentation.physicalNotchWidth
        )
        #expect(wings >= 100)
        let flat = ScreenSnapshot(displayID: 2, frame: screen.frame, visibleFrame: screen.visibleFrame)
        _ = controller.rowLayout(for: detection, on: flat, locale: chinese)
        #expect(controller.presentation.physicalNotchWidth == 0)
    }

    @Test(arguments: [IslandEdge.top, .bottom, .left, .right], [CGFloat(80), 320])
    func oversizedTextAndSmallDisplaysRemainInsideTheirPlacementBounds(edge: IslandEdge, size: CGFloat) {
        let controller = makeController(edge: edge, offset: 1)
        defer { controller.dismiss(animated: false) }
        let small = ScreenSnapshot(displayID: 3, frame: CGRect(x: -120, y: -250, width: size, height: size),
                                   visibleFrame: CGRect(x: -120, y: -250, width: size, height: size))
        let detection = ClipboardAssistantDetection(kind: .text, title: String(repeating: "长", count: 10_000),
                                                    actions: [.copyText("fixture")])
        let layout = controller.rowLayout(for: detection, on: small, locale: chinese)
        #expect(small.frame.contains(layout.frame))
        #expect(layout.frame.width > 0 && layout.frame.height > 0)
        #expect(controller.presentation.physicalNotchWidth == 0)
        #expect(layout.frame.width.isFinite && layout.frame.height.isFinite)
    }

    @Test
    func replacingOrDismissingAPromptClearsExpandedStateAndObsoleteRequests() throws {
        let controller = makeController(edge: .left)
        defer { controller.dismiss(animated: false) }
        let first = ClipboardAssistantDetection(kind: .file, title: "file", fullContent: String(repeating: "first", count: 20))
        let second = ClipboardAssistantDetection(kind: .file, title: "replacement", fullContent: String(repeating: "second", count: 20))
        let old = try #require(controller.present(first, visualStyle: .frosted))
        controller.toggleExpansion(first)
        #expect(controller.isExpanded)
        _ = controller.present(second, visualStyle: .frosted)
        #expect(!controller.isExpanded)
        controller.toggleExpansion(first)
        #expect(!controller.isExpanded, "An obsolete prompt must not expand its replacement")
        controller.updateDetection(first, for: old)
        #expect(controller.presentation.detection == second)
        controller.toggleExpansion(second)
        #expect(controller.isExpanded)
        controller.setScreenLocked(true)
        #expect(!controller.isExpanded)
        #expect(controller.presentation.detection == nil && controller.presentation.layout == nil)
        #expect(controller.present(second, visualStyle: .frosted) == nil)
        controller.setScreenLocked(false)
        #expect(controller.presentation.detection == nil)
    }

    @Test
    func expandedStateResetsForAsyncReplacementLightweightModeAndTranslation() async throws {
        let controller = makeController(edge: .left)
        defer { controller.dismiss(animated: false) }
        let original = ClipboardAssistantDetection(kind: .file, title: "Original", fullContent: "line\nline")
        let replacement = ClipboardAssistantDetection(kind: .file, title: "Replacement", fullContent: "new\nnew")
        let generation = try #require(controller.present(original, visualStyle: .frosted))
        controller.toggleExpansion(original)
        controller.updateDetection(replacement, for: generation)
        #expect(!controller.isExpanded)
        controller.toggleExpansion(replacement)
        #expect(controller.isExpanded)
        controller.isLightweightMode = true
        #expect(!controller.isExpanded)
        controller.isLightweightMode = false
        controller.toggleExpansion(replacement)
        controller.translate("source", targetLanguage: "zh-CN",
                             service: .init(providers: [{ _, _ in "fixture" }]), copyResult: { _ in true })
        #expect(!controller.isExpanded)
        try await #require(controller.translationTask).value
    }

    @Test(arguments: ["screenshot", "share", "translation", "notExpandable", "lightweight", "closed"])
    func temporaryOrUnavailableActionsCannotExpandThePrompt(reason: String) async throws {
        let controller = makeController(edge: .right)
        defer { controller.dismiss(animated: false) }
        let detection = ClipboardAssistantDetection(kind: .file, title: "Fixture", actions: [.share], fullContent: "line\nline")
        controller.present(detection, visualStyle: .frosted)
        switch reason {
        case "screenshot": controller.setScreenshotActive(true)
        case "share": controller.onPerformAction = { _ in }; controller.perform(.share)
        case "translation":
            controller.translate("source", targetLanguage: "zh-CN",
                                 service: .init(providers: [{ _, _ in "fixture" }]), copyResult: { _ in true })
            try await #require(controller.translationTask).value
        case "notExpandable":
            controller.present(ClipboardAssistantDetection(kind: .url, title: "URL", fullContent: "line\nline"),
                               visualStyle: .frosted)
        case "lightweight": controller.isLightweightMode = true
        default: controller.dismiss(animated: false)
        }
        controller.toggleExpansion(controller.presentation.detection ?? detection)
        #expect(!controller.isExpanded, "\(reason) must keep the compact presentation")
    }

    @Test
    func translationLoadingUsesTheCustomPillAndTheResultUsesHorizontalReadingSpace() {
        let controller = makeController(edge: .right)
        defer { controller.dismiss(animated: false) }
        let detection = ClipboardAssistantDetection(kind: .nonSystemLanguageText, title: "source")
        controller.presentation.translation = .loading
        let loading = controller.rowLayout(for: detection, on: screen, locale: chinese)
        #expect(loading.frame == loading.collapsedFrame)
        #expect(loading.frame.width == 24 && loading.frame.height < 250)
        controller.presentation.translation = .result(text: "完整翻译结果", copied: nil)
        let result = controller.rowLayout(for: detection, on: screen, locale: chinese)
        #expect(result.collapsedFrame == loading.collapsedFrame)
        #expect(result.frame.width >= 240)
        #expect(result.frame.maxX == loading.frame.maxX)
        #expect(result.frame.height >= loading.frame.height)
        #expect(controller.presentation.physicalNotchWidth == 0)
    }

    @Test
    func changingPlacementRepositionsTheCurrentPromptWithoutExecutingIt() throws {
        let controller = makeController(edge: .top)
        defer { controller.dismiss(animated: false) }
        let detection = ClipboardAssistantDetection(kind: .text, title: "Synthetic")
        let generation = try #require(controller.present(detection, visualStyle: .frosted))
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        let initial = controller.rowLayout(for: detection, on: screen, locale: chinese)
        controller.screenLayoutConfiguration.placement.edge = .bottom
        let changed = controller.rowLayout(for: detection, on: screen, locale: chinese)
        #expect(changed.edge == .bottom && changed.frame.minY < initial.frame.minY)
        #expect(controller.presentation.detection == detection && actions.isEmpty)
        controller.updateDetection(ClipboardAssistantDetection(kind: .text, title: "New result"), for: generation)
        #expect(controller.presentation.detection?.title == "New result")
    }

    @Test
    func changingPlacementMovesTheExistingWindowAndExpandedDetailsUseTheSavedScreen() throws {
        let panel = FoldWindow()
        defer { panel.close() }
        let controller = ClipboardAssistantController(window: panel, windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        let liveScreen = try #require(NSScreen.screens.first)
        let origin = CGPoint(x: -100_000, y: -100_000)
        var requests: [CGPoint] = []
        controller.screenAtPoint = { requests.append($0); return liveScreen }
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: .top)
        )
        let detection = ClipboardAssistantDetection(kind: .file, title: "Fixture", fullContent: "line\nline")
        controller.present(detection, visualStyle: .frosted, at: origin)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            controller.screenLayoutConfiguration.placement.edge = .bottom
        }
        #expect(controller.presentation.layout?.edge == .bottom)
        controller.toggleExpansion(detection)
        let expanded = try #require(controller.presentation.layout)
        #expect(expanded.frame == expanded.expandedFrame)
        #expect(expanded.frame.minY == expanded.collapsedFrame.minY)
        #expect(requests.allSatisfy { $0 == origin })
    }

    @Test
    func asynchronousTranslationResultsRecomputeTheExistingPillSurface() async throws {
        let controller = makeController(edge: .left)
        defer { controller.dismiss(animated: false) }
        let liveScreen = try #require(NSScreen.screens.first)
        controller.screenAtPoint = { _ in liveScreen }
        let detection = ClipboardAssistantDetection(kind: .nonSystemLanguageText, title: "source")
        controller.present(detection, visualStyle: .frosted)
        controller.translate("source", targetLanguage: "zh-CN",
                             service: .init(providers: [{ _, _ in "fixture" }]), copyResult: { _ in true })
        let loading = try #require(controller.rowLayout(for: detection))
        try await #require(controller.translationTask).value
        let result = try #require(controller.presentation.layout)
        #expect(result.frame.width >= 240)
        #expect(result.collapsedFrame == loading.collapsedFrame)
        #expect(result.frame.minX == loading.frame.minX)
    }

    @Test(arguments: [false, true], IslandEdge.allCases)
    func restoringAScreenshotHiddenPromptUsesItsLatestPlacement(systemScreenshot: Bool, edge: IslandEdge) throws {
        let panel = ScreenshotHiddenWindow()
        defer { panel.close() }
        let controller = ClipboardAssistantController(window: panel, windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        let liveScreen = try #require(NSScreen.screens.first)
        controller.screenAtPoint = { _ in liveScreen }
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge == .top ? .bottom : .top)
        )
        let detection = ClipboardAssistantDetection(kind: .text, title: "Fixture", fullContent: "Synthetic text")
        controller.present(detection, visualStyle: .frosted)
        let initial = try #require(controller.rowLayout(for: detection))
        panel.setFrame(initial.frame, display: false)
        var actions: [ClipboardAssistantAction] = []
        controller.onPerformAction = { actions.append($0) }
        if systemScreenshot {
            controller.setSystemScreenshotActive(true)
        } else {
            controller.setScreenshotActive(true)
            controller.setScreenshotSelectionActive(true)
        }
        #expect(!panel.isVisible)
        controller.screenLayoutConfiguration.placement.edge = edge
        let latest = try #require(controller.presentation.layout)
        #expect(latest.edge == edge && latest.frame != initial.frame)
        if systemScreenshot {
            controller.setSystemScreenshotActive(false)
        } else {
            controller.setScreenshotSelectionActive(false)
            controller.setScreenshotActive(false)
        }
        #expect(panel.isVisible && panel.frame == latest.frame,
                "A restored prompt must use the saved placement changed while the live window was hidden")
        #expect(controller.presentation.detection == detection && actions.isEmpty)
    }

    @Test(arguments: [ClipboardAssistantKind.text, .nonSystemLanguageText, .code, .shellCommand, .math])
    func draggablePromptContentPreservesTheFullText(kind: ClipboardAssistantKind) {
        let content = "  Synthetic 🧑‍💻 content\nwith original spacing  "
        let detection = ClipboardAssistantDetection(kind: kind, title: "Preview", fullContent: content)
        #expect(ClipboardAssistantToastView.dragText(for: detection) == content)
        for empty in [String?.none, "", " \n\t "] {
            let emptyDetection = ClipboardAssistantDetection(kind: kind, title: "Preview", fullContent: empty)
            #expect(ClipboardAssistantToastView.dragText(for: emptyDetection) == nil)
        }
        let file = ClipboardAssistantDetection(kind: .file, title: "File", fullContent: content)
        #expect(ClipboardAssistantToastView.dragText(for: file) == nil)
    }

    @Test(arguments: [false, true])
    func foldingKeepsTheTranslationUntilItFinishesAndCannotClearANewerPrompt(replace: Bool) async throws {
        let panel = FoldWindow()
        defer { panel.close() }
        var finishFold: (@MainActor () -> Void)?
        let controller = ClipboardAssistantController(window: panel, windowPresenter: { _, _ in },
            animateDismissal: { _, _, completion in finishFold = completion })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: .left)
        )
        let detection = ClipboardAssistantDetection(kind: .nonSystemLanguageText, title: "source")
        controller.present(detection, visualStyle: .frosted)
        var copies: [String] = []
        controller.translate("source", targetLanguage: "zh-CN",
                             service: .init(providers: [{ _, _ in "translation fixture" }]),
                             copyResult: { copies.append($0); return true })
        try await #require(controller.translationTask).value
        let translation = try #require(controller.presentation.translation)
        let generation = controller.presentation.translationGeneration
        _ = controller.rowLayout(for: detection, on: screen, locale: chinese)
        controller.dismiss()
        #expect(controller.presentation.isFolding)
        #expect(controller.presentation.translation == translation,
                "The folded surface must retain its translation content until the mask returns to the pill")
        #expect(controller.translationTask == nil)
        controller.translationWindowDidAppear(for: generation)
        controller.translationDidAppear(translation, for: generation, rowWidth: 240, locale: chinese)
        #expect(copies.isEmpty)
        let finish = try #require(finishFold)
        if replace {
            controller.present(detection, visualStyle: .frosted)
            controller.translate("source", targetLanguage: "zh-CN",
                                 service: .init(providers: [{ _, _ in "replacement fixture" }]),
                                 copyResult: { copies.append($0); return true })
            try await #require(controller.translationTask).value
            let newer = try #require(controller.presentation.translation)
            finish()
            #expect(controller.presentation.detection == detection && controller.presentation.translation == newer)
            #expect(!controller.presentation.isFolding)
        } else {
            finish()
            #expect(controller.presentation.translation == nil && controller.presentation.detection == nil)
            #expect(controller.presentation.layout == nil && !controller.presentation.isFolding)
        }
    }

    @Test
    func expandedDetailsRemainMountedDuringTheFoldAndPendingTranslationsCannotReplaceIt() async throws {
        let panel = FoldWindow()
        defer { panel.close() }
        var finishFold: (@MainActor () -> Void)?
        let controller = ClipboardAssistantController(window: panel, windowPresenter: { _, _ in },
            animateDismissal: { _, _, completion in finishFold = completion })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: .right)
        )
        let detection = ClipboardAssistantDetection(kind: .file, title: "Fixture", fullContent: "line\nline")
        controller.present(detection, visualStyle: .frosted)
        controller.toggleExpansion(detection)
        _ = controller.rowLayout(for: detection, on: screen, locale: chinese)
        controller.dismiss()
        #expect(controller.isExpanded && controller.presentation.isFolding)
        let finishDetails = try #require(finishFold)
        finishDetails()
        #expect(!controller.isExpanded && controller.presentation.detection == nil)

        let pending = ClipboardAssistantDetection(kind: .nonSystemLanguageText, title: "source")
        controller.present(pending, visualStyle: .frosted)
        let gate = LateTranslationGate()
        var copies = 0
        controller.translate("source", targetLanguage: "zh-CN",
                             service: .init(providers: [{ _, _ in await gate.wait() }]),
                             copyResult: { _ in copies += 1; return true })
        let task = try #require(controller.translationTask)
        #expect(await XCTWaiter.fulfillment(of: [gate.started], timeout: 2) == .completed)
        _ = controller.rowLayout(for: pending, on: screen, locale: chinese)
        controller.dismiss()
        await task.value
        await gate.resolve()
        #expect(await XCTWaiter.fulfillment(of: [gate.returned], timeout: 2) == .completed)
        #expect(controller.presentation.translation != .result(text: "late fixture", copied: nil))
        #expect(copies == 0)
        let finishTranslation = try #require(finishFold)
        finishTranslation()
        #expect(controller.presentation.translation == nil && controller.presentation.detection == nil)
    }

    @Test(arguments: ["", "短", "a b\nc", "🧑‍💻", String(repeating: "长", count: 100)])
    func verticalPromptMetricsRespectVisibleGraphemesAndKeepTheControls(text: String) {
        let detection = ClipboardAssistantDetection(kind: .text, title: text)
        let length = ClipboardAssistantToastView.compactLength(
            detection: detection, thickness: 32, edge: .left, isLightweightMode: false,
            controlsWidth: 0, locale: chinese
        )
        let textLength = min(168, CGFloat(text.filter { !$0.isWhitespace }.count) * 14)
        #expect(length == 16 + 26 + 12 + textLength + 20)
        let visible = VerticalStatusText.characters(text, availableHeight: textLength)
        #expect(visible.count * 14 <= Int(textLength))
        if text == "🧑‍💻" { #expect(visible == [text]) }
        if text.count > 12 { #expect(visible.last == "…") }
    }

    @Test(arguments: [IslandEdge.left, .right], [LayoutDirection.leftToRight, .rightToLeft])
    func verticalMoreActionsPopoverPointsTowardTheScreenInterior(
        edge: IslandEdge, layoutDirection: LayoutDirection
    ) {
        let expected: Edge
        switch edge {
        case .left:
            expected = layoutDirection == .leftToRight ? .leading : .trailing
        case .right:
            expected = layoutDirection == .leftToRight ? .trailing : .leading
        case .top, .bottom:
            expected = .top
        }
        #expect(ClipboardAssistantToastView.verticalMoreActionsPopoverArrowEdge(
            for: edge, layoutDirection: layoutDirection
        ) == expected)
    }

    private func makeController(edge: IslandEdge, offset: Double = 0.5) -> ClipboardAssistantController {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        controller.displayDuration = .never
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge, offset: offset)
        )
        return controller
    }

    private var chinese: Locale { Locale(identifier: "zh-Hans") }
    private var screen: ScreenSnapshot {
        ScreenSnapshot(displayID: 1, frame: CGRect(x: -1_440, y: -300, width: 1_440, height: 900),
                       visibleFrame: CGRect(x: -1_440, y: -276, width: 1_440, height: 842),
                       safeAreaInsets: ScreenInsets(top: 34),
                       auxiliaryTopLeftArea: CGRect(x: -1_440, y: 566, width: 627.5, height: 34),
                       auxiliaryTopRightArea: CGRect(x: -627.5, y: 566, width: 627.5, height: 34))
    }
}

@MainActor
private final class FoldWindow: NSPanel {
    override var isVisible: Bool { true }

    init() {
        super.init(contentRect: CGRect(x: -100_000, y: -100_000, width: 480, height: 220),
                   styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}

@MainActor
private final class ScreenshotHiddenWindow: NSPanel {
    private var showsPrompt = true
    private var promptFrame = CGRect(x: -100_000, y: -100_000, width: 480, height: 32)
    override var isVisible: Bool { showsPrompt }
    override var frame: NSRect { promptFrame }
    override func setFrame(_ frameRect: NSRect, display flag: Bool) { promptFrame = frameRect }
    override func orderOut(_ sender: Any?) { showsPrompt = false }
    override func orderFrontRegardless() { showsPrompt = true }

    init() {
        super.init(contentRect: CGRect(x: -100_000, y: -100_000, width: 480, height: 32),
                   styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
    }
}

@MainActor
private final class MissingNumberScreen: NSScreen {
    override var deviceDescription: [NSDeviceDescriptionKey: Any] { [:] }
    override var frame: CGRect { CGRect(x: -800, y: -400, width: 800, height: 600) }
    override var visibleFrame: CGRect { frame }
}

private actor LateTranslationGate {
    nonisolated let started = XCTestExpectation(description: "迟到翻译开始")
    nonisolated let returned = XCTestExpectation(description: "迟到翻译返回")
    private var continuation: CheckedContinuation<String, Never>?

    func wait() async -> String {
        started.fulfill()
        defer { returned.fulfill() }
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve() {
        continuation?.resume(returning: "late fixture")
        continuation = nil
    }
}

@MainActor
@Suite(.serialized)
struct ClipboardAssistantCompactRenderingTests {
    @Test(arguments: [IslandEdge.top, .bottom, .left, .right])
    func translationLoadingFitsTheCustomPillWithoutOpeningASubtitleRow(edge: IslandEdge) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge)
        )
        let detection = ClipboardAssistantDetection(kind: .nonSystemLanguageText, title: "source")
        controller.present(detection, visualStyle: .frosted)
        controller.presentation.translation = .loading
        let snapshot = ScreenSnapshot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 866))
        let layout = controller.rowLayout(for: detection, on: snapshot, locale: Locale(identifier: "zh-Hans"))
        let renderer = ImageRenderer(content: ClipboardTranslationResultView(
            translation: .loading, presentation: controller.presentation, controller: controller,
            size: layout.frame.size
        )
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .environment(\.colorScheme, .dark)
        .transaction { $0.disablesAnimations = true }
        .frame(width: layout.frame.width, height: layout.frame.height))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        #expect(try #require(bitmap.colorAt(x: 2, y: 2)).alphaComponent < 0.01,
                "A custom loading prompt keeps rounded pill corners instead of a flush notch edge")
        var points: [CGPoint] = []
        let axisLength = edge.isVertical ? bitmap.pixelsHigh : bitmap.pixelsWide
        for axis in 34..<(axisLength - 34) {
            let thickness = edge.isVertical ? bitmap.pixelsWide : bitmap.pixelsHigh
            for offset in 0..<thickness {
                let x = edge.isVertical ? offset : axis
                let y = edge.isVertical ? axis : offset
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.7 {
                    points.append(CGPoint(x: x, y: y))
                }
            }
        }
        let text = try bounds(of: points)
        if edge.isVertical { #expect(text.height >= 50 && text.width <= 20) }
        else { #expect(text.width >= 45 && text.height <= 20) }
        #expect(layout.frame == layout.collapsedFrame && controller.presentation.translation == .loading)
    }

    @Test(arguments: [IslandEdge.top, .bottom, .left, .right], [LayoutDirection.leftToRight, .rightToLeft])
    func iconPrecedesTheTextWithoutACentralBlankInEveryCustomOrientation(
        edge: IslandEdge, direction: LayoutDirection
    ) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        controller.isLightweightMode = true
        controller.presentation.progressGlowEnabled = false
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge)
        )
        let detection = ClipboardAssistantDetection(
            kind: .color, title: "字字字字字字",
            colorComponents: .init(red: 1, green: 0, blue: 0)
        )
        controller.present(detection, visualStyle: .frosted)
        let snapshot = ScreenSnapshot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 866))
        let layout = controller.rowLayout(for: detection, on: snapshot, locale: Locale(identifier: "zh-Hans"))
        let renderer = ImageRenderer(content: ClipboardAssistantToastView(
            presentation: controller.presentation, controller: controller
        )
        .environment(\.layoutDirection, direction)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .transaction { $0.disablesAnimations = true }
        .frame(width: layout.frame.width, height: layout.frame.height))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var redPoints: [CGPoint] = []
        var textPoints: [CGPoint] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.redComponent > 0.6 && color.greenComponent < 0.3 && color.blueComponent < 0.3 {
                    redPoints.append(CGPoint(x: x, y: y))
                }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.65 {
                    let excludesIndicator = edge.isVertical ? y < bitmap.pixelsHigh - 28
                        : direction == .rightToLeft ? x > 38 : x < bitmap.pixelsWide - 38
                    if excludesIndicator { textPoints.append(CGPoint(x: x, y: y)) }
                }
            }
        }
        let icon = try bounds(of: redPoints)
        let text = try bounds(of: textPoints)
        #expect(controller.presentation.physicalNotchWidth == 0)
        #expect(icon.minX >= 0 && icon.maxX <= layout.frame.width)
        #expect(text.minX >= 0 && text.maxX <= layout.frame.width)
        if edge.isVertical {
            #expect(text.minY > icon.maxY && text.minY - icon.maxY < 20,
                    "The first upright character must immediately follow the upright icon")
            #expect(text.height > text.width * 3, "Side text must be a vertical column of upright characters")
        } else if direction == .rightToLeft {
            #expect(icon.minX > text.maxX && icon.minX - text.maxX < 28)
        } else {
            #expect(text.minX > icon.maxX && text.minX - icon.maxX < 28)
        }
    }

    @Test(arguments: [IslandEdge.bottom, .right])
    func closingDetailsMasksTheExpandedCanvasAtItsOriginalPill(edge: IslandEdge) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge, offset: 0.3)
        )
        let detection = ClipboardAssistantDetection(kind: .file, title: "Fixture", fullContent: "line\nline")
        controller.present(detection, visualStyle: .frosted)
        controller.toggleExpansion(detection)
        let snapshot = ScreenSnapshot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 866))
        let layout = controller.rowLayout(for: detection, on: snapshot)
        controller.presentation.isFolding = true
        let renderer = ImageRenderer(content: ClipboardAssistantToastView(
            presentation: controller.presentation, controller: controller
        )
        .transaction { $0.disablesAnimations = true }
        .frame(width: layout.frame.width, height: layout.frame.height))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let anchor = layout.collapsedFrameInSurface
        #expect(try #require(bitmap.colorAt(x: Int(anchor.midX), y: Int(anchor.midY))).alphaComponent > 0.5)
        let outside = edge == .right ? CGPoint(x: 30, y: layout.frame.height / 2)
            : CGPoint(x: layout.frame.width / 2, y: 2)
        #expect(try #require(bitmap.colorAt(x: Int(outside.x), y: Int(outside.y))).alphaComponent < 0.01,
                "Closing details must fold into their original pill instead of leaving the expanded canvas visible")
    }

    @Test(arguments: [IslandEdge.bottom, .right])
    func closingTranslationMasksTheResultAtItsOriginalLoadingPill(edge: IslandEdge) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge, offset: 0.3)
        )
        let detection = ClipboardAssistantDetection(kind: .nonSystemLanguageText, title: "source")
        let translation = ClipboardTranslationPresentation.result(text: "horizontal fixture", copied: nil)
        controller.present(detection, visualStyle: .frosted)
        controller.presentation.translation = translation
        let snapshot = ScreenSnapshot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 866))
        let layout = controller.rowLayout(for: detection, on: snapshot)
        controller.presentation.isFolding = true
        let renderer = ImageRenderer(content: ClipboardTranslationResultView(
            translation: translation, presentation: controller.presentation, controller: controller,
            size: layout.frame.size
        )
        .transaction { $0.disablesAnimations = true }
        .frame(width: layout.frame.width, height: layout.frame.height))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let anchor = layout.collapsedFrameInSurface
        #expect(try #require(bitmap.colorAt(x: Int(anchor.midX), y: Int(anchor.midY))).alphaComponent > 0.5)
        let outside = edge == .right ? CGPoint(x: 30, y: layout.frame.height / 2)
            : CGPoint(x: layout.frame.width / 2, y: 2)
        #expect(try #require(bitmap.colorAt(x: Int(outside.x), y: Int(outside.y))).alphaComponent < 0.01)
    }

    @Test(arguments: [IslandEdge.left, .right])
    func aTranslationResultKeepsAHorizontalMarqueeAfterItsVerticalLoadingPill(edge: IslandEdge) throws {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        defer { controller.dismiss(animated: false) }
        controller.displayDuration = .never
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge)
        )
        let detection = ClipboardAssistantDetection(kind: .nonSystemLanguageText, title: "source")
        let translation = ClipboardTranslationPresentation.result(
            text: String(repeating: "水平字幕", count: 50), copied: true
        )
        controller.present(detection, visualStyle: .frosted)
        controller.presentation.translation = translation
        let snapshot = ScreenSnapshot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 866))
        let layout = controller.rowLayout(for: detection, on: snapshot, locale: Locale(identifier: "en"))
        let renderer = ImageRenderer(content: ClipboardTranslationResultView(
            translation: translation, presentation: controller.presentation,
            controller: controller, size: layout.frame.size
        )
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.colorScheme, .dark)
        .transaction { $0.disablesAnimations = true }
        .frame(width: layout.frame.width, height: layout.frame.height))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var textPoints: [CGPoint] = []
        for y in Int(layout.rowHeight + 2)..<Int(layout.rowHeight + 20) {
            for x in 12..<(bitmap.pixelsWide - 12) {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.65 {
                    textPoints.append(CGPoint(x: x, y: y))
                }
            }
        }
        let text = try bounds(of: textPoints)
        #expect(text.width >= 180 && text.height <= 20,
                "Translation results must remain a horizontal subtitle rather than a truncated vertical column")
        #expect(controller.presentation.translation == translation)
    }

    private func bounds(of points: [CGPoint]) throws -> CGRect {
        let first = try #require(points.first)
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min() ?? first.x, y: ys.min() ?? first.y,
                      width: (xs.max() ?? first.x) - (xs.min() ?? first.x) + 1,
                      height: (ys.max() ?? first.y) - (ys.min() ?? first.y) + 1)
    }
}
