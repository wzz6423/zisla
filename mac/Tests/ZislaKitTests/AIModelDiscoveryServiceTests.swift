import Testing
@testable import ZislaKit

struct AIModelDiscoveryServiceTests {
    @Test
    func authorizationHeaderUsesNonEmptyTrimmedAPIKey() {
        #expect(AIModelDiscoveryService.authorizationHeader(for: nil) == nil)
        #expect(AIModelDiscoveryService.authorizationHeader(for: "  ") == nil)
        #expect(AIModelDiscoveryService.authorizationHeader(for: "  sk-test  ") == "Bearer sk-test")
    }
}
