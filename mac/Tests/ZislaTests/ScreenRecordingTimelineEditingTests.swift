import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingTimelineEditingTests {
    private var segments: [RecordingSegment] {
        [.init(start: 8, end: 12, speed: 2), .init(start: 0, end: 2, speed: 0.5), .init(start: 8, end: 10)]
    }

    @Test(arguments: [0.25, 1.0, 4.0])
    func outputPlayheadSplitsOnlyItsRepeatedOccurrenceAndKeepsSpeed(_ speed: Double) throws {
        var segments = segments
        segments[2].speed = speed
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        let outputTime = 6 + 1 / speed
        model.seekTimeline(to: outputTime)
        #expect(model.currentTime == 9)
        #expect(model.timelineSplitTarget(at: outputTime)?.segmentID == segments[2].id)

        #expect(model.splitTimeline(at: outputTime) == segments[2].id)

        let edited = try #require(model.project)
        #expect(Array(edited.edits.segments.prefix(2)) == Array(segments.prefix(2)))
        #expect(edited.edits.segments[2].id == segments[2].id)
        #expect(edited.edits.segments[2].start == 8 && edited.edits.segments[2].end == 9)
        #expect(edited.edits.segments[3].start == 9 && edited.edits.segments[3].end == 10)
        #expect(edited.edits.segments[3].id != segments[2].id)
        #expect(edited.edits.segments.suffix(2).allSatisfy { $0.speed == speed })
        #expect(edited.outputDuration == original.outputDuration)
        #expect(model.playbackTime == outputTime && model.currentTime == 9)
        model.undo()
        #expect(model.project == original && !model.canUndo && model.canRedo)
        model.redo()
        #expect(model.project == edited && !model.canRedo)
    }

    @Test(arguments: [0.0, 0.00025, 1.99975, 2, 2.0005, 5.9995, 6, 6.0005, 7.9995, 8, 9, -1, Double.nan, .infinity, -.infinity])
    func splitRejectsCutsEndpointsAndInvalidOutputClocksWithoutCreatingHistory(_ time: Double) throws {
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        #expect(model.timelineSplitTarget(at: time) == nil)
        #expect(model.splitTimeline(at: time) == nil)
        #expect(model.project == original)
        #expect(!model.canUndo && !model.canRedo && !model.isDirty)
    }

    @Test
    func explicitSourceSplitNeverFallsBackToAnotherCopy() throws {
        let segments = segments
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.split(at: 9, segmentID: UUID())
        #expect(model.project == original && !model.canUndo)
        model.split(at: 9, segmentID: segments[2].id)
        let edited = try #require(model.project?.edits.segments)
        #expect(edited[0] == segments[0])
        #expect(edited[2].id == segments[2].id && edited[2].end == 9)
        #expect(edited[3].start == 9)
    }

    @Test
    func duplicationCreatesAnAdjacentUniqueCopyAndSupportsOneStepUndoRedo() throws {
        let segments = segments
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        let id = try #require(model.duplicateSegment(segments[1].id))
        let duplicated = try #require(model.project)
        let copy = duplicated.edits.segments[2]
        #expect(copy.id == id && id != segments[1].id)
        #expect(copy.start == segments[1].start && copy.end == segments[1].end && copy.speed == segments[1].speed)
        #expect(duplicated.edits.segments[1] == segments[1] && duplicated.edits.segments[3] == segments[2])
        model.undo()
        #expect(model.project == original && !model.canUndo)
        model.redo()
        #expect(model.project == duplicated)
    }

    @Test
    func reorderingRetimedCopiesKeepsOutputClockAndSplitsTheNewOccurrence() throws {
        let segments = segments
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.seekTimeline(to: 7)
        #expect(model.currentTime == 9)

        model.moveSegment(segments[0].id, to: 2)

        let moved = try #require(model.project)
        #expect(moved.edits.segments.map(\.id) == [segments[1].id, segments[2].id, segments[0].id])
        #expect(model.playbackTime == 7 && model.currentTime == 10)
        let geometry = try #require(ScreenRecordingTimelineStripGeometry(segments: moved.edits.segments, viewportWidth: 800, zoom: 1))
        #expect(geometry.target(at: 700)?.segmentID == segments[0].id)
        #expect(geometry.target(at: 700)?.sourceTime == model.currentTime)
        #expect(model.splitTimeline(at: 7) == segments[0].id)
        let split = try #require(model.project)
        #expect(split.edits.segments[1] == segments[2])
        #expect(split.edits.segments[2].id == segments[0].id && split.edits.segments[2].end == 10)
        model.undo()
        #expect(model.project == moved)
        model.undo()
        #expect(model.project == original)
        model.redo()
        model.redo()
        #expect(model.project == split)
    }

    @Test
    func deletingACopyKeepsOtherOccurrencesAndCanUndoAnEmptyTimeline() throws {
        let segments = segments
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.seekTimeline(to: 7)
        #expect(model.deleteSegment(segments[2].id) == segments[1].id)
        let deleted = try #require(model.project)
        #expect(deleted.edits.segments == Array(segments.prefix(2)))
        #expect(model.playbackTime == 6 && model.currentTime == 2)
        model.undo()
        #expect(model.project == original)
        model.redo()
        #expect(model.project == deleted)
        #expect(model.deleteSegment(segments[0].id) == segments[1].id)
        #expect(model.deleteSegment(segments[1].id) == nil)
        #expect(model.project?.edits.segments.isEmpty == true && model.playbackTime == 0)
        let empty = try #require(model.project)
        for time in [0.0, 1] {
            #expect(model.timelineSplitTarget(at: time) == nil)
            #expect(model.splitTimeline(at: time) == nil)
        }
        #expect(model.project == empty && model.canUndo && !model.canRedo)
        model.undo()
        #expect(model.project?.edits.segments == [segments[1]])
    }

    @Test
    func invalidAndUnchangedActionsPreserveRedoAndTheProject() throws {
        let segments = segments
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        _ = model.duplicateSegment(segments[0].id)
        model.undo()
        #expect(model.canRedo)
        #expect(model.duplicateSegment(UUID()) == nil)
        #expect(model.deleteSegment(UUID()) == nil)
        model.moveSegment(UUID(), to: 1)
        for destination in [-1, 0, 3, Int.max] { model.moveSegment(segments[0].id, to: destination) }
        #expect(model.project == original)
        #expect(!model.canUndo && model.canRedo)
    }

    @Test
    func segmentLimitRejectsTimelineInsertionsAtomically() throws {
        let segments = (0..<2_000).map { _ in RecordingSegment(start: 0, end: 1) }
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        #expect(model.splitTimeline(at: 0.5) == nil)
        #expect(model.duplicateSegment(segments[0].id) == nil)
        #expect(model.project == original)
        #expect(!model.isDirty && !model.canUndo)
        #expect(model.errorMessage == ScreenRecordingProjectError.invalidProject.localizedDescription)
    }

    @Test
    func busyActionsCannotChangeTheProjectOrReturnAnEditableSelection() async throws {
        let segments = segments
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.aiInstruction = "split"
        model.requestAIEdit()
        #expect(model.isBusy)
        #expect(model.timelineSplitTarget(at: 1) == nil)
        #expect(model.splitTimeline(at: 1) == nil)
        #expect(model.duplicateSegment(segments[0].id) == nil)
        #expect(model.deleteSegment(segments[0].id) == nil)
        model.moveSegment(segments[0].id, to: 1)
        #expect(model.project == original && !model.canUndo && !model.canRedo && !model.isDirty)
        await model.operationTask?.value
        #expect(model.canEdit && model.project == original)
    }

    @Test
    func actionsWithoutAProjectLeaveTheEditorUnchanged() {
        let model = ScreenRecordingStudioModel()
        defer { model.shutdown() }
        #expect(model.splitTimeline(at: 1) == nil)
        #expect(model.duplicateSegment(UUID()) == nil)
        #expect(model.deleteSegment(UUID()) == nil)
        model.moveSegment(UUID(), to: 0)
        #expect(model.project == nil && !model.canUndo && !model.canRedo && !model.isDirty)
    }

    @Test
    func directTimelineButtonsPerformRealUndoableEditsOnTheSelectedCopy() async throws {
        let segments = segments
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.seekTimeline(to: 7)
        var selected: UUID? = segments[2].id
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ScreenRecordingTimelineStrip(model: model,
            selectedID: Binding(get: { selected }, set: { selected = $0 })).frame(width: 700))
        host.sizingOptions = []
        let window = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 700, height: 150),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
        window.orderFrontRegardless()
        await settle(host)
        let split = try #require(button("screenRecording.timelineSplit", in: host))
        #expect(split.enabled)
        try click(split.frame, in: window)
        await settle(host)
        #expect(model.project?.edits.segments.count == 4 && selected == segments[2].id)
        #expect(model.project?.edits.segments[0] == original.edits.segments[0])
        #expect(model.project?.edits.segments[2].end == 9)
        #expect((try #require(button("screenRecording.timelineSplit", in: host))).enabled == false)

        let delete = try #require(button("screenRecording.timelineDelete", in: host))
        try click(delete.frame, in: window)
        await settle(host)
        let remainingID = try #require(model.project?.edits.segments.last?.id)
        #expect(selected == remainingID && remainingID != segments[2].id)
        #expect(model.project?.edits.segments.count == 3 && model.playbackTime == 6 && model.currentTime == 9)

        let duplicate = try #require(button("screenRecording.timelineDuplicate", in: host))
        try click(duplicate.frame, in: window)
        await settle(host)
        #expect(model.project?.edits.segments.count == 4)
        #expect(selected == model.project?.edits.segments.last?.id && selected != remainingID)
        #expect(model.playbackTime == 7 && model.currentTime == 9)
        model.undo()
        model.undo()
        model.undo()
        #expect(model.project == original && !model.canUndo)
        #expect(!window.isKeyWindow)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
    }

    @Test
    func timelineInstallsPinchOnItsScrollViewAndKeepsTheProjectAndPlayheadUnchanged() async throws {
        let (model, root, original) = try fixture(segments)
        defer { model.shutdown(); try? FileManager.default.removeItem(at: root) }
        model.seekTimeline(to: 3)
        let time = model.currentTime
        let host = NSHostingView(rootView: ScreenRecordingTimelineStrip(model: model,
            selectedID: .constant(nil)).frame(width: 700))
        host.sizingOptions = []
        let window = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 700, height: 150),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        window.orderFrontRegardless()
        await settle(host)
        func find(_ view: NSView) -> ScreenRecordingTimelineMagnificationView? {
            if let magnification = view as? ScreenRecordingTimelineMagnificationView { return magnification }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let magnification = try #require(find(host))
        let scroll = try #require(magnification.magnificationRecognizer.view as? NSScrollView)
        let document = try #require(scroll.documentView)
        let originalWidth = document.frame.width
        magnification.magnify(by: 1, phase: .began, location: 208)
        await settle(host)
        #expect(abs(document.frame.width - ((originalWidth - 16) * 2 + 16)) < 1)
        #expect(abs(scroll.contentView.bounds.minX - 200) < 1)
        magnification.magnify(by: 1, phase: .ended, location: 408)
        #expect(model.project == original && !model.canUndo && !model.isDirty)
        #expect(model.playbackTime == 3 && model.currentTime == time)
    }

    private func fixture(_ segments: [RecordingSegment]) throws -> (ScreenRecordingStudioModel, URL, ScreenRecordingProject) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-timeline-edit-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data([1]).write(to: root.appendingPathComponent("screen.mp4"))
        var project = ScreenRecordingProject(name: "Timeline", videoFile: "screen.mp4", duration: 20, width: 64, height: 48)
        project.edits.segments = segments
        let model = ScreenRecordingStudioModel(projectStore: ScreenRecordingProjectStore(root: root),
            renderPreview: { _, _, _ in throw ScreenRecordingExportError.cannotRender },
            aiCompletion: { _, _, _ in throw CancellationError() })
        model.install(project, directory: root)
        return (model, root, project)
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    private func button(_ identifier: String, in host: NSView) -> (frame: CGRect, enabled: Bool)? {
        func find(_ object: NSObject) -> (frame: CGRect, enabled: Bool)? {
            if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
               object.value(forKey: "accessibilityIdentifier") as? String == identifier,
               let element = object as? any NSAccessibilityElementProtocol,
               let enabled = object.value(forKey: "isAccessibilityEnabled") as? Bool {
                return (element.accessibilityFrame(), enabled)
            }
            guard object.responds(to: NSSelectorFromString("accessibilityChildren")) else { return nil }
            for child in object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] {
                if let found = find(child) { return found }
            }
            return nil
        }
        return find(host)
    }

    private func click(_ frame: CGRect, in window: NSWindow) throws {
        let point = window.convertPoint(fromScreen: CGPoint(x: frame.midX, y: frame.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
        }
    }
}
