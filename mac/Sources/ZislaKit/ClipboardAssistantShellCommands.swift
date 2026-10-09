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
        command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let fence = "```"
        var explicitlyShell = false
        if command.hasPrefix(fence) {
            let lines = command.components(separatedBy: "\n")
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
        let lines = command.replacingOccurrences(of: "\\\n", with: " ")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !lines.isEmpty else { return nil }
        // A declared shell block can contain loops and here-documents. Unlabelled text needs
        // command evidence on every line so copied explanations and terminal output stay inert.
        guard explicitlyShell || lines.allSatisfy({
            guard let name = shellCommandName($0) else { return false }
            return commandExists(name)
        }) else { return nil }
        return command
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
