import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct AIAccountBalanceViewTests {
    /// Pixel regions prove camera clearance and both summary lines without treating an image render as device acceptance.
    @Test(arguments: [CGFloat(0), 80, 180], [false, true])
    func compactBalanceKeepsBothLinesOutsidePhysicalCameraGap(centerInset: CGFloat, rightToLeft: Bool) throws {
        let width = centerInset + 320
        let notice = IslandNotice(id: "ai-balance-low-fixture", title: "Claude", style: .status,
            metadata: ["quotaProvider": "Claude", "quotaSeverity": "0", "quotaLine0": "5h 70%", "quotaLine1": "All Weekly 80%"])
        let renderer = ImageRenderer(content: CompactAIAccountBalanceBar(notice: notice, height: 34, centerInset: centerInset)
            .frame(width: width, height: 34).background(.black).foregroundStyle(.white)
            .environment(\.colorScheme, .dark).environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
        renderer.scale = 2
        let image = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let leftEnd = Int((width - centerInset) * renderer.scale / 2), rightStart = Int((width + centerInset) * renderer.scale / 2)
        var leftPixels = 0, rightTop = 0, rightBottom = 0, cameraPixels = 0
        for x in 0..<image.pixelsWide {
            for y in 0..<image.pixelsHigh {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent > 0.5 else { continue }
                if x < leftEnd { leftPixels += 1 }
                else if x >= rightStart {
                    if y < image.pixelsHigh / 2 { rightTop += 1 } else { rightBottom += 1 }
                } else { cameraPixels += 1 }
            }
        }
        #expect(cameraPixels == 0, "Balance text must not overlap the physical camera")
        #expect(leftPixels > 0)
        #expect(rightTop > 0 && rightBottom > 0, "The detailed compact style must render both quota lines")
    }

    /// Offscreen rendering covers edge-dependent dimensions and nonempty quota content across LTR and RTL layouts.
    @Test(arguments: [IslandEdge.top, .bottom, .left, .right], [AppLanguage.simplifiedChinese, .english, .arabic])
    func customAndFloatingShapesRenderTwoQuotaLines(edge: IslandEdge, language: AppLanguage) throws {
        let thickness: CGFloat = 34, length: CGFloat = 300
        let notice = IslandNotice(id: AIAccountBalanceNoticeController.pinnedID, title: "Gemini", style: .status,
            metadata: ["quotaProvider": "Gemini", "quotaSeverity": "1", "quotaLine0": "5h 20%", "quotaLine1": AppLocalization.string("每周额度", language: language) + " 70%"])
        let renderer = ImageRenderer(content: CompactAIAccountBalanceBar(notice: notice, height: thickness, edge: edge)
            .frame(width: edge.isVertical ? thickness : length, height: edge.isVertical ? length : thickness)
            .background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int((edge.isVertical ? thickness : length) * 2))
        #expect(image.height == Int((edge.isVertical ? length : thickness) * 2))
        let bitmap = NSBitmapImageRep(cgImage: image)
        var colored = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent > 0.5 { colored += 1 }
            }
        }
        #expect(colored > 0)
    }

    /// Exact reference pixels catch a truncated provider and lost quota rows at natural and constrained vertical lengths.
    @Test(arguments: [IslandEdge.left, .right], [(CGFloat(32), false), (32, true), (34, false), (34, true)])
    func verticalBalanceReservesMeasuredProviderRowsAndKeepsQuotaWhenConstrained(
        edge: IslandEdge, configuration: (CGFloat, Bool)
    ) throws {
        let (thickness, rightToLeft) = configuration
        let notice = IslandNotice(id: AIAccountBalanceNoticeController.pinnedID, title: "Claude", style: .status,
            metadata: ["quotaProvider": "Claude", "quotaSeverity": "0", "quotaLine0": "5h 70%"])
        let presentation = CompactPillStatusPresentation(priority: .aiAccountBalance, notice: notice, text: "")
        let quotaRows = thickness == 32 ? ["5", "h", "70", "%"] : ["5", "h", "70%"]
        #expect(presentation.length(thickness: thickness, edge: edge) == (thickness == 32 ? 174 : 160),
            "Natural length must use the quota's rendered width, including its 8pt thickness inset")
        func rows(_ values: [String]) -> some View {
            VStack(spacing: 1) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(verbatim: value).font(.system(size: 11, weight: .medium)).frame(height: 13)
                }
            }
        }
        for length in [presentation.length(thickness: thickness, edge: edge), CGFloat(88)] {
            let titleHeight: CGFloat = length == 88 ? (thickness == 32 ? 0 : 14) : 84
            let valueHeight = length - 24 - 8 - titleHeight
            func render(_ content: some View) throws -> NSBitmapImageRep {
                let renderer = ImageRenderer(content: content.frame(width: thickness, height: length)
                    .background(.black).foregroundStyle(.white).environment(\.colorScheme, .dark)
                    .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
                renderer.scale = 2
                return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            }
            let actual = try render(CompactAIAccountBalanceBar(notice: notice, height: thickness, edge: edge))
            let reference = try render(VStack(spacing: 8) {
                rows(length == 88 ? (thickness == 32 ? [] : ["…"]) : ["C", "l", "a", "u", "d", "e"])
                    .frame(height: titleHeight)
                HStack(alignment: .top, spacing: 2) { rows(quotaRows).foregroundStyle(Color.primary) }.frame(height: valueHeight)
            }.padding(.vertical, 12).frame(width: thickness, height: length))
            #expect(actual.pixelsWide == Int(thickness * 2) && actual.pixelsHigh == Int(length * 2))
            var changed = 0
            for y in 0..<actual.pixelsHigh {
                for x in 0..<actual.pixelsWide {
                    let a = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    let b = try #require(reference.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if abs(a.redComponent - b.redComponent) > 0.01 { changed += 1 }
                }
            }
            #expect(changed == 0, "At \(thickness)×\(length)pt, Claude must keep its measured title budget and complete quota")
        }
    }

    /// A queued quota must not undo swipe-to-hide for the real selected media, mail, or ordinary transient.
    @Test(arguments: ["media", "mail", "focus-transition", "headphone", "pinned", "voice", "camera"])
    func queuedPinnedQuotaKeepsOnlyItsSelectedStatusVisible(kind: String) throws {
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: kind == "camera" ? .camera : .custom, edge: .left))
        settings.activityNoticeDisplayDuration = .threeSeconds
        settings.focusModeNoticeDisplayDuration = .threeSeconds
        settings.aiAccountBalancePinnedInCustomIsland = true
        let pinned = IslandNotice(id: AIAccountBalanceNoticeController.pinnedID, title: "Quota", style: .status)
        let selectedID: String?
        let priority: CompactStatusPriority?
        switch kind {
        case "media": (selectedID, priority) = ("media-active-fixture", .media)
        case "mail": (selectedID, priority) = ("mail-notification-fixture", .mail)
        case "focus-transition": (selectedID, priority) = ("focus-transition-fixture", .transient)
        case "headphone": (selectedID, priority) = ("headphone-fixture", .transient)
        case "voice": (selectedID, priority) = ("voice-processing-fixture", nil)
        case "camera": (selectedID, priority) = (nil, nil)
        default: (selectedID, priority) = (pinned.id, .aiAccountBalance)
        }
        settings.compactStatusPriority = priority.map { [$0, .aiAccountBalance] } ?? [.aiAccountBalance]
        let notices = [pinned] + (selectedID.flatMap { id in
            id == pinned.id ? nil : IslandNotice(id: id, title: "Selected", style: kind == "headphone" ? .headphone : .status)
        }.map { [$0] } ?? [])
        let presentation = SideNoticeLayoutEngine().compactBarSizing(for: notices, settings: settings)?.customPillPresentation
        #expect(presentation?.notice.id == selectedID, "The fixture must exercise the real \(kind) selection")
        #expect(presentation?.priority == priority)
        let state = SideNoticeDisplayState()
        _ = SideNoticePresenter.updateCompactVisibility(notices: notices, settings: settings, displayState: state)
        state.compactStatusHidden = true
        #expect(!SideNoticePresenter.updateCompactVisibility(notices: notices, settings: settings, displayState: state))
        #expect(state.compactStatusHidden == (kind != "pinned" && kind != "voice"),
            "Only a selected pinned quota or voice processing may force visibility with short activity durations")
    }

    /// A long model identity must consume extra vertical space instead of compressing values or overflowing a narrow RTL row.
    @Test func narrowRTLBalanceRowsWrapLongIdentityWithoutHorizontalOverflow() async throws {
        let window = AIAccountQuotaWindow(id: "model", kind: .model, remainingPercent: 10,
            resetsAt: Date(timeIntervalSince1970: 1_910_001_000), name: String(repeating: "gemini-long-model ", count: 6))
        let balance = AIAccountBalance(id: "fixture", providers: [.gemini], status: .available, windows: [window])
        let view = AIAccountBalanceSection(balances: [balance], displayedProviders: [.gemini], language: .arabic)
        let host = NSHostingView(rootView: view.frame(width: 240).fixedSize(horizontal: false, vertical: true))
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 500)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width <= 240.5)
        #expect(host.fittingSize.height > 70, "Long window identities must use additional lines instead of squeezing the quota value")
    }

    /// Large task counts must saturate the bounded upper viewport so quota below it remains reachable by outer scrolling.
    @Test func boundedTaskViewportLeavesBalanceReachableAfterManyTasks() {
        for count in [0, 1, 6, 20, 1_000] {
            let height = AIProgressModuleView.taskSectionHeight(taskCount: count, availableHeight: 500)
            #expect(height <= 360 && height <= 325)
        }
        #expect(AIProgressModuleView.taskSectionHeight(taskCount: 20, availableHeight: 500)
            == AIProgressModuleView.taskSectionHeight(taskCount: 1_000, availableHeight: 500))
        let balance = AIAccountBalance(id: "fixture", providers: [.claude], status: .notSignedIn)
        #expect(AIAccountBalanceSection(balances: [balance], displayedProviders: [], language: .english).displayedBalances.isEmpty)
    }
}
