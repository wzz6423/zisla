import AppKit
import SwiftUI
import ZislaCore

struct SettingsSplitView<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    @ObservedObject var input: SettingsInput
    let settings: FeatureSettings
    let onNavigate: (Bool) -> Void
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    func makeNSViewController(context: Context) -> SettingsSplitViewController {
        SettingsSplitViewController(input: input, settings: settings, locale: context.environment.locale, onNavigate: onNavigate)
    }

    func updateNSViewController(_ controller: SettingsSplitViewController, context: Context) {
        controller.update(
            sidebar: AnyView(sidebar().environment(\.self, context.environment)),
            detail: AnyView(detail().environment(\.self, context.environment)),
            settings: settings, locale: context.environment.locale, onNavigate: onNavigate
        )
    }

    static func dismantleNSViewController(_ controller: SettingsSplitViewController, coordinator: ()) {
        controller.detachToolbar()
    }
}

@MainActor
final class SettingsSplitViewController: NSSplitViewController, NSToolbarDelegate {
    static let sidebarIdentifier = NSToolbarItem.Identifier("settings.sidebar")
    static let navigationIdentifier = NSToolbarItem.Identifier("settings.navigation")

    private let input: SettingsInput
    private let sidebarHost = NSHostingController(rootView: AnyView(EmptyView()))
    private let detailHost = NSHostingController(rootView: AnyView(EmptyView()))
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let settingsToolbar = NSToolbar(identifier: "SettingsToolbar")
    private weak var toolbarWindow: NSWindow?
    private var settings: FeatureSettings
    private var locale: Locale
    private var onNavigate: (Bool) -> Void

    init(input: SettingsInput, settings: FeatureSettings, locale: Locale, onNavigate: @escaping (Bool) -> Void) {
        self.input = input
        self.settings = settings
        self.locale = locale
        self.onNavigate = onNavigate
        super.init(nibName: nil, bundle: nil)
        let split = SettingsTrackingSplitView()
        split.isVertical = true
        split.settingsController = self
        splitView = split
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebarItem.minimumThickness = 250
        sidebarItem.titlebarSeparatorStyle = .none
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: detailHost))
        configureNavigationButton(backButton, symbol: "chevron.backward", identifier: "settings-history-back", action: #selector(goBack(_:)))
        configureNavigationButton(forwardButton, symbol: "chevron.forward", identifier: "settings-history-forward", action: #selector(goForward(_:)))
        settingsToolbar.delegate = self
        settingsToolbar.displayMode = .iconOnly
        settingsToolbar.allowsUserCustomization = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(sidebar: AnyView, detail: AnyView, settings: FeatureSettings, locale: Locale, onNavigate: @escaping (Bool) -> Void) {
        self.settings = settings
        self.locale = locale
        self.onNavigate = onNavigate
        sidebarHost.rootView = sidebar
        detailHost.rootView = detail
        splitViewItems[0].isCollapsed = !input.isSidebarVisible
        updateToolbar()
    }

    fileprivate func attachToolbar(to window: NSWindow?) {
        detachToolbar()
        toolbarWindow = window
        window?.toolbar = settingsToolbar
        updateToolbar()
    }

    func detachToolbar() {
        if toolbarWindow?.toolbar === settingsToolbar {
            toolbarWindow?.toolbar = nil
        }
        toolbarWindow = nil
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        let isVisible = !splitViewItems[0].isCollapsed
        input.isSidebarVisible = isVisible
        updateToolbar()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.sidebarIdentifier, .sidebarTrackingSeparator, Self.navigationIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.sidebarIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleSettingsSidebar(_:))
            return item
        case .sidebarTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(identifier: itemIdentifier, splitView: splitView, dividerIndex: 0)
        case Self.navigationIdentifier:
            let group = NSToolbarItemGroup(itemIdentifier: itemIdentifier)
            let back = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("settings.back"))
            back.view = backButton
            let forward = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("settings.forward"))
            forward.view = forwardButton
            group.subitems = [back, forward]
            return group
        default:
            return nil
        }
    }

    @objc private func goBack(_ sender: Any?) { onNavigate(true) }
    @objc private func goForward(_ sender: Any?) { onNavigate(false) }

    @objc private func toggleSettingsSidebar(_ sender: Any?) {
        toggleSidebar(sender)
    }

    private func configureNavigationButton(_ button: NSButton, symbol: String, identifier: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(identifier)
    }

    private func updateToolbar() {
        toolbarWindow?.title = AppLocalization.string("zisla 设置", locale: locale)
        backButton.isEnabled = input.canNavigate(backward: true, settings: settings)
        forwardButton.isEnabled = input.canNavigate(backward: false, settings: settings)
        for (button, key) in [(backButton, "后退"), (forwardButton, "前进")] {
            let label = AppLocalization.string(key, locale: locale)
            button.toolTip = label
            button.setAccessibilityLabel(label)
        }
        for item in settingsToolbar.items {
            if item.itemIdentifier == Self.sidebarIdentifier {
                item.label = AppLocalization.string(input.isSidebarVisible ? "隐藏侧边栏" : "显示侧边栏", locale: locale)
                item.toolTip = item.label
                item.view?.setAccessibilityIdentifier("settings-sidebar-toggle")
            } else if let group = item as? NSToolbarItemGroup {
                group.label = AppLocalization.string("设置", locale: locale)
                group.subitems[0].label = AppLocalization.string("后退", locale: locale)
                group.subitems[1].label = AppLocalization.string("前进", locale: locale)
            }
        }
    }
}

private final class SettingsTrackingSplitView: NSSplitView {
    weak var settingsController: SettingsSplitViewController?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        settingsController?.attachToolbar(to: window)
    }
}
