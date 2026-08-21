import Foundation
import Testing

@testable import Zisla

struct UpdateNoticePresentationTests {
    @Test
    func updateActionUsesUpwardArrow() throws {
        let source = try String(contentsOf: Self.appModelSourceURL, encoding: .utf8)
        let functionStart = try #require(source.range(of: "private func refreshUpdateNotices()"))
        let functionSuffix = source[functionStart.lowerBound...]
        let functionEnd = try #require(functionSuffix.range(of: "// MARK: - Voice model discovery"))
        let functionSource = functionSuffix[..<functionEnd.lowerBound]
        let noticeStart = try #require(functionSource.range(of: "let right = IslandNotice("))
        let noticeSuffix = functionSource[noticeStart.lowerBound...]
        let noticeEnd = try #require(noticeSuffix.range(of: "let activeIDs"))
        let rightNotice = noticeSuffix[..<noticeEnd.lowerBound]

        #expect(rightNotice.contains("symbolName: \"arrow.up.circle\""))
        #expect(!rightNotice.contains("symbolName: \"arrow.down.circle\""))
    }

    @Test
    func compactUpdateWingUsesUpwardArrow() throws {
        let source = try String(contentsOf: Self.sideNoticeViewSourceURL, encoding: .utf8)
        let viewStart = try #require(source.range(of: "private struct CompactUpdateWing: View"))
        let viewSuffix = source[viewStart.lowerBound...]
        let viewEnd = try #require(viewSuffix.range(of: "private struct CompactAIWing: View"))
        let viewSource = viewSuffix[..<viewEnd.lowerBound]

        #expect(viewSource.contains("Image(systemName: \"arrow.up.circle\")"))
        #expect(!viewSource.contains("Image(systemName: \"arrow.down.circle\")"))
    }

    @Test
    func productUpdateIndicatorsUseUpwardArrow() throws {
        let source = try String(contentsOf: Self.settingsViewSourceURL, encoding: .utf8)
        let statusStart = try #require(source.range(of: "private var updateStatusAccessory: some View"))
        let statusSuffix = source[statusStart.lowerBound...]
        let statusEnd = try #require(statusSuffix.range(of: "private var updateStatusText: String"))
        let statusSource = statusSuffix[..<statusEnd.lowerBound]

        #expect(statusSource.contains("symbol: \"arrow.up.circle\""))
        #expect(statusSource.contains("Image(systemName: \"arrow.up.circle.fill\")"))
        #expect(!statusSource.contains("arrow.down.circle"))
        #expect(source.contains("case .updateAvailable: \"arrow.up.circle\""))
    }

    private static var appModelSourceURL: URL {
        sourcesDirectoryURL.appendingPathComponent("Zisla/AppModel.swift")
    }

    private static var sideNoticeViewSourceURL: URL {
        sourcesDirectoryURL.appendingPathComponent("Zisla/SideNoticeView.swift")
    }

    private static var settingsViewSourceURL: URL {
        sourcesDirectoryURL.appendingPathComponent("Zisla/SettingsView.swift")
    }

    private static var sourcesDirectoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }
}
