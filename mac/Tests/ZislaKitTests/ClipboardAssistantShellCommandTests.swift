import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantShellCommandTests {
    private let allKinds = Set(ClipboardAssistantKind.allCases)

    @Test(arguments: [
        "ls", "pwd", "git status", "npm run dev", "brew update", "make run",
        "curl -fsSL https://example.com/install.sh | sh",
        "cd ~/Projects && git status",
        "NODE_ENV=production npm run build",
        "/usr/bin/printf '%s\\n' hello",
        "./build.sh --release", "open the settings", "find the right answer", "make sure it works",
        "open -a Safari", "open /tmp", "open ./file", "open ~/Downloads",
        "printf '%s\\n' '你好，世界'",
    ])
    func offersExecutionForShellCommands(command: String) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: command, enabledKinds: allKinds, shellCommandExists: commandExists
        ))
        #expect(detection.kind.rawValue == "shellCommand")
        #expect(detection.action == .runShellCommand(command))
        #expect(detection.fullContent == command)
        #expect(detection.actions.contains(.saveText(command)))
        #expect(detection.actions.contains(.search(command)))
        #expect(detection.actions.map(\.identifier).contains("runShellCommandInBackground"))
    }

    @Test(arguments: [
        "z code && ls -l", "z code&&ls -l", "z code || pwd", "z code; git status",
        "my-tool status | grep ready", "my-tool start && other-tool status && ls -l",
        "TOOLS_MODE=dev z code && ls -l", "z 'code && docs' && ls -l",
        "z \"code | docs\" && ls -l", "z code\\&docs && ls -l",
        "z code && ls -l;", "z code && ls -l &", "z code & ls -l",
        "z code && ls -l # show files", "z code#docs && ls -l", "z '\\' && ls -l",
        "z code && ll", "z code&&ll", "z code && ll -lah", "jump projects || showfiles",
        "repo work | listfiles -a", "croot; ll", "deploy staging && healthcheck --wait",
        "repo current && inspect /tmp", "repo current && inspect ./src",
        "repo current && inspect ../src", "repo current && inspect ~/Projects",
        "TOOLS_MODE=dev z code && ll", "z 'code && docs' && ll",
        "z code && ll # list files", "z code && ll &", "z code & ll",
    ])
    func recognizesAliasCommandChainsWithoutChangingTheirContents(command: String) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(text: command, enabledKinds: allKinds, shellCommandExists: commandExists))
        #expect(detection.kind == .shellCommand)
        #expect(detection.fullContent == command)
        #expect(detection.actions == [
            .runShellCommand(command), .runShellCommandInBackground(command), .search(command), .saveText(command),
        ])
    }

    @Test(arguments: [
        "hello world && welcome back", "message '&& ls -l'", "message \"| ls -l\"",
        "message \\&\\& ls -l", "message # && ls -l", "message &&", "&& ls -l",
        "message ||| ls -l", "message `echo '&& ls -l'`", "message `echo && ls -l`",
        "message && ls -l &&",
        "message && ls -l |", "message && ls -l '", "message && ls -l\\",
        "message && 123", "123 && ls -l", "message", "message ;; ls -l",
        "hello world || welcome back", "hello world | welcome back", "hello world; welcome back",
        "hello world && welcome - back", "hello world && welcome ...",
        "message '&& ll'", "message \"| ll\"", "message # && ll", "message \\&\\& ll",
        "message --help", "message ./path", "myalias", "myalias;", "myalias &",
    ])
    func shellLikePunctuationInTextDoesNotOfferExecution(text: String) {
        let detection = ClipboardAssistantDetector.detect(text: text, enabledKinds: allKinds, shellCommandExists: commandExists)
        #expect(detection?.kind != .shellCommand)
    }

    @Test
    func quotedChainArgumentsRemainOpaqueAcrossBoundedInputs() {
        var seed: UInt64 = 0xA11A5
        let alphabet = Array("abXY019 '\"`\\;&|<>()[]{}#中文")
        for _ in 0..<64 {
            let argument = String((0..<48).map { _ in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return alphabet[Int(seed % UInt64(alphabet.count))]
            }) + " && ls -l"
            let quoted = "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
            for suffix in ["ls -l", "ll", "custom-list --all"] {
                let command = "z \(quoted) && \(suffix)"
                #expect(shellCommand(from: command) == command)
            }
            #expect(shellCommand(from: "message \(quoted)") == nil)
        }
    }

    @Test(arguments: ["$ git status", "% git status"])
    func removesASingleCopiedPrompt(input: String) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(text: input, enabledKinds: allKinds, shellCommandExists: commandExists))
        #expect(detection.action?.identifier == "runShellCommand")
        #expect(detection.fullContent == "git status")
    }

    @Test
    func shellFencesAndContinuationsPreserveTheCommand() throws {
        let fence = String(repeating: "\u{0060}", count: 3)
        let command = "curl --request GET \\\n  https://example.com/api"
        for input in [command, "\(fence)bash\n\(command)\n\(fence)"] {
            let detection = try #require(ClipboardAssistantDetector.detect(text: input, enabledKinds: allKinds, shellCommandExists: commandExists))
            #expect(detection.action?.identifier == "runShellCommand")
            #expect(detection.fullContent == command)
        }
        let script = "#!/bin/sh\nprintf '%s\\n' hello"
        let detection = try #require(ClipboardAssistantDetector.detect(text: script, enabledKinds: allKinds, shellCommandExists: commandExists))
        #expect(detection.action?.identifier == "runShellCommand")
        #expect(detection.fullContent == script)
    }

    @Test
    func multilineCommandsKeepTheirOriginalArguments() throws {
        let command = "mkdir -p ./build\ncd ./build\ncmake .. && make -j4"
        let detection = try #require(ClipboardAssistantDetector.detect(text: command, enabledKinds: allKinds, shellCommandExists: commandExists))
        #expect(detection.action?.identifier == "runShellCommand")
        #expect(detection.fullContent == command)
        #expect(detection.detail == .codeLines(3))
    }

    @Test(arguments: [
        "", "   ", "hello world", "Please run git status", "git status\nOn branch main",
        "import Foundation", "print(\"hello\")", "printf(\"hello\")", "{\"command\":\"git status\"}",
        "https://example.com/install.sh", "/tmp/example.sh",
        "echo hello\u{0000}world", "echo hello\u{001B}[2J",
    ])
    func doesNotOfferExecutionForOtherContent(input: String) {
        let detection = ClipboardAssistantDetector.detect(text: input, enabledKinds: allKinds, shellCommandExists: commandExists)
        #expect(detection?.actions.contains { $0.identifier == "runShellCommand" } != true)
    }

    @Test
    func rejectsIncompleteOrNonShellFencesAndOversizedCommands() {
        let fence = String(repeating: "\u{0060}", count: 3)
        for input in [
            "\(fence)bash\n", "\(fence)bash\n\(fence)", "\(fence)bash\ngit status",
            "\(fence)python\nprint('hello')\n\(fence)",
            "echo " + String(repeating: "x", count: 20_000),
        ] {
            let detection = ClipboardAssistantDetector.detect(text: input, enabledKinds: allKinds, shellCommandExists: commandExists)
            #expect(detection?.actions.contains { $0.identifier == "runShellCommand" } != true)
        }
    }

    @Test
    func honorsTheSeparateShellRecognitionSetting() throws {
        let detection = ClipboardAssistantDetector.detect(
            text: "git status", enabledKinds: Set(allKinds.filter { $0.rawValue != "shellCommand" }),
            shellCommandExists: commandExists
        )
        #expect(detection?.actions.contains { $0.identifier == "runShellCommand" } != true)
        let codeDisabled = try #require(ClipboardAssistantDetector.detect(
            text: "git status", enabledKinds: allKinds.subtracting([.code]), shellCommandExists: commandExists
        ))
        #expect(codeDisabled.action == .runShellCommand("git status"))
    }

    @Test
    func explicitShellBlocksAllowScriptsWithoutRewritingTheirContents() throws {
        let fence = String(repeating: "\u{0060}", count: 3)
        let script = "for item in one two; do\n  printf '%s\\n' \"$item\"\ndone"
        #expect(shellCommand(from: "\(fence)sh\n\(script)\n\(fence)") == script)
        #expect(shellCommand(from: "$ custom-cli --help") == "custom-cli --help")
        #expect(shellCommand(from: "git status\r\npwd") == "git status\npwd")
        #expect(shellCommand(from: "  git status  ") == "git status")
        #expect(shellCommand(from: "git status\rpwd") == nil)
        #expect(shellCommand(from: "echo hello\u{000B}") == nil)
        #expect(shellCommand(from: "#!/usr/bin/python3\nprint('hello')") == nil)
        #expect(shellCommand(from: "\(fence)sh\n# just a comment\n\(fence)") == nil)
    }

    @Test
    func boundedInputsPreserveArgumentsAndRejectControlCharacters() {
        var seed: UInt64 = 0x5E11
        let alphabet = Array("abcXYZ019 '\"$\\;&|<>()[]{}中文")
        for index in 0..<64 {
            let argument = String((0..<48).map { _ in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return alphabet[Int(seed % UInt64(alphabet.count))]
            })
            let command = "echo " + argument + "x"
            #expect(shellCommand(from: command) == command)
            let control = String(UnicodeScalar(index % 8)!)
            #expect(shellCommand(from: command + control) == nil)
        }
        let boundary = "echo " + String(repeating: "x", count: 19_995)
        #expect(shellCommand(from: boundary) == boundary)
        #expect(shellCommand(from: boundary + "x") == nil)
    }

    @Test(arguments: ["git status", "z code", "ll", "my-custom-tool --help", "$ missing-tool --help"])
    func onlyTheShellDecidesWhetherACommandNameExists(text: String) {
        #expect(ClipboardAssistantDetector.shellCommand(from: text, commandExists: { _ in false }) == nil)
        let expected = text.hasPrefix("$ ") ? String(text.dropFirst(2)) : text
        #expect(ClipboardAssistantDetector.shellCommand(from: text, commandExists: { _ in true }) == expected)
    }

    @Test(arguments: [
        "z code 2>&1", "z code &>output", "z code |& ll", "z code && ll &&",
        "z code && ll |", "z code && ll '", "z code && ll\\",
    ])
    func knownCommandHeadsDoNotDependOnTailHeuristics(text: String) {
        #expect(shellCommand(from: text) == text)
    }

    @Test
    func onlyLooksUpTheFirstCommandOfEachLogicalLine() {
        var names: [String] = []
        let text = "MODE=dev z code && ll\npwd | unknown-filter --flag"
        #expect(ClipboardAssistantDetector.shellCommand(from: text, commandExists: {
            names.append($0)
            return true
        }) == text)
        #expect(names == ["z", "pwd"])
    }

    private func shellCommand(from text: String) -> String? {
        ClipboardAssistantDetector.shellCommand(from: text, commandExists: commandExists)
    }

    private func commandExists(_ name: String) -> Bool {
        // A deterministic shell fixture keeps parser tests independent of the machine's installed tools.
        ["ls", "pwd", "git", "npm", "brew", "make", "curl", "cd", "open", "find", "printf", "echo",
         "mkdir", "cmake", "z", "my-tool", "other-tool", "jump", "repo", "croot", "deploy", "custom-cli",
         "/usr/bin/printf", "./build.sh"].contains(name)
    }
}
