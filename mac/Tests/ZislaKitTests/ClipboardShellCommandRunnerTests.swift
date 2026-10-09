import Foundation
import Darwin
import Testing
@testable import ZislaKit

@MainActor
struct ClipboardShellCommandRunnerTests {
    @Test
    func backgroundLaunchReturnsWhileTheCommandIsRunningAndSurvivesTheCaller() throws {
        try withTemporaryDirectory { directory in
            let shell = directory.appendingPathComponent("fake-shell")
            let gate = directory.appendingPathComponent("gate")
            let marker = directory.appendingPathComponent("completed")
            try #require(mkfifo(gate.path, 0o600) == 0)
            let gateDescriptor = open(gate.path, O_RDWR | O_NONBLOCK)
            try #require(gateDescriptor >= 0)
            defer { close(gateDescriptor) }
            try Data("""
                #!/bin/sh
                read -r signal < "$ZISLA_TEST_GATE"
                printf '%s' "$signal" > "$ZISLA_TEST_MARKER"

                """.utf8).write(to: shell)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shell.path)
            let completed = DispatchSemaphore(value: 0)
            try autoreleasepool {
                let process = try ClipboardShellCommandRunner.runInBackground(
                    "unused", environment: ["SHELL": shell.path, "ZISLA_TEST_GATE": gate.path, "ZISLA_TEST_MARKER": marker.path]
                )
                process.terminationHandler = { _ in completed.signal() }
                #expect(process.isRunning)
                #expect(!FileManager.default.fileExists(atPath: marker.path))
            }
            let writer = FileHandle(fileDescriptor: gateDescriptor, closeOnDealloc: false)
            try writer.write(contentsOf: Data("continue\n".utf8))
            #expect(completed.wait(timeout: .now() + 5) == .success)
            #expect(try String(contentsOf: marker, encoding: .utf8) == "continue")
        }
    }

    @Test
    func backgroundExecutionPreservesArgumentsAndUsesNullIO() throws {
        try withTemporaryDirectory { directory in
            let shell = directory.appendingPathComponent("fake shell")
            let argumentsURL = directory.appendingPathComponent("arguments")
            let workingDirectoryURL = directory.appendingPathComponent("working-directory")
            let marker = directory.appendingPathComponent("must-not-execute")
            try Data("""
                #!/bin/sh
                /usr/bin/printf '%s\\0' "$@" > "$ZISLA_TEST_ARGUMENTS"
                /bin/pwd > "$ZISLA_TEST_DIRECTORY"
                if read -r input; then exit 1; fi
                printf 'discarded stdout'
                printf 'discarded stderr' >&2

                """.utf8).write(to: shell)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shell.path)
            let command = "printf '%s\\n' \"$(touch '\(marker.path)')\"\nprintf '%s' '$HOME'"
            let process = try ClipboardShellCommandRunner.runInBackground(
                command,
                environment: [
                    "SHELL": shell.path,
                    "ZISLA_TEST_ARGUMENTS": argumentsURL.path,
                    "ZISLA_TEST_DIRECTORY": workingDirectoryURL.path,
                ],
                workingDirectory: directory
            )
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            let arguments = try String(contentsOf: argumentsURL, encoding: .utf8)
                .split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init)
            #expect(arguments == ["-ilc", command])
            let workingDirectory = try String(contentsOf: workingDirectoryURL, encoding: .utf8)
                .trimmingCharacters(in: .newlines)
            #expect(URL(fileURLWithPath: workingDirectory).resolvingSymlinksInPath() == directory.resolvingSymlinksInPath())
            #expect(!FileManager.default.fileExists(atPath: marker.path))
            for handle in [process.standardInput, process.standardOutput, process.standardError] {
                #expect((handle as? FileHandle) === FileHandle.nullDevice)
            }
        }
    }

    @Test
    func backgroundLaunchFailureDoesNotCreateFilesAndCanRecover() throws {
        try withTemporaryDirectory { directory in
            #expect(throws: (any Error).self) {
                try ClipboardShellCommandRunner.runInBackground(
                    "pwd", environment: ["SHELL": directory.appendingPathComponent("missing-shell").path],
                    workingDirectory: directory
                )
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
            let marker = directory.appendingPathComponent("completed")
            try Data("""
                /usr/bin/printf '%s' "$ZSH_VERSION" > "$ZISLA_TEST_VERSION"
                exit 0

                """.utf8).write(to: directory.appendingPathComponent(".zshenv"))
            let process = try ClipboardShellCommandRunner.runInBackground(
                "printf unused", environment: ["ZDOTDIR": directory.path, "ZISLA_TEST_VERSION": marker.path],
                workingDirectory: directory
            )
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            #expect(try !String(contentsOf: marker, encoding: .utf8).isEmpty)
        }
    }

    @Test
    func backgroundZshDisablesJobControlButReadsInteractiveConfiguration() throws {
        try withTemporaryDirectory { directory in
            try "unsetopt GLOBAL_RCS\n".write(to: directory.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
            try """
            case $- in *m*) exit 19 ;; esac
            fixture_function() { printf '%s' 'configured' > output; }

            """.write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            let process = try ClipboardShellCommandRunner.runInBackground(
                "fixture_function; exit 7",
                environment: ["SHELL": "/bin/zsh", "HOME": directory.path, "ZDOTDIR": directory.path],
                workingDirectory: directory
            )
            let completed = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in completed.signal() }
            let exited = completed.wait(timeout: .now() + 5) == .success
            defer {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
            try #require(exited)
            #expect(process.terminationStatus == 7)
            #expect(try String(contentsOf: directory.appendingPathComponent("output"), encoding: .utf8) == "configured")
        }
    }

    @Test
    func backgroundCommandReallyRunsAndReportsItsExitStatus() throws {
        try withTemporaryDirectory { directory in
            let marker = directory.appendingPathComponent("output")
            // Disable startup files before the isolated zsh receives the test command.
            try Data("unsetopt RCS\n".utf8).write(to: directory.appendingPathComponent(".zshenv"))
            let process = try ClipboardShellCommandRunner.runInBackground(
                "printf '%s' '你好 $HOME' > output; exit 7",
                environment: ["SHELL": "/bin/zsh", "ZDOTDIR": directory.path], workingDirectory: directory
            )
            process.waitUntilExit()
            #expect(process.terminationStatus == 7)
            #expect(try String(contentsOf: marker, encoding: .utf8) == "你好 $HOME")
        }
    }

    @Test(arguments: [nil, "com.apple.Terminal"] as [String?])
    func foregroundCreatesAnInteractiveSessionWithTheOriginalCommand(terminal: String?) throws {
        let command = "z code && ls -l"
        var result: NSAppleEventDescriptor?
        try ClipboardShellCommandRunner.runInTerminal(command, terminalBundleIdentifier: terminal) { source, argument in
            result = try executeWithTerminalFixture(source, command: argument)
        }
        let commands = try #require(result?.atIndex(1))
        #expect(commands.numberOfItems == 1)
        #expect(commands.atIndex(1)?.stringValue == command)
        #expect(result?.atIndex(2)?.booleanValue == true)
    }

    @Test
    func foregroundPassesStateChangingCommandsWithoutASubshellWrapper() throws {
        var commands = [
            "cd ~/Documents", "export ZISLA_TEST_VALUE=ready", "printf '%s\\n' '你好'",
            "echo \"$(touch must-not-execute)\"", "printf one\nprintf two",
            "printf '%s' '$HOME' \"a\\\\b\"", "exit 7", "",
            "\"\nend tell\ndo shell script \"exit 17\"\n--",
        ]
        var seed: UInt64 = 0xC0FFEE
        let alphabet = Array("abXY019 '\"$`\\;&|<>()[]{}\n\t中文")
        for _ in 0..<32 {
            commands.append(String((0..<80).map { _ in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return alphabet[Int(seed % UInt64(alphabet.count))]
            }))
        }
        for command in commands {
            try ClipboardShellCommandRunner.runInTerminal(command, terminalBundleIdentifier: "com.apple.Terminal") { source, argument in
                let result = try executeWithTerminalFixture(source, command: argument)
                let receivedCommands = try #require(result.atIndex(1))
                #expect(receivedCommands.numberOfItems == 1)
                #expect(receivedCommands.atIndex(1)?.stringValue == command)
                #expect(result.atIndex(2)?.booleanValue == true)
            }
        }
    }

    @Test
    func itermReceivesANewDefaultProfileSessionAndTheOriginalCommand() throws {
        let command = "cd ~/Documents && pwd"
        var request: (String, String)?
        try ClipboardShellCommandRunner.runInTerminal(command, terminalBundleIdentifier: "com.googlecode.iterm2") {
            request = ($0, $1)
        }
        let (source, argument) = try #require(request)
        #expect(argument == command)
        #expect(source.contains("tell application id \"com.googlecode.iterm2\""))
        #expect(source.contains("create window with default profile"))
        #expect(source.contains("tell current session of terminalWindow to write text (item 1 of argv)"))
        #expect(source.contains("\n        activate\n"))
    }

    @Test(arguments: ["", "dev.example.unsupported-terminal"])
    func unsupportedTerminalDoesNotLaunchADifferentAppOrScript(terminal: String) {
        var didExecute = false
        #expect(throws: CocoaError(.featureUnsupported)) {
            try ClipboardShellCommandRunner.runInTerminal("pwd", terminalBundleIdentifier: terminal) { _, _ in
                didExecute = true
            }
        }
        #expect(!didExecute)
    }

    @Test
    func terminalPermissionFailureIsReportedOnceAndCanRecover() throws {
        let denied = NSError(domain: NSOSStatusErrorDomain, code: -1743)
        var attempts = 0
        #expect(throws: denied) {
            try ClipboardShellCommandRunner.runInTerminal("pwd", terminalBundleIdentifier: "com.apple.Terminal") { _, _ in
                attempts += 1
                throw denied
            }
        }
        #expect(attempts == 1)
        try ClipboardShellCommandRunner.runInTerminal("pwd", terminalBundleIdentifier: "com.apple.Terminal") { source, command in
            attempts += 1
            let result = try executeWithTerminalFixture(source, command: command)
            #expect(result.atIndex(1)?.atIndex(1)?.stringValue == "pwd")
        }
        #expect(attempts == 2)
    }

    @Test(arguments: [
        "on run argv\nerror \"Denied\" number -1743\nend run",
        "on run argv\nerror \"Timed out\" number -1712\nend run",
        "on run argv\nthis is not valid AppleScript !!!\nend run",
    ])
    func appleScriptFailuresAreNotReportedAsSuccessfulLaunches(source: String) {
        #expect(throws: CocoaError(.executableLoad)) {
            try ClipboardShellCommandRunner.executeTerminalScript(source, command: "pwd")
        }
    }

    private func executeWithTerminalFixture(_ source: String, command: String) throws -> NSAppleEventDescriptor {
        // Replace only the application boundary; execute the production AppleScript and Apple Event payload.
        let fixture = """
        script terminalFixture
            property commands : {}
            property activated : false
            on «event coredosc» commandText
                set end of commands to commandText
            end «event coredosc»
            on activate
                set activated to true
            end activate
        end script
        """
        let body = source
            .replacingOccurrences(of: "tell application id \"com.apple.Terminal\"", with: "tell terminalFixture")
            .replacingOccurrences(of: "end run", with: "return {commands of terminalFixture, activated of terminalFixture}\nend run")
        return try ClipboardShellCommandRunner.executeTerminalScript(
            fixture + "\nusing terms from application id \"com.apple.Terminal\"\n" + body + "\nend using terms from",
            command: command
        )
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-shell-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        try body(directory)
    }
}
