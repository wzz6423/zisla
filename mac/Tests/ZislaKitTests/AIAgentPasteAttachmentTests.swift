import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct AIAgentPasteAttachmentTests {
    @Test
    func importTextAttachmentUnder200CharactersReturnsPlainTextFile() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let shortText = String(repeating: "测", count: 100)
        let attachment = try store.importTextAttachment(shortText)

        #expect(attachment.kind == .file)
        #expect(attachment.mimeType == "text/plain")
        #expect(attachment.fileName == "备忘录.txt")
        #expect(attachment.state == .active)
        #expect(attachment.byteCount > 0)

        let url = try #require(store.attachmentURL(for: attachment))
        let loaded = try String(contentsOf: url, encoding: .utf8)
        #expect(loaded == shortText)

        store.discardImportedAttachments([attachment])
        #expect(store.attachmentURL(for: attachment) == nil)
    }

    @Test
    func importTextAttachmentOver200CharactersCreatesFile() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let longText = String(repeating: "长文本粘贴内容。", count: 50)
        #expect(longText.count > 200)

        let attachment = try store.importTextAttachment(longText, fileName: "粘贴内容.txt")

        #expect(attachment.kind == .file)
        #expect(attachment.fileName == "粘贴内容.txt")
        #expect(attachment.state == .active)

        let url = try #require(store.attachmentURL(for: attachment))
        let loaded = try String(contentsOf: url, encoding: .utf8)
        #expect(loaded == longText)

        store.discardImportedAttachments([attachment])
    }

    @Test
    func importTextAttachmentRejectsTooLargeContent() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Generate text larger than 25 MiB.
        let hugeText = String(repeating: "x", count: 26 * 1024 * 1024)

        #expect(throws: AIAgentAttachmentStoreError.self) {
            _ = try store.importTextAttachment(hugeText)
        }
    }

    @Test
    func importTextAttachmentTrimsBlankFileName() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let attachment = try store.importTextAttachment("内容", fileName: "   ")

        #expect(attachment.fileName == "备忘录.txt")

        store.discardImportedAttachments([attachment])
    }
}

@MainActor
private func makeStore() -> (AIAgentStore, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("zisla-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = AIAgentStore(
        storageURL: directory.appendingPathComponent("state.json"),
        secretStore: StubSecretStore()
    )
    return (store, directory)
}

private struct StubSecretStore: AIAgentSecretStoring {
    func secret(for reference: String) throws -> String? { nil }
    func setSecret(_ secret: String, for reference: String) throws {}
    func removeSecret(for reference: String) throws {}
}
