import Foundation
import Testing
@testable import ZislaKit

struct ClipboardShellCommandResolverTests {
    @Test(arguments: ["/bin/zsh", "/bin/bash"])
    func resolvesLiveAliasesFunctionsBuiltinsAndExecutablesWithoutExecutingThem(shell: String) async throws {
        try await withShell(shell) { directory, environment in
            let tool = "fixture-" + UUID().uuidString.lowercased()
            let executable = directory.appendingPathComponent(tool)
            try writeExecutable("#!/bin/sh\n/usr/bin/touch \"$ZISLA_EXECUTION_MARKER\"\n", to: executable)
            let startup = """
            export PATH="$HOME"
            alias z='/usr/bin/touch "$ZISLA_EXECUTION_MARKER"'
            alias ll='/usr/bin/touch "$ZISLA_EXECUTION_MARKER"'
            fixture_function() { /usr/bin/touch "$ZISLA_EXECUTION_MARKER"; }

            """
            try startup.write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            try startup.write(to: directory.appendingPathComponent(".bash_profile"), atomically: true, encoding: .utf8)

            for text in [
                "z code", "ll", "z code && ll", "fixture_function project", "cd", "pwd",
                "\(tool) --help", "./\(tool) --help", "~/\(tool) --help", "\(executable.path) --help",
                "MODE=dev z code && ll", "z code\npwd", "z code && missing-command",
            ] {
                let command = await ClipboardShellCommandResolver.resolve(text, environment: environment, workingDirectory: directory)
                #expect(command == text, "The user's shell should recognize: \(text)")
                let detection = ClipboardAssistantDetector.detect(content: .text(text), enabledKinds: [.shellCommand], shellCommandExists: { _ in command != nil })
                #expect(detection?.fullContent == text)
            }
            for text in ["git status", "unknown-cli --help", "hello world && welcome back", "missing-command && pwd", "z code\nmissing-command", "$ missing-command"] {
                #expect(await ClipboardShellCommandResolver.resolve(text, environment: environment, workingDirectory: directory) == nil)
            }
            #expect(!FileManager.default.fileExists(atPath: environment["ZISLA_EXECUTION_MARKER"]!))
        }
    }

    @Test
    func rereadsTheShellConfigurationOnTheNextCopy() async throws {
        try await withShell("/bin/zsh") { directory, environment in
            let name = "alias_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let command = "\(name) workspace"
            #expect(await ClipboardShellCommandResolver.resolve(command, environment: environment, workingDirectory: directory) == nil)
            let config = directory.appendingPathComponent(".zshrc")
            try "alias \(name)='exit 19'\n".write(to: config, atomically: true, encoding: .utf8)
            #expect(await ClipboardShellCommandResolver.resolve(command, environment: environment, workingDirectory: directory) == command)
            try "".write(to: config, atomically: true, encoding: .utf8)
            #expect(await ClipboardShellCommandResolver.resolve(command, environment: environment, workingDirectory: directory) == nil)
        }
    }

    @Test
    func probingNeverEvaluatesArgumentsSubstitutionsOrRedirections() async throws {
        try await withShell("/bin/zsh") { directory, environment in
            let marker = directory.appendingPathComponent("must-not-exist").path
            for text in [
                "echo $(touch \(marker))", "echo `touch \(marker)`", "echo ignored > \(marker)",
                "echo value; touch \(marker)", "echo value && touch \(marker)",
                "MODE='$(touch \(marker))' echo value", "echo '\"; touch \(marker); #'",
            ] {
                #expect(await ClipboardShellCommandResolver.resolve(text, environment: environment, workingDirectory: directory) == text)
                #expect(!FileManager.default.fileExists(atPath: marker))
            }
            let executable = directory.appendingPathComponent("literal$(touch${IFS}marker)")
            try writeExecutable("#!/bin/sh\nexit 9\n", to: executable)
            let text = executable.path + " --help"
            #expect(await ClipboardShellCommandResolver.resolve(text, environment: environment, workingDirectory: directory) == text)
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("marker").path))
        }
    }

    @Test
    func missingShellAndPrematureStartupExitDoNotClaimRecognition() async throws {
        try await withShell("/bin/zsh") { directory, environment in
            var unavailable = environment
            unavailable["SHELL"] = directory.appendingPathComponent("missing-shell").path
            #expect(await ClipboardShellCommandResolver.resolve("pwd", environment: unavailable, workingDirectory: directory) == nil)
            let config = directory.appendingPathComponent(".zshrc")
            try "exit 0\n".write(to: config, atomically: true, encoding: .utf8)
            #expect(await ClipboardShellCommandResolver.resolve("pwd", environment: environment, workingDirectory: directory) == nil)
            try "printf 'startup output\\n'\n".write(to: config, atomically: true, encoding: .utf8)
            #expect(await ClipboardShellCommandResolver.resolve("pwd", environment: environment, workingDirectory: directory) == "pwd")
        }
    }

    @Test
    func timeoutStopsTheProbeEvenWhenTheShellExitsSuccessfully() async throws {
        try await withShell("/bin/zsh") { directory, environment in
            let script = directory.appendingPathComponent("slow-shell")
            try writeExecutable("""
            #!/bin/sh
            trap 'exit 0' TERM
            printf '\\036zisla-command-found\\037'
            while :; do :; done

            """, to: script)
            var slowEnvironment = environment
            slowEnvironment["SHELL"] = script.path
            #expect(await ClipboardShellCommandResolver.resolve("pwd", environment: slowEnvironment, workingDirectory: directory, timeout: 0.1) == nil)
            #expect(await ClipboardShellCommandResolver.resolve("pwd", environment: environment, workingDirectory: directory) == "pwd")
        }
    }

    @Test
    func cancellingAnActiveProbeStopsItsProcess() async throws {
        try await withShell("/bin/zsh") { directory, environment in
            let pidFile = directory.appendingPathComponent("pid")
            let script = directory.appendingPathComponent("waiting-shell")
            try writeExecutable("""
            #!/bin/sh
            trap 'exit 0' TERM
            printf '%s' "$$" > "$HOME/pid"
            while :; do :; done

            """, to: script)
            var waitingEnvironment = environment
            waitingEnvironment["SHELL"] = script.path
            let state = ProbeState()
            let task = Task { [waitingEnvironment] in
                let result = await ClipboardShellCommandResolver.resolve("pwd", environment: waitingEnvironment, workingDirectory: directory)
                await state.finish()
                return result
            }
            defer { task.cancel() }
            var startedPID: Int32?
            repeat {
                startedPID = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap(Int32.init)
                if await state.finished { break }
                await Task.yield()
            } while startedPID == nil
            let pid = try #require(startedPID)
            task.cancel()
            #expect(await task.value == nil)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
        }
    }

    @Test
    func emptyMalformedAndExplicitShellInputsDoNotLaunchAProbe() async throws {
        try await withShell("/bin/zsh") { directory, environment in
            let shell = directory.appendingPathComponent("probe-shell")
            try writeExecutable("#!/bin/sh\n/usr/bin/touch \"$ZISLA_EXECUTION_MARKER\"\n", to: shell)
            var spyEnvironment = environment
            spyEnvironment["SHELL"] = shell.path
            for text in ["", " ", "echo '\u{0000}'", "&& z code", "echo " + String(repeating: "x", count: 20_000)] {
                #expect(await ClipboardShellCommandResolver.resolve(text, environment: spyEnvironment, workingDirectory: directory) == nil)
            }
            #expect(await ClipboardShellCommandResolver.resolve("```sh\ncustom-command --help\n```", environment: spyEnvironment, workingDirectory: directory) == "custom-command --help")
            #expect(!FileManager.default.fileExists(atPath: environment["ZISLA_EXECUTION_MARKER"]!))
        }
    }

    @Test
    func supportsMultilineInputAtTheSizeLimit() async throws {
        try await withShell("/bin/zsh") { directory, environment in
            let text = Array(repeating: "pwd", count: 5_000).joined(separator: "\n")
            #expect(await ClipboardShellCommandResolver.resolve(text, environment: environment, workingDirectory: directory) == text)
        }
    }

    @Test
    func startupOutputAndFailedExitCannotForgeSuccessfulProbes() async throws {
        try await withShell("/bin/zsh") { directory, environment in
            let config = directory.appendingPathComponent(".zshrc")
            try "printf '\\036zisla-command-found\\037'; exit 7\n".write(to: config, atomically: true, encoding: .utf8)
            #expect(await ClipboardShellCommandResolver.resolve("pwd", environment: environment, workingDirectory: directory) == nil)
            try "printf '%05000d' 0\n".write(to: config, atomically: true, encoding: .utf8)
            #expect(await ClipboardShellCommandResolver.resolve("pwd", environment: environment, workingDirectory: directory) == nil)
        }
    }

    @Test
    func usesTheDefaultShellWhenTheEnvironmentOmitsIt() async throws {
        try await withShell("/bin/zsh") { directory, environment in
            var environment = environment
            environment.removeValue(forKey: "SHELL")
            try "alias fixture_alias='exit 9'\n".write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            #expect(await ClipboardShellCommandResolver.resolve("fixture_alias", environment: environment, workingDirectory: directory) == "fixture_alias")
        }
    }

    @Test
    func shellStartupReadsReceiveEOF() async throws {
        try await withShell("/bin/zsh") { directory, environment in
            try "if read -r value; then exit 7; fi\n".write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            #expect(await ClipboardShellCommandResolver.resolve("pwd", environment: environment, workingDirectory: directory) == "pwd")
        }
    }

    private actor ProbeState {
        var finished = false
        func finish() { finished = true }
    }

    private func writeExecutable(_ source: String, to url: URL) throws {
        try source.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func withShell(
        _ shell: String,
        body: (URL, [String: String]) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-shell-resolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        try "unsetopt GLOBAL_RCS\n".write(to: directory.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
        try await body(directory, [
            "SHELL": shell, "HOME": directory.path, "ZDOTDIR": directory.path, "PATH": "/usr/bin:/bin",
            "ZISLA_EXECUTION_MARKER": directory.appendingPathComponent("executed").path,
        ])
    }
}
