import CryptoKit
import Foundation
import Sparkle
import Testing

@testable import Zisla

// This suite drives downloading, verifying, extracting and swapping signed builds against a
// throwaway EdDSA key and a loopback server. Published feed availability remains a separate
// release-time check.
@Suite(
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["ZISLA_RUN_LOCAL_INSTALL_TESTS"] == "1")
)
@MainActor
struct SparkleLocalInstallIntegrationTests {
    @Test
    func realSparkleInstallsAnAdHocSignedUpdateInPlace() async throws {
        let harness = try SparkleLocalInstallHarness(
            installedVersion: "0.1.8",
            installedBuild: "14",
            updateVersion: "0.1.9",
            updateBuild: "15"
        )
        defer { harness.cleanup() }

        #expect(harness.installedShortVersion == "0.1.8")

        try harness.checkForUpdates()
        try await harness.waitUntil(timeout: .seconds(120)) {
            harness.installedShortVersion == "0.1.9" || harness.userDriver.updaterErrors.isEmpty == false
        }

        #expect(
            harness.userDriver.updaterErrors.isEmpty,
            "\(harness.userDriver.updaterErrors)"
        )
        #expect(harness.userDriver.foundVersion == "0.1.9")
        #expect(harness.installedShortVersion == "0.1.9")
        #expect(harness.installedBuildVersion == "15")
        // The swap must keep a valid ad-hoc signature, or macOS refuses to launch what
        // Sparkle just installed.
        #expect(try harness.installedBundleSignatureIsValid())
    }

    // An ad-hoc signature makes TCC key its grants on a cdhash, so every update looks like a
    // different program and the permission has to be granted again. Signing with one stable
    // certificate fixes that, but the release that introduces it updates hosts that are still
    // ad-hoc signed, and Sparkle compares the host's signature against the update's. If it
    // refuses the mismatch, that one release has to be installed by hand.
    @Test(.enabled(if: SparkleLocalInstallTestSigning.fromEnvironment != nil))
    func realSparkleInstallsACertificateSignedUpdateOntoAnAdHocHost() async throws {
        let signing = try #require(SparkleLocalInstallTestSigning.fromEnvironment)
        let harness = try SparkleLocalInstallHarness(
            installedVersion: "0.1.8",
            installedBuild: "14",
            updateVersion: "0.1.9",
            updateBuild: "15",
            updateSigning: signing
        )
        defer { harness.cleanup() }

        try harness.checkForUpdates()
        try await harness.waitUntil(timeout: .seconds(120)) {
            harness.installedShortVersion == "0.1.9" || harness.userDriver.updaterErrors.isEmpty == false
        }

        #expect(
            harness.userDriver.updaterErrors.isEmpty,
            "\(harness.userDriver.stages) \(harness.userDriver.updaterErrors)"
        )
        #expect(harness.installedShortVersion == "0.1.9")
        #expect(try harness.installedBundleSignatureIsValid())
        // The whole point of the switch: what TCC keys on must stop being a cdhash.
        let requirement = try harness.installedDesignatedRequirement()
        #expect(requirement.contains("certificate"), "\(requirement)")
        #expect(!requirement.contains("cdhash"), "\(requirement)")
    }
}

// The transition starts from an ad-hoc host. The new release identity is supplied through
// the environment so the certificate itself never has to live in the repository.
private enum SparkleLocalInstallTestSigning {
    case adHoc
    case identity(name: String, keychain: String?)

    static var fromEnvironment: SparkleLocalInstallTestSigning? {
        let environment = ProcessInfo.processInfo.environment
        guard let name = environment["ZISLA_TEST_SIGNING_IDENTITY"], !name.isEmpty else {
            return nil
        }
        let keychain = environment["ZISLA_TEST_SIGNING_KEYCHAIN"]
        return .identity(name: name, keychain: (keychain?.isEmpty ?? true) ? nil : keychain)
    }

    var codesignArguments: [String] {
        switch self {
        case .adHoc:
            return ["--sign", "-"]
        case let .identity(name, keychain):
            var arguments = ["--sign", name]
            if let keychain {
                arguments += ["--keychain", keychain]
            }
            return arguments
        }
    }
}

@MainActor
private final class SparkleLocalInstallHarness {
    let userDriver: SparkleLocalInstallUserDriver

    private let rootURL: URL
    private let installedBundleURL: URL
    private let server: Process
    private let updater: SPUUpdater

    init(
        installedVersion: String,
        installedBuild: String,
        updateVersion: String,
        updateBuild: String,
        updateSigning: SparkleLocalInstallTestSigning = .adHoc
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-sparkle-install-\(UUID().uuidString)", isDirectory: true)
        let servedURL = rootURL.appendingPathComponent("served", isDirectory: true)
        try FileManager.default.createDirectory(at: servedURL, withIntermediateDirectories: true)

        let signingKey = Curve25519.Signing.PrivateKey()
        let publicKey = signingKey.publicKey.rawRepresentation.base64EncodedString()

        // The update ships from a staging directory so the archive carries the same
        // `zisla.app` name a release archive does.
        let stagingURL = rootURL.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        let updateBundleURL = try Self.makeSignedBundle(
            at: stagingURL.appendingPathComponent("zisla.app", isDirectory: true),
            shortVersion: updateVersion,
            build: updateBuild,
            bundleIdentifier: Self.bundleIdentifier,
            feedURL: nil,
            publicKey: publicKey,
            signing: updateSigning
        )
        let archiveName = "zisla-v\(updateVersion)-macOS-universal.zip"
        let archiveURL = servedURL.appendingPathComponent(archiveName)
        try Self.archive(updateBundleURL, to: archiveURL)
        try FileManager.default.removeItem(at: stagingURL)

        let port = try Self.freePort()
        let archiveSignature = try signingKey
            .signature(for: Data(contentsOf: archiveURL))
            .base64EncodedString()
        try Self.appcast(
            version: updateVersion,
            build: updateBuild,
            enclosure: "http://127.0.0.1:\(port)/\(archiveName)",
            length: try Self.fileSize(of: archiveURL),
            signature: archiveSignature
        ).write(to: servedURL.appendingPathComponent("appcast.xml"), atomically: true, encoding: .utf8)

        installedBundleURL = try Self.makeSignedBundle(
            at: rootURL.appendingPathComponent("zisla.app", isDirectory: true),
            shortVersion: installedVersion,
            build: installedBuild,
            bundleIdentifier: Self.bundleIdentifier,
            feedURL: "http://127.0.0.1:\(port)/appcast.xml",
            publicKey: publicKey,
            signing: .adHoc
        )

        server = try Self.startServer(root: servedURL, port: port)
        let bundle = try #require(Bundle(url: installedBundleURL))
        userDriver = SparkleLocalInstallUserDriver(hostBundle: bundle)
        updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: userDriver,
            delegate: nil
        )
    }

    func checkForUpdates() throws {
        try updater.start()
        updater.checkForUpdates()
    }

    func waitUntil(timeout: Duration, condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard condition() else {
            throw SparkleLocalInstallError.timedOut(
                stage: userDriver.stages,
                updaterErrors: userDriver.updaterErrors
            )
        }
    }

    // Read straight from disk: Bundle caches its info dictionary, so it would keep
    // reporting the version that was installed when the test started.
    var installedShortVersion: String? { infoValue(forKey: "CFBundleShortVersionString") }
    var installedBuildVersion: String? { infoValue(forKey: "CFBundleVersion") }

    private func infoValue(forKey key: String) -> String? {
        guard let data = try? Data(
            contentsOf: installedBundleURL.appendingPathComponent("Contents/Info.plist")
        ),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return nil
        }
        return plist[key] as? String
    }

    func installedBundleSignatureIsValid() throws -> Bool {
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--strict", installedBundleURL.path]
        try verify.run()
        verify.waitUntilExit()
        return verify.terminationStatus == 0
    }

    // TCC stores this string, not the path, which is why it decides whether a grant survives.
    func installedDesignatedRequirement() throws -> String {
        try Self.run("/usr/bin/codesign", ["-d", "-r-", installedBundleURL.path])
    }

    func cleanup() {
        updater.automaticallyChecksForUpdates = false
        if server.isRunning {
            server.terminate()
            server.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: rootURL)
        // Sparkle keeps the downloaded update and its own state per bundle identifier.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let caches {
            try? FileManager.default.removeItem(
                at: caches.appendingPathComponent(Self.bundleIdentifier, isDirectory: true)
            )
        }
        UserDefaults.standard.removePersistentDomain(forName: Self.bundleIdentifier)
    }

    private static let bundleIdentifier = "dev.wzz.zisla.sparkle-install-test"

    // A real Mach-O executable, signed exactly the way `package-release.sh` signs a release:
    // Sparkle compares the signatures of the running app and the update, and an unsigned
    // bundle would take a different branch than a release ever does.
    private static func makeSignedBundle(
        at bundleURL: URL,
        shortVersion: String,
        build: String,
        bundleIdentifier: String,
        feedURL: String?,
        publicKey: String,
        signing: SparkleLocalInstallTestSigning
    ) throws -> URL {
        let macOSURL = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/usr/bin/true"),
            to: macOSURL.appendingPathComponent("zisla")
        )

        var infoDictionary: [String: Any] = [
            "CFBundleExecutable": "zisla",
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "zisla",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": shortVersion,
            "CFBundleVersion": build,
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": true,
            "SUEnableAutomaticChecks": false,
            "SUPublicEDKey": publicKey,
            "SUVerifyUpdateBeforeExtraction": true,
        ]
        if let feedURL {
            infoDictionary["SUFeedURL"] = feedURL
        }
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: infoDictionary,
            format: .xml,
            options: 0
        )
        try infoData.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))

        try run("/usr/bin/codesign", ["--force"] + signing.codesignArguments + [bundleURL.path])
        return bundleURL
    }

    // Same invocation `package-release.sh` uses, so the archive layout matches a release.
    private static func archive(_ bundleURL: URL, to archiveURL: URL) throws {
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", bundleURL.path, archiveURL.path])
    }

    private static func fileSize(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.size] as? Int)
    }

    // Unsigned feed: the signature on the appcast itself is already covered by
    // SparkleUpdateIntegrationTests against a real generate_appcast fixture, and this suite
    // is about what happens to the archive after the feed is parsed.
    private static func appcast(
        version: String,
        build: String,
        enclosure: String,
        length: Int,
        signature: String
    ) -> String {
        """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
            <channel>
                <title>zisla-local-install-test</title>
                <item>
                    <title>\(version)</title>
                    <pubDate>Tue, 01 Sep 2026 17:58:26 +0800</pubDate>
                    <sparkle:version>\(build)</sparkle:version>
                    <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
                    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
                    <enclosure url="\(enclosure)" length="\(length)" \
        type="application/octet-stream" sparkle:edSignature="\(signature)"></enclosure>
                </item>
            </channel>
        </rss>
        """
    }

    @discardableResult
    private static func run(_ executablePath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw SparkleLocalInstallError.commandFailed(
                command: ([executablePath] + arguments).joined(separator: " "),
                status: process.terminationStatus,
                output: text
            )
        }
        return text
    }

    // ATS does not apply to a numeric loopback address, so the feed and the archive can be
    // served over plain HTTP without weakening the transport rules a release depends on.
    private static func freePort() throws -> Int {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { throw SparkleLocalInstallError.noFreePort }
        defer { close(socketDescriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_ANY.bigEndian
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw SparkleLocalInstallError.noFreePort }
        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(socketDescriptor, socketAddress, &length)
            }
        }
        guard named == 0 else { throw SparkleLocalInstallError.noFreePort }
        return Int(assigned.sin_port.bigEndian)
    }

    private static func startServer(root: URL, port: Int) throws -> Process {
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [
            "-m", "http.server", "\(port)",
            "--bind", "127.0.0.1",
            "--directory", root.path,
        ]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        let probeURL = try #require(URL(string: "http://127.0.0.1:\(port)/appcast.xml"))
        while clock.now < deadline {
            if (try? Data(contentsOf: probeURL)) != nil { return server }
            usleep(100_000)
        }
        server.terminate()
        throw SparkleLocalInstallError.serverDidNotStart
    }
}

@MainActor
private final class SparkleLocalInstallUserDriver: SparkleStandardUserDriver {
    var foundVersion: String?
    var updaterErrors: [Error] = []
    private(set) var stages: [String] = []

    init(hostBundle: Bundle) {
        super.init(hostBundle: hostBundle, shouldSuppressUpdaterError: { false })
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
        stages.append("found")
        reply(.install)
    }

    override func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    override func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    override func showUpdateNotFoundWithError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        stages.append("notFound")
        acknowledgement()
    }

    override func showDownloadInitiated(cancellation: @escaping () -> Void) {
        stages.append("downloadStarted")
    }

    override func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    override func showDownloadDidReceiveData(ofLength length: UInt64) {}

    override func showDownloadDidStartExtractingUpdate() {
        stages.append("extracting")
    }

    override func showExtractionReceivedProgress(_ progress: Double) {}

    // Reaching this point already proves the archive downloaded, its EdDSA signature
    // verified and it extracted into a bundle whose code signature matches the host.
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        stages.append("readyToInstall")
        reply(.install)
    }

    override func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        stages.append("installing(terminated: \(applicationTerminated))")
    }

    override func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        stages.append("installed(relaunched: \(relaunched))")
        acknowledgement()
    }

    override func dismissUpdateInstallation() {
        stages.append("dismissed")
    }
}

private enum SparkleLocalInstallError: Error {
    case timedOut(stage: [String], updaterErrors: [Error])
    case commandFailed(command: String, status: Int32, output: String)
    case noFreePort
    case serverDidNotStart
}
