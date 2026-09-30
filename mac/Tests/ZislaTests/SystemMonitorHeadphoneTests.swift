import AppKit
import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
struct SystemMonitorHeadphoneTests {
    @Test
    func replacementRequiresAnEnabledBluetoothHeadphoneAndHonorsNetworkPriority() {
        for bluetooth in [false, true] {
            for name in ["AirPods Pro", "MacBook Speakers"] {
                let headphones = MenuBarIconHeadphoneStatus(
                    device: AudioOutputDevice(id: 1, name: name, isBluetoothAudio: bluetooth),
                    productID: nil, isVolumeMetric: false
                )
                for enabled in [false, true] {
                    for priority in [false, true] {
                        for wifi in [MenuBarWiFiState.connected(strength: 1), .disconnected, .off, .unavailable] {
                            let status = MenuBarIconStatus(
                                battery: nil, wifi: wifi, level: 0.5, headphones: headphones,
                                headphoneOptions: SystemMonitorHeadphoneOptions(
                                    replacesNetworkIcon: enabled, prioritizesNetworkErrors: priority
                                )
                            )
                            let expected = enabled && bluetooth && name == "AirPods Pro"
                                && (!priority || status.wifi.state == .connected)
                            #expect(MenuBarIconMappings.shouldReplaceNetworkIcon(status: status) == expected)
                        }
                    }
                }
            }
        }
        let noDevice = MenuBarIconStatus(
            battery: nil, wifi: .connected(strength: 1), level: nil,
            headphoneOptions: SystemMonitorHeadphoneOptions(replacesNetworkIcon: true)
        )
        #expect(!MenuBarIconMappings.shouldReplaceNetworkIcon(status: noDevice))
    }

    @Test
    func disconnectAndPriorityFallbackRestoreTheUnmodifiedWiFiImage() throws {
        for wifi in [MenuBarWiFiState.connected(strength: 1), .off, .disconnected, .unavailable] {
            let plain = try render(wifi: wifi)
            let enabledWithoutDevice = try render(
                wifi: wifi, options: SystemMonitorHeadphoneOptions(replacesNetworkIcon: true)
            )
            #expect(plain == enabledWithoutDevice)
            let enabled = try render(
                wifi: wifi, headphones: headphone(),
                options: SystemMonitorHeadphoneOptions(replacesNetworkIcon: true)
            )
            if case .connected = wifi {
                #expect(enabled != plain)
            } else {
                #expect(enabled == plain)
                #expect(try render(
                    wifi: wifi, headphones: headphone(),
                    options: SystemMonitorHeadphoneOptions(replacesNetworkIcon: true, prioritizesNetworkErrors: false)
                ) != plain)
            }
        }
    }

    @Test
    func bluetoothSymbolMatchesOriginalCenterScaleAndPalette() throws {
        let headphones = headphone()
        let source = try #require({ () -> String? in
            guard case let .symbol(name) = headphones.source else { return nil }
            return name
        }())
        for foreground in [NSColor.black, .white] {
            for symbolScale in [1.0, 1.6, 1.8] {
                let options = SystemMonitorHeadphoneOptions(replacesNetworkIcon: true, symbolScale: symbolScale)
                let actual = try bitmap(status: MenuBarIconStatus(
                    battery: nil, wifi: .connected(strength: 1), level: 0,
                    headphones: headphones, headphoneOptions: options
                ), foreground: foreground, size: 120)
                let reference = try referenceSymbol(name: source, scale: symbolScale, foreground: foreground)
                for horizontal in 35..<84 {
                    for vertical in 36..<88 {
                        #expect(actual.colorAt(x: horizontal, y: vertical) == reference.colorAt(x: horizontal, y: vertical),
                                "Bluetooth center differs from source at \(horizontal),\(vertical), scale \(symbolScale)")
                    }
                }
            }
        }
    }

    @Test
    func volumeColorDoesNotColorCPUOrOtherIndicators() throws {
        let options = SystemMonitorHeadphoneOptions(usesVolumeColor: true)
        let unchanged = try render(headphones: headphone())
        #expect(try render(headphones: headphone(), options: options) == unchanged)
        #expect(try render(headphones: headphone(isVolumeMetric: true), options: options) != unchanged)
        #expect(try render(options: options) == render())
    }

    @Test
    func headphoneOptionsLeaveLaptopBatteryAndTopIndicatorsUnchanged() throws {
        for charging in [false, true] {
            for lowPower in [false, true] {
                let battery = BatterySnapshot(
                    level: 0.6, isCharging: charging, isPluggedIn: charging,
                    isCharged: false, timeRemainingMinutes: nil, isLowPowerMode: lowPower
                )
                let plain = try bitmap(status: MenuBarIconStatus(battery: battery, wifi: .connected(strength: 1), level: 0.5))
                let combined = try bitmap(status: MenuBarIconStatus(
                    battery: battery, wifi: .connected(strength: 1), level: 0.5,
                    headphones: headphone(), headphoneOptions: SystemMonitorHeadphoneOptions(replacesNetworkIcon: true)
                ))
                for horizontal in 0..<44 {
                    for vertical in 0..<8 {
                        #expect(plain.colorAt(x: horizontal, y: vertical) == combined.colorAt(x: horizontal, y: vertical))
                    }
                }
            }
        }
    }

    @Test
    func batteryRowsPreserveSeparateBudAndCaseReadingsAndUnknownLevels() {
        let airPods = HeadphoneConnection(
            device: AudioOutputDevice(id: 1, name: "AirPods Pro"),
            battery: HeadphoneBatterySnapshot(leftLevel: 91, rightLevel: 83, caseLevel: 62)
        )
        let max = HeadphoneConnection(device: AudioOutputDevice(id: 2, name: "AirPods Max"), battery: nil)
        let rows = SystemMonitorHeadphonePresentation.rows(statuses: [airPods, max], showsBatteryLevels: true)
        #expect(rows.map(\.id) == [1, 2])
        #expect(rows[0].levels.map(\.level) == [91, 83, 62])
        #expect(rows[1].levels == [NoticeBatteryLevel(label: "耳机", level: nil)])
        #expect(rows[0].summary(locale: Locale(identifier: "en")) == "AirPods Pro: Left 91% · Right 83% · Case 62%")
        #expect(rows[1].summary(locale: Locale(identifier: "en")) == "AirPods Max: Headphones --")
        #expect(SystemMonitorHeadphonePresentation.rows(statuses: [airPods], showsBatteryLevels: false).isEmpty)
        #expect(SystemMonitorHeadphonePresentation.rows(statuses: [], showsBatteryLevels: true).isEmpty)
        let repeated = SystemMonitorHeadphonePresentation.rows(statuses: [airPods, airPods], showsBatteryLevels: true)
        #expect(repeated.count == 1)
        #expect(repeated[0] == rows[0])
    }

    @Test
    func batteryRowsLocalizeAcrossEverySupportedLanguageWithoutInventingCharge() throws {
        let status = HeadphoneConnection(
            device: AudioOutputDevice(id: 1, name: "AirPods Pro"),
            battery: HeadphoneBatterySnapshot(leftLevel: 0, rightLevel: nil, caseLevel: 100)
        )
        let row = try #require(SystemMonitorHeadphonePresentation.rows(statuses: [status], showsBatteryLevels: true).first)
        for language in AppLanguage.allCases {
            let summary = row.summary(locale: language.locale)
            #expect(summary.contains("0%") && summary.contains("--") && summary.contains("100%"))
            #expect(summary.contains(BatteryLocalization.metadataText("左", locale: language.locale)))
            #expect(summary.contains(BatteryLocalization.metadataText("右", locale: language.locale)))
            #expect(summary.contains(BatteryLocalization.metadataText("盒", locale: language.locale)))
        }
    }

    private func headphone(isVolumeMetric: Bool = false) -> MenuBarIconHeadphoneStatus {
        MenuBarIconHeadphoneStatus(
            device: AudioOutputDevice(id: 1, name: "AirPods Pro", isBluetoothAudio: true),
            productID: nil, isVolumeMetric: isVolumeMetric
        )
    }

    private func render(
        wifi: MenuBarWiFiState = .connected(strength: 1),
        headphones: MenuBarIconHeadphoneStatus? = nil,
        options: SystemMonitorHeadphoneOptions = SystemMonitorHeadphoneOptions()
    ) throws -> Data {
        let image = try bitmap(status: MenuBarIconStatus(
            battery: nil, wifi: wifi, level: 0.5, headphones: headphones, headphoneOptions: options
        ))
        return try #require(image.representation(using: .png, properties: [:]))
    }

    private func bitmap(
        status: MenuBarIconStatus, foreground: NSColor = .black, size: CGFloat = 22
    ) throws -> NSBitmapImageRep {
        let appearance = SystemMonitorCombinedIconAppearance()
        let foregroundColor = try #require(foreground.usingColorSpace(.deviceRGB)?.cgColor)
        let image = try #require(SystemMonitorMenuBarIconRenderer.render(
            menuBarStatus: status, size: size, scale: size == 120 ? 1 : 2,
            foreground: foregroundColor,
            options: MenuBarIconBatteryOptions(appearance: appearance),
            connectionOptions: MenuBarIconConnectionOptions(appearance: appearance),
            volumeOptions: MenuBarIconVolumeOptions(appearance: appearance)
        ))
        return NSBitmapImageRep(cgImage: image)
    }

    private func referenceSymbol(name: String, scale: Double, foreground: NSColor) throws -> NSBitmapImageRep {
        let image = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 120,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: image))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        // Match the upstream CGColor palette before AppKit converts it into the bitmap color space.
        let referenceColor = foreground == .black
            ? CGColor(red: 0, green: 102.0 / 255.0, blue: 204.0 / 255.0, alpha: 1)
            : CGColor(red: 77.0 / 255.0, green: 163.0 / 255.0, blue: 1, alpha: 1)
        let tint = try #require(NSColor(cgColor: referenceColor))
        let configuration = NSImage.SymbolConfiguration(pointSize: 38 * scale, weight: .semibold)
            .applying(.init(hierarchicalColor: tint))
        let baseSymbol = NSImage(systemSymbolName: name, variableValue: 1, accessibilityDescription: nil)
        let symbol = try #require(baseSymbol?.withSymbolConfiguration(configuration))
        symbol.draw(in: CGRect(
            x: 59.5 - symbol.size.width / 2, y: 120 - (64 + symbol.size.height / 2),
            width: symbol.size.width, height: symbol.size.height
        ))
        return image
    }
}
