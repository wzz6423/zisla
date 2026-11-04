import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ClipboardAssistantMarqueeTests {
    private let title = String(repeating: "天", count: 35)
        + String(repeating: "地", count: 35) + String(repeating: "玄", count: 35)
    private let detail = String(repeating: "黄", count: 40)
        + String(repeating: "宇", count: 40) + String(repeating: "宙", count: 40)

    @Test(arguments: [(IslandLayoutStyle.pill, IslandEdge.top), (.pill, .bottom), (.notch, .top)],
          [LayoutDirection.leftToRight, .rightToLeft])
    func longTitlesAndDetailsFillTheirFirstViewportAndScrollWithinTheSameRow(
        placement: (IslandLayoutStyle, IslandEdge), direction: LayoutDirection
    ) async throws {
        let controller = makeController(style: placement.0, edge: placement.1)
        defer { controller.dismiss(animated: false) }
        let detection = ClipboardAssistantDetection(kind: .color, title: title, detail: .path(detail),
            colorComponents: .init(red: 1, green: 0, blue: 0))
        controller.present(detection, visualStyle: .transparent)
        let layout = controller.rowLayout(for: detection, on: screen, locale: locale(direction))
        let viewport = textViewport(layout: layout, direction: direction,
            notchWidth: controller.presentation.physicalNotchWidth)
        for renderScale in [CGFloat(1), 2] {
            #expect(layout.frame == layout.collapsedFrame)
            #expect(layout.frame.width == ScreenLayoutConfiguration.quickActionRowWidth)
            var samples: [NSBitmapImageRep] = []
            var controls: [[UInt8]] = []
            for progress in [0.0, 0.5, 1] {
                let actual = try await render(ClipboardAssistantToastView(
                    presentation: controller.presentation, controller: controller), size: layout.frame.size,
                    progress: progress, direction: direction, renderScale: renderScale)
                let expected = try await render(referenceHeader(width: viewport.width, direction: direction, progress: progress)
                    .environment(\.layoutDirection, direction)
                    .frame(width: viewport.width, height: viewport.height)
                    .position(x: viewport.midX, y: viewport.midY)
                    .environment(\.layoutDirection, .leftToRight), size: layout.frame.size,
                    progress: progress, direction: direction, renderScale: renderScale)
                let delta = differences(try pixels(actual, in: viewport), try pixels(expected, in: viewport))
                #expect(delta == 0,
                    "The \(placement) header at \(progress) must show the corresponding full-size text window")
                let columns = try inkColumns(actual, in: viewport)
                #expect(columns.first.map { $0 <= 4 } == true
                    && columns.last.map { $0 >= Int(viewport.width) - 5 } == true,
                    "Overflowing content must occupy the first viewport instead of sliding in from an empty row")
                let controlsRect = CGRect(x: direction == .leftToRight ? layout.frame.width - 34 : 14,
                    y: 0, width: 20, height: layout.rowHeight)
                controls.append(try pixels(actual, in: controlsRect))
                if controller.presentation.physicalNotchWidth > 0 {
                    let sideWidth = ClipboardAssistantToastView.physicalNotchSideWidth(
                        totalWidth: layout.frame.width, notchWidth: controller.presentation.physicalNotchWidth)
                    let center = CGRect(x: sideWidth, y: 0,
                        width: controller.presentation.physicalNotchWidth, height: layout.rowHeight)
                    #expect(try pixels(actual, in: center).allSatisfy { $0 < 10 },
                        "Scrolling text and its width probe must never enter the hardware cutout")
                }
                #expect(controller.presentation.detection == detection && controller.presentation.translation == nil)
                #expect(controller.presentation.layout == layout && !controller.isMoreActionsPresented)
                samples.append(actual)
            }
            for y in [CGFloat(0), viewport.height / 2] {
                let line = CGRect(x: viewport.minX, y: y, width: viewport.width, height: viewport.height / 2)
                #expect(differences(try pixels(samples[0], in: line), try pixels(samples[1], in: line)) > 30)
                #expect(differences(try pixels(samples[1], in: line), try pixels(samples[2], in: line)) > 30,
                    "Both the title and detail must continue to their ending rather than remain truncated")
            }
            #expect(controls[0].contains { $0 > 64 })
            #expect(differences(controls[0], controls[1]) == 0 && differences(controls[1], controls[2]) == 0,
                "The close control must remain stationary and visible throughout the text scroll")
        }
    }

    @Test(arguments: [IslandEdge.left, .right], [LayoutDirection.leftToRight, .rightToLeft])
    func verticalQuickActionsFillTheExistingTextBudgetAndScrollUpright(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let controller = makeController(style: .pill, edge: edge)
        defer { controller.dismiss(animated: false) }
        let detection = ClipboardAssistantDetection(kind: .color, title: title,
            colorComponents: .init(red: 1, green: 0, blue: 0))
        controller.present(detection, visualStyle: .transparent)
        let layout = controller.rowLayout(for: detection, on: screen, locale: locale(direction))
        let viewport = CGRect(x: 4, y: 40, width: 24, height: 168)
        #expect(layout.frame.size == CGSize(width: 32, height: 242))
        for renderScale in [CGFloat(1), 2] {
            var samples: [[UInt8]] = []
            for progress in [0.0, 0.5, 1] {
                let actual = try await render(ClipboardAssistantToastView(
                    presentation: controller.presentation, controller: controller), size: layout.frame.size,
                    progress: progress, direction: direction, renderScale: renderScale)
                let expected = try await render(ReferenceVerticalWindow(text: title, size: viewport.size), size: viewport.size,
                    progress: progress, direction: direction, renderScale: renderScale)
                let sample = try pixels(actual, in: viewport)
                #expect(differences(sample, try pixels(expected)) == 0,
                    "A side quick action must scroll its complete upright text within the original 168pt viewport")
                #expect(sample.contains { $0 > 64 })
                samples.append(sample)
                #expect(controller.presentation.layout == layout && controller.presentation.physicalNotchWidth == 0)
                #expect(controller.presentation.detection == detection)
            }
            #expect(differences(samples[0], samples[1]) > 30 && differences(samples[1], samples[2]) > 30)
        }
    }

    @Test(arguments: [(IslandLayoutStyle.pill, IslandEdge.bottom), (.pill, .right), (.notch, .top)],
          [LayoutDirection.leftToRight, .rightToLeft])
    func reduceMotionKeepsOverflowingQuickActionsReadableAndStationary(
        placement: (IslandLayoutStyle, IslandEdge), direction: LayoutDirection
    ) async throws {
        let controller = makeController(style: placement.0, edge: placement.1)
        defer { controller.dismiss(animated: false) }
        let detection = ClipboardAssistantDetection(kind: .color, title: title, detail: .path(detail),
            colorComponents: .init(red: 1, green: 0, blue: 0))
        controller.present(detection, visualStyle: .transparent)
        let layout = controller.rowLayout(for: detection, on: screen, locale: locale(direction))
        let first = try await render(ClipboardAssistantToastView(presentation: controller.presentation,
            controller: controller), size: layout.frame.size, progress: 0,
            direction: direction, reduceMotion: true)
        let later = try await render(ClipboardAssistantToastView(presentation: controller.presentation,
            controller: controller), size: layout.frame.size, progress: 0.5,
            direction: direction, reduceMotion: true)
        #expect(differences(try pixels(first), try pixels(later)) == 0,
            "Reduce Motion must stop automatic text movement while keeping the prompt visible")
        let viewport = placement.1.isVertical ? CGRect(x: 4, y: 40, width: 24, height: 168)
            : textViewport(layout: layout, direction: direction,
                notchWidth: controller.presentation.physicalNotchWidth)
        #expect(try pixels(first, in: viewport).contains { $0 > 64 })
        #expect(controller.presentation.layout == layout && controller.presentation.detection == detection)
    }

    @Test(arguments: [IslandEdge.bottom, .right], [false, true])
    func shortAndEmptyQuickActionsKeepTheirNaturalLengthWithoutMoving(
        edge: IslandEdge, reduceMotion: Bool
    ) async throws {
        let controller = makeController(style: .pill, edge: edge)
        defer { controller.dismiss(animated: false) }
        for text in ["短", ""] {
            let detection = ClipboardAssistantDetection(kind: .color, title: text,
                colorComponents: .init(red: 1, green: 0, blue: 0))
            controller.present(detection, visualStyle: .transparent)
            let layout = controller.rowLayout(for: detection, on: screen, locale: locale(.leftToRight))
            let length = edge.isVertical ? layout.frame.height : layout.frame.width
            #expect(length < 150 && length.isFinite)
            let first = try await render(ClipboardAssistantToastView(presentation: controller.presentation,
                controller: controller), size: layout.frame.size, progress: 0,
                direction: .leftToRight, reduceMotion: reduceMotion)
            let later = try await render(ClipboardAssistantToastView(presentation: controller.presentation,
                controller: controller), size: layout.frame.size, progress: 0.5,
                direction: .leftToRight, reduceMotion: reduceMotion)
            #expect(differences(try pixels(first), try pixels(later)) == 0,
                "A short or empty prompt must not allocate a scrolling gap or expand to the maximum length")
            #expect(controller.presentation.detection == detection && controller.presentation.layout == layout)
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func quickActionTitlesRenderTheirSelectedLanguageWithoutChangingTheRow(language: AppLanguage) async throws {
        let controller = makeController(style: .notch, edge: .top)
        defer { controller.dismiss(animated: false) }
        let detection = ClipboardAssistantDetection(kind: .color, title: "复制结果",
            colorComponents: .init(red: 1, green: 0, blue: 0))
        controller.present(detection, visualStyle: .transparent)
        let layout = controller.rowLayout(for: detection, on: screen, locale: language.locale)
        let direction: LayoutDirection = language.isRightToLeft ? .rightToLeft : .leftToRight
        let viewport = textViewport(layout: layout, direction: direction,
            notchWidth: controller.presentation.physicalNotchWidth)
        let text = AppLocalization.string(detection.title, language: language)
        let actual = try await render(ClipboardAssistantToastView(presentation: controller.presentation,
            controller: controller).environment(\.locale, language.locale), size: layout.frame.size,
            progress: 0, direction: direction)
        let expected = try await render(referenceLine(text, width: viewport.width, fontSize: 12,
            weight: .medium, opacity: 0.92, direction: direction, progress: 0)
            .frame(width: viewport.width, height: viewport.height, alignment: .leading)
            .environment(\.locale, language.locale).environment(\.layoutDirection, direction)
            .position(x: viewport.midX, y: viewport.midY).environment(\.layoutDirection, .leftToRight),
            size: layout.frame.size, progress: 0, direction: direction)
        #expect(!text.isEmpty)
        #expect(differences(try pixels(actual, in: viewport), try pixels(expected, in: viewport)) == 0,
            "A quick action must use the selected \(language.rawValue) locale without falling back to the global locale")
        #expect(controller.presentation.layout == layout && controller.presentation.detection == detection)
    }

    private func makeController(style: IslandLayoutStyle, edge: IslandEdge) -> ClipboardAssistantController {
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        controller.displayDuration = .never
        controller.isLightweightMode = false
        controller.presentation.progressGlowEnabled = false
        controller.screenLayoutConfiguration = ScreenLayoutConfiguration(layoutStyle: style,
            placement: IslandPlacement(mode: style == .pill ? .custom : .camera, edge: edge),
            pillSize: CGSize(width: 80, height: 32))
        return controller
    }

    private func locale(_ direction: LayoutDirection) -> Locale {
        Locale(identifier: direction == .leftToRight ? "zh-Hans" : "ar")
    }

    private var screen: ScreenSnapshot {
        ScreenSnapshot(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 842),
            safeAreaInsets: ScreenInsets(top: 34),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 866, width: 627.5, height: 34),
            auxiliaryTopRightArea: CGRect(x: 812.5, y: 866, width: 627.5, height: 34))
    }

    private func textViewport(layout: ClipboardAssistantController.RowLayout,
        direction: LayoutDirection, notchWidth: CGFloat) -> CGRect {
        let width = notchWidth > 0
            ? ClipboardAssistantToastView.physicalNotchSideWidth(totalWidth: layout.frame.width,
                notchWidth: notchWidth) - 58
            : layout.frame.width - 94
        return CGRect(x: direction == .leftToRight ? 50 : layout.frame.width - 50 - width,
            y: 0, width: width, height: layout.rowHeight)
    }

    private func referenceHeader(width: CGFloat, direction: LayoutDirection, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            referenceLine(title, width: width, fontSize: 12, weight: .medium,
                opacity: 0.92, direction: direction, progress: progress)
            referenceLine(detail, width: width, fontSize: 9.5, weight: .regular,
                opacity: 0.55, direction: direction, progress: progress)
        }
    }

    private func referenceLine(_ text: String, width: CGFloat, fontSize: CGFloat,
        weight: NSFont.Weight, opacity: Double, direction: LayoutDirection, progress: Double) -> some View {
        ReferenceTextWindow(text: text, width: width, fontSize: fontSize,
            weight: weight == .medium ? .medium : .regular, opacity: opacity, direction: direction,
            progress: CGFloat(progress))
    }

    private func render(_ content: some View, size: CGSize, progress: Double,
        direction: LayoutDirection, reduceMotion: Bool = false, renderScale: CGFloat? = nil) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .background(.black).environment(\.locale, locale(direction))
            .environment(\.layoutDirection, direction)
            .environment(\._accessibilityReduceMotion, reduceMotion)
            .transaction { transaction in
                if transaction.animation != nil {
                    transaction.animation = Animation(FrozenProgress(progress: progress))
                }
            })
        host.sizingOptions = []
        let window = RasterPanel(contentRect: CGRect(origin: CGPoint(x: 20_000, y: 0), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.renderScale = renderScale
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        for _ in 0..<24 {
            host.layoutSubtreeIfNeeded()
            host.cacheDisplay(in: host.bounds, to: bitmap)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        #expect(CGFloat(bitmap.pixelsWide) / size.width == window.backingScaleFactor
            && CGFloat(bitmap.pixelsHigh) / size.height == window.backingScaleFactor)
        #expect(host.bounds.size == size && window.frame.size == size,
            "Text scrolling must keep the host and window at their original dimensions")
        #expect(!window.isVisible)
        let converted = try #require(bitmap.converting(to: .sRGB, renderingIntent: .default))
        converted.size = size
        return converted
    }

    private struct ReferenceVerticalWindow: View {
        let text: String
        let size: CGSize
        @State private var progress: CGFloat = 0

        var body: some View {
            VStack(spacing: 1) {
                ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                    Text(String(character)).font(.system(size: 11, weight: .medium)).frame(height: 13)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .offset(y: -max(0, CGFloat(text.count) * 14 - 1 - size.height) * progress)
            .frame(width: size.width, height: size.height, alignment: .top).clipped()
            .foregroundStyle(.white.opacity(0.85))
            .task {
                withAnimation(.linear(duration: 1)) { progress = 1 }
            }
        }
    }

    private struct ReferenceTextWindow: View {
        let text: String
        let width: CGFloat
        let fontSize: CGFloat
        let weight: Font.Weight
        let opacity: Double
        let direction: LayoutDirection
        let progress: CGFloat
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            let naturalWidth = (text as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight == .medium ? .medium : .regular)
            ]).width
            let travel = max(0, ceil(naturalWidth * displayScale) / displayScale - width)
            Text(text).font(.system(size: fontSize)).fontWeight(weight)
                .foregroundStyle(.white.opacity(opacity))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .offset(x: direction == .leftToRight ? -travel * progress : travel * (progress - 1))
                .frame(width: width, alignment: .leading).clipped()
        }
    }

    private func pixels(_ bitmap: NSBitmapImageRep, in rect: CGRect? = nil) throws -> [UInt8] {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let xRange = rect.map { Int($0.minX * scale)..<Int($0.maxX * scale) } ?? 0..<bitmap.pixelsWide
        let yRange = rect.map { Int($0.minY * scale)..<Int($0.maxY * scale) } ?? 0..<bitmap.pixelsHigh
        var result: [UInt8] = []
        for y in yRange {
            for x in xRange {
                let red = try #require(bitmap.colorAt(x: x, y: y)).redComponent
                result.append(UInt8((red * 255).rounded()))
            }
        }
        return result
    }

    private func inkColumns(_ bitmap: NSBitmapImageRep, in rect: CGRect) throws -> [Int] {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        var result: [Int] = []
        for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
            for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
                if try #require(bitmap.colorAt(x: x, y: y)).redComponent > 0.3 {
                    result.append(Int(CGFloat(x) / scale - rect.minX))
                    break
                }
            }
        }
        return result
    }

    private func differences(_ first: [UInt8], _ second: [UInt8]) -> Int {
        #expect(first.count == second.count)
        return zip(first, second).filter { abs(Int($0) - Int($1)) > 3 }.count
    }

    private final class RasterPanel: NSPanel {
        var renderScale: CGFloat?
        override var backingScaleFactor: CGFloat { renderScale ?? super.backingScaleFactor }
    }

    private struct FrozenProgress: CustomAnimation {
        let progress: Double

        func animate<V: VectorArithmetic>(value: V, time: TimeInterval,
            context: inout AnimationContext<V>) -> V? {
            value.scaled(by: progress)
        }
    }
}
