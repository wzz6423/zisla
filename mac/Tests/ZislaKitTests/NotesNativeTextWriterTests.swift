import Foundation
import ApplicationServices
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
@Suite(.serialized)
struct NotesNativeTextWriterTests {
    @Test
    func replacesOnlyTextBeforeAndAfterHandwritingUsingUTF16Ranges() throws {
        let original = "旧👩‍💻\n\u{FFFC}\n中间文字\u{FFFC}\n旧结尾"
        let edit = NotesNativeTextEdit(originalPlainText: original, imageSources: ["drawing"], prefix: "新标题\n", suffix: "\n新结尾")
        let replacements = try #require(edit.replacements(in: original))
        var result = original
        for replacement in replacements {
            #expect(!(result as NSString).substring(with: replacement.range).contains("\u{FFFC}"))
            result = (result as NSString).replacingCharacters(in: replacement.range, with: replacement.text)
        }
        #expect(result == "新标题\n\u{FFFC}\n中间文字\u{FFFC}\n新结尾")
        #expect(result == edit.updatedPlainText)
    }

    @Test
    func handlesEmptyEdgesAndTheNativeTextViewsFinalNewline() throws {
        let edit = NotesNativeTextEdit(originalPlainText: "\u{FFFC}", imageSources: ["drawing"], prefix: "", suffix: "")
        #expect(edit.replacements(in: "\u{FFFC}") == [])
        #expect(edit.replacements(in: "\u{FFFC}\n") == [])
        let append = NotesNativeTextEdit(originalPlainText: "\u{FFFC}", imageSources: ["drawing"], prefix: "", suffix: "\n备注")
        let replacements = try #require(append.replacements(in: "\u{FFFC}\n"))
        #expect(replacements == [.init(range: NSRange(location: 1, length: 1), text: "\n备注\n")])
    }

    @Test
    func refusesStaleTextMissingObjectsAndObjectCharactersInNewText() {
        let edit = NotesNativeTextEdit(originalPlainText: "\u{FFFC}", imageSources: ["drawing"], prefix: "前面", suffix: "后面")
        #expect(edit.replacements(in: "另一个笔记\u{FFFC}") == nil)
        #expect(edit.replacements(in: "") == nil)
        #expect(NotesNativeTextEdit(originalPlainText: "plain", imageSources: [], prefix: "", suffix: "").replacements(in: "plain") == nil)
        for position in [true, false] {
            let invalid = NotesNativeTextEdit(originalPlainText: "\u{FFFC}", imageSources: ["drawing"],
                prefix: position ? "\u{FFFC}" : "", suffix: position ? "" : "\u{FFFC}")
            #expect(invalid.replacements(in: "\u{FFFC}") == nil)
        }
    }

    @Test
    func savesEdgesWithoutReplacingTheHandwritingObject() async throws {
        let fixture = NativeNoteFixture(text: "原文\n\u{FFFC}\n旧结尾")
        let edit = fixture.edit(prefix: "标题\n", suffix: "\n结尾")
        let result = await NotesNativeTextWriter(dependencies: fixture.dependencies).write(noteID: "note", edit: edit)
        if case .failure(let error) = result { Issue.record("Unexpected save failure: \(error)") }
        #expect(fixture.text == "标题\n\u{FFFC}\n结尾")
        #expect(fixture.replacedText.allSatisfy { !$0.contains("\u{FFFC}") })
        #expect(fixture.bodyHTML == fixture.originalBodyHTML)
    }

    @Test
    func unchangedEdgesDoNotOpenNotesOrRequirePermission() async {
        let fixture = NativeNoteFixture(text: "\u{FFFC}")
        fixture.trusted = false
        if case .failure(let error) = await NotesNativeTextWriter(dependencies: fixture.dependencies).write(noteID: "note", edit: fixture.edit()) {
            Issue.record("Unchanged text must succeed: \(error)")
        }
        #expect(fixture.showCount == 0)
        #expect(fixture.replacedText.isEmpty)
    }

    @Test
    func deniesPermissionWithoutOpeningNotesOrChangingContent() async {
        let fixture = NativeNoteFixture(text: "\u{FFFC}")
        fixture.trusted = false
        let result = await NotesNativeTextWriter(dependencies: fixture.dependencies).write(noteID: "note", edit: fixture.edit(prefix: "标题"))
        if case .failure(let error) = result {
            #expect(error == .failed(AppLocalization.text("保存手写备忘录需要辅助功能权限")))
        } else { Issue.record("Permission denial must be reported") }
        #expect(fixture.showCount == 0)
        #expect(fixture.replacedText.isEmpty)
        #expect(fixture.text == "\u{FFFC}")
    }

    @Test
    func refusesChangedImagesAndLockedNotesBeforeOpeningThem() async {
        for fault in ["image", "locked", "not-native", "read", "text"] {
            let fixture = NativeNoteFixture(text: "\u{FFFC}")
            let edit = fixture.edit(prefix: "标题")
            switch fault {
            case "image": fixture.bodyHTML = "<div><img src='different'></div>"
            case "locked": fixture.locked = true
            case "not-native": fixture.native = false
            case "text": fixture.text = "外部修改\u{FFFC}"
            default: fixture.readFailure = .failed("injected read failure")
            }
            if case .success = await NotesNativeTextWriter(dependencies: fixture.dependencies).write(noteID: "note", edit: edit) {
                Issue.record("The \(fault) fault must reject the save")
            }
            #expect(fixture.showCount == 0)
            #expect(fixture.replacedText.isEmpty)
        }
    }

    @Test
    func refusesInvalidNativeEditsWithoutOpeningNotes() async {
        let fixture = NativeNoteFixture(text: "\u{FFFC}")
        for edit in [NotesNativeTextEdit(originalPlainText: "plain", imageSources: ["drawing"], prefix: "", suffix: ""),
                     NotesNativeTextEdit(originalPlainText: "\u{FFFC}", imageSources: [], prefix: "标题", suffix: ""),
                     NotesNativeTextEdit(originalPlainText: "\u{FFFC}", imageSources: ["drawing"], prefix: "\u{FFFC}", suffix: "")] {
            if case .success = await NotesNativeTextWriter(dependencies: fixture.dependencies).write(noteID: "note", edit: edit) {
                Issue.record("Invalid native text edits must not be dispatched")
            }
        }
        #expect(fixture.showCount == 0 && fixture.replacedText.isEmpty)
        #expect(fixture.text == "\u{FFFC}")
    }

    @Test
    func refusesAnUnselectedNoteUnavailableEditorAndFailedShow() async {
        for fault in ["selected", "editor", "show"] {
            let fixture = NativeNoteFixture(text: "\u{FFFC}")
            fixture.selected = fault == "selected" ? "other" : "note"
            fixture.editorAvailable = fault != "editor"
            fixture.showFailure = fault == "show" ? .failed("injected show failure") : nil
            let result = await NotesNativeTextWriter(dependencies: fixture.dependencies).write(noteID: "note", edit: fixture.edit(prefix: "标题"))
            if case .success = result { Issue.record("The \(fault) fault must reject the save") }
            #expect(fixture.replacedText.isEmpty)
        }
    }

    @Test
    func restoresConfirmedSuffixIfThePrefixCannotBeWritten() async {
        let fixture = NativeNoteFixture(text: "旧前面\u{FFFC}旧后面")
        fixture.failReplacement = 2
        let result = await NotesNativeTextWriter(dependencies: fixture.dependencies).write(noteID: "note", edit: fixture.edit(prefix: "新前面", suffix: "新后面"))
        if case .success = result { Issue.record("An injected write failure must be reported") }
        #expect(fixture.text == "旧前面\u{FFFC}旧后面")
        #expect(fixture.replacedText.allSatisfy { !$0.contains("\u{FFFC}") })
    }

    @Test
    func reportsAChangedPreviewOrReadFailureAfterNativeInsertion() async {
        for fault in ["image", "read", "text", "native"] {
            let fixture = NativeNoteFixture(text: "\u{FFFC}")
            fixture.afterWriteFault = fault
            let result = await NotesNativeTextWriter(dependencies: fixture.dependencies).write(noteID: "note", edit: fixture.edit(prefix: "标题"))
            if case .success = result { Issue.record("A failed preservation check must never report success") }
            #expect(fixture.text.filter { $0 == "\u{FFFC}" }.count == 1)
        }
    }

    @Test
    func aRetryRecognizesTextAlreadySavedAfterAReadbackFailure() async {
        let fixture = NativeNoteFixture(text: "\u{FFFC}")
        let edit = fixture.edit(prefix: "标题\n", suffix: "\n结尾")
        let writer = NotesNativeTextWriter(dependencies: fixture.dependencies)
        fixture.afterWriteFault = "read"
        if case .success = await writer.write(noteID: "note", edit: edit) {
            Issue.record("The readback fault must be reported")
        }
        fixture.afterWriteFault = nil
        if case .failure(let error) = await writer.write(noteID: "note", edit: edit) {
            Issue.record("An already-persisted edit must be recoverable: \(error)")
        }
        #expect(fixture.text == edit.updatedPlainText)
        #expect(fixture.showCount == 1, "Retrying a persisted edit must not insert its text again")
    }

    @Test
    func stopsBeforeTheNextReplacementWhenSelectionOrTextChanges() async {
        for fault in ["selected", "text"] {
            let fixture = NativeNoteFixture(text: "旧前面\u{FFFC}旧后面")
            let edit = fixture.edit(prefix: "新前面", suffix: "新后面")
            fixture.onReplacement = {
                if fault == "selected" { fixture.selected = "other" }
                else { fixture.text = "用户输入\u{FFFC}新后面" }
            }
            if case .success = await NotesNativeTextWriter(dependencies: fixture.dependencies).write(noteID: "note", edit: edit) {
                Issue.record("A \(fault) change must stop further writes")
            }
            #expect(fixture.replacementCount == 1)
            #expect(fixture.text == (fault == "selected" ? "旧前面\u{FFFC}新后面" : "用户输入\u{FFFC}新后面"))
        }
    }

    @Test
    func doesNotRollBackIntoAnotherSelectedNote() async {
        let fixture = NativeNoteFixture(text: "旧前面\u{FFFC}旧后面")
        fixture.failReplacement = 2
        fixture.onReplacement = {
            if fixture.replacementCount == 2 { fixture.selected = "other" }
        }
        if case .success = await NotesNativeTextWriter(dependencies: fixture.dependencies).write(
            noteID: "note", edit: fixture.edit(prefix: "新前面", suffix: "新后面")) {
            Issue.record("Selection changes during a failed write must be reported")
        }
        #expect(fixture.text == "旧前面\u{FFFC}新后面")
        #expect(fixture.replacementCount == 2, "Rollback must not target a note the user has switched away from")
    }

    @Test
    func serializesDifferentNotesUntilTheFirstNativeWriteFinishes() async throws {
        let first = NativeNoteFixture(text: "\u{FFFC}")
        let second = NativeNoteFixture(text: "\u{FFFC}")
        let gate = NativeWriteGate()
        let started = NativeWriteGate()
        var selected = ""
        var completed = 0
        let writer = NotesNativeTextWriter(dependencies: .init(isTrusted: { true }, showNote: { id in
            if id == "first" { await gate.pause() }
            else { #expect(completed == 1, "The next note cannot open before the first preservation check finishes") }
            selected = id
            return .success(())
        }, readNote: { id in
            let fixture = id == "first" ? first : second
            if id == "first" { #expect(selected != "second", "A later write must wait for the earlier preservation check") }
            let result = await fixture.dependencies.readNote(id)
            if !fixture.replacedText.isEmpty { completed += 1 }
            return result
        }, selectedNoteID: { selected }, editor: { _ in
            (selected == "first" ? first : second).dependencies.editor("")
        }))
        let task = Task { await writer.write(noteID: "first", edit: first.edit(prefix: "前面")) }
        await gate.waitUntilPaused()
        let next = Task {
            started.signal()
            return await writer.write(noteID: "second", edit: second.edit(suffix: "后面"))
        }
        await started.waitUntilSignaled()
        gate.resume()
        for result in [await task.value, await next.value] {
            if case .failure(let error) = result { Issue.record("Serialized saves must succeed: \(error)") }
        }
        #expect(first.text == "前面\u{FFFC}")
        #expect(second.text == "\u{FFFC}后面")
        #expect(completed == 2)
    }

    @Test
    func detectsOnlyUnexposedNativeObjectsFromTheReadScript() async throws {
        for (text, count, native) in [("plain", "0", false), ("\u{FFFC}", "0", true),
                                     ("\u{FFFC}", "1", false), ("\u{FFFC}\u{FFFC}", "1", true)] {
            let result = await NotesAppBridge.readNote(id: "fixture") { source in
                Self.compileNotesScript(source)
                return .success([text, "<img src='drawing'>", "false", count])
            }
            let content = try result.get()
            #expect(content.requiresNativeTextEditing == native)
            #expect(content.plainText == text)
        }
        let locked = try await NotesAppBridge.readNote(id: "locked") { _ in
            .success(["hidden", "<img src='hidden'>", "true", "0"])
        }.get()
        #expect(locked.isPasswordProtected)
        #expect(locked.plainText.isEmpty && locked.bodyHTML.isEmpty && !locked.requiresNativeTextEditing)
        for values in [[], ["", "", "false"], ["", "", "false", "x"], ["", "", "false", "-1"], ["", "", "invalid", "0"]] {
            if case .success = await NotesAppBridge.readNote(id: "invalid", runScript: { _ in .success(values) }) {
                Issue.record("Malformed Notes replies must be rejected")
            }
        }
        #expect(await NotesAppBridge.readNote(id: "denied", runScript: { _ in .failure(.failed("denied")) }) == .failure(.failed("denied")))
    }

    @Test
    func selectionScriptRejectsMissingAndAmbiguousReplies() async throws {
        let id = await NotesAppBridge.selectedNoteID { source in
            Self.compileNotesScript(source)
            return .success(["fixture"])
        }
        #expect(id == "fixture")
        for reply in [[], [""], ["first", "second"]] {
            #expect(await NotesAppBridge.selectedNoteID(runScript: { _ in .success(reply) }) == nil)
        }
        #expect(await NotesAppBridge.selectedNoteID(runScript: { _ in .failure(.failed("denied")) }) == nil)
    }

    private static func compileNotesScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { Issue.record("Cannot create the production Notes script"); return }
        var error: NSDictionary?
        let compiled = script.compileAndReturnError(&error)
        #expect(compiled, "Production Notes script must compile: \(String(describing: error))")
    }

    @Test
    func nativeEditorRequiresTheExactSelectedRangeBeforeAssigningText() throws {
        for fault in ["none", "selection-denied", "selection-missing", "selection-invalid", "selection-clamped", "text-denied"] {
            var selected: CFTypeRef?
            var assignedText: String?
            let editor = NotesNativeTextWriter.editor(readAttribute: { name in
                if name == kAXValueAttribute { return NSAttributedString(string: "前面\u{FFFC}后面") }
                if fault == "selection-missing" { return nil }
                if fault == "selection-invalid" { return "invalid" as CFString }
                return selected
            }, setAttribute: { name, value in
                #expect(name != kAXValueAttribute, "The attachment-containing AXValue must never be assigned")
                if name == kAXSelectedTextRangeAttribute {
                    if fault == "selection-denied" { return .cannotComplete }
                    if fault == "selection-clamped" {
                        var range = CFRange(location: 0, length: 3)
                        selected = AXValueCreate(.cfRange, &range)
                    } else { selected = value }
                    return .success
                }
                if fault == "text-denied" { return .cannotComplete }
                assignedText = value as? String
                return .success
            })
            #expect(editor.text() == "前面\u{FFFC}后面")
            #expect(editor.replace(NSRange(location: 0, length: 2), "新前面") == (fault == "none"))
            #expect(assignedText == (fault == "none" ? "新前面" : nil), "A changed or unreadable selection cannot be allowed to touch the drawing")
        }
    }

    @Test
    func editorSearchRejectsAmbiguousAndIncompleteAccessibilityTrees() {
        #expect(NotesNativeTextWriter.uniqueElement(in: [0], matches: { $0 == 2 }, children: { $0 == 0 ? [1, 2] : [] }) == 2)
        #expect(NotesNativeTextWriter.uniqueElement(in: [0], matches: { $0 > 0 }, children: { $0 == 0 ? [1, 2] : [] }) == nil)
        #expect(NotesNativeTextWriter.uniqueElement(in: [Int](), matches: { _ in true }, children: { _ in [] }) == nil)
        #expect(NotesNativeTextWriter.uniqueElement(in: [0], matches: { $0 == 2 }, children: { [$0 + 1] }) == nil,
                "A cyclic or too-large tree must not use a match from a partial scan")
        var visited = 0
        let result = NotesNativeTextWriter.uniqueElement(in: [0], matches: { value in
            visited += 1
            return value == 2
        }, children: { $0 < 2_000 ? [$0 + 1] : [] })
        #expect(result == nil, "The 2,001st element must not be removed before enforcing the scan budget")
        #expect(visited == 2_000)
    }

    @Test
    func boundedTextEditsPreserveAllObjectCharacters() throws {
        var seed: UInt64 = 0xA771
        let alphabet = Array("ab中文👩‍💻\n\t &<>\"'")
        func text() -> String {
            String((0..<24).map { _ in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return alphabet[Int(seed % UInt64(alphabet.count))]
            })
        }
        for _ in 0..<32 {
            let original = text() + "\u{FFFC}" + text() + "\u{FFFC}" + text()
            let edit = NotesNativeTextEdit(originalPlainText: original, imageSources: ["a", "b"], prefix: text(), suffix: text())
            var result = original
            for replacement in try #require(edit.replacements(in: original)) {
                result = (result as NSString).replacingCharacters(in: replacement.range, with: replacement.text)
            }
            #expect(result == edit.updatedPlainText)
            #expect(result.filter { $0 == "\u{FFFC}" }.count == 2)
        }
    }

    @Test
    func everyLanguageTranslatesNativeNoteSaveErrors() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/ZislaKit/NotesNativeTextWriter.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)"\)"#)
        let keys = regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
            (source as NSString).substring(with: $0.range(at: 1))
        }
        #expect(keys.count == 3)
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let url = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in keys {
                let translation = try #require(table[key])
                #expect(!translation.isEmpty)
                #expect(AppLocalization.string(key, language: language) == translation)
            }
        }
    }
}

@MainActor
private final class NativeNoteFixture {
    var text: String
    var bodyHTML = "<div><img src='data:image/png;base64,handwriting'></div>"
    let originalBodyHTML = "<div><img src='data:image/png;base64,handwriting'></div>"
    var trusted = true
    var locked = false
    var native = true
    var selected = "note"
    var editorAvailable = true
    var readFailure: NotesAppError?
    var showFailure: NotesAppError?
    var afterWriteFault: String?
    var failReplacement: Int?
    var showCount = 0
    var replacedText: [String] = []
    var replacementCount = 0
    var onReplacement: (() -> Void)?

    init(text: String) { self.text = text }

    func edit(prefix: String = "", suffix: String = "") -> NotesNativeTextEdit {
        NotesNativeTextEdit(originalPlainText: text, imageSources: NotesNativeTextEdit.imageSources(in: bodyHTML), prefix: prefix, suffix: suffix)
    }

    var dependencies: NotesNativeTextWriter.Dependencies {
        .init(isTrusted: { self.trusted }, showNote: { _ in
            self.showCount += 1
            return self.showFailure.map { .failure($0) } ?? .success(())
        }, readNote: { _ in
            if let error = self.readFailure { return .failure(error) }
            if self.replacementCount > 0, self.afterWriteFault == "read" { return .failure(.failed("injected readback failure")) }
            return .success(NotesAppBridge.NoteContent(plainText: self.afterWriteFault == "text" && self.replacementCount > 0 ? "另一个版本\u{FFFC}" : self.text,
                bodyHTML: self.afterWriteFault == "image" && self.replacementCount > 0 ? "<img src='different'>" : self.bodyHTML,
                isPasswordProtected: self.locked, requiresNativeTextEditing: self.native && !(self.afterWriteFault == "native" && self.replacementCount > 0)))
        }, selectedNoteID: { self.selected }, editor: { _ in
            guard self.editorAvailable else { return nil }
            return .init(text: { self.text }, replace: { range, value in
                self.replacementCount += 1
                if self.replacementCount == self.failReplacement {
                    self.onReplacement?()
                    return false
                }
                self.replacedText.append((self.text as NSString).substring(with: range))
                self.text = (self.text as NSString).replacingCharacters(in: range, with: value)
                self.onReplacement?()
                return true
            })
        })
    }
}

@MainActor
private final class NativeWriteGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var signaled = false
    private var signalObserver: CheckedContinuation<Void, Never>?

    func signal() {
        signaled = true
        signalObserver?.resume()
        signalObserver = nil
    }

    func waitUntilSignaled() async {
        if signaled { return }
        await withCheckedContinuation { signalObserver = $0 }
    }

    func pause() async {
        await withCheckedContinuation {
            continuation = $0
            observer?.resume()
            observer = nil
        }
    }

    func waitUntilPaused() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
