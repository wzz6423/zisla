import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct DailyBriefingPNGExportTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var date: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11))!
    }

    private let png = Data([137, 80, 78, 71, 13, 10, 26, 10])

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-briefing-png-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func createsMissingSelectedDirectoryWithoutChangingLocation(language: AppLanguage) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("exports/daily", isDirectory: true)

        let output = try DailyBriefingPNGExport.write(png, for: date, language: language, calendar: calendar, directory: directory)

        #expect(output.deletingLastPathComponent() == directory.standardizedFileURL.resolvingSymlinksInPath())
        #expect(!output.hasDirectoryPath)
        #expect(try Data(contentsOf: output) == png)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [output.lastPathComponent])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["exports"])
    }

    @Test
    func recreatesRemovedSaveDirectoryAndOverwritesOneDailyFileOnRetry() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: directory)

        let first = try DailyBriefingPNGExport.write(png, for: date, language: .simplifiedChinese, calendar: calendar, directory: directory)
        let replacement = png + Data([1])
        let second = try DailyBriefingPNGExport.write(replacement, for: date, language: .simplifiedChinese, calendar: calendar, directory: directory)

        #expect(first == second)
        #expect(try Data(contentsOf: second) == replacement)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [second.lastPathComponent])
    }

    @Test
    func emptyDataCreatesOnlyTheRequestedOutputFile() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("daily", isDirectory: true)

        let output = try DailyBriefingPNGExport.write(Data(), for: date, language: .english, calendar: calendar, directory: directory)

        #expect(try Data(contentsOf: output).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [output.lastPathComponent])
    }

    @Test
    func rejectsNonFileDirectoryWithoutCreatingOutput() throws {
        let directory = try #require(URL(string: "https://example.invalid/daily/"))

        #expect(throws: CocoaError(.fileWriteInvalidFileName)) {
            try DailyBriefingPNGExport.write(png, for: date, language: .english, calendar: calendar, directory: directory)
        }
    }

    @Test
    func directoryCreationFailurePreservesExistingFileAndAllowsRecovery() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("daily", isDirectory: true)
        let existing = Data([99])
        try existing.write(to: directory)

        #expect(throws: (any Error).self) {
            try DailyBriefingPNGExport.write(png, for: date, language: .english, calendar: calendar, directory: directory)
        }
        #expect(try Data(contentsOf: directory) == existing)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["daily"])

        try FileManager.default.removeItem(at: directory)
        let output = try DailyBriefingPNGExport.write(png, for: date, language: .english, calendar: calendar, directory: directory)
        #expect(try Data(contentsOf: output) == png)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [output.lastPathComponent])
    }

    @Test
    func rejectsExistingOutputSymlinkOutsideSelectedDirectoryWithoutSideEffects() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.png")
        let existing = Data([99])
        try existing.write(to: outside)
        let output = directory.appendingPathComponent(DailyBriefingPNGExport.fileName(for: date, language: .english, calendar: calendar))
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: outside)

        #expect(throws: CocoaError(.fileWriteInvalidFileName)) {
            try DailyBriefingPNGExport.write(png, for: date, language: .english, calendar: calendar, directory: directory)
        }
        #expect(try Data(contentsOf: outside) == existing)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: output.path) == outside.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [output.lastPathComponent])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["daily", "outside.png"])
    }

    @Test
    func danglingOutputSymlinkNeverCreatesItsMissingOutsideParent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("daily", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        let target = outside.appendingPathComponent("nested/briefing.png")
        let output = directory.appendingPathComponent(DailyBriefingPNGExport.fileName(for: date, language: .english, calendar: calendar))
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: target)

        let result = try DailyBriefingPNGExport.write(png, for: date, language: .english, calendar: calendar, directory: directory)

        #expect(result == output.standardizedFileURL)
        #expect(try Data(contentsOf: result) == png)
        #expect(try result.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
        #expect(!FileManager.default.fileExists(atPath: outside.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [output.lastPathComponent])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["daily"])
    }

    @Test
    func danglingSaveDirectorySymlinkFailsWithoutCreatingOutsideDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("daily", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)

        #expect(throws: (any Error).self) {
            try DailyBriefingPNGExport.write(png, for: date, language: .english, calendar: calendar, directory: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: outside.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: directory.path) == outside.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["daily"])
    }
}
