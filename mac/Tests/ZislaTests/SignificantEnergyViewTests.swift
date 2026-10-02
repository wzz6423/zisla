import AppKit
import SwiftUI
import Testing
import ZislaKit

@testable import Zisla

@Suite(.serialized)
struct SignificantEnergyViewTests {
    @Test @MainActor
    func topThreeKeepTheNativeRankingAndInstalledAppNamesAndIcons() {
        let processes = ["third", "first", "second", "fourth"].map { identifier in
            SignificantEnergyProcess(
                bundleIdentifier: identifier, responsibleBundleIdentifier: "owner.\(identifier)",
                displayName: identifier
            )
        }
        let icon = NSImage(size: NSSize(width: 18, height: 18))
        var resolved = [String]()
        let items = SignificantEnergyView.presentations(for: processes) { identifier in
            resolved.append(identifier)
            return .init(name: "App \(identifier)", icon: icon)
        }

        #expect(items.map(\.name) == ["App third", "App first", "App second"])
        #expect(items.allSatisfy { $0.icon === icon })
        #expect(resolved == ["third", "first", "second"], "Only visible ranked entries should resolve app metadata")
    }

    @Test @MainActor
    func unresolvedHelperUsesItsResponsibleAppAndUnknownProcessesRemainVisible() {
        let processes = [
            SignificantEnergyProcess(bundleIdentifier: "helper", responsibleBundleIdentifier: "editor", displayName: "helper"),
            SignificantEnergyProcess(bundleIdentifier: "unknown", responsibleBundleIdentifier: "unknown", displayName: "Background Worker"),
        ]
        let icon = NSImage(size: NSSize(width: 18, height: 18))
        let items = SignificantEnergyView.presentations(for: processes) { identifier in
            identifier == "editor" ? .init(name: "Editor", icon: icon) : nil
        }
        #expect(items.map(\.name) == ["Editor", "Background Worker"])
        #expect(items.first?.icon === icon)
        #expect(items.last?.icon == nil)
        #expect(SignificantEnergyView.presentations(for: [], application: { _ in
            Issue.record("An empty list must not resolve application metadata")
            return nil
        }).isEmpty)
    }

    @Test(arguments: ["CFBundleDisplayName", "CFBundleName"], ["Display Name", ""]) @MainActor
    func installedAppMetadataReplacesBundleIDsAndKeepsAReadableFallback(nameKey: String, displayName: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let applicationURL = directory.appendingPathComponent("Example.app")
        let contents = applicationURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var info = [
            "CFBundleIdentifier": "example.\(UUID().uuidString)", "CFBundlePackageType": "APPL",
            "CFBundleName": "Bundle Name",
        ]
        info[nameKey] = displayName
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let icon = NSImage(size: NSSize(width: 18, height: 18))
        let item = try #require(SignificantEnergyView.installedApplication(
            "example", resolve: { _ in applicationURL }, icon: { _ in icon }
        ))
        let expectedFallback = nameKey == "CFBundleDisplayName" ? "Bundle Name" : "Example"
        #expect(item.name == (displayName.isEmpty ? expectedFallback : displayName))
        #expect(item.icon === icon)
    }

    @Test @MainActor
    func aMissingApplicationDoesNotRequestAnIcon() {
        let item = SignificantEnergyView.installedApplication("missing", resolve: { _ in nil }, icon: { _ in
            Issue.record("Missing applications cannot supply a file icon")
            return NSImage()
        })
        #expect(item == nil)
    }

    @Test @MainActor
    func threeLongNamesAndIconsFitOnOneRow() throws {
        let items = (0..<3).map { index in
            SignificantEnergyView.ProcessPresentation(name: "Example application with a long name \(index)", icon: nil)
        }
        let renderer = ImageRenderer(content: SignificantEnergyView.processRow(items).frame(width: 390))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == 780)
        #expect(image.height == 36, "Process names must truncate instead of adding more rows")
    }

    @Test(arguments: [SignificantEnergyState.idle, .loading]) @MainActor
    func initialReadNeverAppearsAsAnEmptySystemList(state: SignificantEnergyState) {
        #expect(SignificantEnergyView.messageKey(for: state) == "正在读取能耗信息…")
    }

    @Test @MainActor
    func emptySystemListHasItsOwnMessage() {
        #expect(SignificantEnergyView.messageKey(for: .available([])) == "当前没有使用大量能耗的 App")
    }

    @Test(arguments: [
        (SignificantEnergyUnavailableReason.unsupported, "当前系统不支持读取能耗信息"),
        (.permissionDenied, "系统限制了能耗信息访问"),
        (.invalidResponse, "无法读取能耗信息，请重试"),
        (.readFailed, "无法读取能耗信息，请重试"),
    ]) @MainActor
    func unavailableReasonsRemainDistinctFromANormalEmptyList(
        reason: SignificantEnergyUnavailableReason,
        expected: String
    ) {
        #expect(SignificantEnergyView.messageKey(for: .unavailable(reason)) == expected)
    }

    @Test @MainActor
    func nativeProcessesReplaceStatusCopy() {
        let processes = [
            SignificantEnergyProcess(
                bundleIdentifier: "com.example.helper",
                responsibleBundleIdentifier: "com.example.editor",
                displayName: "Example Renderer"
            ),
        ]
        #expect(SignificantEnergyView.messageKey(for: .available(processes)) == nil)
    }
}
