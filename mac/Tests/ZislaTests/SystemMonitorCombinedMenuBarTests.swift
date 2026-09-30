import AppKit
import Foundation
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct SystemMonitorCombinedMenuBarTests {
    @Test
    func compactRowsShowUserSelectedMetricsAndOrder() {
        let snapshot = Self.snapshot()
        #expect(Self.rows(top: [.cpu], bottom: [.gpu], snapshot: snapshot) == ["C 90%", "G 80%"])
        #expect(Self.rows(top: [.cpu], bottom: [.memory], snapshot: snapshot) == ["C 90%", "M 80%"])
        #expect(Self.rows(top: [.memory], bottom: [.cpu], snapshot: snapshot) == ["M 80%", "C 90%"])
        #expect(Self.rows(top: [.cpu, .gpu], bottom: [.fan], snapshot: snapshot) == ["C 90%  G 80%", "F 2014 5277"])
        #expect(Self.rows(top: [.cpu, .gpu], bottom: [.memory, .disk], snapshot: snapshot) == ["C 90%  G 80%", "M 80%  D 80%"])
        #expect(Self.rows(top: [.fan], bottom: [.memory, .cpu], snapshot: snapshot) == ["F 2014 5277", "M 80%  C 90%"])
    }

    @Test
    func detailedRowsRetainFullMetricLabels() {
        #expect(SystemMonitorCombinedMenuBarPresentation.rows(
            top: [.cpu, .gpu], bottom: [.fan], snapshot: Self.snapshot(), style: .detailed
        ) == ["CPU 90%  GPU 80%", "Fans 2014 5277"])
    }

    @Test
    func missingAndInvalidReadingsDoNotBecomeZeroUsage() {
        #expect(Self.rows(top: [.cpu], bottom: [.gpu], snapshot: nil) == ["C --", "G --"])
        var snapshot = Self.snapshot()
        snapshot.gpu = .unavailable(reason: "not supported")
        snapshot.fan = .unavailable(reason: "not supported")
        #expect(Self.rows(top: [.gpu], bottom: [.fan], snapshot: snapshot) == ["G --", "F --"])
        snapshot.cpu.usage = .nan
        snapshot.fan = .available(rpm: [.nan, -.infinity, -1], detail: nil)
        #expect(Self.rows(top: [.cpu], bottom: [.fan], snapshot: snapshot) == ["C --", "F -- -- --"])
        snapshot.memory.totalBytes = 0
        snapshot.disk.totalBytes = 0
        #expect(Self.rows(top: [.memory], bottom: [.disk], snapshot: snapshot) == ["M --", "D --"])
        snapshot.network.receiveBytesPerSecond = .infinity
        snapshot.network.sendBytesPerSecond = -1
        #expect(Self.rows(top: [.network], bottom: [.gpu], snapshot: snapshot)[0] == "N ↓-- ↑--")
    }

    @Test
    func percentageBoundariesAreSafe() {
        #expect(SystemMonitorCombinedMenuBarPresentation.percent(nil) == "--")
        #expect(SystemMonitorCombinedMenuBarPresentation.percent(.infinity) == "--")
        #expect(SystemMonitorCombinedMenuBarPresentation.percent(-1) == "0%")
        #expect(SystemMonitorCombinedMenuBarPresentation.percent(2) == "100%")
        #expect(SystemMonitorCombinedMenuBarPresentation.percent(0.995) == "100%")
    }

    @Test
    func bottomIndicatorUsesOnlyItsSelectedDataSource() {
        let levels = MenuBarSystemLevels(volume: 0.35, brightness: 0.62)
        let snapshot = Self.snapshot()
        #expect(SystemMonitorCombinedMenuBarPresentation.level(metric: .cpu, snapshot: snapshot, levels: levels) == 0.9)
        #expect(SystemMonitorCombinedMenuBarPresentation.level(metric: .gpu, snapshot: snapshot, levels: levels) == 0.8)
        #expect(SystemMonitorCombinedMenuBarPresentation.level(metric: .memory, snapshot: snapshot, levels: levels) == 0.8)
        #expect(SystemMonitorCombinedMenuBarPresentation.level(metric: .volume, snapshot: nil, levels: levels) == 0.35)
        #expect(SystemMonitorCombinedMenuBarPresentation.level(metric: .brightness, snapshot: nil, levels: levels) == 0.62)
        #expect(SystemMonitorCombinedMenuBarPresentation.level(metric: .cpu, snapshot: nil, levels: levels) == nil)
        #expect(SystemMonitorCombinedMenuBarPresentation.level(metric: .brightness, snapshot: snapshot, levels: MenuBarSystemLevels()) == nil)
        #expect(SystemMonitorCombinedMenuBarPresentation.level(metric: .volume, snapshot: nil, levels: MenuBarSystemLevels(volume: .nan)) == nil)
    }

    @Test @MainActor
    func lowPowerRingIsYellowEvenWhenChargedOrLow() {
        var battery = Self.battery()
        battery.isLowPowerMode = true
        battery.isCharged = true
        #expect(MenuBarIconMappings.batteryColorRole(MenuBarIconStatus(battery: battery, wifi: .off, level: nil).battery) == .lowPower)
        battery.level = 0.1
        #expect(MenuBarIconMappings.batteryColorRole(MenuBarIconStatus(battery: battery, wifi: .off, level: nil).battery) == .lowPower)
        battery.isLowPowerMode = false
        #expect(MenuBarIconMappings.batteryColorRole(MenuBarIconStatus(battery: battery, wifi: .off, level: nil).battery) == .critical)
        battery.level = 1
        #expect(MenuBarIconMappings.batteryColorRole(MenuBarIconStatus(battery: battery, wifi: .off, level: nil).battery) == .charging)
        battery.isCharged = false
        battery.isPluggedIn = false
        #expect(MenuBarIconMappings.batteryColorRole(MenuBarIconStatus(battery: battery, wifi: .off, level: nil).battery) == .foreground)
    }

    @Test @MainActor
    func stackedImageFitsBothRowsAndUsesATemplate() throws {
        let rows = Self.rows(top: [.cpu, .gpu], bottom: [.fan], snapshot: Self.snapshot())
        let image = try #require(SystemMonitorMenuBarImageRenderer.stacked(rows: rows, style: .compact))
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        for row in rows {
            #expect(image.size.width > (row as NSString).size(withAttributes: [.font: font]).width)
        }
        #expect(image.size.height == 22)
        #expect(image.isTemplate)
        #expect(image.accessibilityDescription == "C 90%  G 80%, F 2014 5277")
        let representation = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(representation.pixelsHigh == 44)
        #expect(representation.pixelsWide == Int(image.size.width * 2))
        for verticalRange in [1..<20, 24..<43] {
            let ink = verticalRange.reduce(0) { count, vertical in
                count + (0..<representation.pixelsWide).filter { horizontal in
                    (representation.colorAt(x: horizontal, y: vertical)?.alphaComponent ?? 0) > 0.1
                }.count
            }
            #expect(ink > 10)
        }
    }

    @Test @MainActor
    func unequalStackedRowsStartAtTheSameLeftEdge() throws {
        for style in SystemMonitorMenuBarDisplayStyle.allCases {
            for rows in [["C 90%", "C 90%  M 80%"], ["C 90%  G 80%", "C 90%"]] {
                let image = try #require(SystemMonitorMenuBarImageRenderer.stacked(rows: rows, style: style))
                let representation = try #require(image.representations.first as? NSBitmapImageRep)
                let leftEdges = [1..<20, 24..<43].map { verticalRange in
                    (0..<representation.pixelsWide).first { horizontal in
                        verticalRange.contains { vertical in
                            (representation.colorAt(x: horizontal, y: vertical)?.alphaComponent ?? 0) > 0.1
                        }
                    }
                }
                let firstEdge = try #require(leftEdges[0])
                let secondEdge = try #require(leftEdges[1])
                #expect(abs(firstEdge - secondEdge) <= 1)
                #expect(firstEdge < 4)
                #expect(secondEdge < 4)
            }
        }
    }

    @Test @MainActor
    func combinedIconLeavesTheLowerRingOpenWithoutAFlatIndicator() throws {
        let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: Self.battery(), wifi: .connected(strength: 1), level: 1, foreground: .black,
            configuration: SystemMonitorCombinedIconAppearance(
                iconSize: 22, ringStrokeStyle: .regular, showsBatteryPercentage: false,
                showsChargingIndicator: false, showsPercentageWhenConnected: false, wifiScale: 1
            )
        ))
        let representation = try Self.bitmap(image)
        #expect((representation.colorAt(x: 22, y: 4)?.alphaComponent ?? 0) > 0.8)
        #expect((representation.colorAt(x: 22, y: 35)?.alphaComponent ?? 0) < 0.1)
        for point in SystemMonitorMenuBarIconGeometry.volumeDots() {
            let horizontal = Int(point.x / 120 * 44)
            let vertical = Int(point.y / 120 * 44)
            #expect((representation.colorAt(x: horizontal, y: vertical)?.alphaComponent ?? 0) > 0.8)
        }
    }

    @Test @MainActor
    func bottomDotsShowOriginalFourStepsAndMissingLevelsStayInactive() throws {
        var images: [Data] = []
        for level in [Double?.some(0), 0.25, 0.5, 0.75, 1, nil] {
            let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: nil, wifi: .off, level: level, foreground: .black
            ))
            images.append(try #require(image.tiffRepresentation))
        }
        #expect(Set(images.prefix(5)).count == 5)
        #expect(images.last == images.first)
        let step = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: nil, wifi: .off, level: 0.25, foreground: .black
        ))
        let partial = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: nil, wifi: .off, level: 0.1, foreground: .black
        ))
        #expect(step.tiffRepresentation == partial.tiffRepresentation)
    }

    @Test @MainActor
    func invalidIndicatorLevelsUseUnavailableAndFiniteLevelsClamp() throws {
        func image(_ level: Double?) throws -> Data {
            let result = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: nil, wifi: .off, level: level, foreground: .black
            ))
            return try #require(result.tiffRepresentation)
        }
        #expect(try image(.nan) == image(nil))
        #expect(try image(.infinity) == image(nil))
        #expect(try image(-1) == image(0))
        #expect(try image(2) == image(1))
    }

    @Test @MainActor
    func zeroAndInvalidBatteryLevelsDoNotDrawProgress() throws {
        let appearance = SystemMonitorCombinedIconAppearance(
            showsBatteryPercentage: false, showsChargingIndicator: false,
            showsPercentageWhenConnected: false
        )
        let unavailable = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: nil, wifi: .connected(strength: 1), level: 0, foreground: .black, configuration: appearance
        ))
        var battery = Self.battery()
        for level in [0, -1, Double.nan, .infinity] {
            battery.level = level
            let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: battery, wifi: .connected(strength: 1), level: 0, foreground: .black, configuration: appearance
            ))
            #expect(image.tiffRepresentation == unavailable.tiffRepresentation)
        }
        battery.level = 2
        let clamped = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: battery, wifi: .connected(strength: 1), level: 0, foreground: .black, configuration: appearance
        ))
        battery.level = 1
        let full = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: battery, wifi: .connected(strength: 1), level: 0, foreground: .black, configuration: appearance
        ))
        #expect(clamped.tiffRepresentation == full.tiffRepresentation)
    }

    @Test @MainActor
    func wifiConnectionStatesUseOriginalSymbols() throws {
        for foreground in [NSColor.black, .white] {
            let connected = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: nil, wifi: .connected(strength: 1), level: 0, foreground: foreground
            ))
            let disconnected = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: nil, wifi: .disconnected, level: 0, foreground: foreground
            ))
            let off = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: nil, wifi: .off, level: 0, foreground: foreground
            ))
            let unavailable = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: nil, wifi: .unavailable, level: 0, foreground: foreground
            ))
            #expect(connected.tiffRepresentation != disconnected.tiffRepresentation)
            #expect(disconnected.tiffRepresentation != off.tiffRepresentation)
            #expect(off.tiffRepresentation == unavailable.tiffRepresentation)
        }
    }

    @Test @MainActor
    func combinedIconPreservesYellowPixelsAtRetinaResolution() throws {
        var battery = Self.battery()
        battery.isLowPowerMode = true
        for foreground in [NSColor.black, .white] {
            let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
                battery: battery, wifi: .connected(strength: 0.8), level: 0.5, foreground: foreground
            ))
            #expect(image.size == NSSize(width: 24, height: 24))
            #expect(!image.isTemplate)
            let representation = try Self.bitmap(image)
            #expect(representation.pixelsWide == 48)
            #expect(representation.pixelsHigh == 48)
            let yellowPixels = (0..<48).reduce(0) { count, horizontal in
                count + (0..<48).filter { vertical in
                    guard let color = representation.colorAt(x: horizontal, y: vertical)?.usingColorSpace(.deviceRGB) else { return false }
                    return color.alphaComponent > 0.5 && color.redComponent > 0.6 && color.greenComponent > 0.5 && color.blueComponent < 0.4
                }.count
            }
            #expect(yellowPixels > 20)
        }
    }

    @Test @MainActor
    func disconnectedWiFiDiffersButUnavailableBottomLevelsUseOriginalInactiveDots() throws {
        let connected = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: nil, wifi: .connected(strength: 1), level: 0, foreground: .black
        ))
        let disconnected = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: nil, wifi: .disconnected, level: 0, foreground: .black
        ))
        let unavailable = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: nil, wifi: .disconnected, level: nil, foreground: .black
        ))
        #expect(connected.tiffRepresentation != disconnected.tiffRepresentation)
        #expect(disconnected.tiffRepresentation == unavailable.tiffRepresentation)
    }

    @Test @MainActor
    func emptyBatteryRingAndEmptyIndicatorDoNotRenderAsFull() throws {
        var battery = Self.battery()
        battery.level = 0
        let empty = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: battery, wifi: .off, level: 0, foreground: .black
        ))
        battery.level = 1
        let full = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(
            battery: battery, wifi: .off, level: 1, foreground: .black
        ))
        #expect(empty.tiffRepresentation != full.tiffRepresentation)
    }

    @Test
    func allMenuBarConfigurationLabelsAreLocalized() throws {
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let keys = [
            "菜单栏布局", "独立", "合并", "独立与合并", "上行", "下行", "无", "合并状态图标", "底部指标", "音量", "屏幕亮度", "未连接",
            "显示数量", "%ld项", "普通指标可选2或4项；网络或风扇可选2或3项；两者同时显示时仅可选2项",
            "电量环、Wi-Fi 与实时指标合并显示；点击打开系统监控",
        ]
        for language in AppLanguage.allCases {
            let tableURL = packageRoot.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: tableURL) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue) is missing \(key)")
                #expect(!value.isEmpty)
                #expect(AppLocalization.string(key, language: language) == value)
                if key == "%ld项" {
                    #expect(value.components(separatedBy: "%ld").count == 2)
                    for count in [2, 3, 4] {
                        let formatted = AppLocalization.format(key, locale: language.locale, [count])
                        #expect(formatted == String(format: value, locale: language.locale, arguments: [count]))
                        #expect(!formatted.contains("%ld"))
                    }
                }
                if language != .simplifiedChinese && language != .traditionalChinese
                    && !(language == .japanese && key == "音量") {
                    #expect(value != key)
                }
            }
        }
    }

    private static func rows(top: [SystemMonitorMenuBarMetric], bottom: [SystemMonitorMenuBarMetric], snapshot: SystemMetricsSnapshot?) -> [String] {
        SystemMonitorCombinedMenuBarPresentation.rows(top: top, bottom: bottom, snapshot: snapshot, style: .compact)
    }

    @MainActor
    private static func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        let data = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: data))
    }

    private static func battery() -> BatterySnapshot {
        BatterySnapshot(level: 1, isCharging: false, isPluggedIn: true, isCharged: false, timeRemainingMinutes: nil)
    }

    private static func snapshot() -> SystemMetricsSnapshot {
        SystemMetricsSnapshot(
            sampledAt: .distantPast,
            cpu: CPUMetrics(usage: 0.9, userFraction: 0.7, systemFraction: 0.2, idleFraction: 0.1, niceFraction: 0),
            memory: MemoryMetrics(totalBytes: 100, usedBytes: 80, freeBytes: 20, activeBytes: 0, inactiveBytes: 0, wiredBytes: 0, compressedBytes: 0, pressureRatio: 0.1),
            disk: DiskMetrics(totalBytes: 100, freeBytes: 20, usedBytes: 80, volumeURL: URL(fileURLWithPath: "/")),
            network: .zero, gpu: .available(GPUUsageMetrics(usage: 0.8)),
            fan: .available(rpm: [2014, 5277], detail: nil)
        )
    }
}
