import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct MediaRemoteAdapterWatchdogTests {
    @Test
    func adapterEnvironmentIncludesParentLifecycleKey() {
        let environment = MediaRemoteAdapterClient.parentLifecycleEnvironment()

        #expect(environment[MediaRemoteAdapterClient.parentLifecycleEnvironmentKey] == "1")
        #expect(environment.count >= ProcessInfo.processInfo.environment.count)
    }
}
