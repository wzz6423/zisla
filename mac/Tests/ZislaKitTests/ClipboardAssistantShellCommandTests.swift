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

    @Test
    func hereDocumentsKeepEmbeddedScriptsAndFollowingCommands() throws {
        let command = #"""
        cat > verify.py <<'VERIFY_REVIEW'
        from pathlib import Path
        import re
        from PIL import Image, ImageOps, ImageDraw

        stage = Path('visual')
        pages = sorted(stage.glob('page-*.png'))
        pdf_text = Path('review.txt').read_text()
        segments = [page for page in pdf_text.split('\f') if page.strip()]
        assert len(pages) == len(segments) > 0
        assert not re.search(r'\\(?:frac|mathbf|mathrm)|\$\$|�|file:///|https?://', pdf_text)

        for index, page in enumerate(segments, 1):
            lines = [line.strip() for line in page.splitlines() if line.strip()]
            if len(lines) < 15:
                raise ValueError(f'Page {index} has only {len(lines)} lines: {lines}')
            print(f'{index}: {len(lines)} 行  {lines[0][:66]}')
        compact = re.sub(r'\s+', '', pdf_text)
        for s in ['第12题', '五段指令流水线', '最低位密度', '根', '491520', '97.5',
                  '3.75', '75%', 'S1关中断', 'S2设备服务', 'S3开中断', 'T1中断周期', 'T2中断服务']:
            assert s in compact, s

        for start in range(0, len(pages), 5):
            sheet = Image.new('RGB', (1458, 1440), '#ededed')
            draw = ImageDraw.Draw(sheet)
            for index, page in enumerate(pages[start:start+5]):
                im = ImageOps.contain(Image.open(page), (464, 656))
                x = (index % 3) * 486 + 11
                y = (index // 3) * 705 + 14
                draw.text((x, y), str(start+index+1), fill='#333333')
                sheet.paste(im, (x, y+19))
            sheet.save(stage/f'overview-{start//5+1}.jpg', quality=93)
        VERIFY_REVIEW
        stat -f '%N %z' noto-*.otf
        """#
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: command, enabledKinds: allKinds, shellCommandExists: commandExists
        ))
        #expect(detection.kind == .shellCommand)
        #expect(detection.fullContent == command)
        #expect(detection.actions == [
            .runShellCommand(command), .runShellCommandInBackground(command), .search(command), .saveText(command),
        ])
        #expect(detection.detail == .codeLines(command.split(separator: "\n").count))
    }

    @Test
    func copiedHereDocumentWithEscapedLinesKeepsItsExactContents() throws {
        let command = #"""
        cat > verify.py <<'VERIFY_REVIEW'\\\
        from pathlib import Path\\\
        import re\\\
        from PIL import Image, ImageOps, ImageDraw\\\
        \\\
        stage = Path('visual')\\\
        pages = sorted(stage.glob('page-\\\*.png'))\\\
        pdf_text = Path('review\\.txt').read_text()\\\
        segments = [page for page in pdf_text.split('\f') if page.strip()]\\\
        assert len(pages) == len(segments) > 0\\\
        assert not re.search(r'\\\\\\\\(?:frac|mathbf|mathrm)|\\\\$\\\\$|�|file:///|https?://', pdf_text)\\\
        \\\
        for index, page in enumerate(segments, 1):\\\
        &#x20;   lines = [line.strip() for line in page.splitlines() if line.strip()]\\\
        &#x20;   if len(lines) < 15:\\\
        &#x20;       raise ValueError(f'Page {index} has only {len(lines)} lines: {lines}')\\\
        &#x20;   print(f'{index}: {len(lines)} 行  {lines[0][:66]}')\\\
        compact = re.sub(r'\s+','"''"',pdf_text)\\\
        for s in ['第12题','五段指令流水线','最低位密度','根','491520','97.5','3.75','75%',\\\
        &#x20;         'S1关中断','S2设备服务','S3开中断','T1中断周期','T2中断服务']:\\\
        &#x20;   assert s in compact, s\\\
        \\\
        for start in range(0,len(pages),5):\\\
        &#x20;   sheet=Image.new('RGB',(1458,1440),'#ededed')\\\
        &#x20;   draw=ImageDraw\\.Draw(sheet)\\\
        &#x20;   for index,page in enumerate(pages[start:start+5]):\\\
        &#x20;       im=ImageOps.contain(Image.open(page),(464,656))\\\
        &#x20;       x=(index%3)\\\*486+11\\\
        &#x20;       y=(index//3)\\\*705+14\\\
        &#x20;       draw\\.text((x,y),str(start+index+1),fill='#333333')\\\
        &#x20;       sheet.paste(im,(x,y+19))\\\
        &#x20;   sheet.save(stage/f'overview-{start//5+1}.jpg',quality=93)\\\
        VERIFY_REVIEW\\\
        stat -f '%N %z' noto-\\\*.otf\
        """#
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: command, enabledKinds: allKinds, shellCommandExists: commandExists
        ))
        #expect(detection.kind == .shellCommand)
        #expect(detection.fullContent == command)
        #expect(detection.actions == [
            .runShellCommand(command), .runShellCommandInBackground(command), .search(command), .saveText(command),
        ])
    }

    @Test(arguments: [1, 2, 3])
    func copiedLineEscapesDoNotReplaceCommandEvidence(backslashes: Int) {
        let suffix = String(repeating: "\\", count: backslashes)
        let command = ["cat <<'PY'", "from pathlib import Path", "&#x20;   print('hello')", "PY", "stat -f '%N %z' noto-*.otf"]
            .map { $0 + suffix }.joined(separator: "\n")
        #expect(shellCommand(from: command) == command)
        #expect(shellCommand(from: command.replacingOccurrences(of: "cat <<", with: "missing-command <<")) == nil)
        #expect(shellCommand(from: command.replacingOccurrences(of: "\nPY" + suffix, with: "\nWRONG" + suffix)) == nil)
        #expect(shellCommand(from: command + "\nmissing-command" + suffix) == nil)
    }

    @Test(arguments: [
        ("<<EOF", "EOF"), ("<< 'EOF'", "EOF"), ("<<\"EOF\"", "EOF"),
        ("<<\\EOF", "EOF"), ("<<E\"OF\"", "EOF"), ("<<'END OF SCRIPT'", "END OF SCRIPT"),
        ("<<-EOF", "\tEOF"), ("<<-'EOF'", "\t\tEOF"), ("<<''", ""),
        ("<<\"E\\OF\"", "E\\OF"),
    ])
    func hereDocumentDelimitersFollowShellQuotingAndTabRules(header: String, ending: String) {
        let command = "cat \(header)\n\tprint('hello')\n\n# payload\n\(ending)\npwd"
        #expect(shellCommand(from: command) == command)
    }

    @Test
    func hereDocumentsAreConsumedInOrderWithoutLookingUpTheirBodies() {
        let command = "cat <<FIRST <<'SECOND'\ncat <<IGNORED\nFIRST\nprint('hello')\nSECOND\npwd"
        var names: [String] = []
        #expect(ClipboardAssistantDetector.shellCommand(from: command, commandExists: {
            names.append($0)
            return commandExists($0)
        }) == command)
        #expect(names == ["cat", "pwd"])
        let continued = "cat > verify.py \\\n  <<'PY'\nprint('hello')\\\nPY\npwd"
        #expect(shellCommand(from: continued) == continued)
    }

    @Test(arguments: [
        "cat <<''\npayload\n\n", "cat <<'EOF '\npayload\nEOF ",
        "cat <<'EOF'\nprint('hello')\nEOF\n", "cat <<EOF\nEO\\\nF\npwd",
        "cat <<EOF\npayload\\\\\nEOF\npwd",
        "cat <<-EOF\nEO\\\n\tF\nEOF\npwd",
        "cat <<EO\\\nF\npayload\nEOF\npwd", "cat <<EOF\\ \npayload\nEOF \npwd",
        "echo ${value:-{} <<'EOF'\nnot-a-command\nEOF\npwd",
    ])
    func hereDocumentEndingsKeepSignificantWhitespaceAndUnquotedContinuations(command: String) {
        #expect(shellCommand(from: command) == command)
    }

    @Test(arguments: [
        "cat <<EOF\necho payload", "cat <<EOF\necho payload\n EOF\npwd",
        "cat <<EOF\necho payload\nEOF \npwd", "cat <<EOF\necho payload\n\tEOF\npwd",
        "cat <<FIRST <<SECOND\necho payload\nFIRST", "cat <<EOF\nEOF\nmissing-command",
        "missing-command <<EOF\nprint('hello')\nEOF", "cat <<\npwd",
        "cat '<<EOF'\nprint('hello')\nEOF", "cat \"<<EOF\"\nprint('hello')\nEOF",
        "cat \\<<EOF\nprint('hello')\nEOF", "cat # <<EOF\nprint('hello')\nEOF",
        "cat <<<EOF\nprint('hello')\nEOF", "echo $((1 << 2))\nprint('hello')\nEOF",
        "cat <<EOF\necho payload\u{0000}\nEOF", "cat <<;\npwd\n;\npwd",
        "cat << #comment\necho payload\n#comment\npwd", "cat <<'EOF'\nEO\\\nF\npwd",
        "cat <<EOF\nEO\\\\\nF\npwd",
    ])
    func incompleteOrQuotedHereDocumentLookalikesDoNotOfferExecution(command: String) {
        #expect(shellCommand(from: command) == nil)
    }

    @Test(arguments: [
        "echo '<<EOF'\npwd", "echo \"<<EOF\"\npwd", "echo \\<<EOF\npwd",
        "echo value # <<EOF\npwd", "cat <<<EOF\npwd", "echo $((1 << 2))\npwd",
        "echo result=$((1 << 2))\npwd", "echo $((1 << 2)).txt\npwd",
        "echo $(((1 + (1 << 2)) << 3))\npwd", "echo ${value:-<<EOF}\npwd",
        "echo ${value:-${other:-<<EOF}}\npwd", "echo $(echo '<<EOF')\npwd",
        "echo `echo '<<EOF'`\npwd", "echo '$((1'\npwd", "echo '${value:-<<EOF}'\npwd",
        "echo \"$(echo \"<<EOF\")\"\npwd", "echo \"${value:-\"<<EOF\"}\"\npwd",
    ])
    func quotedOperatorsCommentsAndHereStringsKeepOrdinaryCommandRecognition(command: String) {
        #expect(shellCommand(from: command) == command)
    }

    @Test
    func hereDocumentPayloadsStayOpaqueAcrossBoundedInputs() {
        var seed: UInt64 = 0xD0C
        let alphabet = Array("abc019 '\"$\\;&|<>()[]{}#\t中文")
        for index in 0..<32 {
            let payload = String((0..<48).map { _ in
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return alphabet[Int(seed % UInt64(alphabet.count))]
            })
            let delimiter = "PAYLOAD_\(index)"
            let command = "cat <<'\(delimiter)'\n\(payload)\n\(delimiter)\npwd"
            #expect(shellCommand(from: command) == command)
            #expect(shellCommand(from: command.replacingOccurrences(of: "\n\(delimiter)\n", with: "\nWRONG\n")) == nil)
        }
        let prefix = "cat <<'EOF'\n"
        let suffix = "\nEOF\npwd"
        let boundary = prefix + String(repeating: "x", count: 20_000 - prefix.utf8.count - suffix.utf8.count) + suffix
        #expect(shellCommand(from: boundary) == boundary)
        #expect(shellCommand(from: boundary + "x") == nil)
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
        ["ls", "pwd", "git", "npm", "brew", "make", "curl", "cd", "open", "find", "printf", "echo", "cat", "stat",
         "mkdir", "cmake", "z", "my-tool", "other-tool", "jump", "repo", "croot", "deploy", "custom-cli",
         "/usr/bin/printf", "./build.sh"].contains(name)
    }
}
