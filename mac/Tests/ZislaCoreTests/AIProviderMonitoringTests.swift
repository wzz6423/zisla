import Foundation
import Testing
@testable import ZislaCore

struct AIProviderMonitoringTests {
    @Test func addedSourcesHaveStableEncodingAndKeepGrokCLISeparateFromBot() throws {
        for (token, provider) in [("cursor", AIProvider.cursor), ("Cursor-IDE", .cursor),
                                  ("grok bot", .grokBot), ("grok-bot", .grokBot), ("sand", .grokBot),
                                  ("muse-code", .muse), ("grok", .grok), ("claude", .claude)] {
            #expect(AIProvider(token: token) == provider)
            #expect(try JSONDecoder().decode(AIProvider.self, from: JSONEncoder().encode(provider)) == provider)
        }
        #expect(AIProvider.grok.rawValue == "grok" && AIProvider.grokBot.rawValue == "grok-bot")
        #expect(AIProvider(token: "today") == nil && AIProvider(token: "dots") == nil)
    }
}
