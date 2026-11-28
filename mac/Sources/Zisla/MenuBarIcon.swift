import AppKit
import ApplicationServices
import ZislaCore

struct MenuBarIconRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String

    static func localID(_ item: String) -> String { "zisla:\(item)" }

    static func local(_ item: String, title: String) -> Self {
        Self(id: localID(item), title: title)
    }

    var isLocal: Bool { id.hasPrefix("zisla:") }

    func label(locale: Locale) -> String {
        if isLocal || id.hasPrefix("system:") { return AppLocalization.string(title, locale: locale) }
        return title
    }
}

// An AX element is an immutable process-local handle. Only the row identity is persisted.
struct MenuBarIcon: @unchecked Sendable {
    let element: AXUIElement
    let row: MenuBarIconRow
    let frame: CGRect
    var unambiguous = false

    struct Candidate: Equatable {
        let identifier: String?
        let title: String?
    }

    private static let hosts = ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.MenuBarAgent"]
    private static let systemItems: [String: (title: String, symbol: String)] = [
        "wifi": ("Wi-Fi", "wifi"), "bluetooth": ("蓝牙", "dot.radiowaves.left.and.right"), "battery": ("电池", "battery.100percent"),
        "sound": ("声音", "speaker.wave.2"), "focusmode": ("专注模式", "moon"), "nowplaying": ("正在播放", "play.circle"),
        "siri": ("Siri", "waveform"), "display": ("屏幕亮度", "sun.max"), "weather": ("天气", "cloud.sun"),
        "timemachine": ("Time Machine", "clock.arrow.circlepath"), "spotlight": ("Spotlight", "magnifyingglass"),
        "textinput": ("输入法", "keyboard"), "vpn": ("VPN", "lock.shield"), "user": ("用户", "person.crop.circle"),
        "volume": ("声音", "speaker.wave.2"),
    ]

    static func symbol(for row: MenuBarIconRow) -> String {
        guard row.id.hasPrefix("system:"), let key = row.id.split(separator: ".").last else { return "app" }
        return systemItems[String(key)]?.symbol ?? "menubar.rectangle"
    }

    static func rows(owner: String, app: String, candidates: [Candidate]) -> [MenuBarIconRow?] {
        let systemHost = hosts.contains(owner)
        let ids = candidates.compactMap(\.identifier)
        let titles = candidates.compactMap(\.title)
        return candidates.map { item in
            if systemHost {
                guard let identifier = item.identifier?.lowercased(), identifier.hasPrefix("com.apple.menuextra."),
                      let key = identifier.split(separator: ".").last, let title = systemItems[String(key)]?.title else { return nil }
                return MenuBarIconRow(id: "system:\(identifier)", title: title)
            }
            if owner == "com.apple.weather.menu", candidates.count == 1 {
                return MenuBarIconRow(id: "system:com.apple.menuextra.weather", title: "天气")
            }
            if owner == "com.apple.TextInputMenuAgent", candidates.count == 1 {
                return MenuBarIconRow(id: "system:com.apple.menuextra.textinput", title: "输入法")
            }
            let component: String
            if let identifier = item.identifier, ids.filter({ $0 == identifier }).count == 1 {
                component = "id:\(identifier)"
            } else if candidates.count == 1 {
                component = "single"
            } else if let title = item.title, titles.filter({ $0 == title }).count == 1 {
                component = "name:\(title)"
            } else {
                // Indistinguishable siblings could trade places and apply a saved rule to the wrong icon.
                return nil
            }
            let title = candidates.count > 1 ? item.title ?? item.identifier ?? app : app
            return MenuBarIconRow(id: "\(owner)|\(component)", title: title == app ? app : "\(app) · \(title)")
        }
    }

    static func attribute(_ key: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    static func children(of application: AXUIElement) -> [AXUIElement] {
        guard let bar = attribute(kAXExtrasMenuBarAttribute, of: application),
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        let element = unsafeDowncast(bar, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.15)
        return attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }

    static func owners(for ids: Set<String>) -> Set<String> {
        var owners = Set<String>()
        for id in ids {
            if id.hasPrefix("system:") {
                owners.formUnion(hosts)
                if id.hasSuffix(".textinput") { owners.insert("com.apple.TextInputMenuAgent") }
                if id.hasSuffix(".weather") { owners.insert("com.apple.weather.menu") }
            } else if let separator = id.firstIndex(of: "|") {
                owners.insert(String(id[..<separator]))
            }
        }
        return owners
    }

    @MainActor
    static func inventory(owners: Set<String>? = nil) async -> [MenuBarIcon] {
        guard AXIsProcessTrusted() else { return [] }
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String, String)? in
            guard !(["appex", "xpc"].contains(app.bundleURL?.pathExtension ?? "")),
                  let bundle = app.bundleIdentifier ?? app.bundleURL?.standardizedFileURL.path,
                  let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent else { return nil }
            let owner = app.processIdentifier == ProcessInfo.processInfo.processIdentifier ? "zisla:" : bundle
            guard owners?.contains(owner) != false else { return nil }
            return (app.processIdentifier, owner, name)
        }
        let read = Task.detached(priority: .userInitiated) {
            var items: [MenuBarIcon] = []
            for (pid, owner, app) in apps {
                if Task.isCancelled { break }
                let application = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(application, 0.15)
                let elements = children(of: application).filter {
                    AXUIElementSetMessagingTimeout($0, 0.15)
                    return attribute(kAXRoleAttribute, of: $0) as? String == kAXMenuBarItemRole
                }
                let candidates = elements.map { element in
                    let identifier = (attribute(kAXIdentifierAttribute, of: element) as? String).flatMap { $0.isEmpty ? nil : $0 }
                    let title = [kAXTitleAttribute, kAXDescriptionAttribute].lazy.compactMap {
                        (attribute($0, of: element) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.first { !$0.isEmpty && !$0.contains("\n") && $0.count <= 80 }
                    return Candidate(identifier: identifier, title: title)
                }
                // Own buttons have native switches. Track their live frames only to protect them while moving another app's icon.
                let listed = owner == "zisla:" ? zip(elements, candidates).map { element, item -> MenuBarIconRow? in
                    guard item.identifier != MenuBarHidingArea.dividerID, item.title != MenuBarHidingArea.dividerID else { return nil }
                    let key = item.identifier.flatMap { $0.hasPrefix("zisla:") ? $0 : nil }
                    return MenuBarIconRow(id: key ?? MenuBarIconRow.localID("observed-\(CFHash(element))"), title: app)
                } : rows(owner: owner, app: app, candidates: candidates)
                for (element, row) in zip(elements, listed) {
                    guard let row, let frame = AccessibilityGeometry.frame(of: element), !frame.isEmpty else { continue }
                    items.append(MenuBarIcon(element: element, row: row, frame: frame))
                }
            }
            return items
        }
        return await withTaskCancellationHandler { await read.value } onCancel: { read.cancel() }
    }

    static func hostMatches(_ target: Candidate, hit: Candidate, unambiguous: Bool = false) -> Bool {
        if let id = target.identifier, !id.isEmpty, !id.hasPrefix("Item-"), hit.identifier == id { return true }
        if let title = target.title, !title.isEmpty { return title == hit.title }
        // Some apps expose only AppKit's generic item ID. Use it only at an uncontested frame.
        return unambiguous && hit.title == nil && target.identifier != nil && target.identifier == hit.identifier
    }

    func isAt(_ point: CGPoint, unambiguous: Bool) -> Bool {
        var hit: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              var current = hit else { return false }
        for _ in 0..<4 {
            if CFEqual(current, element) { return true }
            if Self.attribute(kAXRoleAttribute, of: current) as? String == kAXMenuBarItemRole,
               let hitFrame = AccessibilityGeometry.frame(of: current), hitFrame == AccessibilityGeometry.frame(of: element) {
                var pid: pid_t = 0
                if AXUIElementGetPid(current, &pid) == .success,
                   NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.MenuBarAgent" {
                    func identity(_ item: AXUIElement) -> Candidate {
                        Candidate(identifier: Self.attribute(kAXIdentifierAttribute, of: item) as? String,
                                  title: [kAXTitleAttribute, kAXDescriptionAttribute].lazy.compactMap {
                                      Self.attribute($0, of: item) as? String
                                  }.first { !$0.isEmpty })
                    }
                    // A hidden icon can keep the old frame now occupied by an unrelated hosted button.
                    if Self.hostMatches(identity(element), hit: identity(current), unambiguous: unambiguous) { return true }
                }
            }
            guard let parent = Self.attribute(kAXParentAttribute, of: current),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            current = unsafeDowncast(parent, to: AXUIElement.self)
        }
        return false
    }

    @MainActor
    static func visible(_ icons: [MenuBarIcon]) async -> [MenuBarIcon] {
        guard let top = NSScreen.screens.first?.frame.maxY else { return [] }
        let bars = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width,
                   height: max($0.safeAreaInsets.top, NSStatusBar.system.thickness))
        }
        return await Task.detached(priority: .userInitiated) {
            return icons.compactMap { icon -> MenuBarIcon? in
                let center = CGPoint(x: icon.frame.midX, y: icon.frame.midY)
                let alone = !icons.contains { $0.row.id != icon.row.id && $0.frame.contains(center) }
                guard bars.contains(where: { $0.contains(center) }), icon.isAt(center, unambiguous: alone) else { return nil }
                var result = icon
                result.unambiguous = alone
                return result
            }
        }.value
    }
}
