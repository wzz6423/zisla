import AppKit
import ApplicationServices
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct MenuBarManagementTests {
    @Test
    func controlsFollowSettingsAndReleaseTheHiddenAreaWhenDisabled() throws {
        let suite = "MenuBarManagementTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FeatureSettingsStore(defaults: defaults)
        var items: [LocalStatusItem] = []
        @MainActor final class Displays {
            var widths: [CGFloat] = [1440]
        }
        let displays = Displays()
        let manager = MenuBarManager(store: store, displayWidths: { displays.widths }) {
            let item = LocalStatusItem()
            items.append(item)
            return item
        }
        manager.start()
        #expect(items.isEmpty)
        store.settings.menuBarManagementMode = .expanded
        #expect(items.count == 2)
        let arrow = try #require(items.first)
        let divider = try #require(items.last)
        #expect(arrow.isVisible && divider.isVisible)
        #expect(arrow.autosaveName != divider.autosaveName)
        #expect(!divider.localButton.title.isEmpty)
        try press(arrow)
        #expect(store.settings.menuBarManagementMode == .collapsed)
        let firstWidth = divider.length
        #expect(firstWidth > 100)
        displays.widths = [1920]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(divider.length > firstWidth)
        #expect(divider.localButton.title.isEmpty)
        store.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: defaults).settings.menuBarManagementMode == .collapsed)
        try press(arrow)
        #expect(store.settings.menuBarManagementMode == .expanded)
        #expect(divider.length == NSStatusItem.squareLength)
        try press(divider)
        store.settings.menuBarManagementMode = .disabled
        #expect(!arrow.isVisible && !divider.isVisible)
        #expect(divider.length == NSStatusItem.squareLength)
        store.settings.menuBarManagementMode = .expanded
        #expect(items.count == 2 && arrow.isVisible && divider.isVisible)
    }

    @Test
    func upgradesAndUnknownModesLeaveExistingSettingsIntact() throws {
        for json in [#"{"menuBarAppIconEnabled":false}"#, #"{"menuBarAppIconEnabled":false,"menuBarManagementMode":"future"}"#] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
            #expect(settings.menuBarManagementMode == .disabled)
            #expect(!settings.menuBarAppIconEnabled)
        }
    }

    @Test
    func collapseAccountsForAllAttachedDisplaysAndTheModernSlotLimit() {
        let widths: [CGFloat] = [3840, 1440]
        let legacy = MenuBarManager.dividerLength(mode: .collapsed, widths: widths, modernMenuBar: false)
        #expect(legacy > 3840)
        let modern = MenuBarManager.dividerLength(mode: .collapsed, widths: widths, modernMenuBar: true)
        #expect(650..<720 ~= modern)
        #expect(MenuBarManager.dividerLength(mode: .collapsed, widths: [], modernMenuBar: true) == NSStatusItem.squareLength)
    }

    @Test(arguments: [false, true])
    func movingAnIconUsesTheCorrectSideAndWaitsForTheActualLayout(rightToLeft: Bool) async {
        let layout = makeLayout(rightToLeft: rightToLeft)
        var frame = CGRect(x: rightToLeft ? -180 : -40, y: 6, width: 18, height: 16)
        var framesReadAfterDrop = 0
        for hidden in [true, false] {
            let target = layout.dropPoint(hidden: hidden)
            var drag: (CGPoint, CGPoint)?
            let before = frame
            let moved = await MenuBarManager.arrange(hidden: hidden) {
                (layout, frame)
            } drag: { start, end in
                drag = (start, end)
                return true
            } settle: {
                framesReadAfterDrop += 1
                if framesReadAfterDrop.isMultiple(of: 2) {
                    frame.origin.x = hidden != rightToLeft ? -180 : -40
                }
            }
            #expect(moved && framesReadAfterDrop.isMultiple(of: 2))
            #expect(drag?.0 == CGPoint(x: before.midX, y: before.midY))
            #expect(drag?.1 == target)
            #expect((target.x < layout.divider.midX) == (hidden != rightToLeft))
        }
    }

    @Test
    func aRefusedCancelledOrStaleMoveNeverReportsSuccess() async {
        let layout = makeLayout()
        let visible = CGRect(x: -40, y: 4, width: 20, height: 20)
        let stale = visible.offsetBy(dx: 0, dy: 50)
        for frame in [stale, layout.divider, CGRect.zero] {
            let moved = await MenuBarManager.arrange(hidden: true, placement: { (layout, frame) },
                                                     drag: { _, _ in Issue.record("Dragged an unavailable item"); return true })
            #expect(!moved)
        }
        #expect(await MenuBarManager.arrange(hidden: false, placement: { (layout, visible) },
                                             drag: { _, _ in Issue.record("Already on the requested side"); return false }))
        #expect(await !MenuBarManager.arrange(hidden: true, placement: { nil }, drag: { _, _ in false }))
        #expect(await !MenuBarManager.arrange(hidden: true, placement: { (layout, visible) }, drag: { _, _ in false }))
        var polls = 0
        #expect(await !MenuBarManager.arrange(hidden: true, placement: { (layout, visible) }, drag: { _, _ in true },
                                              settle: { polls += 1 }))
        #expect(1...10 ~= polls)
        #expect(await !MenuBarManager.arrange(hidden: true, placement: { (layout, visible) }, drag: { _, _ in true },
                                              settle: { throw CancellationError() }))
    }

    @Test
    func commandDragPostsAMatchedGestureAndReleasesAtTheOriginOnInterruption() async {
        let start = CGPoint(x: 280, y: 15)
        let end = CGPoint(x: 192, y: 15)
        for interruptAt in [nil, 1, 2, 3] as [Int?] {
            var ticks = 0
            var events: [CGEvent] = []
            let drop = await MenuBarManager.postDrag(from: start, to: end, while: { true }, post: { events.append($0) }) {
                ticks += 1
                if interruptAt == ticks { throw CancellationError() }
            }
            #expect(events.first?.type == .leftMouseDown && events.first?.location == start)
            #expect(events.last?.type == .leftMouseUp && events.last?.location == drop)
            #expect(events.allSatisfy { $0.flags.contains(.maskCommand) })
            #expect(drop == (interruptAt == nil ? end : start))
            #expect(events.count == (interruptAt.map { $0 + 1 } ?? 4))
        }
        var allowed = false
        var events: [CGEventType] = []
        #expect(await MenuBarManager.postDrag(from: start, to: end, while: { allowed },
                                              post: { events.append($0.type) }, pause: {}) == nil)
        #expect(events.isEmpty)
        allowed = true
        #expect(await MenuBarManager.postDrag(from: start, to: end, while: { allowed },
                                              post: { events.append($0.type) }, pause: { allowed = false }) == start)
        #expect(events == [.leftMouseDown, .leftMouseUp])
    }

    @Test
    func thirdPartyIconsRemainEligibleEvenWithNoApplicationHideSetting() {
        let id = "com.apple.menuextra.clock"
        #expect(MenuBarIcon.isFixed(identifier: id, owner: "com.apple.controlcenter"))
        #expect(MenuBarIcon.isFixed(identifier: "com.apple.menuextra.controlcenter", owner: "com.apple.MenuBarAgent"))
        #expect(!MenuBarIcon.isFixed(identifier: id, owner: "test.pinned-app"))
        #expect(!MenuBarIcon.isFixed(identifier: nil, owner: "test.pinned-app"))
        #expect(!MenuBarIcon.isFixed(identifier: "com.apple.menuextra.wifi", owner: "com.apple.controlcenter"))
    }

    @Test(arguments: AppLanguage.allCases)
    func managementPageAndIconActionsAreTranslatedAndSearchable(language: AppLanguage) throws {
        let section = SettingsSection.menuBarManagement
        let keys = [section.title, section.subtitle, "菜单栏图标", "启用菜单栏分隔线",
                    "按住 ⌘，将要收起的图标拖到分隔线远离时钟的一侧。", "收起图标",
                    "点按菜单栏中的箭头也可以展开或收起图标。", "授权后可以直接在此选择要收起的图标。",
                    "收起时隐藏", "未能移动图标。按住 ⌘，将分隔线拖过这个图标。", "系统固定", "当前无法移动", "暂未找到菜单栏图标"]
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let table = try #require(NSDictionary(contentsOf: package.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )) as? [String: String])
        for key in keys {
            let translation = try #require(table[key])
            #expect(!translation.isEmpty && AppLocalization.string(key, language: language) == translation)
            if language != .simplifiedChinese { #expect(translation != key) }
        }
        let query = AppLocalization.string("收起时隐藏", language: language)
        let results = SettingsSearchIndex.results(for: query, settings: .default, locale: language.locale, displayCount: 1)
        #expect(results.contains { $0.section == section && $0.anchor == .group("菜单栏图标") })
    }

    private func makeLayout(rightToLeft: Bool = false) -> MenuBarManager.Layout {
        MenuBarManager.Layout(divider: CGRect(x: -100, y: 0, width: 24, height: 24),
                              bar: CGRect(x: -1440, y: 0, width: 1440, height: 28), rightToLeft: rightToLeft)
    }

    private func press(_ item: LocalStatusItem) throws {
        let action = try #require(item.localButton.action)
        let target = try #require(item.localButton.target as? NSObject)
        _ = target.perform(action)
    }
}

private final class LocalStatusItem: NSStatusItem {
    @MainActor let localButton = NSStatusBarButton(frame: .zero)
    private var savedLength: CGFloat = NSStatusItem.squareLength
    private var storedVisibility = false
    private var savedName: String?

    override var button: NSStatusBarButton? { localButton }
    override var length: CGFloat {
        get { savedLength }
        set { savedLength = newValue }
    }
    override var isVisible: Bool {
        get { storedVisibility }
        set { storedVisibility = newValue }
    }
    override var autosaveName: String? {
        get { savedName }
        set { savedName = newValue }
    }
}
