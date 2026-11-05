import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

@MainActor
@Suite(.serialized)
struct UserCareMessageRenderingTests {
    @Test(arguments: ["🍵", "💧", "🌿", "👀", "🍚", "💤", "🌙", "(๑•̀ㅂ•́)و✧"], [CGFloat(1), 2])
    func decorationsKeepTheirCompleteGlyphsInsideTheExistingTwentyPointRow(text: String, scale: CGFloat) async throws {
        for language in [AppLanguage.simplifiedChinese, .arabic] {
            let reference = try await render(Text(text).font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 120, height: 40, alignment: .leading), language: language, scale: scale, height: 40)
            let expected = try pixels(reference, rect: CGRect(x: 0, y: 10, width: 120, height: 20))
            #expect(expected.contains { $0 > 64 }, "The reference must draw visible emoji or kaomoji glyphs")
            #expect(try pixels(reference, rect: CGRect(x: 0, y: 0, width: 120, height: 10)).allSatisfy { $0 < 4 })
            #expect(try pixels(reference, rect: CGRect(x: 0, y: 30, width: 120, height: 10)).allSatisfy { $0 < 4 },
                "The existing 20pt row must contain the full natural glyph height")
            for reduceMotion in [false, true] {
                let actual = try await render(MessageScrollingText(text: text, reduceMotion: reduceMotion),
                    language: language, scale: scale)
                #expect(differences(try pixels(actual), expected) == 0,
                    "A short decoration must keep every glyph in both layout directions and motion settings")
            }
        }
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic, .vietnamese], [false, true])
    func decoratedCompletionMessagesRevealTheirEndingInTheExistingScroll(language: AppLanguage, petEnabled: Bool) async throws {
        let text = UserCareReminder.restCompleted.localizedMessage(petEnabled: petEnabled, language: language)
        let actual = try await render(MessageScrollingText(text: text, reduceMotion: false),
            language: language, scale: 2, progress: 1)
        let expected = try await render(Text(text).font(.system(size: 11, weight: .medium))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .frame(width: 104, height: 20, alignment: .trailing).padding(.trailing, 16),
            language: language, scale: 2)
        let center = CGRect(x: 8, y: 0, width: 104, height: 20)
        #expect(differences(try pixels(actual, rect: center), try pixels(expected, rect: center)) == 0,
            "The last words and shared decoration must remain readable at the existing scroll endpoint")
    }

    private func render(_ content: some View, language: AppLanguage, scale: CGFloat,
        height: CGFloat = 20, progress: Double = 0) async throws -> NSBitmapImageRep {
        let size = CGSize(width: 120, height: height)
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .foregroundStyle(.white).background(.black).environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
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
