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
