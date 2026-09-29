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
        "./build.sh --release",
        "open -a Safari", "open /tmp", "open ./file", "open ~/Downloads",
        "printf '%s\\n' '你好，世界'",
    ])
    func offersExecutionForShellCommands(command: String) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: command, enabledKinds: allKinds
        ))
        #expect(detection.kind.rawValue == "shellCommand")
        #expect(detection.action == .runShellCommand(command))
        #expect(detection.fullContent == command)
        #expect(detection.actions.contains(.saveText(command)))
        #expect(detection.actions.contains(.search(command)))
        #expect(detection.actions.map(\.identifier).contains("runShellCommandInBackground"))
    }

    @Test(arguments: ["$ git status", "% git status"])
    func removesASingleCopiedPrompt(input: String) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(text: input, enabledKinds: allKinds))
        #expect(detection.action?.identifier == "runShellCommand")
        #expect(detection.fullContent == "git status")
    }

    @Test
    func shellFencesAndContinuationsPreserveTheCommand() throws {
        let fence = String(repeating: "\u{0060}", count: 3)
        let command = "curl --request GET \\\n  https://example.com/api"
        for input in [command, "\(fence)bash\n\(command)\n\(fence)"] {
            let detection = try #require(ClipboardAssistantDetector.detect(text: input, enabledKinds: allKinds))
            #expect(detection.action?.identifier == "runShellCommand")
            #expect(detection.fullContent == command)
        }
        let script = "#!/bin/sh\nprintf '%s\\n' hello"
        let detection = try #require(ClipboardAssistantDetector.detect(text: script, enabledKinds: allKinds))
        #expect(detection.action?.identifier == "runShellCommand")
        #expect(detection.fullContent == script)
    }

    @Test
    func multilineCommandsKeepTheirOriginalArguments() throws {
        let command = "mkdir -p ./build\ncd ./build\ncmake .. && make -j4"
        let detection = try #require(ClipboardAssistantDetector.detect(text: command, enabledKinds: allKinds))
        #expect(detection.action?.identifier == "runShellCommand")
        #expect(detection.fullContent == command)
        #expect(detection.detail == .codeLines(3))
    }

    @Test(arguments: [
        "", "   ", "hello world", "Please run git status", "make sure it works",
        "open the settings", "find the right answer", "git status\nOn branch main",
        "import Foundation", "print(\"hello\")", "printf(\"hello\")", "{\"command\":\"git status\"}",
        "https://example.com/install.sh", "/tmp/example.sh",
        "echo hello\u{0000}world", "echo hello\u{001B}[2J",
    ])
    func doesNotOfferExecutionForOtherContent(input: String) {
        let detection = ClipboardAssistantDetector.detect(text: input, enabledKinds: allKinds)
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
            let detection = ClipboardAssistantDetector.detect(text: input, enabledKinds: allKinds)
            #expect(detection?.actions.contains { $0.identifier == "runShellCommand" } != true)
        }
    }

    @Test
    func honorsTheSeparateShellRecognitionSetting() throws {
        let detection = ClipboardAssistantDetector.detect(
            text: "git status", enabledKinds: Set(allKinds.filter { $0.rawValue != "shellCommand" })
        )
        #expect(detection?.actions.contains { $0.identifier == "runShellCommand" } != true)
        let codeDisabled = try #require(ClipboardAssistantDetector.detect(
            text: "git status", enabledKinds: allKinds.subtracting([.code])
        ))
        #expect(codeDisabled.action == .runShellCommand("git status"))
    }

    @Test
    func explicitShellBlocksAllowScriptsWithoutRewritingTheirContents() throws {
        let fence = String(repeating: "\u{0060}", count: 3)
        let script = "for item in one two; do\n  printf '%s\\n' \"$item\"\ndone"
        #expect(ClipboardAssistantDetector.shellCommand(from: "\(fence)sh\n\(script)\n\(fence)") == script)
        #expect(ClipboardAssistantDetector.shellCommand(from: "$ custom-cli --help") == "custom-cli --help")
        #expect(ClipboardAssistantDetector.shellCommand(from: "git status\r\npwd") == "git status\npwd")
        #expect(ClipboardAssistantDetector.shellCommand(from: "  git status  ") == "git status")
        #expect(ClipboardAssistantDetector.shellCommand(from: "git status\rpwd") == nil)
        #expect(ClipboardAssistantDetector.shellCommand(from: "echo hello\u{000B}") == nil)
        #expect(ClipboardAssistantDetector.shellCommand(from: "#!/usr/bin/python3\nprint('hello')") == nil)
        #expect(ClipboardAssistantDetector.shellCommand(from: "\(fence)sh\n# just a comment\n\(fence)") == nil)
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
            #expect(ClipboardAssistantDetector.shellCommand(from: command) == command)
            let control = String(UnicodeScalar(index % 8)!)
            #expect(ClipboardAssistantDetector.shellCommand(from: command + control) == nil)
        }
        let boundary = "echo " + String(repeating: "x", count: 19_995)
        #expect(ClipboardAssistantDetector.shellCommand(from: boundary) == boundary)
        #expect(ClipboardAssistantDetector.shellCommand(from: boundary + "x") == nil)
    }
}
