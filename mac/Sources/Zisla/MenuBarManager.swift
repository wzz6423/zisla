import AppKit
import Combine
import ZislaCore
import ZislaKit

@MainActor
final class MenuBarManager: ObservableObject {
    @Published private(set) var rows: [MenuBarIconRow] = []
    @Published private(set) var busy = false
    @Published private(set) var failedID: String?
    @Published private(set) var loading = false

    private let store: FeatureSettingsStore
    private let area: any MenuBarIconPlacing
    private let inventory: @MainActor (Set<String>?) async -> [MenuBarIcon]
    private let visible: @MainActor ([MenuBarIcon]) async -> [MenuBarIcon]
    private let trusted: () -> Bool
    private let settle: () async -> Void
    private var localRows: [MenuBarIconRow] = []
    private var visibleRows: [MenuBarIconRow] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var appsObservation: NSKeyValueObservation?
    private var pending: Task<Void, Never>?
    private var probe: Task<Void, Never>?
    private var timer: AnyCancellable?
    private struct Snapshot: Equatable {
        var available: Set<String>
        var visibleRows: [MenuBarIconRow]
        var hidden: Set<String>
    }
    private var lastApplied: Snapshot?
    private var generation = 0
    private var stopped = false
    private var pageOpen = false

    init(store: FeatureSettingsStore, area: any MenuBarIconPlacing = MenuBarHidingArea(),
         inventory: @escaping @MainActor (Set<String>?) async -> [MenuBarIcon] = MenuBarIcon.inventory,
         visible: @escaping @MainActor ([MenuBarIcon]) async -> [MenuBarIcon] = MenuBarIcon.visible,
         trusted: @escaping () -> Bool = { AccessibilityPermission.isTrusted },
         settle: @escaping () async -> Void = { try? await Task.sleep(for: .milliseconds(100)) }) {
        self.store = store
        self.area = area
        self.inventory = inventory
        self.visible = visible
        self.trusted = trusted
        self.settle = settle
    }

    func start() {
        store.$settings.map { $0.hiddenMenuBarIcons.filter { !$0.key.hasPrefix("zisla:") } }.removeDuplicates()
            .sink { [weak self] rules in
                guard let self else { return }
                if rules.isEmpty {
                    timer = nil
                } else if timer == nil {
                    // Some apps recreate status items without relaunching. Probe only the owners of saved rules.
                    timer = Timer.publish(every: 12, on: .main, in: .common).autoconnect()
                        .sink { [weak self] _ in self?.checkHiddenOwners() }
                }
                if !busy { scheduleUpdate() }
            }.store(in: &subscriptions)
        appsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.environmentChanged() }
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification))
            .sink { [weak self] _ in
                self?.lastApplied = nil
                self?.environmentChanged()
            }.store(in: &subscriptions)
    }

    func stop() {
        stopped = true
        generation += 1
        appsObservation = nil
        subscriptions.removeAll()
        pending?.cancel()
        probe?.cancel()
        timer = nil
        area.setArea(.inactive)
    }

    private var blocked: [String: String] { store.settings.hiddenMenuBarIcons }
    private var external: Set<String> { Set(blocked.keys.filter { !$0.hasPrefix("zisla:") }) }

    private func environmentChanged() {
        guard pageOpen || !external.isEmpty else { return }
        scheduleUpdate()
    }

    private func scheduleUpdate() {
        pending?.cancel()
        pending = Task {
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            pending = nil
            guard !stopped else { return }
            if busy { scheduleUpdate(); return }
            await reapply()
        }
    }

    func setPageOpen(_ open: Bool) {
        pageOpen = open
    }

    func updateLocalRows(_ items: [MenuBarIconRow]) {
        guard localRows != items else { return }
        localRows = items
        publishRows()
    }

    private func publishRows() {
        var seen = Set<String>()
        let saved = blocked.sorted { $0.key < $1.key }.map { MenuBarIconRow(id: $0.key, title: $0.value) }
        // Keep hidden rows available even when the owning app is closed.
        let updated = (localRows + visibleRows.filter { !$0.isLocal } + saved).filter { seen.insert($0.id).inserted }.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        if rows != updated { rows = updated }
    }

    private func snapshot() async -> Snapshot {
        let all = await inventory(nil)
        var seen = Set<String>()
        let shown = await visible(all).filter { seen.insert($0.row.id).inserted }
            .sorted { $0.frame.midX < $1.frame.midX }.map(\.row)
        return Snapshot(available: Set(all.map(\.row.id)), visibleRows: shown, hidden: external)
    }

    private func checkHiddenOwners() {
        guard !busy, !stopped, pending == nil, probe == nil else { return }
        guard trusted() else {
            area.setArea(.inactive)
            lastApplied = nil
            return
        }
        let rules = external
        guard !rules.isEmpty else { return }
        probe = Task {
            defer { probe = nil }
            let candidates = await inventory(MenuBarIcon.owners(for: rules)).filter { rules.contains($0.row.id) }
            let shown = Set(await visible(candidates).map(\.row.id))
            guard !busy, !stopped, rules == external else { return }
            let previous = Set(lastApplied?.visibleRows.map(\.id) ?? []).intersection(rules)
            if !shown.isEmpty && shown != previous { scheduleUpdate() }
        }
    }

    func refresh() async {
        guard !busy, !stopped else { return }
        generation += 1
        let request = generation
        if !trusted() {
            area.setArea(.inactive)
            lastApplied = nil
            visibleRows = []
            loading = false
            publishRows()
            return
        }
        loading = true
        let icons = await snapshot()
        guard generation == request, !stopped else { return }
        visibleRows = icons.visibleRows
        loading = false
        publishRows()
        if !external.isEmpty && lastApplied != icons { scheduleUpdate() }
    }

    func isShown(_ row: MenuBarIconRow) -> Bool {
        blocked[row.id] == nil
    }

    func setVisible(_ shown: Bool, row: MenuBarIconRow) async {
        guard !busy, !stopped, rows.contains(where: { $0.id == row.id }),
              isShown(row) != shown else { return }
        failedID = nil
        if row.isLocal {
            store.settings.hiddenMenuBarIcons[row.id] = shown ? nil : row.title
            publishRows()
            return
        }
        guard trusted() else {
            area.setArea(.inactive)
            if shown { store.settings.hiddenMenuBarIcons[row.id] = nil }
            else { failedID = row.id }
            publishRows()
            return
        }
        busy = true
        loading = false
        generation += 1
        defer { busy = false }
        let old = external
        var desired = old
        if shown { desired.remove(row.id) } else { desired.insert(row.id) }
        let before = await snapshot().visibleRows
        guard shown || before.contains(where: { $0.id == row.id }) else {
            failedID = row.id
            visibleRows = before
            publishRows()
            return
        }
        let keepVisible = Set(before.map(\.id)).subtracting(desired)
        let success = await apply(desired, protecting: keepVisible, toggled: row.id, shown: shown)
        guard !stopped else { return }
        if success {
            store.settings.hiddenMenuBarIcons[row.id] = shown ? nil : row.title
        } else {
            failedID = row.id
            // A rejected move may have changed the order. Restore the previously accepted selection.
            _ = await apply(old, protecting: Set(before.map(\.id)).subtracting(old))
        }
        let current = await snapshot()
        guard !stopped else { return }
        lastApplied = current
        visibleRows = current.visibleRows
        publishRows()
    }

    func reapply() async {
        guard !busy, !stopped else { return }
        let desired = external
        guard !desired.isEmpty, trusted() else {
            area.setArea(.inactive)
            lastApplied = nil
            publishRows()
            if pageOpen { await refresh() }
            return
        }
        busy = true
        loading = false
        generation += 1
        defer { busy = false }
        let before = await snapshot()
        guard !stopped else { return }
        if lastApplied == before {
            visibleRows = before.visibleRows
            publishRows()
            return
        }
        let success = await apply(desired, protecting: Set(before.visibleRows.map(\.id)).subtracting(desired))
        guard !stopped else { return }
        let after = await snapshot()
        guard !stopped else { return }
        failedID = success ? nil : after.visibleRows.first { desired.contains($0.id) }?.id
        lastApplied = after
        visibleRows = after.visibleRows
        publishRows()
    }

    private func apply(_ desired: Set<String>, protecting before: Set<String>,
                       toggled: String? = nil, shown: Bool = false) async -> Bool {
        guard !stopped, trusted() else { return false }
        area.setArea(desired.isEmpty ? .inactive : .editing)
        await settle()
        guard !stopped else { return false }
        let all = await inventory(nil)
        let live = Set(all.map(\.row.id))
        if let toggled, !shown, !live.contains(toggled) {
            area.setArea(.inactive)
            return false
        }
        let targets = desired.intersection(live)
        var protected = before
        if let toggled, shown, live.contains(toggled) { protected.insert(toggled) }
        if targets.isEmpty {
            area.setArea(.inactive)
        } else {
            var seen = Set<String>()
            let expanded = await visible(all).filter { seen.insert($0.row.id).inserted }
            protected.formUnion(expanded.map(\.row.id).filter { !desired.contains($0) })
            var candidates = expanded
            for pass in 0...1 {
                guard !stopped, let layout = await area.layout() else { area.setArea(.inactive); return false }
                var movedBoundary = false
                for icon in candidates.sorted(by: { !desired.contains($0.row.id) && desired.contains($1.row.id) }) {
                    let hidden = desired.contains(icon.row.id)
                    guard let side = layout.onHiddenSide(icon.frame), side != hidden else { continue }
                    if await area.move(icon, hidden: hidden, byMovingBoundary: false) { continue }
                    guard !stopped, pass == 0, await area.move(icon, hidden: hidden, byMovingBoundary: true) else {
                        area.setArea(.inactive)
                        return false
                    }
                    movedBoundary = true
                    break
                }
                guard movedBoundary else { break }
                // Moving the boundary also changes neighboring icons' sides. Re-read them before hiding.
                candidates = await visible(inventory(nil))
            }
            guard !stopped, trusted() else { area.setArea(.inactive); return false }
        }

        // Some displays reject a status item's requested width. Only commit after reading the resulting bar.
        var widths = [MenuBarHidingArea.State.hiding]
        if !targets.isEmpty, #available(macOS 27, *) { widths.append(.compactHiding) }
        for width in widths {
            if !targets.isEmpty { area.setArea(width) }
            for _ in 0..<3 {
                await settle()
                guard !stopped, trusted() else { area.setArea(.inactive); return false }
                let current = await inventory(nil)
                guard !current.isEmpty || targets.isEmpty else { continue }
                let onScreen = Set(await visible(current).map(\.row.id))
                if targets.isDisjoint(with: onScreen), protected.isSubset(of: onScreen) { return true }
            }
        }
        area.setArea(.inactive)
        return false
    }
}
