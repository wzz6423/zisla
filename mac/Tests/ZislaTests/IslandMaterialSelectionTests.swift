import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct IslandMaterialSelectionTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func selectedMaterialReplacesThePreviousNativeSurface(floatingTarget: Bool) async throws {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let name = "zisla-material-selection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer {
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: name)
        }
        let host = NSHostingView(rootView: MaterialFixture(settings: settings, floatingTarget: floatingTarget))
        host.sizingOptions = []
        let panel = FileShelfShakeController.makeWindow(
            contentView: host,
            frame: CGRect(origin: CGPoint(x: -100_000, y: -100_000), size: FileShelfShakeLayout.size)
        )
        defer { panel.close() }
        for style in [IslandVisualStyle.transparent, .frosted, .transparent, .frosted] {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withAnimation(ZislaMotion.selection, completionCriteria: .removed) {
                    settings.settings.islandVisualStyle = style
                } completion: {
                    continuation.resume()
                }
            }
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let views = descendants(of: host)
            let effects = views.compactMap { $0 as? NSVisualEffectView }
            if #available(macOS 26.0, *) {
                let glass = views.compactMap { $0 as? NSGlassEffectView }
                #expect(glass.isEmpty == (style == .frosted || reduceTransparency))
            }
            if reduceTransparency {
                #expect(effects.isEmpty)
            } else if style == .frosted {
                #expect(effects.contains { $0.material == .hudWindow })
            }
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private struct MaterialFixture: View {
        @ObservedObject var settings: FeatureSettingsStore
        let floatingTarget: Bool

        var body: some View {
            if floatingTarget {
                FileShelfShakeView(settingsStore: settings, onItems: { _ in }, onShare: { _, _ in })
            } else {
                IslandSurface(visualStyle: settings.settings.islandVisualStyle) {
                    Color.clear.islandGlassSurface(.card, cornerRadius: 18)
                }
                .environment(\.islandVisualStyle, settings.settings.islandVisualStyle)
                .environment(\.colorScheme, .dark)
            }
        }
    }
}
