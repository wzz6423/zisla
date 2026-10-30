import AppKit
import AVKit
import CoreImage
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite(.serialized) @MainActor
struct ScreenRecordingCanvasEditorTests {
    @Test(arguments: [false, true], [false, true])
    func multitrackStudioKeepsTypedTextAfterPreviewRefreshAndEnterOrFocusLoss(_ caption: Bool, _ loseFocus: Bool) async throws {
        let fixture = try Fixture(kind: .text, caption: caption, multitrack: true)
        defer { fixture.close() }
        fixture.model.seekTimeline(to: 0.5)
        await fixture.ready()
        let original = try #require(fixture.model.project)
        if caption {
            fixture.model.selectCanvasTimelineContent(.caption(try #require(original.captions.first).id))
        } else {
            fixture.model.selectCanvasTimelineContent(.annotation(try #require(original.edits.annotations?.first).id))
        }
        let defaultsName = "zisla-canvas-multitrack-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let host = NSHostingView(rootView: ScreenRecordingStudioView(model: fixture.model,
            languageStore: AppLanguageStore(defaults: defaults), prepareCapture: {}))
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
        let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        await settle(host)
        let canvas = try #require(descendants(RecordingCanvasEditorView.self, in: host).first)
        let point = fixture.selectionPoint(in: canvas)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(point, to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 2, pressure: 1))
        canvas.mouseDown(with: event)
        let editor = try #require(canvas.textEditor)
        editor.insertText("Typed", replacementRange: editor.selectedRange())
        editor.keyDown(with: fixture.key(49, characters: " "))
        editor.insertText("5678", replacementRange: editor.selectedRange())
        #expect(editor.string == "Typed 5678" && canvas.draft?.text == "Typed 5678")
        #expect(fixture.model.project == original && !fixture.model.canUndo)
        fixture.model.refreshPreview()
        await fixture.model.previewTask?.value
        await settle(host)
        #expect(canvas.textEditor === editor && editor.string == "Typed 5678",
                "Refreshing a multitrack preview must preserve the active native text draft")
        if loseFocus {
            let field = try #require(descendants(NSTextField.self, in: host).first(where: { $0.isEditable }),
                                     "The real inspector must provide another focusable control")
            #expect(window.makeFirstResponder(field))
        } else {
            editor.keyDown(with: fixture.key(36, characters: "\r"))
        }
        await fixture.model.previewTask?.value
        await settle(host)
        let edited = try #require(fixture.model.project)
        #expect((caption ? edited.captions.first?.text : edited.edits.annotations?.first?.text) == "Typed 5678",
                "Enter and native focus loss must commit the typed multitrack text")
        #expect(canvas.textEditor == nil && fixture.model.canUndo)
        try fixture.model.save()
        #expect(try fixture.model.projectStore.load(from: fixture.directory) == edited)
        fixture.model.undo()
        #expect(fixture.model.project == original && !fixture.model.canUndo)
        fixture.model.redo()
        #expect(fixture.model.project == edited && !fixture.model.canRedo)
        fixture.model.install(try fixture.model.projectStore.load(from: fixture.directory), directory: fixture.directory)
        await fixture.model.previewTask?.value
        await settle(host)
        #expect(fixture.model.project == edited && !fixture.model.canUndo && !fixture.model.canRedo,
                "Reopening the saved project must retain the submitted text without restoring edit history")
        let reopenedCanvas = try #require(descendants(RecordingCanvasEditorView.self, in: host).first)
        #expect(try bytes(#require(reopenedCanvas.renderedImage)) == bytes(#require(fixture.model.canvasPreview)),
                "The reopened canvas must show the same text pixels as the rebuilt preview")
        #expect(!window.isVisible && !fixture.window.isVisible)
    }

    @Test(arguments: [false, true], [false, true])
    func markedTextSurvivesTheIMEConfirmKeyAndNativeFocusLoss(_ caption: Bool, _ loseFocus: Bool) async throws {
        let fixture = try Fixture(kind: .text, caption: caption, multitrack: true)
        defer { fixture.close() }
        await fixture.ready()
        let original = try #require(fixture.model.project)
        fixture.view.mouseDown(with: fixture.textMouse())
        let editor = try #require(fixture.view.textEditor)
        editor.setMarkedText("中文输入", selectedRange: NSRange(location: 4, length: 0), replacementRange: editor.selectedRange())
        #expect(editor.hasMarkedText() && editor.string == "中文输入")
        fixture.model.refreshPreview()
        await fixture.ready()
        #expect(fixture.view.textEditor === editor && editor.hasMarkedText() && editor.string == "中文输入",
                "An asynchronous preview must preserve the composition that has no did-change notification")
        #expect(fixture.model.project == original && !fixture.model.canUndo)
        if loseFocus {
            let field = NSTextField(frame: CGRect(x: 10, y: 10, width: 120, height: 30))
            fixture.view.addSubview(field)
            #expect(fixture.window.makeFirstResponder(field))
        } else {
            editor.keyDown(with: fixture.key(36, characters: "\r"))
            #expect(fixture.view.textEditor === editor,
                    "Return must confirm marked input before it can submit the canvas text editor")
            #expect(!editor.hasMarkedText() && editor.string == "中文输入",
                    "Confirming a composition must preserve its text without inserting a newline")
            editor.keyDown(with: fixture.key(36, characters: "\r"))
        }
        #expect((caption ? fixture.model.project?.captions.first?.text : fixture.model.project?.edits.annotations?.first?.text) == "中文输入",
                "Submitting or leaving marked input must keep its current text")
        #expect(fixture.view.textEditor == nil && fixture.model.canUndo)
        fixture.model.undo()
        #expect(fixture.model.project == original && !fixture.model.canUndo)
    }

    @Test(arguments: [false, true], ["enter", "focus", "save"])
    func submittingReadsTheCurrentNativeTextWhenTheDraftNotificationIsPending(_ caption: Bool, _ finish: String) async throws {
        let fixture = try Fixture(kind: .text, caption: caption, multitrack: true)
        defer { fixture.close() }
        await fixture.ready()
        let original = try #require(fixture.model.project)
        fixture.model.commitPendingCanvasText = { [weak view = fixture.view] in view?.finishTextEditing(commit: true) }
        fixture.view.mouseDown(with: fixture.textMouse())
        let editor = try #require(fixture.view.textEditor)
        editor.insertText("Earlier draft", replacementRange: editor.selectedRange())
        editor.string = "Current 中文 👩🏽‍💻"
        #expect(fixture.view.draft?.text == "Earlier draft" && fixture.model.project == original)
        if finish == "enter" {
            editor.keyDown(with: fixture.key(36, characters: "\r"))
        } else if finish == "focus" {
            let field = NSTextField(frame: CGRect(x: 10, y: 10, width: 120, height: 30))
            fixture.view.addSubview(field)
            #expect(fixture.window.makeFirstResponder(field))
        } else {
            try fixture.model.save()
        }
        let edited = try #require(fixture.model.project)
        #expect((caption ? edited.captions.first?.text : edited.edits.annotations?.first?.text) == editor.string,
                "Submitting must read current native text even when the did-change draft still contains earlier text")
        #expect(fixture.view.textEditor == nil && fixture.commits == 1 && fixture.model.canUndo)
        try fixture.model.save()
        #expect(try fixture.model.projectStore.load(from: fixture.directory) == edited)
        fixture.model.undo()
        #expect(fixture.model.project == original && !fixture.model.canUndo)
        fixture.model.redo()
        #expect(fixture.model.project == edited && !fixture.model.canRedo)
    }

    @Test(arguments: [false, true])
    func savingPendingCompositionBoundsGraphemesAndPreservesEmptyTextObjects(_ caption: Bool) async throws {
        let fixture = try Fixture(kind: .text, caption: caption, multitrack: true)
        defer { fixture.close() }
        await fixture.ready()
        let original = try #require(fixture.model.project)
        fixture.model.commitPendingCanvasText = { [weak view = fixture.view] in view?.finishTextEditing(commit: true) }
        let text = String(repeating: "x", count: 3_999) + "👩🏽‍💻z"
        fixture.view.mouseDown(with: fixture.textMouse())
        let editor = try #require(fixture.view.textEditor)
        editor.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0),
                             replacementRange: editor.selectedRange())
        #expect(editor.hasMarkedText() && editor.string == text)
        try fixture.model.save()
        let edited = try #require(fixture.model.project)
        let committed = try #require(caption ? edited.captions.first?.text : edited.edits.annotations?.first?.text)
        #expect(committed == String(text.prefix(4_000)) && committed.count == 4_000,
                "Saving pending composition must enforce the project limit without splitting a grapheme")
        #expect(fixture.commits == 1 && fixture.view.textEditor == nil && fixture.model.errorMessage == nil)
        #expect(try fixture.model.projectStore.load(from: fixture.directory) == edited)
        fixture.model.undo()
        #expect(fixture.model.project == original && !fixture.model.canUndo)
        fixture.model.redo()
        #expect(fixture.model.project == edited && !fixture.model.canRedo)
        await fixture.ready()
        fixture.view.mouseDown(with: fixture.textMouse())
        let emptyEditor = try #require(fixture.view.textEditor)
        emptyEditor.string = ""
        try fixture.model.save()
        let empty = try #require(fixture.model.project)
        #expect((caption ? empty.captions.first?.text : empty.edits.annotations?.first?.text) == "")
        #expect(empty.timeline == edited.timeline,
                "Saving an empty label must preserve the object and its existing timeline clip")
        #expect(caption ? empty.captions.count == 1 : empty.edits.annotations?.count == 1)
        #expect(fixture.commits == 2)
        #expect(try fixture.model.projectStore.load(from: fixture.directory) == empty)
        fixture.model.undo()
        #expect(fixture.model.project == edited)
        fixture.model.undo()
        #expect(fixture.model.project == original && !fixture.model.canUndo)
    }

    @Test(arguments: [false, true])
    func studioHostsTheInteractiveCanvasAndConnectsTextEditsToTheSelectedInspector(_ caption: Bool) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        var exportRequests = 0
        let fixture = try Fixture(kind: .text, caption: caption, presentExportPanel: { _, completion in
            exportRequests += 1
            completion(nil)
        }, aiCompletion: { _, _, _ in
            "{\"version\":1,\"operations\":[{\"type\":\"caption\",\"start\":0,\"end\":2,\"text\":\"Stale AI text\"}]}"
        })
        defer { fixture.close() }
        await fixture.ready()
        let defaultsName = "zisla-canvas-host-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let host = NSHostingView(rootView: ScreenRecordingStudioView(model: fixture.model,
            languageStore: AppLanguageStore(defaults: defaults), prepareCapture: {}))
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
        let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        await settle(host)
        let canvas = try #require(descendants(RecordingCanvasEditorView.self, in: host).first,
                                  "The real studio must mount its editable canvas after preparing a preview")
        #expect(canvas.canvasRect.width > 300 && canvas.canvasRect.height > 200)
        let point = fixture.selectionPoint(in: canvas)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(point, to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 2, pressure: 1))
        canvas.mouseDown(with: event)
        await settle(host)
        let editor = try #require(canvas.textEditor, "Double-clicking the real canvas must open its text editor")
        editor.string = "Canvas 5678"
        canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        editor.keyDown(with: fixture.key(36))
        await settle(host)
        let project = try #require(fixture.model.project)
        let rowID: String
        if caption {
            let value = try #require(project.captions.first)
            #expect(value.text == "Canvas 5678")
            rowID = "screenRecording.caption." + value.id.uuidString
        } else {
            let value = try #require(project.edits.annotations?.first)
            #expect(value.text == "Canvas 5678")
            rowID = "screenRecording.annotation." + value.id.uuidString
        }
        for scroll in descendants(NSScrollView.self, in: host) {
            if let document = scroll.documentView, document.bounds.height > scroll.contentView.bounds.height {
                scroll.contentView.scroll(to: CGPoint(x: 0, y: document.bounds.maxY - scroll.contentView.bounds.height))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        await settle(host)
        let editableValues = descendants(NSTextField.self, in: host).filter(\.isEditable).map(\.stringValue)
            + descendants(NSTextView.self, in: host).filter(\.isEditable).map(\.string)
        #expect(editableValues.contains("Canvas 5678"), "The selected inspector must expose the actual editable text control")
        #expect(accessibilityIdentifiers(in: host).contains(rowID),
                "Selecting a canvas object must open the matching inspector section and row")
        #expect(fixture.model.canUndo)

        func typeWithoutSubmitting(_ text: String) throws {
            canvas.mouseDown(with: event)
            let editor = try #require(canvas.textEditor)
            editor.string = text
            canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        }
        func currentText(_ project: ScreenRecordingProject?) -> String? {
            caption ? project?.captions.first?.text : project?.edits.annotations?.first?.text
        }

        try typeWithoutSubmitting("Saved without Enter")
        try fixture.model.save()
        #expect(currentText(try fixture.model.projectStore.load(from: fixture.directory)) == "Saved without Enter")
        #expect(canvas.textEditor == nil)
        fixture.model.undo()
        #expect(currentText(fixture.model.project) == "Canvas 5678", "Saving must commit exactly one text revision")
        await settle(host)

        try typeWithoutSubmitting("Exported without Enter")
        fixture.model.export()
        #expect(exportRequests == 1 && !fixture.model.isChoosingFile)
        #expect(currentText(fixture.model.project) == "Exported without Enter" && canvas.textEditor == nil,
                "Text must commit before export captures the project or shows its destination panel")
        fixture.model.undo()
        #expect(currentText(fixture.model.project) == "Canvas 5678")
        await settle(host)

        try typeWithoutSubmitting("Undo without Enter")
        fixture.model.undo()
        #expect(currentText(fixture.model.project) == "Canvas 5678" && canvas.textEditor == nil)
        await settle(host)

        try typeWithoutSubmitting("Seeked without Enter")
        fixture.model.seekTimeline(to: 0.5)
        #expect(currentText(fixture.model.project) == "Seeked without Enter" && canvas.textEditor == nil)
        #expect(fixture.model.currentTime == 0.5)
        fixture.model.undo()
        #expect(currentText(fixture.model.project) == "Canvas 5678")
        await settle(host)

        fixture.model.aiInstruction = "Synthetic edit"
        fixture.model.requestAIEdit()
        await fixture.model.operationTask?.value
        await settle(host)
        #expect(fixture.model.pendingAIProject != nil)
        try typeWithoutSubmitting("Newer canvas text")
        fixture.model.applyAIEdit()
        #expect(currentText(fixture.model.project) == "Newer canvas text" && fixture.model.pendingAIProject == nil,
                "Committing current text must invalidate an AI proposal based on older project data")
        fixture.model.undo()
        #expect(currentText(fixture.model.project) == "Canvas 5678")
        await settle(host)

        try typeWithoutSubmitting("Played without Enter")
        fixture.model.playSource()
        #expect(currentText(fixture.model.project) == "Played without Enter" && canvas.textEditor == nil)
        await settle(host)
        #expect(descendants(RecordingCanvasEditorView.self, in: host).isEmpty,
                "Playback must remove the editor surface so it cannot consume video interactions")
        #expect(!descendants(AVPlayerView.self, in: host).isEmpty)
        #expect(!window.isVisible && !fixture.window.isVisible)
    }

    @Test
    func closingCommitsTextAndTheModelDoesNotRetainItsRemovedCanvas() async throws {
        let fixture = try Fixture(kind: .text)
        defer { fixture.close() }
        await fixture.ready()
        let defaultsName = "zisla-canvas-release-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        weak var removedCanvas: RecordingCanvasEditorView?
        do {
            var host: NSHostingView<ScreenRecordingStudioView>? = NSHostingView(rootView: ScreenRecordingStudioView(
                model: fixture.model, languageStore: AppLanguageStore(defaults: defaults), prepareCapture: {}))
            host?.sizingOptions = []
            host?.frame = CGRect(x: 0, y: 0, width: 1_180, height: 760)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1_180, height: 760),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            await settle(try #require(host))
            do {
                let content = try #require(host)
                let canvas = try #require(descendants(RecordingCanvasEditorView.self, in: content).first)
                removedCanvas = canvas
                let point = fixture.selectionPoint(in: canvas)
                let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: canvas.convert(point, to: nil),
                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 2, pressure: 1))
                canvas.mouseDown(with: event)
                let editor = try #require(canvas.textEditor)
                editor.string = "Closed without Enter"
                canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
                #expect(fixture.model.prepareToClose())
                #expect(try fixture.model.projectStore.load(from: fixture.directory).edits.annotations?.first?.text == "Closed without Enter")
            }
            window.contentView = nil
            host = nil
            window.close()
        }
        for _ in 0..<4 { await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } } }
        #expect(removedCanvas == nil, "The model callback must hold its canvas weakly")
        try fixture.model.save()
        fixture.model.seek(to: 0.25)
        #expect(fixture.model.project?.edits.annotations?.first?.text == "Closed without Enter")
        fixture.model.undo()
        #expect(!fixture.model.canUndo, "Closing must commit the pending text once")
        fixture.model.shutdown()
        #expect(fixture.model.commitPendingCanvasText == nil)
    }

    @Test(arguments: [false, true])
    func inlineTextUndoAndRedoChangeOnlyTheDraftUntilOneProjectCommit(_ caption: Bool) async throws {
        let fixture = try Fixture(kind: .text, caption: caption)
        defer { fixture.close() }
        await fixture.ready()
        let original = try #require(fixture.model.project)
        let originalText = try #require(caption ? original.captions.first?.text : original.edits.annotations?.first?.text)
        fixture.view.mouseDown(with: fixture.textMouse())
        let editor = try #require(fixture.view.textEditor)
        editor.insertText("Edited draft", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        #expect(fixture.view.draft?.text == "Edited draft")
        #expect(fixture.model.project == original && !fixture.model.canUndo)

        #expect(TextEditingCommands.handle(fixture.key(6, characters: "z", modifiers: .command)) == nil)
        #expect(editor.string == originalText && fixture.view.draft?.text == originalText)
        #expect(fixture.model.project == original && !fixture.model.canUndo)
        #expect(TextEditingCommands.handle(fixture.key(6, characters: "Z", modifiers: [.command, .shift])) == nil)
        #expect(editor.string == "Edited draft" && fixture.view.draft?.text == "Edited draft")
        #expect(fixture.model.project == original && !fixture.model.canUndo)

        editor.keyDown(with: fixture.key(36))
        let edited = try #require(fixture.model.project)
        #expect((caption ? edited.captions.first?.text : edited.edits.annotations?.first?.text) == "Edited draft")
        #expect(fixture.view.textEditor == nil && fixture.model.canUndo)
        #expect(editor.undoManager?.canUndo == false && editor.undoManager?.canRedo == false)
        fixture.model.undo()
        #expect(fixture.model.project == original && !fixture.model.canUndo,
                "Typing, undo and redo must commit exactly one project revision")
        fixture.model.redo()
        #expect(fixture.model.project == edited)
    }

    @Test(arguments: [false, true])
    func finishingOrCancellingInlineTextClearsOnlyItsOwnHistory(_ commit: Bool) async throws {
        let fixture = try Fixture(kind: .text)
        defer { fixture.close() }
        await fixture.ready()
        let original = try #require(fixture.model.project)
        let other = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        other.allowsUndo = true
        other.string = "Other input"
        fixture.view.addSubview(other)
        #expect(fixture.window.makeFirstResponder(other))
        other.insertText("Other draft", replacementRange: NSRange(location: 0, length: 11))
        other.breakUndoCoalescing()
        let otherHistory = try #require(other.undoManager)
        #expect(otherHistory.canUndo)

        fixture.view.mouseDown(with: fixture.textMouse())
        let editor = try #require(fixture.view.textEditor)
        editor.insertText("Canvas draft", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        #expect(editor.undoManager?.canUndo == true)
        if commit { editor.keyDown(with: fixture.key(36)) }
        else { fixture.view.cancelEditing() }

        #expect(editor.undoManager?.canUndo == false && editor.undoManager?.canRedo == false)
        #expect(otherHistory.canUndo, "Ending an inline editor must not clear another input's undo stack")
        #expect(fixture.window.makeFirstResponder(other))
        #expect(TextEditingCommands.handle(fixture.key(6, characters: "z", modifiers: .command)) == nil)
        #expect(other.string == "Other input")
        if commit {
            #expect(fixture.model.project?.edits.annotations?.first?.text == "Canvas draft")
            fixture.model.undo()
        }
        #expect(fixture.model.project == original && !fixture.model.canUndo)
    }

    @Test
    func flushingTextCannotReportSuccessForASplitRejectedByTheSegmentLimit() async throws {
        let fixture = try Fixture(kind: .text)
        defer { fixture.close() }
        fixture.model.update { project in project.edits.segments = (0..<2_000).map { _ in .init(start: 0, end: 2) } }
        await fixture.ready()
        let original = try #require(fixture.model.project)
        fixture.model.commitPendingCanvasText = { [weak view = fixture.view] in view?.finishTextEditing(commit: true) }
        fixture.view.mouseDown(with: fixture.textMouse())
        let editor = try #require(fixture.view.textEditor)
        editor.string = "Keep this text"
        fixture.view.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))

        #expect(fixture.model.splitTimeline(at: 0.5) == nil,
                "Only a changed segment list can indicate a successful split")
        #expect(fixture.model.project?.edits.segments == original.edits.segments)
        #expect(fixture.model.project?.edits.annotations?.first?.text == "Keep this text")
        fixture.model.undo()
        #expect(fixture.model.project == original, "The accepted text edit must remain exactly one undo step")
    }

    @Test
    func liveDragErasesTheOldObjectAndCommitsOneUndoStepWithMatchingStoredAndExportedPixels() async throws {
        let fixture = try Fixture(kind: .rectangle)
        defer { fixture.close() }
        await fixture.ready()
        let original = try #require(fixture.model.project)
        fixture.view.mouseDown(with: fixture.mouse(.leftMouseDown, x: 0.4, y: 0.3))
        for step in 1...40 {
            fixture.view.mouseDragged(with: fixture.mouse(.leftMouseDragged, x: 0.4 + Double(step) / 200, y: 0.3))
        }
        #expect(fixture.model.project == original && !fixture.model.canUndo,
                "Live rendering must not create project revisions before mouse-up")
        let draft = try #require(fixture.view.draft)
        #expect(draft != .annotation(try #require(original.edits.annotations?.first)))
        var expected = original
        draft.write(to: &expected, replacing: .annotation(try #require(original.edits.annotations?.first)))
        let liveImage = try #require(fixture.view.renderedImage)
        let exportFrame = try fixture.render(expected)
        #expect(try bytes(liveImage) == bytes(exportFrame), "The moving object must replace its old pixels and match the shared export renderer")

        fixture.view.mouseUp(with: fixture.mouse(.leftMouseUp, x: 0.4 + 40.0 / 200, y: 0.3))
        #expect(fixture.model.project == expected && fixture.model.canUndo)
        #expect(fixture.commits == 1)
        try fixture.model.save()
        #expect(try fixture.model.projectStore.load(from: fixture.directory) == expected)
        fixture.model.undo()
        #expect(fixture.model.project == original && !fixture.model.canUndo)
        fixture.model.redo()
        #expect(fixture.model.project == expected && !fixture.model.canRedo)
    }

    @Test
    func cancelledDragAndNoMotionPreserveTheExistingObjectAndUndoHistory() async throws {
        let fixture = try Fixture(kind: .rectangle)
        defer { fixture.close() }
        await fixture.ready()
        let original = fixture.model.project
        let initialPixels = try bytes(#require(fixture.view.renderedImage))
        fixture.view.mouseDown(with: fixture.mouse(.leftMouseDown, x: 0.4, y: 0.3))
        fixture.view.mouseDragged(with: fixture.mouse(.leftMouseDragged, x: 0.6, y: 0.5))
        fixture.view.keyDown(with: fixture.key(53))
        fixture.view.mouseUp(with: fixture.mouse(.leftMouseUp, x: 0.6, y: 0.5))
        #expect(fixture.model.project == original && !fixture.model.canUndo && fixture.commits == 0)
        #expect(try bytes(#require(fixture.view.renderedImage)) == initialPixels)
        fixture.view.mouseDown(with: fixture.mouse(.leftMouseDown, x: 0.4, y: 0.3))
        fixture.view.mouseUp(with: fixture.mouse(.leftMouseUp, x: 0.4, y: 0.3))
        #expect(fixture.model.project == original && !fixture.model.canUndo && fixture.commits == 0)
    }

    @Test(arguments: [false, true])
    func directTextEditingCommitsOnceAndEscapeRestoresTheOldTextAndPixels(_ caption: Bool) async throws {
        let fixture = try Fixture(kind: .text, caption: caption)
        defer { fixture.close() }
        await fixture.ready()
        let original = try #require(fixture.model.project)
        let initialPixels = try bytes(#require(fixture.view.renderedImage))
        fixture.view.mouseDown(with: fixture.textMouse())
        let editor = try #require(fixture.view.textEditor)
        editor.string = "新内容1234\nSecond line"
        fixture.view.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        #expect(fixture.model.project == original && !fixture.model.canUndo)
        #expect(try bytes(#require(fixture.view.renderedImage)) == bytes(fixture.base),
                "The raster must hide the old text while the native text editor draws the draft")
        editor.keyDown(with: fixture.key(53))
        #expect(fixture.view.textEditor == nil && fixture.view.draft == nil)
        #expect(fixture.model.project == original && fixture.commits == 0)
        #expect(try bytes(#require(fixture.view.renderedImage)) == initialPixels)

        fixture.view.mouseDown(with: fixture.textMouse())
        let secondEditor = try #require(fixture.view.textEditor)
        secondEditor.string = "新内容1234"
        fixture.view.textDidChange(Notification(name: NSText.didChangeNotification, object: secondEditor))
        secondEditor.keyDown(with: fixture.key(36))
        #expect(fixture.view.textEditor == nil && fixture.commits == 1)
        if caption { #expect(fixture.model.project?.captions.first?.text == "新内容1234") }
        else { #expect(fixture.model.project?.edits.annotations?.first?.text == "新内容1234") }
        #expect(fixture.model.canUndo)
        let expected = try #require(fixture.model.project)
        #expect(try bytes(#require(fixture.view.renderedImage)) == bytes(fixture.render(expected)))
        fixture.model.undo()
        #expect(fixture.model.project == original && !fixture.model.canUndo)
    }

    @Test
    func textDraftBoundsItsInputAndFocusLossCommitsWithoutDeletingAnEmptyLabel() async throws {
        let fixture = try Fixture(kind: .text)
        defer { fixture.close() }
        await fixture.ready()
        fixture.view.mouseDown(with: fixture.textMouse())
        let editor = try #require(fixture.view.textEditor)
        editor.string = String(repeating: "字", count: 4_001)
        fixture.view.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        #expect(editor.string.count == 4_000 && fixture.view.draft?.text?.count == 4_000)
        editor.string = ""
        fixture.view.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        fixture.view.textDidEndEditing(Notification(name: NSText.didEndEditingNotification, object: editor))
        #expect(fixture.model.project?.edits.annotations?.count == 1)
        #expect(fixture.model.project?.edits.annotations?.first?.text == "")
        #expect(fixture.commits == 1)
    }

    @Test
    func arrowEndpointsAndTextResizeUseTheLivePreviewAndCanBeUndone() async throws {
        for kind in [RecordingAnnotationKind.arrow, .text] {
            let fixture = try Fixture(kind: kind)
            defer { fixture.close() }
            await fixture.ready()
            let original = try #require(fixture.model.project)
            let element = RecordingCanvasElement.annotation(try #require(original.edits.annotations?.first))
            let corner = try #require(RecordingCanvasGeometry.handles(for: element, canvas: fixture.view.canvasSize).last).1
            let x = corner.x / fixture.view.canvasSize.width, y = corner.y / fixture.view.canvasSize.height
            fixture.view.mouseDown(with: fixture.mouse(.leftMouseDown, x: x, y: y))
            fixture.view.mouseDragged(with: fixture.mouse(.leftMouseDragged, x: x + 0.15, y: y + 0.1))
            fixture.view.mouseUp(with: fixture.mouse(.leftMouseUp, x: x + 0.15, y: y + 0.1))
            let edited = try #require(fixture.model.project)
            #expect(edited != original && fixture.commits == 1)
            #expect(try bytes(#require(fixture.view.renderedImage)) == bytes(fixture.render(edited)))
            if kind == .text { #expect(edited.edits.annotations!.first!.fontSize > original.edits.annotations!.first!.fontSize) }
            fixture.model.undo()
            #expect(fixture.model.project == original && !fixture.model.canUndo)
        }
    }

    @Test
    func playbackAndLosingTheEditedObjectCancelDraftsAndPassMouseEventsThrough() async throws {
        let fixture = try Fixture(kind: .text)
        defer { fixture.close() }
        await fixture.ready()
        fixture.view.mouseDown(with: fixture.textMouse())
        let editor = try #require(fixture.view.textEditor)
        editor.string = "Uncommitted"
        fixture.view.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        fixture.view.configure(project: fixture.model.project, sourceTime: 0, baseImage: fixture.model.canvasPreview,
            selection: fixture.selection, editable: false)
        #expect(fixture.view.textEditor == nil && fixture.view.draft == nil && fixture.commits == 0)
        #expect(fixture.view.hitTest(CGPoint(x: 300, y: 200)) == nil,
                "The editor must not capture playback clicks when editing is disabled")
        await fixture.ready()
        fixture.view.mouseDown(with: fixture.textMouse())
        #expect(fixture.view.textEditor != nil)
        var removed = try #require(fixture.model.project)
        removed.edits.annotations = []
        fixture.view.configure(project: removed, sourceTime: 0, baseImage: fixture.model.canvasPreview,
            selection: fixture.selection, editable: true)
        #expect(fixture.view.textEditor == nil && fixture.view.draft == nil && fixture.commits == 0)
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(data: pointer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(type, in: $0) }
    }

    private func accessibilityIdentifiers(in host: NSView) -> Set<String> {
        var identifiers = Set<String>()
        func visit(_ object: NSObject) {
            if let element = object as? any NSAccessibilityElementProtocol,
               let identifier = element.accessibilityIdentifier?() { identifiers.insert(identifier) }
            if object.responds(to: NSSelectorFromString("accessibilityChildren")) {
                for child in object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
            }
        }
        for child in host.accessibilityChildren() as? [NSObject] ?? [] { visit(child) }
        return identifiers
    }

    @MainActor private final class Fixture {
        let model: ScreenRecordingStudioModel
        let view = RecordingCanvasEditorView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let window: NSWindow
        let root: URL
        let directory: URL
        let base: CGImage
        var selection: RecordingCanvasSelection?
        var commits = 0

        init(kind: RecordingAnnotationKind, caption: Bool = false, multitrack: Bool = false,
             presentExportPanel: @escaping (NSSavePanel, @escaping (URL?) -> Void) -> Void = { _, completion in completion(nil) },
             aiCompletion: ((ScreenRecordingProject, String, AIModelConfigurationReference?) async throws -> String)? = nil) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-canvas-test-\(UUID())")
            let store = ScreenRecordingProjectStore(root: root)
            directory = try store.createDirectory()
            try Data([1]).write(to: directory.appendingPathComponent("screen.mp4"))
            var project = ScreenRecordingProject(name: "Canvas", videoFile: "screen.mp4", duration: 2, width: 400, height: 300)
            project.edits.background = .none
            project.edits.padding = 0
            project.edits.cornerRadius = 0
            project.edits.shadow = 0
            project.edits.showCursor = false
            project.edits.clickEffects = false
            if caption {
                let value = RecordingCaption(start: 0, end: 2, text: "Original 1234", layout: .init(x: 0.2, y: 0.2, width: 0.5, height: 0.2), fontSize: 0.06)
                project.captions = [value]
                selection = .caption(value.id)
            } else {
                let value = RecordingAnnotation(kind: kind, start: 0, end: 2, text: "Original 1234")
                project.edits.annotations = [value]
                selection = .annotation(value.id)
            }
            if multitrack {
                project.version = ScreenRecordingProject.currentVersion
                project.timeline = RecordingMultitrackTimeline.migrating(project)
                project.timeline?.clips.removeAll { $0.content.assetID != nil }
                let imageURL = directory.appendingPathComponent("background.png")
                let image = try #require(CIContext().createCGImage(CIImage(color: .black),
                    from: CGRect(x: 0, y: 0, width: 400, height: 300)))
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: imageURL)
                let asset = RecordingMediaAsset(name: "Background", file: "background.png", kind: .image,
                    duration: 2, width: 400, height: 300)
                project.timeline?.assets = [asset]
                let mediaTrack = try #require(project.timeline?.tracks.first)
                project.timeline?.clips.insert(.init(trackID: mediaTrack.id, content: .image(asset.id),
                    start: 0, sourceEnd: 2), at: 0)
            }
            base = try #require(CIContext().createCGImage(CIImage(color: .black), from: CGRect(x: 0, y: 0, width: 400, height: 300)))
            let base = self.base
            model = ScreenRecordingStudioModel(projectStore: store, renderPreview: { _, _, _ in base },
                                               presentExportPanel: presentExportPanel, aiCompletion: aiCompletion)
            window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            model.install(project, directory: directory)
            view.onSelect = { [weak self] in self?.selection = $0 }
            view.onCommit = { [weak self] original, replacement in
                guard let self else { return }
                commits += 1
                model.update { replacement.write(to: &$0, replacing: original) }
            }
            view.onRenderingFailure = { error in Issue.record("Unexpected canvas render failure: \(error)") }
        }

        func ready() async {
            await model.previewTask?.value
            view.configure(project: model.project, sourceTime: model.overlayTime, baseImage: model.canvasPreview,
                           selection: selection, editable: true, multitrackScene: model.multitrackPreviewScene)
        }

        func close() { view.cancelEditing(); window.close(); model.shutdown(); try? FileManager.default.removeItem(at: root) }

        func mouse(_ type: NSEvent.EventType, x: Double, y: Double, clicks: Int = 1) -> NSEvent {
            let point = view.convert(CGPoint(x: x * view.bounds.width, y: y * view.bounds.height), to: nil)
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }

        func selectionPoint(in canvas: RecordingCanvasEditorView) -> CGPoint {
            let element = RecordingCanvasElement.visible(in: model.project!, at: model.currentTime)
                .first { $0.selection == selection }!
            let box = element.bounds(canvas: canvas.canvasSize)
            return CGPoint(x: canvas.canvasRect.minX + box.midX * canvas.canvasRect.width / canvas.canvasSize.width,
                           y: canvas.canvasRect.minY + box.midY * canvas.canvasRect.height / canvas.canvasSize.height)
        }

        func textMouse() -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(selectionPoint(in: view), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 2, pressure: 1)!
        }

        func key(_ code: UInt16, characters: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code)!
        }

        func render(_ project: ScreenRecordingProject) throws -> CGImage {
            try RecordingExportRenderer(project: project, size: CGSize(width: base.width, height: base.height))
                .image(screen: CIImage(cgImage: base), camera: nil, sourceTime: 0)
        }
    }
}
