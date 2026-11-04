import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct VoiceRecordingTextLayoutTests {
    @Test(arguments: AppLanguage.allCases)
    func idleCircleReservesTheEntireLocalizedListeningPrompt(language: AppLanguage) async throws {
        let text = AppLocalization.string("正在聆听…", language: language)
        let naturalWidth = (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium)
        ]).width
        for edge in [IslandEdge.top, .bottom] {
            let geometry = recordingGeometry(edge: edge, language: language)
            #expect(geometry.transcriptRowFrame.width - 24 >= naturalWidth,
                "The 32pt idle circle must reserve every glyph of the localized listening prompt")
            #expect(geometry.surfaceSize.height == 52,
                "The listening prompt must keep the existing single 20pt transcript row")
            for scale in [CGFloat(1), 2] {
                let actual = try await render(VoiceTranscriptionView(isRecording: true, transcript: " \n ",
                    errorDescription: nil, geometry: geometry, keepsIconsAdjacent: true)
                    .mask(recordingMask(geometry)), geometry: geometry, language: language,
                    reduceMotion: true, scale: scale)
                let expected = try await render(referenceRow(text, geometry: geometry,
                    direction: language.isRightToLeft ? .rightToLeft : .leftToRight),
                    geometry: geometry, language: language, reduceMotion: true, scale: scale)
                #expect(try differences(actual, expected, in: geometry.transcriptRowFrame) == 0,
                    "The complete \(language.rawValue) listening prompt must survive the rounded island mask")
            }
        }
    }

    @Test(arguments: IslandEdge.allCases, [LayoutDirection.leftToRight, .rightToLeft])
    func liveTranscriptionKeepsItsLogicalTailInsideTheExistingRow(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let language: AppLanguage = direction == .rightToLeft ? .arabic : .simplifiedChinese
        let geometry = recordingGeometry(edge: edge, language: language)
        let text = direction == .rightToLeft
            ? "بداية " + String(repeating: "هذا نص طويل للاختبار ", count: 10) + "نهاية التسجيل"
            : "开头 " + String(repeating: "实时识别内容需要继续更新 ", count: 10) + "录音结尾"
        for reduceMotion in [false, true] {
            let actual = try await render(VoiceTranscriptionView(isRecording: true, transcript: " \n\(text)\n ",
                errorDescription: nil, geometry: geometry, keepsIconsAdjacent: true)
                .mask(recordingMask(geometry)), geometry: geometry, language: language,
                reduceMotion: reduceMotion)
            let expected = try await render(referenceRow(text, geometry: geometry, alignment: .trailing,
                direction: direction),
                geometry: geometry, language: language, reduceMotion: reduceMotion)
            #expect(try differences(actual, expected, in: geometry.transcriptRowFrame) == 0,
                "Live transcription must retain its logical ending in \(direction), including with Reduce Motion")
        }
    }

    @Test(arguments: [AppLanguage.vietnamese, .arabic], [CGFloat(1), 2])
    func shortLiveTranscriptionKeepsItsCompleteDiacritics(language: AppLanguage, scale: CGFloat) async throws {
        let geometry = recordingGeometry(edge: .top, language: language)
        let direction: LayoutDirection = language.isRightToLeft ? .rightToLeft : .leftToRight
        let text = language == .arabic ? "جارٍ" : "lắng"
        let actual = try await render(VoiceTranscriptionView(isRecording: true, transcript: text,
            errorDescription: nil, geometry: geometry, keepsIconsAdjacent: true)
            .mask(recordingMask(geometry)), geometry: geometry, language: language,
            reduceMotion: true, scale: scale)
        let expected = try await render(referenceRow(text, geometry: geometry, direction: direction),
            geometry: geometry, language: language, reduceMotion: true, scale: scale)
        #expect(try differences(actual, expected, in: geometry.transcriptRowFrame) == 0,
            "A short live transcript must retain every diacritic inside the static clipping window")
    }

    @Test(arguments: [IslandEdge.top, .right], [LayoutDirection.leftToRight, .rightToLeft])
    func recordingErrorsReadFromTheHeadThenReachTheTail(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let language: AppLanguage = direction == .rightToLeft ? .arabic : .simplifiedChinese
        let geometry = recordingGeometry(edge: edge, language: language)
        let message = direction == .rightToLeft
            ? "تعذر التسجيل " + String(repeating: "تحقق من إذن الميكروفون ", count: 8) + "ثم أعد المحاولة"
            : "录音失败 " + String(repeating: "请检查麦克风权限和输入设备 ", count: 8) + "然后重新尝试"
        for progress in [0.0, 1] {
            let actual = try await render(VoiceTranscriptionView(isRecording: true, transcript: "stale transcript",
                errorDescription: message, geometry: geometry, keepsIconsAdjacent: true),
                geometry: geometry, language: language, progress: progress)
            let expected = try await render(referenceRow(message, geometry: geometry,
                alignment: progress == 0 ? .leading : .trailing, direction: direction), geometry: geometry,
                language: language, progress: progress)
            #expect(try differences(actual, expected, in: geometry.transcriptRowFrame) == 0,
                "A recording error must be readable from its beginning and finish its existing single scroll pass")
        }
    }

    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func aScreenConstrainedListeningPromptStartsAtItsHead(direction: LayoutDirection) async throws {
        let language: AppLanguage = direction == .rightToLeft ? .arabic : .dutch
        let geometry = VoiceRecordingIslandGeometry(collapsedSize: CGSize(width: 32, height: 32),
            availableSize: CGSize(width: 70, height: 52))
        let text = AppLocalization.string("正在聆听…", language: language)
        for progress in [0.0, 1] {
            let actual = try await render(VoiceTranscriptionView(isRecording: true, transcript: "",
                errorDescription: nil, geometry: geometry, keepsIconsAdjacent: true),
                geometry: geometry, language: language, progress: progress)
            let expected = try await render(referenceRow(text, geometry: geometry,
                alignment: progress == 0 ? .leading : .trailing, direction: direction), geometry: geometry,
                language: language, progress: progress)
            #expect(try differences(actual, expected, in: geometry.transcriptRowFrame) == 0,
                "When screen space constrains a localized status, its scroll must include both its beginning and ending")
        }
    }

    @Test
    func preparingHidesThePreviousTakeAndEmptyErrorsKeepAnEmptyRow() async throws {
        let geometry = recordingGeometry(edge: .top, language: .simplifiedChinese)
        for error in [String?.none, ""] {
            let actual = try await render(VoiceTranscriptionView(isRecording: false, transcript: "previous take",
                errorDescription: error, geometry: geometry, keepsIconsAdjacent: true),
                geometry: geometry, language: .simplifiedChinese, reduceMotion: true)
            let expected = try await render(referenceRow(error ?? "…", geometry: geometry),
                geometry: geometry, language: .simplifiedChinese, reduceMotion: true)
            #expect(try differences(actual, expected, in: geometry.transcriptRowFrame, requiresText: error == nil) == 0,
                "Preparation must not expose a prior take, and an empty error must not claim the microphone is listening")
        }
    }

    @Test(arguments: IslandEdge.allCases, [LayoutDirection.leftToRight, .rightToLeft])
    func transientNoticesReadHeadToTailInsideTheirPhysicalTextRow(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let language: AppLanguage = direction == .rightToLeft ? .arabic : .simplifiedChinese
        let geometry = recordingGeometry(edge: edge, language: language)
        let message = direction == .rightToLeft
            ? "بداية " + String(repeating: "تعذر إكمال هذه العملية ", count: 10) + "النهاية"
            : "开头 " + String(repeating: "无法完成操作，请检查设置 ", count: 10) + "结尾"
        for progress in [0.0, 1] {
            let actual = try await render(TransientNoticeView(message: message, geometry: geometry)
                .mask(recordingMask(geometry)), geometry: geometry, language: language, progress: progress)
            let expected = try await render(referenceRow(message, geometry: geometry,
                alignment: progress == 0 ? .leading : .trailing, direction: direction, opacity: 0.82),
                geometry: geometry, language: language, progress: progress)
            #expect(try differences(actual, expected, in: geometry.transcriptRowFrame) == 0,
                "Transient errors must read from head to tail inside the same physical row in every placement")
        }
    }

    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft], [0.0, 1])
    func defaultMarqueesKeepTheirExistingLogicalReadingDirection(
        direction: LayoutDirection, progress: Double
    ) async throws {
        let language: AppLanguage = direction == .rightToLeft ? .arabic : .simplifiedChinese
        let geometry = recordingGeometry(edge: .top, language: language)
        let row = geometry.transcriptRowFrame
        let text = direction == .rightToLeft
            ? "بداية " + String(repeating: "هذا نص للاختبار ", count: 10) + "النهاية"
            : "开头 " + String(repeating: "保持原有滚动方向 ", count: 10) + "结尾"
        let actual = try await render(MarqueeText(text, font: .system(size: 10.5),
            textColor: .white.opacity(0.72), fontWeight: .medium, repeats: false,
            scrollProgress: progress, viewportHeight: row.height)
            .environment(\.layoutDirection, direction)
            .padding(.horizontal, 12).frame(width: row.width, height: row.height)
            .position(x: row.midX, y: row.midY).environment(\.layoutDirection, .leftToRight),
            geometry: geometry, language: language)
        let expected = try await render(referenceRow(text, geometry: geometry,
            alignment: progress == 0 ? .leading : .trailing, direction: direction),
            geometry: geometry, language: language)
        #expect(try differences(actual, expected, in: row) == 0,
            "Default marquees must preserve their existing logical head-to-tail direction in RTL interfaces")
    }

    private func recordingGeometry(edge: IslandEdge, language: AppLanguage) -> VoiceRecordingIslandGeometry {
        let collapsed = CGSize(width: 32, height: 32)
        let layout = IslandModuleLayout.compactSurface(collapsedSize: collapsed, overflowWidth: 32,
            edge: edge, locale: language.locale)
        return VoiceRecordingIslandGeometry(collapsedSize: collapsed, availableSize: layout.islandSize, edge: edge)
    }

    private func recordingMask(_ geometry: VoiceRecordingIslandGeometry) -> IslandRevealMask {
        IslandRevealMask(collapsedSize: geometry.collapsedSize, expandedSize: geometry.surfaceSize,
            isCollapsed: false, expandedBottomCornerRadius: VoiceRecordingIslandGeometry.bottomCornerRadius,
            layoutStyle: .pill)
    }

    private func referenceRow(_ text: String, geometry: VoiceRecordingIslandGeometry,
        alignment: Alignment = .leading, direction: LayoutDirection = .leftToRight,
        opacity: Double = 0.72) -> some View {
        let row = geometry.transcriptRowFrame
        return Text(text)
            .font(.system(size: 10.5)).fontWeight(.medium)
            .foregroundStyle(.white.opacity(opacity))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .frame(width: row.width - 24, height: row.height, alignment: alignment)
            .environment(\.layoutDirection, direction)
            .clipped().padding(.horizontal, 12)
            .frame(width: row.width, height: row.height)
            .position(x: row.midX, y: row.midY)
            .environment(\.layoutDirection, .leftToRight)
    }

    private func render(_ content: some View, geometry: VoiceRecordingIslandGeometry, language: AppLanguage,
        progress: Double = 0, reduceMotion: Bool = false, scale: CGFloat = 2) async throws -> NSBitmapImageRep {
        let size = geometry.surfaceSize
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .background(.black).environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .environment(\._accessibilityReduceMotion, reduceMotion)
            .transaction { transaction in
                if transaction.animation != nil { transaction.animation = Animation(FrozenProgress(progress: progress)) }
            })
        host.sizingOptions = []
        let window = RasterPanel(contentRect: CGRect(origin: CGPoint(x: 20_000, y: 0), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.renderScale = scale
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        for _ in 0..<12 {
            host.layoutSubtreeIfNeeded()
            host.cacheDisplay(in: host.bounds, to: bitmap)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        #expect(host.bounds.size == size && window.frame.size == size)
        #expect(!window.isVisible)
        let converted = try #require(bitmap.converting(to: .sRGB, renderingIntent: .default))
        converted.size = size
        return converted
    }

    private func differences(_ actual: NSBitmapImageRep, _ expected: NSBitmapImageRep, in rect: CGRect,
        requiresText: Bool = true) throws -> Int {
        #expect(actual.pixelsWide == expected.pixelsWide && actual.pixelsHigh == expected.pixelsHigh)
        let scale = CGFloat(actual.pixelsWide) / actual.size.width
        var count = 0
        var expectedInk = 0
        for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
            for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
                let first = try #require(actual.colorAt(x: x, y: y)).redComponent
                let second = try #require(expected.colorAt(x: x, y: y)).redComponent
                if abs(first - second) > 3.0 / 255 { count += 1 }
                if second > 0.25 { expectedInk += 1 }
            }
        }
        if requiresText {
            #expect(expectedInk > 0, "A nonempty reference must draw visible text inside the physical transcript row")
        }
        return count
    }

    private final class RasterPanel: NSPanel {
        var renderScale: CGFloat = 2
        override var backingScaleFactor: CGFloat { renderScale }
    }

    private struct FrozenProgress: CustomAnimation {
        let progress: Double

        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            value.scaled(by: progress)
        }
    }
}
