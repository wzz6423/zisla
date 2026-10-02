import AppKit
import SwiftUI
import Testing
@testable import Zisla
@testable import ZislaKit

@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct WiFiNetworkPanelViewTests {
    @Test(arguments: [Bool?(true), false, nil], [NSAppearance.Name.aqua, .darkAqua])
    func observedPowerKeepsItsColorAndToggleSemanticsInAnInactiveWindow(
        powerOn: Bool?, appearance: NSAppearance.Name
    ) async throws {
        let backend = PanelWiFiBackend(powerOn: powerOn)
        let controller = SystemWiFiPanelController(
            backend: backend, authorizer: PanelWiFiAuthorization(), openURL: { _ in false }
        )
        controller.openPanel()
        await controller.operationTask?.value
        defer { controller.closePanel() }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: WiFiNetworkPanelView(controller: controller)
            .accentColor(.blue)
            .environment(\.controlActiveState, .inactive)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 20_000, y: 100, width: 320, height: 320),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        host.sizingOptions = []
        window.contentView = host
        defer { window.close() }
        await settle(host)
        let pixels = try accentPixels(host)
        #expect(powerOn == true ? pixels > 100 : pixels == 0)
        #expect(!window.isKeyWindow)
        #expect(!window.isVisible)
        let toggle = try #require(host.accessibilityChildren()?.compactMap { $0 as? NSSwitch }.first)
        #expect(toggle.state == (powerOn == true ? .on : .off))
        #expect(toggle.isEnabled == (powerOn != nil))
        #expect(toggle.accessibilitySubrole() == NSAccessibility.Subrole(rawValue: "AXSwitch"))
        if let powerOn {
            let gate = PanelWiFiGate()
            defer { gate.resume() }
            backend.powerGate = gate
            _ = toggle.accessibilityPerformPress()
            await gate.waitUntilSuspended()
            await settle(host)
            let pendingToggle = try #require(host.accessibilityChildren()?.compactMap { $0 as? NSSwitch }.first)
            #expect(!pendingToggle.isEnabled)
            #expect(pendingToggle.state == (powerOn ? .on : .off))
            let pendingPixels = try accentPixels(host)
            #expect(powerOn ? pendingPixels > 100 : pendingPixels == 0)
            _ = pendingToggle.accessibilityPerformPress()
            #expect(backend.powerRequests == [!powerOn])
            gate.resume()
            await controller.operationTask?.value
            #expect(controller.snapshot?.powerOn == !powerOn)
        } else {
            _ = toggle.accessibilityPerformPress()
            #expect(backend.powerRequests.isEmpty)
            #expect(controller.snapshot == nil)
        }
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private func accentPixels(_ host: NSView) throws -> Int {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.blueComponent - color.redComponent > 0.15,
                   color.blueComponent - color.greenComponent > 0.05,
                   color.alphaComponent > 0.2 { count += 1 }
            }
        }
        return count
    }
}

@MainActor
private final class PanelWiFiBackend: WiFiNetworkBackend {
    var state: WiFiNetworkSnapshot?
    var powerGate: PanelWiFiGate?
    var powerRequests: [Bool] = []
    init(powerOn: Bool?) { state = powerOn.map { WiFiNetworkSnapshot(powerOn: $0) } }
    func readState(scan: Bool) async throws -> WiFiNetworkSnapshot {
        guard let state else { throw WiFiNetworkFailure.interfaceUnavailable }
        return state
    }
    func setPower(_ enabled: Bool) async throws -> WiFiNetworkSnapshot {
        powerRequests.append(enabled)
        if let powerGate { await powerGate.suspend() }
        let result = WiFiNetworkSnapshot(powerOn: enabled)
        state = result
        return result
    }
    func connect(to id: WiFiNetwork.ID, password: String?) async throws -> WiFiNetworkSnapshot {
        throw WiFiNetworkFailure.networkUnavailable
    }
}

@MainActor
private final class PanelWiFiAuthorization: WiFiNetworkAuthorizing {
    var status: WiFiNetworkAuthorizationState { .denied }
    var onChange: (@MainActor () -> Void)?
    func request() {}
    func cancel() {}
}

@MainActor
private final class PanelWiFiGate {
    private var suspended: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation in
            suspended = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilSuspended() async {
        guard suspended == nil else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func resume() {
        suspended?.resume()
        suspended = nil
    }
}
