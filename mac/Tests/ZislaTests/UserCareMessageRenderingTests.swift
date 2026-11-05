import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@MainActor
@Suite(.serialized)
struct UserCareMessageRenderingTests {
    @Test(arguments: ["🍵", "💧", "🌿", "👀", "🍚", "💤", "🌙", "📝", "📌", "(๑•̀ㅂ•́)و✧"], [CGFloat(1), 2])
    func decorationsKeepTheirCompleteGlyphsInsideTheExistingTwentyPointRow(text: String, scale: CGFloat) async throws {
        let geometry = VoiceRecordingIslandGeometry(collapsedSize: CGSize(width: 240, height: 32),
            availableSize: CGSize(width: 240, height: 52))
        for language in [AppLanguage.simplifiedChinese, .arabic] {
            let reference = try await render(Text(text).font(TransientNoticeMetrics.font)
                .fontWeight(TransientNoticeMetrics.fontWeight).foregroundStyle(.white.opacity(0.82))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(width: 216, height: 40, alignment: .leading).padding(.horizontal, 12),
                language: language, scale: scale, size: CGSize(width: 240, height: 40))
            let expected = try pixels(reference, rect: CGRect(x: 0, y: 10, width: 240, height: 20))
            #expect(expected.contains { $0 > 64 }, "The reference must draw visible emoji or kaomoji glyphs")
            #expect(try pixels(reference, rect: CGRect(x: 0, y: 0, width: 240, height: 10)).allSatisfy { $0 < 4 })
            #expect(try pixels(reference, rect: CGRect(x: 0, y: 30, width: 240, height: 10)).allSatisfy { $0 < 4 },
                "The existing 20pt row must contain the full natural glyph height")
            for reduceMotion in [false, true] {
                let actual = try await render(TransientNoticeView(message: text, geometry: geometry),
                    language: language, scale: scale, size: geometry.surfaceSize, reduceMotion: reduceMotion)
                #expect(differences(try pixels(actual, rect: geometry.transcriptRowFrame), expected) == 0,
                    "Island feedback must keep every decoration glyph in both layout directions and motion settings")
            }
        }
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic, .vietnamese], [false, true])
    func noteAndEyeCareFeedbackReadsFromHeadToTailInTheExistingSmallIsland(language: AppLanguage, petEnabled: Bool) async throws {
        let geometry = VoiceRecordingIslandGeometry(collapsedSize: CGSize(width: 100, height: 32),
            availableSize: CGSize(width: 120, height: 52))
        let row = geometry.transcriptRowFrame
        for reminder in [UserCareReminder.noteCreated, .noteUpdated, .eyeDrops] {
            let text = reminder.localizedMessage(petEnabled: petEnabled, language: language)
            for style in [IslandLayoutStyle.notch, .pill] {
                let mask = IslandRevealMask(collapsedSize: geometry.collapsedSize, expandedSize: geometry.surfaceSize,
                    isCollapsed: false, expandedBottomCornerRadius: VoiceRecordingIslandGeometry.bottomCornerRadius,
                    layoutStyle: style)
                for progress in [0.0, 1] {
                    let actual = try await render(TransientNoticeView(message: text, geometry: geometry).mask(mask),
                        language: language, scale: 2, size: geometry.surfaceSize, progress: progress)
                    let expected = try await render(referenceRow(text, geometry: geometry, language: language,
                        alignment: progress == 0 ? .leading : .trailing).mask(mask),
                        language: language, scale: 2, size: geometry.surfaceSize, progress: progress)
                    #expect(differences(try pixels(actual, rect: row), try pixels(expected, rect: row)) == 0,
                        "Health and note feedback must retain both ends inside the existing notch and capsule notice row")
                }
            }
        }
    }

    private func referenceRow(_ text: String, geometry: VoiceRecordingIslandGeometry,
        language: AppLanguage, alignment: Alignment) -> some View {
        let row = geometry.transcriptRowFrame
        return Text(text).font(TransientNoticeMetrics.font).fontWeight(TransientNoticeMetrics.fontWeight)
            .foregroundStyle(.white.opacity(0.82)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .frame(width: row.width - 24, height: row.height, alignment: alignment)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .clipped().padding(.horizontal, 12)
            .frame(width: row.width, height: row.height)
            .position(x: row.midX, y: row.midY)
            .environment(\.layoutDirection, .leftToRight)
    }

    private func render(_ content: some View, language: AppLanguage, scale: CGFloat,
        size: CGSize, progress: Double = 0, reduceMotion: Bool = false) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .foregroundStyle(.white).background(.black).environment(\.locale, language.locale)
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
        #expect(!window.isVisible && host.bounds.size == size)
        let converted = try #require(bitmap.converting(to: .sRGB, renderingIntent: .default))
        converted.size = size
        return converted
    }

    private func pixels(_ bitmap: NSBitmapImageRep, rect: CGRect? = nil) throws -> [UInt8] {
        let rect = rect ?? CGRect(origin: .zero, size: bitmap.size)
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        var result: [UInt8] = []
        for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
            for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                for component in [color.redComponent, color.greenComponent, color.blueComponent] {
                    result.append(UInt8((component * 255).rounded()))
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
