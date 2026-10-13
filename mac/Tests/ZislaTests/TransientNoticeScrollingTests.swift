import Foundation
import Testing

@testable import Zisla
@testable import ZislaKit

/// A transient notice too wide for its row has to scroll from head to tail. Both rows used to be handed a
/// constant `scrollProgress`, which `MarqueeText` treats as an externally-driven position: at `1` an
/// overflowing message sat at the end of its travel with the head clipped off the leading edge, so the
/// reader only ever saw its last few words. The dismissal timer was a fixed four seconds, which is shorter
/// than the pass a long error needs.
struct TransientNoticeScrollingTests {
    @Test
    func compactNoticeScrollsItselfInsteadOfHoldingAFixedPosition() throws {
        let notice = try Self.islandSlice(
            from: "private struct TransientNoticeView",
            to: "@MainActor\nprivate final class IslandDropState"
        )

        #expect(notice.contains("MarqueeText("))
        #expect(notice.contains("repeats: false"))
        #expect(!notice.contains("scrollProgress"))
        // A hard clip hides the overflow mid-glyph; without it Reduce Motion gets an ellipsis instead.
        #expect(!notice.contains("clipsOverflowWhenStatic"))
        // Shared metrics keep the row's layout and the dismissal timer on one font and one speed.
        #expect(notice.contains("TransientNoticeMetrics.font"))
        #expect(notice.contains("TransientNoticeMetrics.pointsPerSecond"))
    }

    @Test
    func expandedNoticeBarScrollsItselfToo() throws {
        let bar = try Self.islandSlice(
            from: "private func transientNoticeBar(",
            to: "private func shareDetectedLink()"
        )

        #expect(bar.contains("MarqueeText("))
        #expect(bar.contains("repeats: false"))
        #expect(!bar.contains("scrollProgress"))
        #expect(!bar.contains("clipsOverflowWhenStatic"))
        #expect(bar.contains("TransientNoticeMetrics.font"))
        #expect(bar.contains("TransientNoticeMetrics.pointsPerSecond"))
    }

    @Test
    func dismissalIsDerivedFromTheMessageRatherThanAFixedBeat() throws {
        let source = try String(contentsOf: Self.sourceURL("AppModel.swift"), encoding: .utf8)

        #expect(source.contains("TransientNoticeMetrics.displayDuration("))
        #expect(!source.contains("transientMessageDuration"))
    }

    @Test
    func aMessageThatFitsKeepsTheShortToastBeat() {
        let duration = TransientNoticeMetrics.displayDuration(textWidth: 120, rowWidth: 240)

        #expect(duration == .seconds(TransientNoticeMetrics.minimumSeconds))
    }

    @Test
    func anOverflowingMessageOutlivesItsScrollPass() {
        let rowWidth: CGFloat = 240
        let travel: CGFloat = 205
        let available = rowWidth - TransientNoticeMetrics.rowHorizontalPadding * 2
        let duration = TransientNoticeMetrics.displayDuration(
            textWidth: available + travel,
            rowWidth: rowWidth
        )

        #expect(duration > Self.scrollPass(travel: travel))
        #expect(duration > .seconds(TransientNoticeMetrics.minimumSeconds))
    }

    /// Past the cap the pass is cut short on purpose: a notice that never leaves is worse than one whose
    /// tail has to be read in the module that raised it.
    @Test
    func nothingCampsOnTheNotch() {
        let duration = TransientNoticeMetrics.displayDuration(textWidth: 20_000, rowWidth: 240)

        #expect(duration == .seconds(TransientNoticeMetrics.maximumSeconds))
    }

    /// The message that surfaced the bug: it overflows the collapsed pill in every localization.
    @Test
    func theMailUnavailableNoticeIsGivenTimeToScroll() throws {
        let message = try #require(MailService.mailUnavailableMessage(isRunning: false))
        let rowWidth: CGFloat = 240
        let available = rowWidth - TransientNoticeMetrics.rowHorizontalPadding * 2
        let travel = TransientNoticeMetrics.textWidth(of: message) - available
        #expect(travel > 0)

        let duration = TransientNoticeMetrics.displayDuration(for: message, rowWidth: rowWidth)

        #expect(duration > Self.scrollPass(travel: travel))
        #expect(duration > .seconds(TransientNoticeMetrics.minimumSeconds))
        #expect(duration <= .seconds(TransientNoticeMetrics.maximumSeconds))
    }

    private static func scrollPass(travel: CGFloat) -> Duration {
        .seconds(Double(travel) / TransientNoticeMetrics.pointsPerSecond)
    }

    /// Comments are stripped so the assertions read the call sites themselves: the rows explain in prose
    /// which arguments they must not pass, and naming them there must not satisfy the checks.
    private static func islandSlice(from head: String, to tail: String) throws -> String {
        let source = try String(contentsOf: sourceURL("IslandRootView.swift"), encoding: .utf8)
        let start = try #require(source.range(of: head))
        let suffix = source[start.lowerBound...]
        let end = try #require(suffix.range(of: tail))
        return suffix[..<end.lowerBound]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private static func sourceURL(_ fileName: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla")
            .appendingPathComponent(fileName)
    }
}
