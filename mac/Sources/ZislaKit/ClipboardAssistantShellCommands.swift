import AppKit
import ZislaCore

extension ClipboardAssistantDetector {
    static func shellCommandDetection(_ text: String, commandExists: (String) -> Bool) -> ClipboardAssistantDetection? {
        guard let command = shellCommand(from: text, commandExists: commandExists) else { return nil }
        return ClipboardAssistantDetection(
            kind: .shellCommand,
            title: previewText(command),
            detail: .codeLines(command.split(separator: "\n").count),
            actions: [.runShellCommand(command), .runShellCommandInBackground(command), .search(command), .saveText(command)],
            fullContent: command
        )
    }

    static func shellCommand(from text: String, commandExists: (String) -> Bool) -> String? {
        guard text.utf8.count <= 20_000 else { return nil }
        var command = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !command.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control && $0 != "\n" && $0 != "\t"
        }) else { return nil }
        command = String(command.drop(while: \.isWhitespace))
        let fence = "```"
        var explicitlyShell = false
        if command.hasPrefix(fence) {
            let lines = command.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard lines.count >= 3, lines.last == fence,
                  ["sh", "bash", "zsh", "shell", "fish", "ksh", "dash"]
                    .contains(String(lines[0].dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased())
            else { return nil }
            command = lines.dropFirst().dropLast().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            explicitlyShell = true
        }
        if command.hasPrefix("#!") {
            guard command.range(
                of: #"^#!\h*(?:/(?:usr/)?bin/|/usr/bin/env\h+)(?:sh|bash|zsh|fish|ksh|dash)(?:\h|\n|$)"#,
                options: .regularExpression
            ) != nil else { return nil }
            explicitlyShell = true
        }
        let hasPrompt = command.hasPrefix("$ ") || command.hasPrefix("% ")
        if hasPrompt { command.removeFirst(2) }
        let lines = command.components(separatedBy: "\n")
        if explicitlyShell {
            return lines.contains(where: {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return !line.isEmpty && !line.hasPrefix("#")
            }) ? command.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }
        var hereDocuments: [(delimiter: String, stripsTabs: Bool, isQuoted: Bool)] = []
        var invocation = ""
        var hasCommand = false
        var hasHereDocument = false
        for (index, line) in lines.enumerated() {
            if let document = hereDocuments.first {
                invocation += line
                if !document.isQuoted, index < lines.count - 1,
                   line.reversed().prefix(while: { $0 == "\\" }).count % 2 == 1 {
                    invocation.removeLast()
                    continue
                }
                let ending = document.stripsTabs ? invocation.drop(while: { $0 == "\t" }) : invocation[...]
                if ending == document.delimiter { hereDocuments.removeFirst() }
                invocation = ""
                continue
            }
            invocation += line
            if index < lines.count - 1, line.hasSuffix("\\") {
                invocation.removeLast()
                invocation += " "
                continue
            }
            let logicalLine = invocation.trimmingCharacters(in: .whitespaces)
            invocation = ""
            if logicalLine.isEmpty || logicalLine.hasPrefix("#") { continue }
            guard let name = shellCommandName(logicalLine), commandExists(name) else { return nil }
            hasCommand = true
            // Only command lines are tokenized; embedded scripts remain opaque clipboard data.
            if lines.count > 1 {
                guard let documents = shellHereDocuments(in: logicalLine) else { return nil }
                hereDocuments = documents
                hasHereDocument = hasHereDocument || !documents.isEmpty
            }
        }
        guard hasCommand, hereDocuments.isEmpty else { return nil }
        return hasHereDocument ? command : command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shellHereDocuments(in line: String) -> [(delimiter: String, stripsTabs: Bool, isQuoted: Bool)]? {
        let word = #"(?:[^\s;&|<>()'"\\]|'[^']*'|"(?:[^"\\]|\\.)*"|\\.)+"#
        let pattern = word + #"|<<<|<<-|<<|[^\s]"#
        let source = line as NSString
        let tokens = (try! NSRegularExpression(pattern: pattern))
            .matches(in: shellTokenSource(line), range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
        var documents: [(delimiter: String, stripsTabs: Bool, isQuoted: Bool)] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("#") { break }
            index += 1
            guard token == "<<" || token == "<<-" else { continue }
            guard index < tokens.count,
                  tokens[index].range(of: "^" + word + "$", options: .regularExpression) != nil,
                  !tokens[index].hasPrefix("#") else { return nil }
            var delimiter = ""
            var quote: Character?
            var escaped = false
            for character in tokens[index] {
                if escaped {
                    if quote == "\"", !"$`\"\\".contains(character) { delimiter.append("\\") }
                    delimiter.append(character)
                    escaped = false
                } else if character == "\\", quote != "'" {
                    escaped = true
                } else if let currentQuote = quote {
                    if character == currentQuote { quote = nil }
                    else { delimiter.append(character) }
                } else if character == "'" || character == "\"" {
                    quote = character
                } else {
                    delimiter.append(character)
                }
            }
            documents.append((delimiter, token == "<<-", tokens[index].contains(where: { "'\"\\".contains($0) })))
            index += 1
        }
        return documents
    }

    private static func shellTokenSource(_ line: String) -> String {
        var characters = Array(line.utf16)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == 92 {
                index += 2
                continue
            }
            let expansion = character == 36 && index + 1 < characters.count
                && (characters[index + 1] == 40 || characters[index + 1] == 123)
            guard expansion || character == 39 || character == 34 || character == 96 else {
                index += 1
                continue
            }
            let start = index
            var endings: [UInt16] = [expansion ? (characters[index + 1] == 40 ? 41 : 125) : character]
            index += expansion ? 2 : 1
            while index < characters.count, let ending = endings.last {
                let next = characters[index]
                index += 1
                let quoted = ending == 39 || ending == 34 || ending == 96
                if next == 92, ending != 39 {
                    index += 1
                } else if next == ending {
                    endings.removeLast()
                } else if (!quoted || ending == 34), next == 36, index < characters.count,
                          characters[index] == 40 || characters[index] == 123 {
                    endings.append(characters[index] == 40 ? 41 : 125)
                    index += 1
                } else if !quoted, next == 39 || next == 34 || next == 96 {
                    endings.append(next)
                } else if ending == 34, next == 96 {
                    endings.append(96)
                } else if next == 40, ending == 41 {
                    endings.append(41)
                } else if next == 123, ending == 125 {
                    endings.append(125)
                }
            }
            // Keep UTF-16 offsets so token ranges still reference the original clipboard words.
            for position in start..<min(index, characters.count) { characters[position] = 120 }
        }
        return String(decoding: characters, as: UTF16.self)
    }

    private static func shellCommandName(_ line: String) -> String? {
        let assignments = #"^(?:[A-Za-z_][A-Za-z0-9_]*=(?:'[^']*'|"[^"]*"|[^\s]+)\h+)*"#
        let invocation = line.replacingOccurrences(of: assignments, with: "", options: .regularExpression)
        guard let range = invocation.range(
            of: #"^(?:[A-Za-z_][A-Za-z0-9_.+-]*|(?:/|\./|\.\./|~/)[^\s'";&|<>]+)(?=$|[\s;&|<>])"#,
            options: .regularExpression
        ) else { return nil }
        return String(invocation[range])
    }
}

// Detached subprocesses have no terminal for zsh job control. Keep interactive
// startup files for aliases/functions without changing other shells' options.
private func detachedShellArguments(for shell: URL, command: String) -> [String] {
    (shell.lastPathComponent == "zsh" ? ["+m", "-ilc"] : ["-ilc"]) + [command]
}

public enum ClipboardShellCommandResolver {
    public static func resolve(
        _ text: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: TimeInterval = 2
    ) async -> String? {
        var names: [String] = []
        guard let command = ClipboardAssistantDetector.shellCommand(from: text, commandExists: {
            names.append($0)
            return true
        }) else { return nil }
        guard !names.isEmpty else { return command }

        var environment = environment
        var checks: [String] = []
        for (index, name) in names.enumerated() {
            let key = "ZISLA_SHELL_COMMAND_\(index)"
            environment[key] = name.hasPrefix("~/")
                ? (environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path) + name.dropFirst()
                : name
            checks.append("type \"$\(key)\" >/dev/null 2>&1")
        }
        // Only variable references enter shell source; clipboard text stays inert environment data.
        let marker = "\u{001E}zisla-command-found\u{001F}"
        checks.append("printf '\\036zisla-command-found\\037'")
        let shell = URL(fileURLWithPath: environment["SHELL"] ?? "/bin/zsh")
        guard let result = try? await AIAgentProcessRunner.run(
            executableURL: shell,
            arguments: detachedShellArguments(for: shell, command: checks.joined(separator: " && ")),
            standardInput: Data(),
            environment: environment,
            workingDirectoryURL: workingDirectory,
            timeout: timeout,
            maximumOutputBytes: 4096,
            maximumErrorBytes: 1
        ), !result.didTimeout, result.status == 0,
           result.standardOutput.suffix(marker.utf8.count) == Data(marker.utf8) else { return nil }
        return command
    }
}

@MainActor
public enum ClipboardShellCommandRunner {
    public static func runInTerminal(_ command: String) async throws {
        let terminalBundleIdentifier = LSCopyDefaultRoleHandlerForContentType(
            "com.apple.terminal.shell-script" as CFString, .all
        )?.takeRetainedValue() as String?
        try await Task.detached(priority: .userInitiated) {
            try runInTerminal(command, terminalBundleIdentifier: terminalBundleIdentifier) { source, command in
                _ = try executeTerminalScript(source, command: command)
            }
        }.value
    }

    nonisolated static func runInTerminal(
        _ command: String,
        terminalBundleIdentifier: String?,
        execute: (String, String) throws -> Void
    ) throws {
        let source: String
        switch terminalBundleIdentifier {
        case nil, "com.apple.Terminal":
            source = """
            on run argv
                tell application id "com.apple.Terminal"
                    do script (item 1 of argv)
                    activate
                end tell
            end run
            """
        case "com.googlecode.iterm2":
            source = """
            on run argv
                tell application id "com.googlecode.iterm2"
                    set terminalWindow to (create window with default profile)
                    tell current session of terminalWindow to write text (item 1 of argv)
                    activate
                end tell
            end run
            """
        default:
            throw CocoaError(.featureUnsupported)
        }
        try execute(source, command)
    }

    nonisolated static func executeTerminalScript(_ source: String, command: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw CocoaError(.executableLoad) }
        // Pass clipboard contents as Apple Event data, never as AppleScript source.
        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: command), at: 1)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if error != nil { throw CocoaError(.executableLoad) }
        return result
    }

    @discardableResult
    public static func runInBackground(
        _ command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> Process {
        let process = Process()
        let shell = URL(fileURLWithPath: environment["SHELL"] ?? "/bin/zsh")
        process.executableURL = shell
        process.arguments = detachedShellArguments(for: shell, command: command)
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}
