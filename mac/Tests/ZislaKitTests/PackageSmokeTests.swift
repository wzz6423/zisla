import Testing
@testable import ZislaCore
@testable import ZislaKit

struct PackageSmokeTests {
    @Test
    func bundleIdentifierIsStable() {
        #expect(ZislaKitInfo.bundleIdentifier == "dev.wzz.zisla")
    }

    @Test
    @MainActor
    func coreAndKitPublicSurfacesInitializeWithoutExternalServices() {
        let settings = FeatureSettings()
        var reducer = IslandPresentationReducer()
        let monitor = SystemMonitorService(samplingInterval: 1)

        #expect(settings.clipboardHistoryEnabled)
        #expect(settings.clipboardDetectionEnabled)
        #expect(reducer.start() == [.collapse])
        #expect(reducer.state.visibility == .collapsed)
        #expect(monitor.snapshot == nil)
        #expect(!monitor.isSampling)
    }
}
