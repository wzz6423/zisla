import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

@Suite(.serialized)
struct AIAgentCLIUpdateServiceTests {
    @Test
    func reportsOnlyInstalledNPMCLIsWithNewerSemanticVersions() async {
        let service = AIAgentCLIUpdateService { kind in
            switch kind {
            case .codex: "1.2.0"
            case .claude: "2.1.181"
            case .gemini: "0.9.0"
            case .grok, .opencode: nil
            }
        }

        let updates = await service.availableUpdates(for: [
            AgentCLIStatus(kind: .codex, executablePath: "/usr/local/bin/codex", version: "1.1.0"),
            AgentCLIStatus(kind: .claude, executablePath: "/usr/local/bin/claude", version: "2.1.181 (Claude Code)"),
            AgentCLIStatus(kind: .gemini),
            AgentCLIStatus(kind: .grok, executablePath: "/usr/local/bin/grok", version: "1.0.0"),
        ])

        #expect(updates == [
            AIAgentCLIUpdate(kind: .codex, installedVersion: "1.1.0", latestVersion: "1.2.0"),
        ])
    }

    @Test
    func skipsInvalidOrNonNewerVersions() async {
        let service = AIAgentCLIUpdateService { kind in
            kind == .claude ? "2.0.0" : nil
        }

        let updates = await service.availableUpdates(for: [
            AgentCLIStatus(kind: .claude, executablePath: "/usr/local/bin/claude", version: "not-a-version"),
            AgentCLIStatus(kind: .codex, executablePath: "/usr/local/bin/codex", version: "1.0.0"),
        ])

        #expect(updates.isEmpty)
    }
}
