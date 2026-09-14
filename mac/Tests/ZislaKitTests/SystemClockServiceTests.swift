import AppKit
import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct SystemClockServiceTests {
    @Test(arguments: [
        (SystemClockService.Destination.timer, "clock-timer://"),
        (SystemClockService.Destination.alarm, "clock-alarm://"),
    ])
    func opensRequestedPageInSystemClock(
        destination: SystemClockService.Destination,
        expectedURL: String
    ) async throws {
        var requestedURLs: [URL] = []
        var requestedApplication: URL?

        try await SystemClockService.open(destination) { urls, application, configuration in
            requestedURLs = urls
            requestedApplication = application
            #expect(configuration.activates)
            #expect(!configuration.createsNewApplicationInstance)
        }

        #expect(requestedURLs.map(\.absoluteString) == [expectedURL])
        #expect(requestedApplication?.path == "/System/Applications/Clock.app")
    }

    @Test(arguments: [
        CocoaError.Code.fileNoSuchFile,
        .fileReadNoPermission,
        .featureUnsupported,
    ])
    func openingFailureReachesCaller(code: CocoaError.Code) async {
        let failure = CocoaError(code)

        do {
            try await SystemClockService.open(.timer) { _, _, _ in
                throw failure
            }
            Issue.record("系统时钟启动失败时应将错误交给调用方显示")
        } catch {
            #expect((error as NSError).domain == NSCocoaErrorDomain)
            #expect((error as NSError).code == failure.errorCode)
        }
    }
}
