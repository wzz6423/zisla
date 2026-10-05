import SwiftUI

private struct SettingsSearchTargetKey: EnvironmentKey {
    static let defaultValue: SettingsSearchAnchor? = nil
}

private extension EnvironmentValues {
    var settingsSearchTarget: SettingsSearchAnchor? {
        get { self[SettingsSearchTargetKey.self] }
        set { self[SettingsSearchTargetKey.self] = newValue }
    }
}

private struct SettingsSearchLayoutKey: PreferenceKey {
    static let defaultValue: [SettingsSearchAnchor: CGRect] = [:]

    static func reduce(value: inout [SettingsSearchAnchor: CGRect], nextValue: () -> [SettingsSearchAnchor: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct SettingsSearchAnchorModifier: ViewModifier {
    let anchor: SettingsSearchAnchor
    @Environment(\.settingsSearchTarget) private var target

    func body(content: Content) -> some View {
        content
            .id(anchor)
            .background {
                if target == anchor {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: SettingsSearchLayoutKey.self,
                            value: [anchor: geometry.frame(in: .named("settings-search-content"))]
                        )
                    }
                }
            }
    }
}

extension View {
    func settingsSearchAnchor(_ anchor: SettingsSearchAnchor) -> some View {
        modifier(SettingsSearchAnchorModifier(anchor: anchor))
    }
}

struct SettingsSearchScrollView<Content: View>: View {
    let target: SettingsSearchAnchor?
    let resetID: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
                    .coordinateSpace(name: "settings-search-content")
            }
            .id(resetID)
            .thinScrollChrome()
            .environment(\.settingsSearchTarget, target)
            .onPreferenceChange(SettingsSearchLayoutKey.self) { frames in
                guard let target, let frame = frames[target], frame.height > 0 else { return }
                // A mounted page can still have no scrollable layout; wait for the destination's geometry.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }
}
