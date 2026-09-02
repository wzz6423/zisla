import Foundation
import Sparkle
import Testing

@testable import Zisla

@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["ZISLA_RUN_NETWORK_UPDATE_TESTS"] == "1")
)
@MainActor
struct SparkleUpdateIntegrationTests {
    @Test
    func realSparkleCheckReportsCurrentFromPrimaryAppcast() async throws {
        let primaryURL = try Self.signedFixtureAppcastURL
        let fallbackURL = try #require(URL(string: "https://httpbin.org/status/500"))

        let harness = try SparkleIntegrationHarness(
            feeds: SparkleFeedPair(gitee: primaryURL, github: fallbackURL),
            installedVersion: "0.1.8",
            installedBuild: "14",
            updateChoice: .dismiss
        )
        defer { harness.cleanup() }

        try harness.checkForUpdates()
        try await harness.waitUntil {
            harness.userDriver.didReportNoUpdate || harness.finalCheckError != nil
        }

        #expect(harness.userDriver.didReportNoUpdate)
        #expect(harness.userDriver.foundVersion == nil)
        #expect(harness.userDriver.updaterErrors.isEmpty)
        #expect(harness.finalCheckError == nil, "\(String(describing: harness.finalCheckError))")
        #expect(harness.fallbackRequestCount == 0)
    }

    @Test
    func realSparkleCheckFallsBackAfterPrimaryAppcastFailureAndFindsUpdate() async throws {
        let primaryURL = try #require(URL(string: "https://httpbin.org/status/404"))
        let fallbackURL = try Self.signedFixtureAppcastURL

        let harness = try SparkleIntegrationHarness(
            feeds: SparkleFeedPair(gitee: primaryURL, github: fallbackURL),
            installedVersion: "0.1.7",
            installedBuild: "13",
            updateChoice: .dismiss
        )
        defer { harness.cleanup() }

        try harness.checkForUpdates()
        try await harness.waitUntil {
            harness.userDriver.foundVersion == "0.1.8" || harness.finalCheckError != nil
        }

        #expect(harness.userDriver.foundVersion == "0.1.8")
        #expect(harness.userDriver.didReportNoUpdate == false)
        #expect(harness.userDriver.updaterErrors.isEmpty)
        #expect(harness.finalCheckError == nil, "\(String(describing: harness.finalCheckError))")
        #expect(harness.fallbackRequestCount == 1)
    }

    private static var signedFixtureAppcastURL: URL {
        get throws {
            let base64 = signedFixtureAppcastBase64
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let encoded = base64.addingPercentEncoding(withAllowedCharacters: allowed)
            return try #require(encoded.flatMap { URL(string: "https://httpbin.org/base64/\($0)") })
        }
    }

    private static let signedFixtureAppcastBase64 = """
    PD94bWwgdmVyc2lvbj0iMS4wIiBzdGFuZGFsb25lPSJ5ZXMiPz48IS0tIHNwYXJrbGUtc2lnbi13YXJuaW5nOgpJTVBPUlRBTlQ6IFRoaXMgZmlsZSB3YXMgc2lnbmVkIGJ5IFNwYXJrbGUuIEFueSBtb2RpZmljYXRpb25zIHRvIHRoaXMgZmlsZSByZXF1aXJlcyByZS1zaWduaW5nIHRoaXMgZmlsZSB3aXRoIGdlbmVyYXRlX2FwcGNhc3Qgb3Igc2lnbl91cGRhdGUhIFRoZSBzaWduZWQgc2lnbmF0dXJlIHdpbGwgYmUgZW1iZWRkZWQgYXQgdGhlIGVuZCBvZiB0aGlzIGZpbGUuCi0tPjxyc3MgeG1sbnM6c3BhcmtsZT0iaHR0cDovL3d3dy5hbmR5bWF0dXNjaGFrLm9yZy94bWwtbmFtZXNwYWNlcy9zcGFya2xlIiB2ZXJzaW9uPSIyLjAiPgogICAgPGNoYW5uZWw+CiAgICAgICAgPHRpdGxlPnppc2xhLXRlc3Q8L3RpdGxlPgogICAgICAgIDxpdGVtPgogICAgICAgICAgICA8dGl0bGU+MC4xLjg8L3RpdGxlPgogICAgICAgICAgICA8cHViRGF0ZT5UdWUsIDAxIFNlcCAyMDI2IDE3OjU4OjI2ICswODAwPC9wdWJEYXRlPgogICAgICAgICAgICA8c3BhcmtsZTp2ZXJzaW9uPjE0PC9zcGFya2xlOnZlcnNpb24+CiAgICAgICAgICAgIDxzcGFya2xlOnNob3J0VmVyc2lvblN0cmluZz4wLjEuODwvc3BhcmtsZTpzaG9ydFZlcnNpb25TdHJpbmc+CiAgICAgICAgICAgIDxzcGFya2xlOm1pbmltdW1TeXN0ZW1WZXJzaW9uPjE0LjA8L3NwYXJrbGU6bWluaW11bVN5c3RlbVZlcnNpb24+CiAgICAgICAgICAgIDxlbmNsb3N1cmUgdXJsPSJodHRwczovL2Rvd25sb2Fkcy56aXNsYS50ZXN0L3ppc2xhLXYwLjEuOC1tYWNPUy11bml2ZXJzYWwuemlwIiBsZW5ndGg9IjEyOTEiIHR5cGU9ImFwcGxpY2F0aW9uL29jdGV0LXN0cmVhbSIgc3BhcmtsZTplZFNpZ25hdHVyZT0iRjF6MGdYOGphalZRMjNGOTNBV3pUV003Tnp4dVc4SEY2VTFxRHJPaWlObGhvampidUFGUlYyOGRTM0ltNlVZcGNWY2tXL3hSNmVkdzU3MWpPUEc3Q0E9PSI+PC9lbmNsb3N1cmU+CiAgICAgICAgPC9pdGVtPgogICAgPC9jaGFubmVsPgo8L3Jzcz48IS0tIHNwYXJrbGUtc2lnbmF0dXJlczoKZWRTaWduYXR1cmU6IFQvNGJNNDlOQ3pONE1rQnFiaHNvYnEvVlhGUTNDY3d6QURkTktYYUpQUDJ1NnJVT2prczBNNWppZzNBY1ZiWW0zN0NXUzYzdXM0c2huOHdWeUZwcEJnPT0KbGVuZ3RoOiAxMDIyCi0tPgo=
    """
}

@MainActor
private final class SparkleIntegrationHarness {
    let userDriver: SparkleIntegrationUserDriver
    private(set) var fallbackRequestCount = 0
    private(set) var finalCheckError: Error?

    private let rootURL: URL
    private let updater: SPUUpdater
    private let updaterDelegate: SparkleFeedDelegate

    init(
        feeds: SparkleFeedPair,
        installedVersion: String,
        installedBuild: String,
        updateChoice: SPUUserUpdateChoice
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-sparkle-integration-\(UUID().uuidString)", isDirectory: true)
        let bundle = try Self.makeApplicationBundle(
            in: rootURL,
            feedURL: feeds.gitee,
            installedVersion: installedVersion,
            installedBuild: installedBuild
        )
        let delegate = SparkleFeedDelegate(feeds: feeds)
        let driver = SparkleIntegrationUserDriver(
            hostBundle: bundle,
            updateChoice: updateChoice,
            shouldSuppressUpdaterError: { [weak delegate] in
                delegate?.shouldSuppressUpdaterError == true
            }
        )
        userDriver = driver
        updaterDelegate = delegate
        updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: userDriver,
            delegate: updaterDelegate
        )

        updaterDelegate.onFallbackRequested = { [weak updater] updateCheck in
            guard let updater else { return }
            self.fallbackRequestCount += 1
            switch updateCheck {
            case .updates:
                updater.checkForUpdates()
            case .updatesInBackground:
                updater.checkForUpdatesInBackground()
            case .updateInformation:
                updater.checkForUpdateInformation()
            @unknown default:
                updater.checkForUpdateInformation()
            }
        }
        updaterDelegate.onCheckFailed = { error in
            self.finalCheckError = error
        }
    }

    func checkForUpdates() throws {
        try updater.start()
        updater.checkForUpdates()
    }

    func waitUntil(
        timeout: Duration = .seconds(8),
        condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard condition() else {
            throw SparkleIntegrationError.timedOut(
                fallbackRequestCount: fallbackRequestCount,
                updaterErrors: userDriver.updaterErrors,
                finalCheckError: finalCheckError
            )
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func makeApplicationBundle(
        in rootURL: URL,
        feedURL: URL,
        installedVersion: String,
        installedBuild: String
    ) throws -> Bundle {
        let contentsURL = rootURL.appendingPathComponent("zisla-test.app/Contents", isDirectory: true)
        let executableURL = contentsURL.appendingPathComponent("MacOS/zisla-test")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let infoDictionary: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": "zisla Sparkle Integration Test",
            "CFBundleExecutable": "zisla-test",
            "CFBundleIdentifier": "dev.wzz.zisla.sparkle-test.\(UUID().uuidString)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "zisla-test",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": installedVersion,
            "CFBundleVersion": installedBuild,
            "LSMinimumSystemVersion": "14.0",
            "SUEnableAutomaticChecks": false,
            "SUFeedURL": feedURL.absoluteString,
            "SUPublicEDKey": "RTy+qQHkv0VMQ/6VS/D/oyzOdRmRld7+3nqUywhuqNI=",
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: infoDictionary,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: contentsURL.deletingLastPathComponent()))
    }
}

@MainActor
private final class SparkleIntegrationUserDriver: SparkleStandardUserDriver {
    var foundVersion: String?
    var didReportNoUpdate = false
    var updaterErrors: [Error] = []

    private let updateChoice: SPUUserUpdateChoice

    init(
        hostBundle: Bundle,
        updateChoice: SPUUserUpdateChoice,
        shouldSuppressUpdaterError: @escaping () -> Bool
    ) {
        self.updateChoice = updateChoice
        super.init(
            hostBundle: hostBundle,
            shouldSuppressUpdaterError: shouldSuppressUpdaterError
        )
        onUpdaterErrorPresented = { [weak self] error in
            self?.updaterErrors.append(error)
        }
    }

    override func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }

    override func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    override func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        foundVersion = appcastItem.displayVersionString
        reply(updateChoice)
    }

    override func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    override func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    override func showUpdateNotFoundWithError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        didReportNoUpdate = true
        acknowledgement()
    }

    override func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    override func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    override func showDownloadDidReceiveData(ofLength length: UInt64) {}
    override func showDownloadDidStartExtractingUpdate() {}
    override func showExtractionReceivedProgress(_ progress: Double) {}

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.dismiss)
    }

    override func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {}

    override func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    override func dismissUpdateInstallation() {}
}

private enum SparkleIntegrationError: Error {
    case timedOut(fallbackRequestCount: Int, updaterErrors: [Error], finalCheckError: Error?)
}
