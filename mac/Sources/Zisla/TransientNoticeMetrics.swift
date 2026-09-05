import AppKit
import SwiftUI

/// Metrics shared by the two transient-notice rows — the one protruding under the collapsed pill and the
/// bar along an expanded panel's bottom edge — and by the model that recycles them.
///
/// The rows are one line wide enough for a short result message. Anything longer scrolls once from head
/// to tail, so the dismissal timer has to be derived from the same font, padding and scroll speed the
/// rows lay out with: on a fixed timer a long error vanishes half-read.
enum TransientNoticeMetrics {
    static let fontSize: CGFloat = 10.5
    static let font: Font = .system(size: fontSize)
    static let fontWeight: Font.Weight = .medium
    /// Leading and trailing inset of the notice row inside the collapsed pill's width.
    static let rowHorizontalPadding: CGFloat = 12
    /// Marquee reading speed in points per second.
    static let pointsPerSecond: Double = 32
    /// A message that fits shows instantly, so it only needs the beat every result toast has had.
    static let minimumSeconds: Double = 4
    /// An error worth reading beats a shorter notice, but nothing camps on the notch: past this the
    /// pass is cut short and the module's own error surface has to carry the rest.
    static let maximumSeconds: Double = 16
    /// Time left over once the pass ends, so the tail can be read instead of vanishing with it.
    private static let tailHoldSeconds: Double = 2.4

    static func displayDuration(for message: String, rowWidth: CGFloat) -> Duration {
        displayDuration(textWidth: textWidth(of: message), rowWidth: rowWidth)
    }

    static func displayDuration(textWidth: CGFloat, rowWidth: CGFloat) -> Duration {
        let available = max(0, rowWidth - rowHorizontalPadding * 2)
        let travel = max(0, textWidth - available)
        let seconds = min(
            maximumSeconds,
            max(minimumSeconds, Double(travel) / pointsPerSecond + tailHoldSeconds)
        )
        return .milliseconds(Int((seconds * 1000).rounded()))
    }

    /// `MarqueeText` measures its own rendered label to decide how far to scroll; this mirrors that
    /// measurement so the timer and the animation agree on the travel distance. The font is built per
    /// call because `NSFont` is not `Sendable` and this has to stay callable off the main actor.
    static func textWidth(of message: String) -> CGFloat {
        let measurementFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        return (message as NSString).size(withAttributes: [.font: measurementFont]).width
    }
}
