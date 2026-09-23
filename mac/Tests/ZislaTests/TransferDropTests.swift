import AppKit
import Testing
import SwiftUI
import UniformTypeIdentifiers

@testable import Zisla
@testable import ZislaKit

struct TransferDropTests {
    @Test @MainActor
    func nativeShelfTargetRegistersPromisedFilesAndPlainContent() {
        let view = ShelfDropHostingView(rootView: AnyView(EmptyView()))
        let types = Set(view.registeredDraggedTypes.map(\.rawValue))
        #expect(types.isSuperset(of: NSFilePromiseReceiver.readableDraggedTypes))
        #expect(types.contains(NSPasteboard.PasteboardType.fileURL.rawValue))
        #expect(types.contains(NSPasteboard.PasteboardType.URL.rawValue))
        #expect(types.contains(NSPasteboard.PasteboardType.string.rawValue))
        #expect(types.contains(NSPasteboard.PasteboardType.png.rawValue))
        #expect(types.contains(NSPasteboard.PasteboardType.tiff.rawValue))
    }

    @Test
    func textDataKeepsWhitespaceInsteadOfBecomingRelativeURL() {
        let text = "  selected text\nsecond line  "
        #expect(TransferDropDelegate.dropItem(from: Data(text.utf8) as NSData, type: UTType.utf8PlainText.identifier) == .text(text))
    }

    @Test
    func URLsAreAcceptedOnlyForTheirDeclaredSafeType() {
        let file = URL(fileURLWithPath: "/tmp/drop.txt")
        #expect(TransferDropDelegate.dropItem(from: Data(file.absoluteString.utf8) as NSData, type: UTType.fileURL.identifier) == .file(file))
        #expect(TransferDropDelegate.dropItem(from: "https://example.invalid/file" as NSString, type: UTType.fileURL.identifier) == nil)
        #expect(TransferDropDelegate.dropItem(from: "javascript:alert(1)" as NSString, type: UTType.url.identifier) == nil)
        #expect(TransferDropDelegate.dropItem(from: "https://example.invalid/path" as NSString, type: UTType.url.identifier) == .link(URL(string: "https://example.invalid/path")!))
        #expect(TransferDropDelegate.dropItem(from: " \n\t" as NSString, type: UTType.plainText.identifier) == nil)
        #expect(TransferDropDelegate.dropItem(from: Data([0xFF, 0xFE]) as NSData, type: UTType.plainText.identifier) == nil)
    }

    @Test
    func asyncProvidersKeepInputOrderAndIgnoreRepeatedCompletion() async {
        let result = await withCheckedContinuation { continuation in
            let loader = TransferDropLoader(count: 3) { continuation.resume(returning: $0) }
            loader.finish(at: 2, with: .text("third"))
            loader.finish(at: 2, with: .text("duplicate"))
            loader.finish(at: 1, with: nil)
            loader.finish(at: 0, with: .text("first"))
        }
        #expect(result == [.text("first"), .text("third")])
    }

    @Test
    func shelfPayloadKeepsAllFilesLinksAndText() {
        let text = "  note\n "
        let file = URL(fileURLWithPath: "/tmp/file.txt")
        let link = URL(string: "https://example.invalid")!
        let items: [TransferDropItem] = [.file(file), .link(link), .text(text), .image(Data())]
        #expect(items.compactMap(\.shelfPayload) == [.file(file), .text(link.absoluteString), .text(text)])
        #expect(TransferDropItem(payload: .text(link.absoluteString)) == .link(link))
        #expect(TransferDropItem(payload: .text(text)) == .text(text))
    }
}
