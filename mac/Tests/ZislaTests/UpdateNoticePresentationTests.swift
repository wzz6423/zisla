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

    private static var appModelSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/AppModel.swift")
    }
}
