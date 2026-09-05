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

    /// For a control whose label *is* its content (action buttons, status labels, menu pickers) sitting
    /// next to wrappable copy. A settings row gives its title/description column `.layoutPriority(1)`,
    /// so the description takes the width it wants and leaves the control only its minimum — which,
    /// once tightening and scaling are allowed, is close to zero: German "Tastenklang anhören" rendered
    /// as "T…". Claiming the label's own width instead pushes the description into wrapping, and
    /// changes nothing wherever the description already fits on one line.
    ///
    /// A menu picker gets this twice over: its intrinsic width comes from its widest menu item, so a
    /// hard-coded width both starves long option sets (German "Umschaltmodus" laid out at 31.5 of
    /// 151.5pt) and wastes space on short ones (pet side left/right claiming 150pt for 61.5pt of text).
    func keepsIntrinsicWidth() -> some View {
        fixedSize(horizontal: true, vertical: false)
    }

    /// For menu items whose text comes from user data (model names, imported file names): caps how much
    /// width one item may contribute to the picker's intrinsic size, keeping the row's description
    /// readable. A 40-character model name would otherwise widen the picker to 300pt and push the row
    /// from 27 to 85pt tall.
    func fitsMenuItem(maxWidth: CGFloat) -> some View {
        modifier(MenuItemFit(maxWidth: maxWidth))
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

private struct MenuItemFit: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: maxWidth)
    }
}
