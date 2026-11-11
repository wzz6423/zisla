import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit

@testable import Zisla

struct BatteryChargeToFullButtonTests {
    @Test @MainActor
    func systemMonitorRoutesTheBatteryActionToItsExistingMessageOwner() throws {
        var messages: [String] = []
        let monitor = BatteryMonitor()
        let view = SystemMonitorView(service: SystemMonitorService(), batteryMonitor: monitor,
            networkMonitor: NetworkBatteryMonitor(), showsSystemMonitor: false, showsBatteryMonitor: true,
            onCleanupRequested: {}, onTransientMessage: { messages.append($0) })
        let detail: BatteryDetailView = try #require(value(in: view.body))
        let battery = BatterySnapshot(level: 0.8, isCharging: false, isPluggedIn: true,
            isCharged: false, timeRemainingMinutes: nil)
        let action: BatteryChargeToFullButton = try #require(value(in: detail.localBatterySection(battery)))
        let message = BatteryLocalization.string("无法立即充至100%，请重试。", locale: Locale(identifier: "en"))
        action.onTransientMessage(message)
        #expect(messages == [message], "A nested battery error must reach the system monitor's existing notice owner")
    }

    @Test(.timeLimit(.minutes(1)), arguments: AppLanguage.allCases, ["missing", "refused", "accepted"]) @MainActor
    func chargeActionsUseOnlyTheExistingTransientNotice(language: AppLanguage, scenario: String) async throws {
        let controller = BatteryChargingController(
            readState: { BatteryChargingState(chargeLimit: 80, chargingOverrideAllowed: true) },
            requestCharge: {
                if scenario == "missing" { Issue.record("The debug action must not charge a missing battery") }
                if scenario == "refused" { throw BatteryChargingError.requestFailed }
            }
        )
        let domain = "zisla.charge-action-fixture.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let battery: BatterySnapshot? = scenario == "missing" ? nil : BatterySnapshot(level: 0.8,
            isCharging: false, isPluggedIn: true, isCharged: false, timeRemainingMinutes: nil)
        let monitor = BatteryMonitor(defaults: defaults, notificationCenter: NotificationCenter(),
            snapshotProvider: { battery }, runLoopSourceFactory: { _ in nil })
        monitor.refresh()
        let completions = AsyncStream<Bool>.makeStream()
        let observation = controller.$isRequesting.dropFirst().filter { !$0 }
            .sink { _ in completions.continuation.yield(true) }
        defer { observation.cancel(); completions.continuation.finish() }
        var messages = ["Existing notice"]
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let window = NSPanel(contentRect: CGRect(x: -100_000, y: -100_000, width: 280, height: 48),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: BatteryChargeToFullButton(batteryMonitor: monitor,
            onTransientMessage: { messages.append($0) },
            environment: ["ZISLA_DEBUG_SHOW_CHARGE_TO_FULL": "1"], isDebugBuild: true, controller: controller)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        func descendants(_ object: NSObject) -> [NSObject] {
            let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                ? object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
            return [object] + children.flatMap(descendants)
        }
        let button = try #require(descendants(host).first {
            $0.responds(to: NSSelectorFromString("accessibilityRole")) && $0.value(forKey: "accessibilityRole") as? String == "AXButton"
        })
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(button.responds(to: press))
        var iterator = completions.stream.makeAsyncIterator()
        for attempt in 1...2 {
            _ = button.perform(press)
            try #require(await iterator.next() == true)
            let errors = scenario == "accepted" ? [] : Array(repeating:
                BatteryLocalization.string("无法立即充至100%，请重试。", locale: language.locale), count: attempt)
            #expect(messages == ["Existing notice"] + errors,
                    "Each failed click must refresh the existing notice; successful charging must preserve it")
            #expect(NSApp.modalWindow == nil && window.attachedSheet == nil,
                    "Charging errors must use the same nonmodal notice as an empty Trash")
        }
        #expect(!controller.isRequesting)
        #expect(controller.canChargeToFull == (scenario == "refused"))
        #expect(monitor.snapshot == battery)
    }

    @Test(arguments: [String?.none, "1", "0", "", "true", "01", " 1", "1 "], [false, true]) @MainActor
    func debugEnvironmentOnlyShowsTheActionForAnExactOptIn(value: String?, isDebugBuild: Bool) throws {
        let environment = value.map { ["ZISLA_DEBUG_SHOW_CHARGE_TO_FULL": $0] } ?? [:]
        let monitor = BatteryMonitor()
        let view = BatteryChargeToFullButton(batteryMonitor: monitor, onTransientMessage: { _ in },
            environment: environment, isDebugBuild: isDebugBuild)
        let image = try render(view.frame(width: 280, height: 48), language: .english)
        var hasVisibleAction = false
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                let color = try #require(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                hasVisibleAction = hasVisibleAction || color.blueComponent > 0.25
            }
        }
        #expect(hasVisibleAction == (isDebugBuild && value == "1"),
                "Only an explicit opt-in in a debug app may display an ineligible charge action")
        #expect(monitor.snapshot == nil, "The display override must not invent a battery snapshot")
    }

    @Test
    func fullChargeActionAndFailureUseTheRequestedLocale() {
        #expect(BatteryLocalization.string("立即充至100%", locale: Locale(identifier: "en")) == "Charge to 100% Now")
        #expect(BatteryLocalization.string("立即充至100%", locale: Locale(identifier: "zh-Hans")) == "立即充至100%")
        #expect(BatteryLocalization.string("立即充至100%", locale: Locale(identifier: "ar")) == "الشحن إلى 100% الآن")
        #expect(BatteryLocalization.string("无法立即充至100%，请重试。", locale: Locale(identifier: "en"))
            == "Couldn't charge to 100% now. Please try again.")
    }

    /// The shared header must preserve the intrinsic action beside all three power modes, including RTL.
    @Test(arguments: AppLanguage.allCases, [false, true]) @MainActor
    func buttonFitsTheExistingCompactHeaderInEveryLanguage(language: AppLanguage, isRequesting: Bool) throws {
        let battery = BatterySnapshot(level: 0.8, isCharging: false, isPluggedIn: true,
            isCharged: false, timeRemainingMinutes: nil, isLowPowerMode: true)
        let view = BatteryDetailView(batteryMonitor: BatteryMonitor(), networkMonitor: NetworkBatteryMonitor(),
            onTransientMessage: { _ in })
        let presentation = BatteryPowerModePresentation(
            currentMode: .lowPower, powerSource: .powerAdapter,
            supportedModes: BatteryPowerMode.allCases, isChanging: false, error: nil
        )
        let action = BatteryChargeToFullButton.chargeButton(
            isRequesting: isRequesting, locale: language.locale, action: {}
        ).border(Color(red: 1, green: 0, blue: 1), width: 1)
        let reference = try render(action.fixedSize(), language: language)
        let marker = try #require(reference.colorAt(x: reference.pixelsWide / 2, y: 0)?.usingColorSpace(.deviceRGB))
        let width = IslandModuleLayout.battery.islandSize.width - IslandSurfaceGeometry.moduleInset * 2 - 24
        let header = try render(view.localBatteryHeader(battery, locale: language.locale) {
            BatteryPowerModeButton.modeButtons(currentMode: .lowPower, presentation: presentation, select: { _ in })
        } chargingAction: {
            action
        }.frame(width: width).clipped(), language: language)

        var actionBounds: CGRect?
        for y in 0..<header.pixelsHigh {
            for x in 0..<header.pixelsWide {
                let color = try #require(header.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if abs(color.redComponent - marker.redComponent) < 0.02
                    && abs(color.greenComponent - marker.greenComponent) < 0.02
                    && abs(color.blueComponent - marker.blueComponent) < 0.02 {
                    let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                    actionBounds = actionBounds.map { $0.union(pixel) } ?? pixel
                }
            }
        }
        let bounds = try #require(actionBounds, "The charge action must remain visible beside the modes and battery status")
        #expect(header.pixelsHigh <= 52, "Keep all controls in the compact battery row")
        #expect(abs(bounds.width - CGFloat(reference.pixelsWide)) <= 1,
                "The complete translated action must retain its width in \(language.rawValue)")
        #expect(abs(bounds.height - CGFloat(reference.pixelsHigh)) <= 1)
        let image = try #require(header.cgImage?.cropping(to: bounds))
        let actual = NSBitmapImageRep(cgImage: image)
        try #require(actual.pixelsWide == reference.pixelsWide && actual.pixelsHigh == reference.pixelsHigh,
                     "The pixel comparison must run at matching dimensions")
        var differentPixels = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let expected = try #require(reference.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let rendered = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if abs(expected.redComponent - rendered.redComponent) > 0.05
                    || abs(expected.greenComponent - rendered.greenComponent) > 0.05
                    || abs(expected.blueComponent - rendered.blueComponent) > 0.05 {
                    differentPixels += 1
                }
            }
        }
        #expect(differentPixels <= reference.pixelsWide * reference.pixelsHigh / 20,
                "The constrained header must preserve the full action label without clipping or scaling")
    }

    /// Uses one color scheme and scale so comparisons isolate layout compression.
    @MainActor
    private func render<Content: View>(_ content: Content, language: AppLanguage) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: content
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.colorScheme, .dark).background(.black))
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    private func value<Value>(in content: Any) -> Value? {
        if let value = content as? Value { return value }
        let mirror = Mirror(reflecting: content)
        guard mirror.displayStyle != .class else { return nil }
        return mirror.children.lazy.compactMap { value(in: $0.value) }.first
    }
}
