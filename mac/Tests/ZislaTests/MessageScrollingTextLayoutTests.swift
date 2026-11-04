import AppKit
import SwiftUI
import Testing
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct MessageScrollingTextLayoutTests {
    @Test(arguments: ["休息一下", "Listening…", "Đang lắng nghe…", "جارٍ الاستماع…", ""], [false, true])
    func shortMessagesKeepEveryGlyphAtFullOpacity(text: String, reduceMotion: Bool) async throws {
        let direction: LayoutDirection = text.contains("الاستماع") ? .rightToLeft : .leftToRight
        let actual = try await render(MessageScrollingText(text: text, reduceMotion: reduceMotion), direction: direction)
        let expected = try await render(reference(text, reduceMotion: reduceMotion), direction: direction)
        #expect(try differences(actual, expected) == 0,
            "A message that fits must not fade its leading or trailing glyphs")
    }

    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func overflowingMessagesReachTheirLogicalEnding(direction: LayoutDirection) async throws {
        let text = direction == .rightToLeft
            ? "بداية " + String(repeating: "تحقق من الإعدادات ", count: 10) + "النهاية"
            : "开头 " + String(repeating: "检查设置并重新尝试 ", count: 10) + "结尾"
        for progress in [0.0, 1] {
            let actual = try await render(MessageScrollingText(text: text, reduceMotion: false),
                direction: direction, progress: progress)
            let expected = try await render(Text(text).font(.system(size: 11, weight: .medium))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(width: progress == 0 ? 120 : 104, height: 20,
                    alignment: progress == 0 ? .leading : .trailing)
                .padding(.trailing, progress == 0 ? 0 : 16), direction: direction)
            #expect(try differences(actual, expected, inset: 8) == 0,
                "The existing scroll must expose the logical head and ending in both layout directions")
        }
    }

    @Test
    func reduceMotionKeepsTheTruncatedMessageAndItsEllipsisAtFullOpacity() async throws {
        let text = "请休息一下 " + String(repeating: "长时间工作后活动一下肩颈 ", count: 10)
        let actual = try await render(MessageScrollingText(text: text, reduceMotion: true))
        let expected = try await render(reference(text, reduceMotion: true))
        #expect(try differences(actual, expected) == 0,
            "Reduce Motion must retain the complete static glyphs and the existing tail ellipsis")
    }

    @Test
    func overflowingMessagesKeepTheirExistingEdgeFadeAndMovement() async throws {
        let text = "开头 " + String(repeating: "天", count: 20) + String(repeating: "地", count: 20) + " 结尾"
        let head = try await render(MessageScrollingText(text: text, reduceMotion: false))
        let middle = try await render(MessageScrollingText(text: text, reduceMotion: false), progress: 0.5)
        let unfadedHead = try await render(reference(text, reduceMotion: false))
        #expect(try differences(head, middle) > 30,
            "The existing back-and-forth scroll must continue to move overflowing messages")
        #expect(try differences(head, unfadedHead, inset: 8) == 0,
            "The fade must leave the center of the text unchanged")
        let fadedLeadingInk = try pixels(head, rect: CGRect(x: 0, y: 0, width: 8, height: 20)).reduce(0, +)
        let fullLeadingInk = try pixels(unfadedHead, rect: CGRect(x: 0, y: 0, width: 8, height: 20)).reduce(0, +)
        #expect(fadedLeadingInk > 0 && fadedLeadingInk < fullLeadingInk,
            "Only an actively scrolling overflow keeps the existing edge fade")
    }

    private func reference(_ text: String, reduceMotion: Bool) -> some View {
        Group {
            if reduceMotion {
                Text(text).font(.system(size: 11, weight: .medium))
                    .fitsSingleLine().truncationMode(.tail)
            } else {
                Text(text).font(.system(size: 11, weight: .medium))
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(width: 120, height: 20, alignment: .leading).clipped()
    }

    private func render(_ content: some View, direction: LayoutDirection = .leftToRight,
        progress: Double = 0) async throws -> NSBitmapImageRep {
        let size = CGSize(width: 120, height: 20)
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .foregroundStyle(.white).background(.black)
            .environment(\.layoutDirection, direction)
            .transaction { transaction in
                if transaction.animation != nil { transaction.animation = Animation(FrozenProgress(progress: progress)) }
            })
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 20_000, y: 0), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
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

    private func differences(_ actual: NSBitmapImageRep, _ expected: NSBitmapImageRep, inset: CGFloat = 0) throws -> Int {
        let rect = CGRect(x: inset, y: 0, width: 120 - inset * 2, height: 20)
        return try zip(pixels(actual, rect: rect), pixels(expected, rect: rect))
            .filter { abs($0 - $1) > 3 }.count
    }

    private func pixels(_ bitmap: NSBitmapImageRep, rect: CGRect) throws -> [Int] {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        var result: [Int] = []
        for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
            for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
                let red = try #require(bitmap.colorAt(x: x, y: y)).redComponent
                result.append(Int((red * 255).rounded()))
            }
        }
        return result
    }

    private struct FrozenProgress: CustomAnimation {
        let progress: Double

        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            value.scaled(by: progress)
        }
    }
}
