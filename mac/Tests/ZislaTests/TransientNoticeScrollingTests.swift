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

}
