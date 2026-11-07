import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
@Suite(.serialized)
struct ManagedToolApplicationTests {
    @Test
    func installsAndUpdatesSignedQuietMDWithoutLaunchingIt() async throws {
        #if arch(arm64)
        let fixture = try Fixture()
        let service = fixture.service()
        QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.7")
        await service.install(.quietMD)
        #expect(service.states[.quietMD]?.installedVersion == "0.1.7")
        #expect(service.states[.quietMD]?.location == .external(fixture.executable.path))
        #expect(service.states[.quietMD]?.phase == .idle)
        #expect(service.states[.quietMD]?.errorMessage == nil)
        #expect(FileManager.default.isExecutableFile(atPath: fixture.executable.path))

        fixture.releaseVersion = "0.1.8"
        QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.8")
        await service.install(.quietMD)
        #expect(service.states[.quietMD]?.installedVersion == "0.1.8")
        #expect(service.states[.quietMD]?.errorMessage == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.applications.path) == ["quiet.md.app"])
        #expect(!FileManager.default.fileExists(atPath: fixture.executable.path + ".started"))

        let restored = fixture.service()
        await restored.refreshInstalledVersions()
        #expect(restored.states[.quietMD]?.installedVersion == "0.1.8")
        let resolver = ManagedToolService(
            toolsDirectory: fixture.root.appendingPathComponent("Tools"), applicationsDirectory: fixture.applications,
            bundleURL: fixture.root, defaults: fixture.defaults
        )
        let resolved = try #require(resolver.resolvedExecutable(for: .quietMD))
        #expect(resolved.url == fixture.executable.resolvingSymlinksInPath())
        #expect(resolved.location == .external(fixture.executable.path))
        #endif
    }

    @Test(arguments: ["unsigned", "wrongIdentifier", "missingVersion", "worldWritable", "corrupt", "symlink", "traversal"])
    func rejectedUpdatesPreserveTheExistingApplicationAndRemoveStagingFiles(failure: String) async throws {
        #if arch(arm64)
        let fixture = try Fixture()
        let service = fixture.service()
        QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.7")
        await service.install(.quietMD)
        let previous = try Data(contentsOf: fixture.application.appendingPathComponent("Contents/Info.plist"))
        fixture.releaseVersion = "0.1.8"

        switch failure {
        case "unsigned": QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.8", signed: false)
        case "wrongIdentifier": QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.8", identifier: "example.other")
        case "missingVersion": QuietMDDownloadProtocol.payload = try await fixture.archive(version: nil)
        case "worldWritable": QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.8", worldWritable: true)
        case "corrupt": QuietMDDownloadProtocol.payload = Data("invalid zip".utf8)
        case "symlink": QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.8", symlink: true)
        default:
            let script = "import zipfile,sys\nwith zipfile.ZipFile(sys.argv[1], 'w') as z: z.writestr('quiet.md.app/../escaped', 'unsafe')"
            let archive = fixture.root.appendingPathComponent("traversal.zip")
            guard case .success = await ManagedToolService.runProcess(
                URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", script, archive.path], timeout: 30
            ) else { throw ManagedToolError.notExecutable("fixture archiving failed") }
            QuietMDDownloadProtocol.payload = try Data(contentsOf: archive)
        }
        await service.install(.quietMD)

        #expect(service.states[.quietMD]?.installedVersion == "0.1.7")
        #expect(service.states[.quietMD]?.phase == .idle)
        #expect(service.states[.quietMD]?.errorMessage != nil)
        #expect(try Data(contentsOf: fixture.application.appendingPathComponent("Contents/Info.plist")) == previous)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.applications.path) == ["quiet.md.app"])
        #endif
    }

    @Test
    func failedReleaseLookupLeavesQuietMDUninstalledAndCanRecover() async throws {
        #if arch(arm64)
        let fixture = try Fixture()
        var unavailable = true
        let service = fixture.service { _ in
            if unavailable { throw ManagedToolError.releaseUnavailable("HTTP 503") }
            return fixture.release
        }
        await service.install(.quietMD)
        #expect(service.states[.quietMD]?.phase == .idle)
        #expect(service.states[.quietMD]?.location == nil)
        #expect(service.states[.quietMD]?.errorMessage != nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.applications.path))

        unavailable = false
        QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.7")
        await service.install(.quietMD)
        #expect(service.states[.quietMD]?.installedVersion == "0.1.7")
        #expect(service.states[.quietMD]?.errorMessage == nil)
        #endif
    }

    @Test
    func automaticUpdatesIgnoreMissingQuietMDAndRefreshAnInstalledCopy() async throws {
        #if arch(arm64)
        let fixture = try Fixture()
        var requests = 0
        let service = fixture.service { repository in
            #expect(repository == "s1dashu/quiet-md")
            requests += 1
            return fixture.release
        }
        await service.updateInstalledTools()
        #expect(requests == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.applications.path))

        QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.6")
        fixture.releaseVersion = "0.1.6"
        await service.install(.quietMD)
        fixture.releaseVersion = "0.1.7"
        QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.7")
        await service.updateInstalledTools()
        #expect(service.states[.quietMD]?.installedVersion == "0.1.7")
        #expect(service.states[.quietMD]?.phase == .idle)
        #expect(service.states[.quietMD]?.errorMessage == nil)
        #endif
    }

    @Test
    func uninstallDuringDownloadDoesNotRecreateQuietMD() async throws {
        #if arch(arm64)
        let fixture = try Fixture()
        let service = fixture.service()
        QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.6")
        await service.install(.quietMD)
        QuietMDDownloadProtocol.payload = try await fixture.archive(version: "0.1.7")
        QuietMDDownloadProtocol.beforeLoading = { [application = fixture.application] in
            try? FileManager.default.removeItem(at: application)
        }
        defer { QuietMDDownloadProtocol.beforeLoading = nil }

        await service.updateInstalledTools()

        #expect(!FileManager.default.fileExists(atPath: fixture.application.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.applications.path).isEmpty)
        #expect(service.states[.quietMD]?.phase == .idle)
        #endif
    }

    @Test(arguments: ["", "/quiet.md.app/file", "quiet.md.app/../escaped", "quiet.md.app/./file", "quiet.md.app\\file", "other.app/file"])
    func archiveValidationRejectsUnsafePaths(path: String) {
        #expect(throws: ManagedToolError.self) {
            try ManagedToolService.validateApplicationArchive(entries: path, details: Self.details, bundleName: "quiet.md.app")
        }
    }

    @Test(arguments: ["1 file, 536870913 bytes uncompressed, 1 bytes compressed: 0%", "invalid metadata", "lrwxr-xr-x link\n1 file, 1 bytes uncompressed, 1 bytes compressed: 0%"])
    func archiveValidationRejectsOversizedUnparseableAndSymlinkEntries(details: String) {
        #expect(throws: ManagedToolError.self) {
            try ManagedToolService.validateApplicationArchive(entries: "quiet.md.app/Contents/MacOS/quiet_md", details: details, bundleName: "quiet.md.app")
        }
    }

    @Test
    func archiveValidationAllowsApplicationResourcesAndAppleMetadata() throws {
        try ManagedToolService.validateApplicationArchive(
            entries: "quiet.md.app/\nquiet.md.app/Contents/MacOS/quiet_md\nquiet.md.app/._Contents",
            details: Self.details, bundleName: "quiet.md.app"
        )
    }

    private static let details = "3 files, 536870912 bytes uncompressed, 1 bytes compressed: 0%"

    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-quiet-md-tests-\(UUID().uuidString)")
        let suiteName = "ManagedToolApplicationTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var applications: URL { root.appendingPathComponent("Applications") }
        var application: URL { applications.appendingPathComponent("quiet.md.app") }
        var executable: URL { application.appendingPathComponent("Contents/MacOS/quiet_md") }
        var releaseVersion = "0.1.7"
        var release: Data { Data("""
        {"tag_name":"v\(releaseVersion)","assets":[{"name":"quiet-md-\(releaseVersion)-macos-arm64.zip","browser_download_url":"https://github.com/s1dashu/quiet-md/releases/download/v\(releaseVersion)/quiet-md-\(releaseVersion)-macos-arm64.zip"}]}
        """.utf8) }

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        @MainActor
        func service(releaseLoader: ((String) async throws -> Data)? = nil) -> ManagedToolService {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [QuietMDDownloadProtocol.self]
            return ManagedToolService(
                toolsDirectory: root.appendingPathComponent("Tools"), applicationsDirectory: applications,
                bundleURL: root, session: URLSession(configuration: configuration), defaults: defaults,
                releaseLoader: releaseLoader ?? { [self] _ in release },
                executableResolver: { [self] tool in
                    tool == .quietMD && FileManager.default.isExecutableFile(atPath: executable.path)
                        ? (executable, .external(executable.path)) : nil
                }
            )
        }

        @MainActor
        func archive(version: String?, signed: Bool = true, identifier: String = "com.s1dashu.quietmd", symlink: Bool = false, worldWritable: Bool = false) async throws -> Data {
            let source = root.appendingPathComponent(UUID().uuidString)
            let app = source.appendingPathComponent("quiet.md.app")
            let executable = app.appendingPathComponent("Contents/MacOS/quiet_md")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
            var info = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "quiet_md", "CFBundlePackageType": "APPL"]
            if let version { info["CFBundleShortVersionString"] = version }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            if symlink {
                try FileManager.default.createSymbolicLink(atPath: app.appendingPathComponent("Contents/link").path, withDestinationPath: "../..")
            }
            if signed {
                guard case .success = await ManagedToolService.runProcess(
                    URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--force", "--sign", "-", app.path], timeout: 30
                ) else { throw ManagedToolError.notExecutable("fixture signing failed") }
            } else {
                guard case .success = await ManagedToolService.runProcess(
                    URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--remove-signature", executable.path], timeout: 30
                ) else { throw ManagedToolError.notExecutable("fixture signature removal failed") }
            }
            if worldWritable {
                try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: executable.path)
            }
            let archive = source.appendingPathComponent("quiet.zip")
            guard case .success = await ManagedToolService.runProcess(
                URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-c", "-k", "--keepParent", app.path, archive.path], timeout: 30
            ) else { throw ManagedToolError.notExecutable("fixture archiving failed") }
            return try Data(contentsOf: archive)
        }
    }
}

private final class QuietMDDownloadProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var beforeLoading: (@Sendable () -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.beforeLoading?()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
