import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct SystemMonitorMenuBarModeIntegrationTests {
    @Test @MainActor
    func nestedToggleBindingsAllowAllModesAndPreserveSelections() {
        var settings = FeatureSettings.default
        settings.systemMonitorEnabled = true
        settings.systemMonitorMenuBarMetrics = [.memory, .fan]
        settings.systemMonitorMenuBarTopRow = [.network, .cpu]
        settings.systemMonitorMenuBarBottomRow = [.fan, .gpu]
        settings.systemMonitorMenuBarCombinedIconEnabled = true
        let original = settings
        let binding = Binding(get: { settings }, set: { settings = $0 })
        binding.systemMonitorMenuBarLayout.stackedEnabled.wrappedValue = true
        #expect(settings.systemMonitorMenuBarLayout == .both)
        #expect(settings.systemMonitorMenuBarLayout.individualEnabled)
        #expect(settings.systemMonitorMenuBarLayout.stackedEnabled)
        #expect(settings.systemMonitorMenuBarCombinedIconEnabled)
        binding.systemMonitorMenuBarLayout.individualEnabled.wrappedValue = false
        #expect(settings.systemMonitorMenuBarLayout == .stacked)
        binding.systemMonitorMenuBarLayout.stackedEnabled.wrappedValue = false
        #expect(settings.systemMonitorMenuBarLayout == .none)
        #expect(settings.systemMonitorMenuBarCombinedIconEnabled)
        binding.systemMonitorMenuBarLayout.individualEnabled.wrappedValue = true
        #expect(settings.systemMonitorMenuBarLayout == .individual)
        #expect(settings == original)
    }

    @Test(.serialized, arguments: AppLanguage.allCases) @MainActor
    func metricPickerColumnsAlignAcrossLanguages(language: AppLanguage) async throws {
        let suite = "SystemMonitorMenuBarModeIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
        defer { store.flushPendingChanges() }
        store.settings.systemMonitorMenuBarLayout = .stacked
        store.settings.systemMonitorMenuBarTopRow = [.cpu, .gpu]
        store.settings.systemMonitorMenuBarBottomRow = [.disk, .memory]
        store.settings.systemMonitorMenuBarCombinedIconEnabled = true
        store.settings.systemMonitorMenuBarCombinedIconMetric = .volume
        store.settings.systemMonitorMenuBarHeadphoneOptions.replacesNetworkIcon = true

        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: VStack {
            HStack {
                Picker("Reference", selection: Binding.constant(0)) { Text("Medium").tag(0) }
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .accessibilityIdentifier("reference-menu")
                Toggle("Reference", isOn: .constant(true))
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .accessibilityIdentifier("reference-switch")
            }
            SystemMonitorMenuBarSettingsView(settingsStore: store)
        }
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        )
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 20_000, y: 0, width: 560, height: 1_200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }

        let controls = accessibilityObjects(host)
        let referenceMenu = try #require(controls.first {
            value($0, "accessibilityIdentifier") as? String == "reference-menu"
        } as? any NSAccessibilityElementProtocol)
        let referenceSwitch = try #require(controls.first {
            value($0, "accessibilityIdentifier") as? String == "reference-switch"
        } as? any NSAccessibilityElementProtocol)
        let menus = controls.filter {
            value($0, "accessibilityRole") as? String == NSAccessibility.Role.popUpButton.rawValue
                && value($0, "accessibilityIdentifier") as? String != "reference-menu"
        }
        #expect(menus.count == 8)
        for menu in menus {
            let element = try #require(menu as? any NSAccessibilityElementProtocol)
            #expect(abs(element.accessibilityFrame().height - referenceMenu.accessibilityFrame().height) < 0.5,
                    "Every monitor menu must keep the native medium height, including nested menus")
        }
        let switches = controls.compactMap { $0 as? NSSwitch }.filter {
            $0.accessibilityIdentifier() != "reference-switch"
        }
        #expect(switches.count == 9)
        for control in switches {
            #expect(control.controlSize == .regular)
            #expect(abs(control.accessibilityFrame().height - referenceSwitch.accessibilityFrame().height) < 0.5)
        }
        var frames = [String: NSRect]()
        for child in controls {
            guard let element = child as? any NSAccessibilityElementProtocol,
                  let identifier = element.accessibilityIdentifier?(),
                  identifier.hasPrefix("system-monitor-row-") else { continue }
            frames[identifier] = element.accessibilityFrame()
        }
        try #require(frames.count == 4)
        for slot in 0..<2 {
            let top = try #require(frames["system-monitor-row-0-metric-\(slot)"])
            let bottom = try #require(frames["system-monitor-row-1-metric-\(slot)"])
            #expect(top.width > 0)
            #expect(abs(top.minX - bottom.minX) < 0.5)
            #expect(abs(top.maxX - bottom.maxX) < 0.5)
            #expect(top.midY != bottom.midY)
        }
        #expect(window.alphaValue == 0)
        #expect(!window.isVisible)
    }

    @MainActor private func accessibilityObjects(_ object: NSObject) -> [NSObject] {
        [object] + (value(object, "accessibilityChildren") as? [NSObject] ?? []).flatMap(accessibilityObjects)
    }

    @MainActor private func value(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }

}
