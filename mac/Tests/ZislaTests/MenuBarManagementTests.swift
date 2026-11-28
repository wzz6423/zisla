import AppKit
import ApplicationServices
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct MenuBarManagementTests {
    @Test
    func oneSwitchHidesJustItsIconAndTheSameRowRestoresIt() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        await f.manager.refresh()
        let music = try #require(f.manager.rows.first { $0.id == "music" })
        #expect(f.manager.isShown(music))
        #expect(f.bar.state == .inactive)
        await f.manager.setVisible(false, row: music)
        #expect(f.manager.failedID == nil)
        #expect(!f.manager.isShown(music))
        #expect(f.manager.rows.contains(music))
        #expect(f.bar.shown() == ["chat", "mail"])
        #expect(f.store.settings.hiddenMenuBarIcons == ["music": "Music"])
        f.store.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: f.defaults).settings.hiddenMenuBarIcons == ["music": "Music"])
        await f.manager.setVisible(true, row: music)
        #expect(f.manager.isShown(music))
        #expect(f.bar.shown() == ["music", "chat", "mail"])
        #expect(f.bar.state == .inactive && f.store.settings.hiddenMenuBarIcons.isEmpty)
    }

    @Test
    func thePageHasOneDisplaySwitchPerIconAndCanRestoreWithTheSameSwitch() async throws {
        let f = Fixture()
        let release = EnhancedAccessibilityTestScope.acquire()
        await f.manager.refresh()
        let panel = NSWindow(contentRect: NSRect(x: 20_000, y: 0, width: 520, height: 320),
                             styleMask: .borderless, backing: .buffered, defer: false)
        panel.alphaValue = 0
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MenuBarIconList(manager: f.manager, store: f.store, hasAccessibility: true,
                                                           requestAccess: {}).environment(\.locale, Locale(identifier: "en")))
        host.sizingOptions = []
        panel.contentView = host
        defer {
            panel.contentView = nil
            panel.close()
            release()
            f.cleanUp()
        }
        func layout() async {
            for _ in 0..<5 {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
        }
        func objects(_ object: NSObject) -> [NSObject] {
            let children = value(object, "accessibilityChildren") as? [NSObject] ?? []
            return [object] + children.flatMap(objects)
        }
        func value(_ object: NSObject, _ key: String) -> Any? {
            object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
        }
        func controls() -> [NSObject] {
            objects(host).filter { value($0, "accessibilityRole") as? String == NSAccessibility.Role.checkBox.rawValue || $0 is NSSwitch }
        }
        func musicSwitch() throws -> NSObject {
            try #require(controls().first { value($0, "accessibilityIdentifier") as? String == "menu-bar-visibility-music" })
        }
        await layout()
        let ids = controls().compactMap { value($0, "accessibilityIdentifier") as? String }
        #expect(ids.count == f.manager.rows.count)
        #expect(Set(ids) == Set(["chat", "music", "mail"].map { "menu-bar-visibility-" + $0 }))
        let music = try musicSwitch()
        #expect(value(music, "accessibilityValue") as? NSNumber == 1)
        _ = music.perform(NSSelectorFromString("accessibilityPerformPress"))
        await layout()
        let hidden = try musicSwitch()
        #expect(value(hidden, "accessibilityValue") as? NSNumber == 0 && !f.bar.shown().contains("music"))
        _ = hidden.perform(NSSelectorFromString("accessibilityPerformPress"))
        await layout()
        #expect(f.bar.shown().contains("music"))
        #expect(controls().allSatisfy { value($0, "accessibilityValue") as? NSNumber == 1 })
        #expect(!panel.isVisible)
    }

    @Test
    func aFailedHidePreservesExistingRulesAndProtectsOtherIcons() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        await f.manager.refresh()
        let music = try #require(f.manager.rows.first { $0.id == "music" })
        let chat = try #require(f.manager.rows.first { $0.id == "chat" })
        await f.manager.setVisible(false, row: music)
        f.bar.refuses = "chat"
        await f.manager.setVisible(false, row: chat)
        #expect(f.manager.failedID == "chat" && f.manager.isShown(chat))
        #expect(f.store.settings.hiddenMenuBarIcons == ["music": "Music"])
        #expect(f.bar.shown() == ["chat", "mail"])
        f.bar.refuses = nil
        f.bar.leaks = "chat"
        await f.manager.setVisible(false, row: chat)
        #expect(f.manager.failedID == "chat" && f.manager.isShown(chat))
        #expect(f.store.settings.hiddenMenuBarIcons == ["music": "Music"])
        f.bar.leaks = nil
        f.bar.suppressesMailWithChat = true
        await f.manager.setVisible(false, row: chat)
        #expect(f.manager.failedID == "chat" && f.bar.shown().contains("mail"))
        #expect(f.store.settings.hiddenMenuBarIcons == ["music": "Music"])
    }

    @Test
    func immovableItemCanBeHiddenByMovingTheBoundaryAndKeepingItsNeighborVisible() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        await f.manager.refresh()
        let music = try #require(f.manager.rows.first { $0.id == "music" })
        f.bar.refuses = "music"
        f.bar.canRepositionBoundary = true
        await f.manager.setVisible(false, row: music)
        #expect(f.manager.failedID == nil && !f.manager.isShown(music))
        #expect(f.bar.shown() == ["chat", "mail"])
        await f.manager.setVisible(true, row: music)
        #expect(f.bar.shown() == ["chat", "music", "mail"])
    }

    @Test
    func aSavedIconCanReturnAfterRelaunchOrBeRestoredWhileItsAppIsClosed() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.store.settings.hiddenMenuBarIcons = ["music": "Music"]
        f.bar.icons.removeValue(forKey: "music")
        await f.manager.reapply()
        let music = try #require(f.manager.rows.first { $0.id == "music" })
        #expect(!f.manager.isShown(music) && f.bar.state == .inactive)
        f.bar.icons["music"] = "New Music Title"
        f.bar.hiddenSide = ["mail"]
        await f.manager.reapply()
        #expect(f.bar.shown() == ["chat", "mail"])
        #expect(!f.manager.isShown(music))
        f.bar.icons.removeValue(forKey: "music")
        await f.manager.setVisible(true, row: music)
        #expect(f.store.settings.hiddenMenuBarIcons.isEmpty && f.bar.state == .inactive)
        #expect(f.manager.rows.allSatisfy { $0.id != "music" })
    }

    @Test
    func ownIconsUseNativeVisibilityWithoutAccessibilityOrExternalPlacement() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.bar.trusted = false
        let cpu = MenuBarIconRow.local("cpu", title: "CPU")
        let memory = MenuBarIconRow.local("memory", title: "内存")
        f.manager.updateLocalRows([cpu, memory])
        await f.manager.refresh()
        await f.manager.setVisible(false, row: cpu)
        #expect(Set(f.manager.rows.map(\.id)) == [cpu.id, memory.id])
        #expect(!f.manager.isShown(cpu) && f.manager.isShown(memory))
        let cpuItem = LocalStatusItem(), memoryItem = LocalStatusItem()
        func update(_ destination: StatusIconDestination) -> [IslandStatusIcon] {
            IslandStatusIconRouting.update(destination: destination, application: nil,
                                           metrics: [(.cpu, cpuItem, "30%"), (.memory, memoryItem, "40%")],
                                           stacked: nil, readings: [], combined: nil, style: .compact,
                                           hidden: f.store.settings.hiddenMenuBarIcons)
        }
        #expect(update(.menuBar).isEmpty && !cpuItem.isVisible && memoryItem.isVisible)
        #expect(update(.island).map(\.id).contains("status-icon-cpu"))
        await f.manager.setVisible(true, row: cpu)
        _ = update(.menuBar)
        #expect(cpuItem.isVisible && memoryItem.isVisible && f.bar.state == .inactive)
    }

    @Test
    func deniedAccessKeepsSavedRulesRecoverableAndDoesNotMoveAnything() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.store.settings.hiddenMenuBarIcons = ["music": "Music"]
        f.bar.trusted = false
        await f.manager.refresh()
        let music = try #require(f.manager.rows.first)
        #expect(f.manager.rows.count == 1 && !f.manager.isShown(music))
        await f.manager.setVisible(true, row: music)
        #expect(f.bar.hiddenSide.isEmpty && f.store.settings.hiddenMenuBarIcons.isEmpty)
        #expect(f.manager.rows.isEmpty)
    }

    @Test
    func missingAndMalformedRulesLeaveOtherSettingsIntact() throws {
        for json in [#"{"menuBarAppIconEnabled":false,"menuBarManagementMode":"collapsed"}"#,
                     #"{"menuBarAppIconEnabled":false,"hiddenMenuBarIcons":[5]}"#] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(json.utf8))
            #expect(settings.hiddenMenuBarIcons.isEmpty && !settings.menuBarAppIconEnabled)
        }
    }

    @Test
    func inventoryFiltersHostChromeAndKeepsStableNamesForIndividualIcons() throws {
        typealias Item = MenuBarIcon.Candidate
        let system = MenuBarIcon.rows(owner: "com.apple.MenuBarAgent", app: "MenuBarAgent", candidates: [
            Item(identifier: nil, title: nil), Item(identifier: "overflow", title: "显示隐藏菜单栏项目"),
            Item(identifier: "com.apple.menuextra.clock", title: "12:00"),
            Item(identifier: "com.apple.menuextra.wifi", title: "Wi-Fi: 80%"),
        ]).compactMap { $0 }
        #expect(system == [MenuBarIconRow(id: "system:com.apple.menuextra.wifi", title: "Wi-Fi")])
        #expect(MenuBarIcon.rows(owner: "com.apple.weather.menu", app: "WeatherMenu",
                                 candidates: [Item(identifier: nil, title: "调高亮度")]).compactMap { $0 }.first?.title == "天气")
        let app = "test.app"
        let one = MenuBarIcon.rows(owner: app, app: "Player", candidates: [Item(identifier: nil, title: "00:01")])
        let restarted = MenuBarIcon.rows(owner: app, app: "Player", candidates: [Item(identifier: nil, title: "00:50")])
        #expect(one == restarted && one.compactMap { $0 }.first?.title == "Player")
        let a = Item(identifier: "music", title: "Music"), b = Item(identifier: "upload", title: "Uploads")
        let two = MenuBarIcon.rows(owner: app, app: "Player", candidates: [a, b]).compactMap { $0 }
        #expect(two.count == 2 && two[0].id != two[1].id)
        #expect(MenuBarIcon.rows(owner: app, app: "Player", candidates: [b, a]).compactMap { $0 } == two.reversed())
        #expect(MenuBarIcon.rows(owner: app, app: "Player", candidates: [a, a]).allSatisfy { $0 == nil })
    }

    @Test
    func hostedItemsNeedMatchingIdentityEvenWhenTheirFramesCoincide() {
        typealias Item = MenuBarIcon.Candidate
        #expect(!MenuBarIcon.hostMatches(Item(identifier: "Item-0", title: nil), hit: Item(identifier: "Item-0", title: nil)))
        #expect(MenuBarIcon.hostMatches(Item(identifier: "Item-0", title: nil), hit: Item(identifier: "Item-0", title: nil), unambiguous: true))
        #expect(!MenuBarIcon.hostMatches(Item(identifier: "Item-0", title: "Mail"), hit: Item(identifier: "Item-0", title: "Music")))
        #expect(MenuBarIcon.hostMatches(Item(identifier: "app.music", title: nil), hit: Item(identifier: "app.music", title: "New song")))
        #expect(MenuBarIcon.hostMatches(Item(identifier: nil, title: "Music"), hit: Item(identifier: "Item-3", title: "Music")))
        let owners = MenuBarIcon.owners(for: ["test.music|id:Item-0", "system:com.apple.menuextra.weather"])
        #expect(owners.contains("test.music") && owners.contains("com.apple.weather.menu") && owners.contains("com.apple.MenuBarAgent"))
        #expect(!owners.contains("test.mail"))
    }

    @Test
    func anUnchangedLayoutDoesNotRearrangeVisibleNeighborsInTheBackground() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        await f.manager.refresh()
        let row = try #require(f.manager.rows.first { $0.id == "music" })
        await f.manager.setVisible(false, row: row)
        let edits = f.bar.edits
        await f.manager.reapply()
        #expect(f.bar.edits == edits && f.bar.shown() == ["chat", "mail"])
        f.bar.hiddenSide.remove("music")
        await f.manager.reapply()
        #expect(f.bar.edits > edits && !f.bar.shown().contains("music"))
    }

    @available(macOS 27, *)
    @Test
    func rejectedWideSlotRetriesWithANarrowerSlotAndVerifiesItsEffect() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.bar.rejectsWideSlot = true
        await f.manager.refresh()
        let row = try #require(f.manager.rows.first { $0.id == "music" })
        await f.manager.setVisible(false, row: row)
        #expect(f.bar.state == .compactHiding && f.bar.shown() == ["chat", "mail"])
        #expect(!f.manager.isShown(row) && f.manager.failedID == nil)
    }

    @Test
    func collapseAccountsForAllAttachedDisplaysAndTheModernSlotLimit() {
        let widths: [CGFloat] = [3840, 1440]
        #expect(MenuBarHidingArea.hidingWidth(widths: widths, compact: false) > 3840)
        #expect(650..<720 ~= MenuBarHidingArea.hidingWidth(widths: widths, compact: true))
        #expect(MenuBarHidingArea.hidingWidth(widths: [], compact: true) == 1)
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
            let moved = await MenuBarHidingArea.arrange(hidden: hidden) {
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
            let moved = await MenuBarHidingArea.arrange(hidden: true, placement: { (layout, frame) },
                                                        drag: { _, _ in Issue.record("Dragged an unavailable item"); return true })
            #expect(!moved)
        }
        #expect(await MenuBarHidingArea.arrange(hidden: false, placement: { (layout, visible) },
                                                drag: { _, _ in Issue.record("Already on the requested side"); return false }))
        #expect(await !MenuBarHidingArea.arrange(hidden: true, placement: { nil }, drag: { _, _ in false }))
        #expect(await !MenuBarHidingArea.arrange(hidden: true, placement: { (layout, visible) }, drag: { _, _ in false }))
        var polls = 0
        #expect(await !MenuBarHidingArea.arrange(hidden: true, placement: { (layout, visible) }, drag: { _, _ in true },
                                                 settle: { polls += 1 }))
        #expect(1...10 ~= polls)
        #expect(await !MenuBarHidingArea.arrange(hidden: true, placement: { (layout, visible) }, drag: { _, _ in true },
                                                 settle: { throw CancellationError() }))
    }

    @Test
    func commandDragPostsAMatchedGestureAndReleasesAtTheOriginOnInterruption() async {
        let start = CGPoint(x: 280, y: 15)
        let end = CGPoint(x: 192, y: 15)
        for interruptAt in [nil, 1, 2, 3] as [Int?] {
            var ticks = 0
            var events: [CGEvent] = []
            let drop = await MenuBarHidingArea.postDrag(from: start, to: end, while: { true }, post: { events.append($0) }) {
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
        #expect(await MenuBarHidingArea.postDrag(from: start, to: end, while: { allowed },
                                                 post: { events.append($0.type) }, pause: {}) == nil)
        #expect(events.isEmpty)
        allowed = true
        #expect(await MenuBarHidingArea.postDrag(from: start, to: end, while: { allowed },
                                                 post: { events.append($0.type) }, pause: { allowed = false }) == start)
        #expect(events == [.leftMouseDown, .leftMouseUp])
    }

    @Test(arguments: AppLanguage.allCases)
    func managementPageAndIconActionsAreTranslatedAndSearchable(language: AppLanguage) throws {
        let section = SettingsSection.menuBarManagement
        let keys = [section.title, section.subtitle, "在菜单栏显示", "管理其他应用的图标需要辅助功能权限。",
                    "无法更改此图标的显示状态。", "暂未找到菜单栏图标", "输入法"]
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let table = try #require(NSDictionary(contentsOf: package.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings"
        )) as? [String: String])
        for key in keys {
            let translation = try #require(table[key])
            #expect(!translation.isEmpty && AppLocalization.string(key, language: language) == translation)
            if language != .simplifiedChinese { #expect(translation != key) }
        }
        let query = AppLocalization.string("在菜单栏显示", language: language)
        let results = SettingsSearchIndex.results(for: query, settings: .default, locale: language.locale, displayCount: 1)
        #expect(results.contains { $0.section == section && $0.anchor == .group("在菜单栏显示") })
    }

    private func makeLayout(rightToLeft: Bool = false) -> MenuBarHidingArea.Layout {
        MenuBarHidingArea.Layout(divider: CGRect(x: -100, y: 0, width: 24, height: 24),
                                 bar: CGRect(x: -1440, y: 0, width: 1440, height: 28), rightToLeft: rightToLeft)
    }

}

@MainActor
private final class Fixture {
    let suite = "MenuBarManagementTests." + UUID().uuidString
    let defaults: UserDefaults
    let store: FeatureSettingsStore
    let bar = TestMenuBar()
    let manager: MenuBarManager

    init() {
        defaults = UserDefaults(suiteName: suite)!
        store = FeatureSettingsStore(defaults: defaults)
        let bar = self.bar
        manager = MenuBarManager(store: store, area: bar, inventory: { _ in bar.inventory },
                                 visible: { icons in icons.filter { bar.shown().contains($0.row.id) } },
                                 trusted: { bar.trusted }, settle: {})
    }

    func cleanUp() {
        manager.stop()
        store.flushPendingChanges()
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class TestMenuBar: MenuBarIconPlacing {
    var state = MenuBarHidingArea.State.inactive
    var icons = ["music": "Music", "chat": "Chat", "mail": "Mail"]
    var hiddenSide: Set<String> = []
    var trusted = true
    var edits = 0
    var refuses: String?
    var canRepositionBoundary = false
    var leaks: String?
    var suppressesMailWithChat = false
    var rejectsWideSlot = false

    var inventory: [MenuBarIcon] {
        icons.sorted { $0.key < $1.key }.enumerated().map { offset, entry in
            let x = (hiddenSide.contains(entry.key) ? 20 : 240) + offset * 24
            return MenuBarIcon(element: AXUIElementCreateApplication(pid_t(100 + offset)),
                               row: MenuBarIconRow(id: entry.key, title: entry.value),
                               frame: CGRect(x: x, y: 2, width: 20, height: 20))
        }
    }

    func shown() -> Set<String> {
        var result = Set(icons.keys)
        if (state == .hiding && !rejectsWideSlot) || state == .compactHiding {
            result.subtract(hiddenSide)
            if let leaks, icons[leaks] != nil { result.insert(leaks) }
            if suppressesMailWithChat && hiddenSide.contains("chat") { result.remove("mail") }
        }
        return result
    }

    func setArea(_ state: MenuBarHidingArea.State) {
        self.state = state
        if state == .editing { edits += 1 }
    }
    func layout() async -> MenuBarHidingArea.Layout? {
        .init(divider: CGRect(x: 140, y: 0, width: 12, height: 24),
              bar: CGRect(x: 0, y: 0, width: 1024, height: 24), rightToLeft: false)
    }

    func move(_ icon: MenuBarIcon, hidden: Bool, byMovingBoundary: Bool) async -> Bool {
        guard trusted else { return false }
        if byMovingBoundary {
            guard canRepositionBoundary else { return false }
            hiddenSide.insert("mail")
        } else if refuses == icon.row.id { return false }
        if hidden { hiddenSide.insert(icon.row.id) } else { hiddenSide.remove(icon.row.id) }
        return true
    }
}

private final class LocalStatusItem: NSStatusItem {
    private var storedVisibility = true
    override var isVisible: Bool {
        get { storedVisibility }
        set { storedVisibility = newValue }
    }
}
