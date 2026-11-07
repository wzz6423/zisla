import AppKit
import ApplicationServices
import ZislaCore

public struct NotesNativeTextEdit: Equatable, Sendable {
    public let originalPlainText: String
    public let imageSources: [String]
    public let prefix: String
    public let suffix: String

    public init(originalPlainText: String, imageSources: [String], prefix: String, suffix: String) {
        self.originalPlainText = originalPlainText
        self.imageSources = imageSources
        self.prefix = prefix
        self.suffix = suffix
    }

    public var updatedPlainText: String {
        guard let range = protectedRange(in: originalPlainText) else { return originalPlainText }
        return prefix + (originalPlainText as NSString).substring(with: range) + suffix
    }

    struct Replacement: Equatable {
        let range: NSRange
        let text: String
    }

    func replacements(in currentText: String) -> [Replacement]? {
        guard !prefix.contains("\u{FFFC}"), !suffix.contains("\u{FFFC}"),
              currentText == originalPlainText || currentText == originalPlainText + "\n",
              let range = protectedRange(in: currentText) else { return nil }
        let current = currentText as NSString
        let trailingNewline = currentText == originalPlainText + "\n" ? "\n" : ""
        let suffixRange = NSRange(location: NSMaxRange(range), length: current.length - NSMaxRange(range))
        let prefixRange = NSRange(location: 0, length: range.location)
        return [Replacement(range: suffixRange, text: suffix + trailingNewline),
                Replacement(range: prefixRange, text: prefix)]
            .filter { current.substring(with: $0.range) != $0.text }
    }

    public static func imageSources(in html: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: #"(?is)<img\b[^>]*\bsrc\s*=\s*["']([^"']*)["']"#)
        return expression.matches(in: html, range: NSRange(html.startIndex..., in: html)).map {
            (html as NSString).substring(with: $0.range(at: 1))
        }
    }

    private func protectedRange(in text: String) -> NSRange? {
        let text = text as NSString
        let first = text.range(of: "\u{FFFC}")
        let last = text.range(of: "\u{FFFC}", options: .backwards)
        guard first.location != NSNotFound else { return nil }
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }
}

@MainActor
final class NotesNativeTextWriter {
    @MainActor
    struct Editor {
        let text: () -> String?
        let replace: (NSRange, String) -> Bool
    }

    @MainActor
    struct Dependencies {
        let isTrusted: () -> Bool
        let showNote: (String) async -> Result<Void, NotesAppError>
        let readNote: (String) async -> Result<NotesAppBridge.NoteContent, NotesAppError>
        let selectedNoteID: () async -> String?
        let editor: (String) -> Editor?

        static var live: Self {
            Self(
                isTrusted: { AccessibilityPermission.promptIfNeeded() },
                showNote: { await NotesAppBridge.showNote(id: $0) },
                readNote: { await NotesAppBridge.readNote(id: $0) },
                selectedNoteID: { await NotesAppBridge.selectedNoteID() },
                editor: { NotesNativeTextWriter.findEditor(expectedText: $0) }
            )
        }
    }

    private let dependencies: Dependencies
    private var pendingWrite: Task<Result<Void, NotesAppError>, Never>?
    private var pendingToken: UUID?

    init(dependencies: Dependencies = .live) { self.dependencies = dependencies }

    func write(noteID: String, edit: NotesNativeTextEdit) async -> Result<Void, NotesAppError> {
        let previous = pendingWrite
        let token = UUID()
        let task = Task { [self] in
            _ = await previous?.value
            return await writeNow(noteID: noteID, edit: edit)
        }
        pendingToken = token
        pendingWrite = task
        let result = await task.value
        if pendingToken == token {
            pendingWrite = nil
            pendingToken = nil
        }
        return result
    }

    private func writeNow(noteID: String, edit: NotesNativeTextEdit) async -> Result<Void, NotesAppError> {
        guard edit.replacements(in: edit.originalPlainText) != nil, !edit.imageSources.isEmpty else {
            return .failure(conflictError)
        }
        let before: NotesAppBridge.NoteContent
        switch await dependencies.readNote(noteID) {
        case .success(let content): before = content
        case .failure(let error): return .failure(error)
        }
        guard !before.isPasswordProtected, before.requiresNativeTextEditing,
              before.plainText == edit.originalPlainText || before.plainText == edit.updatedPlainText,
              NotesNativeTextEdit.imageSources(in: before.bodyHTML) == edit.imageSources else {
            return .failure(conflictError)
        }
        if before.plainText == edit.updatedPlainText { return .success(()) }
        guard dependencies.isTrusted() else {
            return .failure(.failed(AppLocalization.text("保存手写备忘录需要辅助功能权限")))
        }
        if case .failure(let error) = await dependencies.showNote(noteID) { return .failure(error) }
        guard let editor = dependencies.editor(edit.originalPlainText), let initialText = editor.text(),
              let replacements = edit.replacements(in: initialText) else {
            return .failure(saveError)
        }
        var expectedText = initialText
        var completed: [(range: NSRange, original: String)] = []
        for replacement in replacements {
            guard await dependencies.selectedNoteID() == noteID, editor.text() == expectedText else {
                return .failure(conflictError)
            }
            let original = (expectedText as NSString).substring(with: replacement.range)
            let updated = (expectedText as NSString).replacingCharacters(in: replacement.range, with: replacement.text)
            guard editor.replace(replacement.range, replacement.text), editor.text() == updated else {
                // Undo only confirmed edits; never replace the attachment-containing AXValue.
                for step in completed.reversed() {
                    guard await dependencies.selectedNoteID() == noteID,
                          editor.text() == expectedText, editor.replace(step.range, step.original) else { break }
                    expectedText = (expectedText as NSString).replacingCharacters(in: step.range, with: step.original)
                }
                return .failure(saveError)
            }
            expectedText = updated
            completed.append((NSRange(location: replacement.range.location, length: replacement.text.utf16.count), original))
        }
        switch await dependencies.readNote(noteID) {
        case .success(let after):
            guard after.requiresNativeTextEditing,
                  after.plainText == edit.updatedPlainText,
                  NotesNativeTextEdit.imageSources(in: after.bodyHTML) == edit.imageSources else {
                return .failure(conflictError)
            }
            return .success(())
        case .failure(let error): return .failure(error)
        }
    }

    private var conflictError: NotesAppError {
        .failed(AppLocalization.text("备忘录内容已变化，请重新打开后编辑"))
    }

    private var saveError: NotesAppError {
        .failed(AppLocalization.text("无法保存手写备忘录的文本，请在备忘录中打开后重试"))
    }

    private static func findEditor(expectedText: String) -> Editor? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").first else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        let windows = (attribute(kAXWindowsAttribute, from: application) as? [AXUIElement]) ?? []
        guard let element = uniqueElement(in: windows, matches: { element in
            AXUIElementSetMessagingTimeout(element, 0.5)
            return attribute(kAXRoleAttribute, from: element) as? String == kAXTextAreaRole as String
                && text(of: element).map { $0 == expectedText || $0 == expectedText + "\n" } == true
        }, children: { attribute(kAXChildrenAttribute, from: $0) as? [AXUIElement] ?? [] }) else { return nil }
        return editor(readAttribute: { attribute($0, from: element) },
                      setAttribute: { AXUIElementSetAttributeValue(element, $0 as CFString, $1) })
    }

    static func uniqueElement<Element>(in roots: [Element], matches: (Element) -> Bool,
                                       children: (Element) -> [Element]) -> Element? {
        var pending = roots
        var found: Element?
        var visited = 0
        while visited < 2_000, let element = pending.popLast() {
            visited += 1
            if matches(element) {
                guard found == nil else { return nil }
                found = element
            }
            pending.append(contentsOf: children(element))
        }
        return pending.isEmpty ? found : nil
    }

    static func editor(readAttribute: @escaping (String) -> CFTypeRef?,
                       setAttribute: @escaping (String, CFTypeRef) -> AXError) -> Editor {
        Editor(text: {
            let value = readAttribute(kAXValueAttribute)
            return (value as? String) ?? (value as? NSAttributedString)?.string
        }, replace: { range, text in
            var range = CFRange(location: range.location, length: range.length)
            guard let value = AXValueCreate(.cfRange, &range),
                  setAttribute(kAXSelectedTextRangeAttribute, value) == .success,
                  let selected = readAttribute(kAXSelectedTextRangeAttribute), CFGetTypeID(selected) == AXValueGetTypeID() else { return false }
            var actual = CFRange()
            guard AXValueGetValue(selected as! AXValue, .cfRange, &actual),
                  actual.location == range.location, actual.length == range.length else { return false }
            return setAttribute(kAXSelectedTextAttribute, text as CFString) == .success
        })
    }

    private static func text(of element: AXUIElement) -> String? {
        let value = attribute(kAXValueAttribute, from: element)
        return (value as? String) ?? (value as? NSAttributedString)?.string
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
