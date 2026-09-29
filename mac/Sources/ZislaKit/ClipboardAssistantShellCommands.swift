import AppKit
import ZislaCore

extension ClipboardAssistantDetector {
    static func shellCommandDetection(_ text: String) -> ClipboardAssistantDetection? {
        guard let command = shellCommand(from: text) else { return nil }
        return ClipboardAssistantDetection(
            kind: .shellCommand,
            title: previewText(command),
            detail: .codeLines(command.split(separator: "\n").count),
            actions: [.runShellCommand(command), .runShellCommandInBackground(command), .search(command), .saveText(command)],
            fullContent: command
        )
    }

    static func shellCommand(from text: String) -> String? {
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
            hasShellCommandPrefix($0, allowsUnknownCommand: hasPrompt && lines.count == 1)
                || hasShellCommandChain($0)
        }) else { return nil }
        return command
    }

    private static func hasShellCommandChain(_ line: String) -> Bool {
        var commands: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var lastSeparator = ""
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            index = line.index(after: index)
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\", quote != "'" {
                current.append(character)
                escaped = true
            } else if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
            } else if character == "'" || character == "\"" || character == "`" {
                current.append(character)
                quote = character
            } else if character == "#", current.isEmpty || current.last?.isWhitespace == true {
                break
            } else if character == "&" || character == "|" || character == ";" {
                let command = current.trimmingCharacters(in: .whitespaces)
                commands.append(command)
                current = ""
                lastSeparator = String(character)
                if character != ";", index < line.endIndex, line[index] == character {
                    lastSeparator.append(character)
                    index = line.index(after: index)
                }
            } else {
                current.append(character)
            }
        }
        guard quote == nil, !escaped else { return false }
        let command = current.trimmingCharacters(in: .whitespaces)
        if !command.isEmpty {
            commands.append(command)
        } else if lastSeparator != ";" && lastSeparator != "&" {
            return false
        }
        return commands.allSatisfy { hasShellCommandPrefix($0, allowsUnknownCommand: true) }
            && commands.contains { hasShellCommandPrefix($0, allowsUnknownCommand: false) }
    }

    private static func hasShellCommandPrefix(_ line: String, allowsUnknownCommand: Bool) -> Bool {
        let assignments = #"^(?:[A-Za-z_][A-Za-z0-9_]*=(?:'[^']*'|"[^"]*"|[^\s]+)\h+)*"#
        let invocation = line.replacingOccurrences(of: assignments, with: "", options: .regularExpression)
        guard let range = invocation.range(
            of: #"^(?:[A-Za-z_][A-Za-z0-9_.+-]*|(?:/|\./|\.\./|~/)[^\s'";&|<>]+)(?=$|[\s;&|])"#,
            options: .regularExpression
        ) else { return false }
        let name = String(invocation[range])
        let arguments = invocation[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if name.contains("/") { return !arguments.isEmpty }
        if shellCommandNames.contains(name) { return true }
        if ["open", "find", "make"].contains(name) {
            if arguments.hasPrefix("-") || arguments.hasPrefix("/") || arguments.hasPrefix(".")
                || arguments.hasPrefix("~") { return true }
            return name == "make"
                && ["all", "build", "clean", "install", "test", "check", "run", "update", "stop", "dev", "lint", "release", "help"]
                    .contains(arguments)
        }
        return allowsUnknownCommand
    }

    private static let shellCommandNames: Set<String> = [
        "ls", "cd", "pwd", "cat", "head", "tail", "less", "grep", "rg", "fd", "sed", "awk",
        "sort", "uniq", "wc", "cut", "tr", "tee", "xargs", "echo", "printf", "touch", "mkdir",
        "cp", "mv", "rm", "ln", "chmod", "chown", "tar", "zip", "unzip", "gzip", "gunzip",
        "git", "hg", "svn", "curl", "wget", "ssh", "scp", "sftp", "rsync", "ping", "dig",
        "nslookup", "lsof", "ps", "top", "htop", "kill", "killall", "pkill", "df", "du",
        "uname", "whoami", "which", "env", "printenv", "export", "unset", "sudo", "command",
        "nohup", "bash", "zsh", "sh", "fish", "ksh", "dash", "brew", "port", "apt", "apt-get",
        "yum", "dnf", "pacman", "npm", "npx", "pnpm", "yarn", "bun", "node", "deno",
        "python", "python3", "pip", "pip3", "uv", "poetry", "ruby", "gem", "bundle",
        "go", "cargo", "rustc", "cmake", "ninja", "swift", "xcodebuild", "xcrun",
        "docker", "podman", "kubectl", "helm", "terraform", "ansible", "defaults",
        "launchctl", "osascript", "plutil", "mdfind", "mdls", "pbcopy", "pbpaste",
    ]
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
        process.executableURL = URL(fileURLWithPath: environment["SHELL"] ?? "/bin/zsh")
        process.arguments = ["-ilc", command]
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}
