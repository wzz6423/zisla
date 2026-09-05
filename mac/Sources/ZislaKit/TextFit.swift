import SwiftUI

/// Localized copy runs 1.6–2.1x wider than the Chinese source (fr/es/it average 2.0x, over half
/// of all strings at 2x or more), so layouts sized for Chinese truncate in most other languages.
/// These modifiers keep the Chinese rendering untouched — tightening and scaling only engage once
/// the text no longer fits — while giving every other language a graceful fallback.
public extension View {
    /// For copy that must stay on one line (metrics, timestamps, compact labels).
    /// Tightens tracking first, then scales down, and only truncates as a last resort.
    /// Leaves `truncationMode` alone so callers keep their own choice (e.g. `.middle` for paths).
    func fitsSingleLine(_ minScale: CGFloat = 0.75) -> some View {
        modifier(TextFit(lines: 1, minScale: minScale))
    }

    /// For copy that may wrap (descriptions, hints, multi-word titles).
    /// Wraps up to `lines` first, then scales down.
    func fitsLines(_ lines: Int, minScale: CGFloat = 0.8) -> some View {
        modifier(TextFit(lines: lines, minScale: minScale))
    }
}

/// Applying the three modifiers through a `ViewModifier` instead of chaining them at each call site
/// keeps the caller's static type one level deeper rather than three. Chaining them directly inside
/// `SettingsView.sidebar` pushed `body` past the compiler's substitution limit and crashed
/// swift-frontend ("Possible non-terminating type substitution detected") in optimized builds only.
private struct TextFit: ViewModifier {
    let lines: Int
    let minScale: CGFloat

    func body(content: Content) -> some View {
        content
            .lineLimit(lines)
            .minimumScaleFactor(minScale)
            .allowsTightening(true)
    }
}
