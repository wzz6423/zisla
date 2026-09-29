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

    @Test
    func handsOffAPrivateExecutableCommandFileWithoutDeletingItEarly() throws {
        try withTemporaryDirectory { directory in
            var launchedURL: URL?
            try ClipboardShellCommandRunner.runInTerminal("git status", temporaryDirectory: directory) {
                launchedURL = $0
                return true
            }
            let url = try #require(launchedURL)
            #expect(url.pathExtension == "command")
            #expect(FileManager.default.isExecutableFile(atPath: url.path))
            #expect(try permissions(at: url) == 0o700)
            #expect(try permissions(at: url.deletingLastPathComponent()) == 0o700)
            #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("#!/bin/sh\n"))
        }
    }

    @Test
    func launchFailureRemovesTheScriptAndAllowsAnotherAttempt() throws {
        try withTemporaryDirectory { directory in
            #expect(throws: CocoaError.self) {
                try ClipboardShellCommandRunner.runInTerminal("git status", temporaryDirectory: directory) { _ in false }
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
            var launchedURL: URL?
            try ClipboardShellCommandRunner.runInTerminal("pwd", temporaryDirectory: directory) {
                launchedURL = $0
                return true
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
            #expect(launchedURL != nil)
        }
    }

    @Test
    func unavailableTemporaryDirectoryDoesNotLaunchOrChangeExistingFiles() throws {
        try withTemporaryDirectory { directory in
            let file = directory.appendingPathComponent("existing.txt")
            try Data("unchanged".utf8).write(to: file)
            var didLaunch = false
            #expect(throws: CocoaError.self) {
                try ClipboardShellCommandRunner.runInTerminal("pwd", temporaryDirectory: file) { _ in
                    didLaunch = true
                    return true
                }
            }
            #expect(!didLaunch)
            #expect(try String(contentsOf: file, encoding: .utf8) == "unchanged")
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["existing.txt"])
        }
    }

    @Test
    func shellReceivesTheExactCommandAfterTheTemporaryScriptCleansItself() throws {
        try withTemporaryDirectory { directory in
            let shell = directory.appendingPathComponent("fake shell")
            let argumentsURL = directory.appendingPathComponent("arguments")
            let workingDirectoryURL = directory.appendingPathComponent("working-directory")
            let marker = directory.appendingPathComponent("must-not-execute")
            try Data("""
                #!/bin/sh
                /usr/bin/printf '%s\\0' "$@" > "$ZISLA_TEST_ARGUMENTS"
                /bin/pwd > "$ZISLA_TEST_DIRECTORY"

                """.utf8).write(to: shell)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shell.path)
            let launchDirectory = directory.appendingPathComponent("launch 'with quotes'", isDirectory: true)
            try FileManager.default.createDirectory(at: launchDirectory, withIntermediateDirectories: false)
            var commands = [
                "printf '%s\\n' '你好'",
                "echo \"$(/usr/bin/touch '\(marker.path)')\"",
                "echo '; /usr/bin/touch \"\(marker.path)\"; #",
                "printf one\nprintf two",
                "printf '%s' '$HOME' \"a\\\\b\"",
                "exit 7",
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
                var launchedURL: URL?
                try ClipboardShellCommandRunner.runInTerminal(command, temporaryDirectory: launchDirectory) {
                    launchedURL = $0
                    return true
                }
                let url = try #require(launchedURL)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [url.path]
                process.currentDirectoryURL = url.deletingLastPathComponent()
                process.environment = ProcessInfo.processInfo.environment.merging([
                    "SHELL": shell.path,
                    "ZISLA_TEST_ARGUMENTS": argumentsURL.path,
                    "ZISLA_TEST_DIRECTORY": workingDirectoryURL.path,
                ]) { _, value in value }
                let errors = Pipe()
                process.standardError = errors
                try process.run()
                process.waitUntilExit()
                #expect(process.terminationStatus == 0, "\(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))")
                let arguments = try String(contentsOf: argumentsURL, encoding: .utf8)
                    .split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init)
                #expect(arguments == ["-ilc", command])
                #expect(try String(contentsOf: workingDirectoryURL, encoding: .utf8)
                    .trimmingCharacters(in: .newlines) == FileManager.default.homeDirectoryForCurrentUser.path)
                #expect(try FileManager.default.contentsOfDirectory(atPath: launchDirectory.path).isEmpty)
                #expect(!FileManager.default.fileExists(atPath: marker.path))
            }
        }
    }

    @Test
    func emptyShellEnvironmentUsesZshWithoutReadingUserStartupFiles() throws {
        try withTemporaryDirectory { directory in
            let versionURL = directory.appendingPathComponent("shell-version")
            try Data("""
                /usr/bin/printf '%s' "$ZSH_VERSION" > "$ZISLA_TEST_VERSION"
                exit 0

                """.utf8).write(to: directory.appendingPathComponent(".zshenv"))
            var launchedURL: URL?
            try ClipboardShellCommandRunner.runInTerminal("printf unused", temporaryDirectory: directory) {
                launchedURL = $0
                return true
            }
            let url = try #require(launchedURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [url.path]
            var environment = ProcessInfo.processInfo.environment
            // sh can synthesize an unset SHELL from the account's login shell.
            environment["SHELL"] = ""
            environment["ZDOTDIR"] = directory.path
            environment["ZISLA_TEST_VERSION"] = versionURL.path
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            #expect(try !String(contentsOf: versionURL, encoding: .utf8).isEmpty)
            #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        }
    }

    private func permissions(at url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
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
