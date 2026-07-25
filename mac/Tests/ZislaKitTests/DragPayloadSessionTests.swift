import Testing
import UniformTypeIdentifiers

@testable import ZislaKit

struct DragPayloadSnapshotTests {
    @Test
    func fileURLItemIsSupported() {
        let snapshot = DragPayloadSnapshot(
            changeCount: 2,
            itemTypeIdentifiers: [[UTType.fileURL.identifier]]
        )

        #expect(snapshot.hasSupportedTransferPayload)
    }

    @Test(arguments: [
        UTType.url.identifier, UTType.plainText.identifier, UTType.utf8PlainText.identifier,
    ])
    func linkAndTextItemsAreSupported(typeIdentifier: String) {
        let snapshot = DragPayloadSnapshot(
            changeCount: 2,
            itemTypeIdentifiers: [[typeIdentifier]]
        )

        #expect(snapshot.hasSupportedTransferPayload)
    }

    @Test
    func emptyOrUnrelatedItemsAreRejected() {
        let empty = DragPayloadSnapshot(changeCount: 2, itemTypeIdentifiers: [])
        let image = DragPayloadSnapshot(
            changeCount: 2,
            itemTypeIdentifiers: [[UTType.png.identifier]]
        )

        #expect(!empty.hasSupportedTransferPayload)
        #expect(!image.hasSupportedTransferPayload)
    }
}

struct DragPayloadSessionClassifierTests {
    @Test
    func sessionRequiresANewPasteboardChange() {
        var classifier = DragPayloadSessionClassifier(initialChangeCount: 10)
        let stale = DragPayloadSnapshot(
            changeCount: 10,
            itemTypeIdentifiers: [[UTType.fileURL.identifier]]
        )
        let current = DragPayloadSnapshot(
            changeCount: 11,
            itemTypeIdentifiers: [[UTType.fileURL.identifier]]
        )

        let acceptedStale = classifier.inspect(stale)
        let acceptedCurrent = classifier.inspect(current)
        let acceptedRepeatedEvent = classifier.inspect(current)

        #expect(!acceptedStale)
        #expect(acceptedCurrent)
        #expect(acceptedRepeatedEvent)
    }

    @Test
    func completedSessionCannotBeReusedByAnOrdinaryDrag() {
        var classifier = DragPayloadSessionClassifier(initialChangeCount: 10)
        let payload = DragPayloadSnapshot(
            changeCount: 11,
            itemTypeIdentifiers: [[UTType.fileURL.identifier]]
        )

        let accepted = classifier.inspect(payload)
        classifier.finish(with: payload)
        let acceptedAfterCompletion = classifier.inspect(payload)

        #expect(accepted)
        #expect(!acceptedAfterCompletion)
    }

    @Test
    func pointerDownDoesNotConsumeANewPasteboardChange() {
        var classifier = DragPayloadSessionClassifier(initialChangeCount: 10)
        let payload = DragPayloadSnapshot(
            changeCount: 11,
            itemTypeIdentifiers: [[UTType.fileURL.identifier]]
        )

        classifier.prepareForPointerDrag()

        let accepted = classifier.inspect(payload)

        #expect(accepted)
    }

    @Test
    func pointerDownClosesThePreviousActiveSession() {
        var classifier = DragPayloadSessionClassifier(initialChangeCount: 10)
        let payload = DragPayloadSnapshot(
            changeCount: 11,
            itemTypeIdentifiers: [[UTType.fileURL.identifier]]
        )
        let accepted = classifier.inspect(payload)
        #expect(accepted)

        classifier.prepareForPointerDrag()
        let acceptedAfterPointerDown = classifier.inspect(payload)

        #expect(!acceptedAfterPointerDown)
    }

    @Test
    func completionOnlyNeedsThePasteboardChangeCount() {
        var classifier = DragPayloadSessionClassifier(initialChangeCount: 10)
        let payload = DragPayloadSnapshot(
            changeCount: 11,
            itemTypeIdentifiers: [[UTType.fileURL.identifier]]
        )

        let accepted = classifier.inspect(payload)
        #expect(accepted)
        classifier.finish(changeCount: payload.changeCount)

        let acceptedAfterCompletion = classifier.inspect(payload)
        #expect(!acceptedAfterCompletion)
    }
}

struct PointerEdgeEventActionTests {
    @Test
    func ordinaryPointerMovementDoesNotEnterTheDragPasteboardPath() {
        #expect(PointerEdgeEventAction(eventType: .mouseMoved) == .moved)
        #expect(PointerEdgeEventAction(eventType: .leftMouseDown) == .pointerDown)
        #expect(PointerEdgeEventAction(eventType: .leftMouseDragged) == .dragging)
        #expect(PointerEdgeEventAction(eventType: .leftMouseUp) == .dragEnded)
    }
}
