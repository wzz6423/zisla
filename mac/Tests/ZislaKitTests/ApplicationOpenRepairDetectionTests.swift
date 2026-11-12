import Darwin
import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ApplicationOpenRepairDetectionTests {
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func cancellationReachesBackgroundFileInspection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-app-repair-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let marker = Data("test".utf8)
        #expect(marker.withUnsafeBytes { setxattr(app.path, "com.apple.quarantine", $0.baseAddress, $0.count, 0, 0) } == 0)
        let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        defer { started.continuation.finish() }
        let release = DispatchSemaphore(value: 0)
        let task = Task { @MainActor in
            await ClipboardAssistantDetector.detectInBackground(content: .text("echo hello"), enabledKinds: [.shellCommand],
                shellCommandExists: { _ in
                    started.continuation.yield(())
                    #expect(release.wait(timeout: .now() + 10) == .success)
                    let cancelled = Task.isCancelled
                    #expect(cancelled)
                    let needsRepair = ApplicationOpenRepairService.needsRepair(at: app)
                    #expect(!needsRepair)
                    return true
                })
        }
        // The main actor resumes after the detector suspends with its cancellation handler installed.
        for await _ in started.stream {
            task.cancel()
            release.signal()
            break
        }
        _ = await task.value
        #expect(getxattr(app.path, "com.apple.quarantine", nil, 0, 0, 0) == marker.count)
    }

    @Test
    func quarantinedAppOffersOnlyRepairWithoutChangingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-app-repair-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let marker = Array("0081;00000000;ZislaTest;".utf8)
        #expect(marker.withUnsafeBytes { setxattr(app.path, "com.apple.quarantine", $0.baseAddress, $0.count, 0, 0) } == 0)
        let content = ClipboardHistoryContent.file(ClipboardFileReference(url: app, displayName: "Example.app", bookmark: Data()))

        let detection = try #require(ClipboardAssistantDetector.detect(content: content, enabledKinds: Set(ClipboardAssistantKind.allCases)))

        #expect(detection.kind.rawValue == "appCannotOpen")
        #expect(detection.actions.map(\.identifier) == ["repairAndOpenApp"])
        #expect(getxattr(app.path, "com.apple.quarantine", nil, 0, 0, 0) == marker.count)
    }

    @Test
    func nestedQuarantineTriggersOnlyTheEnabledRepairAction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-app-repair-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let executable = app.appendingPathComponent("executable")
        try Data("test".utf8).write(to: executable)
        let marker = Data("test".utf8)
        #expect(marker.withUnsafeBytes { setxattr(executable.path, "com.apple.quarantine", $0.baseAddress, $0.count, 0, 0) } == 0)
        let content = ClipboardHistoryContent.file(ClipboardFileReference(url: app, displayName: "Example.app", bookmark: Data()))
        #expect(ClipboardAssistantDetector.detect(content: content, enabledKinds: [.appCannotOpen])?.kind == .appCannotOpen)
        #expect(ClipboardAssistantDetector.detect(content: content, enabledKinds: [.file])?.kind == .file)
        #expect(ClipboardAssistantDetector.detect(content: content, enabledKinds: []) == nil)
        #expect(getxattr(executable.path, "com.apple.quarantine", nil, 0, 0, 0) == marker.count)
    }

    @Test
    func ordinaryFilesAndUnquarantinedAppsKeepFileActions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-app-repair-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = directory.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let document = directory.appendingPathComponent("example.txt")
        try Data("example".utf8).write(to: document)
        for url in [app, document] {
            let content = ClipboardHistoryContent.file(ClipboardFileReference(url: url, displayName: url.lastPathComponent, bookmark: Data()))
            let detection = try #require(ClipboardAssistantDetector.detect(content: content, enabledKinds: Set(ClipboardAssistantKind.allCases)))
            #expect(detection.kind == .file)
            #expect(detection.actions == [.revealInFinder(url.standardizedFileURL), .compress(url.standardizedFileURL)])
        }
    }
}
