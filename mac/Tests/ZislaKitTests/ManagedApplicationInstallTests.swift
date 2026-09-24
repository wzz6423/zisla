import Darwin
import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
@Suite(.serialized)
struct ManagedApplicationInstallTests {
    @Test
    func installsAndUpdatesOfficialApplicationArchive() async throws {
        let fixture = try ApplicationFixture()
        defer { fixture.cleanUp() }
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        let service = fixture.service()

        #expect(await service.checkLatest(.pulse) == "1.4.0")
        await service.install(.pulse)

        #expect(service.states[.pulse]?.installedVersion == "1.4.0")
        #expect(service.states[.pulse]?.location == .managed)
        #expect(try appVersion(at: fixture.destination) == "1.4.0")
        let link = fixture.destination.appendingPathComponent("Contents/Frameworks/Test.framework/Resources")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "Versions/Current/Resources")

        fixture.version = "1.5.0"
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        await service.updateInstalledTools()

        #expect(service.states[.pulse]?.installedVersion == "1.5.0")
        #expect(try appVersion(at: fixture.destination) == "1.5.0")
        #expect(await ManagedToolService.readVersion(of: .pulse, at: fixture.executable) == "1.5.0")
        #expect(service.states[.pulse]?.errorMessage == nil)
        fixture.expectClean()
    }

    @Test
    func manualUpdateReplacesTheDetectedExternalApplication() async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0", external: true)
        defer { fixture.cleanUp() }
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        let service = fixture.service()

        await service.install(.pulse)

        #expect(try appVersion(at: fixture.destination) == "1.4.0")
        #expect(!FileManager.default.fileExists(atPath: fixture.applications.appendingPathComponent("Pulse.app").path))
        #expect(service.states[.pulse]?.location == .external(fixture.executable.path))
        fixture.expectClean()
    }

    @Test(arguments: ["1.4.0", "2.0.0"], [false, true])
    func manualUpdatePreservesANewerInstalledVersion(_ version: String, _ automatically: Bool) async throws {
        let fixture = try ApplicationFixture(installed: version)
        defer { fixture.cleanUp() }
        let previous = try Data(contentsOf: fixture.executable)
        let service = fixture.service()

        if automatically { await service.updateInstalledTools() } else { await service.install(.pulse) }

        #expect(try appVersion(at: fixture.destination) == version)
        #expect(try Data(contentsOf: fixture.executable) == previous)
        #expect(service.states[.pulse]?.installedVersion == version)
        #expect(service.states[.pulse]?.hasUpdate == false)
        #expect(ApplicationArchiveProtocol.requests == 0)
        #expect(fixture.service().states[.pulse]?.installedVersion == version)
        fixture.expectClean()
    }

    @Test
    func automaticUpdatesNeverInstallAMissingApplication() async throws {
        let fixture = try ApplicationFixture()
        defer { fixture.cleanUp() }
        let service = fixture.service(load: { _ in
            Issue.record("未安装的推荐应用不应请求发布信息")
            return Data()
        })

        await service.updateInstalledTools()

        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(ApplicationArchiveProtocol.requests == 0)
        fixture.expectClean()
    }

    @Test
    func acceptsAValidUncompressedApplicationArchive() async throws {
        let fixture = try ApplicationFixture()
        defer { fixture.cleanUp() }
        let payload = storedZIP(try fixture.minimalArchiveMembers())
        let archive = fixture.root.appendingPathComponent("fixture.zip")
        try payload.write(to: archive)
        _ = try await ManagedToolService.runProcess(
            URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-t", archive.path]
        ).get()
        ApplicationArchiveProtocol.configure(data: payload)
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage == nil)
        #expect(try appVersion(at: fixture.destination) == "1.4.0")
        fixture.expectClean()
    }

    @Test
    func removalDuringReleaseLookupClearsTheInstalledState() async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        let service = fixture.service(load: { _ in
            try FileManager.default.removeItem(at: fixture.destination)
            return try fixture.release()
        })

        await service.updateInstalledTools()

        #expect(service.states[.pulse]?.isInstalled == false)
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
        #expect(ApplicationArchiveProtocol.requests == 0)
        fixture.expectClean()
    }

    @Test
    func cancellationDuringLookupDoesNotReportAStaleRunningError() async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        let service = fixture.service(load: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return try fixture.release()
        }, running: { _ in true })

        await Task { await service.updateInstalledTools() }.value

        #expect(service.states[.pulse]?.errorMessage == nil)
        #expect(service.states[.pulse]?.phase == .idle)
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        #expect(ApplicationArchiveProtocol.requests == 0)
        fixture.expectClean()
    }

    @Test(arguments: [
        "bundleID", "version", "executableName", "missingExecutable", "nonExecutable",
        "contentsLink", "infoLink", "executableLink", "resourceLink",
    ])
    func invalidApplicationKeepsTheInstalledVersion(_ defect: String) async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        let outside = fixture.root.appendingPathComponent("Outside.app")
        try writeApplication(at: outside, version: "1.4.0")
        let previous = try Data(contentsOf: fixture.executable)
        ApplicationArchiveProtocol.configure(data: try fixture.archive { app in
            let infoURL = app.appendingPathComponent("Contents/Info.plist")
            let executable = app.appendingPathComponent("Contents/MacOS/Pulse")
            switch defect {
            case "bundleID", "version", "executableName":
                var info = try appInfo(at: app)
                let key = defect == "bundleID" ? "CFBundleIdentifier"
                    : defect == "version" ? "CFBundleShortVersionString" : "CFBundleExecutable"
                info[key] = defect == "version" ? "1.3.0" : "unexpected"
                try writeInfo(info, to: infoURL)
            case "missingExecutable":
                try FileManager.default.removeItem(at: executable)
            case "nonExecutable":
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)
            case "contentsLink", "infoLink", "executableLink":
                let relative = defect == "contentsLink" ? "Contents"
                    : defect == "infoLink" ? "Contents/Info.plist" : "Contents/MacOS/Pulse"
                let link = app.appendingPathComponent(relative)
                try FileManager.default.removeItem(at: link)
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.appendingPathComponent(relative))
            default:
                try FileManager.default.createSymbolicLink(
                    at: app.appendingPathComponent("Contents/Resources/escape"), withDestinationURL: outside
                )
            }
        })
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil, "应拒绝 \(defect)")
        #expect(service.states[.pulse]?.phase == .idle)
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        #expect(try Data(contentsOf: fixture.executable) == previous)
        #expect(try appVersion(at: outside) == "1.4.0")
        fixture.expectClean()
    }

    @Test
    func aForeignArchiveNeverCreatesAnApplicationInstallDirectory() async throws {
        let fixture = try ApplicationFixture()
        defer { fixture.cleanUp() }
        ApplicationArchiveProtocol.configure(data: try fixture.archive { app in
            var info = try appInfo(at: app)
            info["CFBundleIdentifier"] = "another.app"
            try writeInfo(info, to: app.appendingPathComponent("Contents/Info.plist"))
        })
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.applications.path))
        fixture.expectClean()
    }

    @Test(arguments: ["relative", "absolute", "embedded"])
    func archiveTraversalNeverWritesOutsideTheExtractionDirectory(_ attack: String) async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        let sentinel = fixture.root.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)
        let path = attack == "absolute" ? sentinel.path
            : attack == "relative" ? "../../../sentinel" : "Pulse.app/../../../../sentinel"
        ApplicationArchiveProtocol.configure(data: storedZIP(try fixture.minimalArchiveMembers() + [ZipMember(path, Data("changed".utf8))]))
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil)
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        fixture.expectClean()
    }

    @Test
    func archiveCannotWriteThroughAnExternalSymlink() async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        let outside = fixture.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)
        ApplicationArchiveProtocol.configure(data: storedZIP(try fixture.minimalArchiveMembers() + [
            ZipMember("Pulse.app/Contents/Resources/escape", Data(outside.path.utf8), mode: 0o120777),
            ZipMember("Pulse.app/Contents/Resources/escape/sentinel", Data("changed".utf8)),
        ]))
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil)
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        fixture.expectClean()
    }

    @Test(arguments: ["invalid", "truncated", "empty", "expandedSize", "entryCount"])
    func malformedOrOversizedArchivesFailWithoutReplacingTheApplication(_ defect: String) async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        let payload: Data
        switch defect {
        case "truncated": payload = Data(try fixture.archive().prefix(64))
        case "empty": payload = storedZIP([])
        case "expandedSize":
            payload = storedZIP([ZipMember("Pulse.app/large", Data(), declaredSize: 512 * 1024 * 1024 + 1)])
        case "entryCount":
            payload = storedZIP(try fixture.minimalArchiveMembers() + (0..<4097).map { ZipMember("Pulse.app/\($0)", Data()) })
        default: payload = Data("not a ZIP".utf8)
        }
        ApplicationArchiveProtocol.configure(data: payload)
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil)
        if defect == "expandedSize" {
            #expect(service.states[.pulse]?.errorMessage == ManagedToolError.notExecutable("Pulse").message)
        }
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        fixture.expectClean()
    }

    @Test(arguments: ["offline", "http"])
    func failedDownloadPreservesTheApplicationAndCanRecover(_ failure: String) async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        ApplicationArchiveProtocol.configure(
            status: failure == "http" ? 503 : 200,
            error: failure == "offline" ? URLError(.networkConnectionLost) : nil
        )
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil)
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        fixture.expectClean()

        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage == nil)
        #expect(try appVersion(at: fixture.destination) == "1.4.0")
        fixture.expectClean()
    }

    @Test(arguments: [true, false])
    func runningApplicationIsNeverReplaced(_ alreadyRunning: Bool) async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        var checks = 0
        let service = fixture.service(running: { identifier in
            #expect(identifier == "io.github.qunqin24.Pulse")
            checks += 1
            return alreadyRunning || checks > 1
        })

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage == ManagedToolError.applicationRunning("Pulse").message)
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        #expect(ApplicationArchiveProtocol.requests == (alreadyRunning ? 0 : 1))
        fixture.expectClean()
    }

    @Test
    func partialCopyFailurePreservesTheOldBundleAndRemovesStaging() async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        fixture.fileManager.failCopy = true
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil)
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        fixture.expectClean()

        fixture.fileManager.failCopy = false
        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage == nil)
        #expect(try appVersion(at: fixture.destination) == "1.4.0")
        fixture.expectClean()
    }

    @Test(arguments: ["metadata", "fifo"])
    func stagingCorruptionCannotReplaceTheInstalledApplication(_ corruption: String) async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        fixture.fileManager.afterCopy = { staging in
            if corruption == "metadata" {
                try Data("broken plist".utf8).write(to: staging.appendingPathComponent("Contents/Info.plist"))
            } else {
                let pipe = staging.appendingPathComponent("Contents/Resources/pipe")
                try #require(mkfifo(pipe.path, 0o600) == 0)
            }
        }
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil)
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        fixture.expectClean()
    }

    @Test
    func enumerationFailureCannotApproveAnIncompleteBundleValidation() async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        let fileManager = fixture.fileManager
        fileManager.afterCopy = { staging in
            let unreadable = staging.appendingPathComponent("Contents/Resources/Unreadable")
            try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
            try Data("unreadable".utf8).write(to: unreadable.appendingPathComponent("entry"))
            fileManager.unreadableDirectory = unreadable
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        }
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil)
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        fixture.expectClean()
    }

    @Test
    func aConcurrentNewerVersionIsNotOverwrittenAfterDownload() async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        let destination = fixture.destination
        fixture.fileManager.afterCopy = { _ in try writeApplication(at: destination, version: "2.0.0") }
        let service = fixture.service()

        await service.install(.pulse)

        #expect(try appVersion(at: fixture.destination) == "2.0.0")
        #expect(service.states[.pulse]?.installedVersion == "2.0.0")
        #expect(service.states[.pulse]?.errorMessage == nil)
        fixture.expectClean()
    }

    @Test(arguments: ["uninstall", "cancel"])
    func interruptionBeforeCommitNeverRestoresOrReplacesTheApplication(_ interruption: String) async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        let destination = fixture.destination
        fixture.fileManager.afterCopy = { _ in
            if interruption == "uninstall" {
                try FileManager.default.removeItem(at: destination)
            } else {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let service = fixture.service()

        await Task { await service.install(.pulse) }.value

        if interruption == "uninstall" {
            #expect(!FileManager.default.fileExists(atPath: fixture.destination.path))
            #expect(service.states[.pulse]?.isInstalled == false)
        } else {
            #expect(try appVersion(at: fixture.destination) == "1.0.0")
        }
        #expect(service.states[.pulse]?.phase == .idle)
        fixture.expectClean()
    }

    @Test
    func aFailedAtomicSwapKeepsTheOldVersionAndCanRetry() async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: fixture.destination.path)
            fixture.cleanUp()
        }
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: fixture.destination.path)
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil)
        #expect(try appVersion(at: fixture.destination) == "1.0.0")
        fixture.expectClean()

        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: fixture.destination.path)
        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage == nil)
        #expect(try appVersion(at: fixture.destination) == "1.4.0")
        fixture.expectClean()
    }

    @Test(arguments: ["empty", "directory", "file"])
    func anUnrecognizedDestinationIsNeverOverwritten(_ kind: String) async throws {
        let fixture = try ApplicationFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.applications, withIntermediateDirectories: true)
        if kind == "file" {
            try Data("keep".utf8).write(to: fixture.destination)
        } else {
            try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: true)
            if kind == "directory" {
                try Data("keep".utf8).write(to: fixture.destination.appendingPathComponent("user-data"))
            }
        }
        ApplicationArchiveProtocol.configure(data: try fixture.archive())
        let service = fixture.service()

        await service.install(.pulse)

        #expect(service.states[.pulse]?.errorMessage != nil)
        if kind != "empty" {
            let sentinel = kind == "file" ? fixture.destination : fixture.destination.appendingPathComponent("user-data")
            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.executable.path))
        fixture.expectClean()
    }

    @Test
    func nativeVersionReadingUsesFreshMetadataWithoutLaunchingTheApp() async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        #expect(await ManagedToolService.readVersion(of: .pulse, at: fixture.executable) == "1.0.0")

        var info = try appInfo(at: fixture.destination)
        info["CFBundleShortVersionString"] = "1.1.0"
        try writeInfo(info, to: fixture.destination.appendingPathComponent("Contents/Info.plist"))

        #expect(await ManagedToolService.readVersion(of: .pulse, at: fixture.executable) == "1.1.0")
        fixture.expectClean()
    }

    @Test(arguments: ["", "not-a-version", "1.0.0\n", "1.0.0beta"])
    func invalidNativeVersionIsNotReported(_ version: String) async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        var info = try appInfo(at: fixture.destination)
        info["CFBundleShortVersionString"] = version
        try writeInfo(info, to: fixture.destination.appendingPathComponent("Contents/Info.plist"))

        #expect(await ManagedToolService.readVersion(of: .pulse, at: fixture.executable) == nil)
        fixture.expectClean()
    }

    @Test(arguments: ["bundleID", "application", "contents", "macOS", "info", "executable"])
    func discoveryRejectsForeignBundleIdentifiersAndLinkedExecutables(_ defect: String) async throws {
        let fixture = try ApplicationFixture(installed: "1.0.0")
        defer { fixture.cleanUp() }
        let service = ManagedToolService(
            toolsDirectory: fixture.root.appendingPathComponent("Tools"),
            applicationsDirectory: fixture.applications, bundleURL: fixture.root, defaults: fixture.defaults,
            applicationIsRunning: { _ in false }
        )
        #expect(service.resolvedExecutable(for: .pulse)?.url == fixture.executable.resolvingSymlinksInPath())
        if defect == "bundleID" {
            var info = try appInfo(at: fixture.destination)
            info["CFBundleIdentifier"] = "another.app"
            try writeInfo(info, to: fixture.destination.appendingPathComponent("Contents/Info.plist"))
        } else {
            let path = defect == "application" ? "" : defect == "contents" ? "Contents"
                : defect == "macOS" ? "Contents/MacOS" : defect == "info" ? "Contents/Info.plist" : "Contents/MacOS/Pulse"
            let source = path.isEmpty ? fixture.destination : fixture.destination.appendingPathComponent(path)
            let outside = fixture.root.appendingPathComponent("Outside.app")
            try FileManager.default.moveItem(atPath: source.path, toPath: outside.path)
            try FileManager.default.createSymbolicLink(atPath: source.path, withDestinationPath: outside.path)
        }

        let resolved = service.resolvedExecutable(for: .pulse)?.url
        #expect(resolved?.path.hasPrefix(fixture.root.resolvingSymlinksInPath().path) != true)
        fixture.expectClean()
    }
}

@MainActor
private final class ApplicationFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-app-install-\(UUID().uuidString)", isDirectory: true)
    let suite = "zisla-app-install-\(UUID().uuidString)"
    let defaults: UserDefaults
    let fileManager: ApplicationFileManager
    let external: Bool
    var version = "1.4.0"
    private var sessions: [URLSession] = []

    var applications: URL { root.appendingPathComponent("Applications", isDirectory: true) }
    var destination: URL {
        (external ? root.appendingPathComponent("External") : applications).appendingPathComponent("Pulse.app", isDirectory: true)
    }
    var executable: URL { destination.appendingPathComponent("Contents/MacOS/Pulse") }

    init(installed: String? = nil, external: Bool = false) throws {
        self.external = external
        defaults = try #require(UserDefaults(suiteName: suite))
        fileManager = ApplicationFileManager(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let installed { try writeApplication(at: destination, version: installed) }
        ApplicationArchiveProtocol.configure()
    }

    func service(
        load: ((String) async throws -> Data)? = nil,
        running: @escaping (String) -> Bool = { _ in false }
    ) -> ManagedToolService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ApplicationArchiveProtocol.self]
        let session = URLSession(configuration: configuration)
        sessions.append(session)
        return ManagedToolService(
            toolsDirectory: root.appendingPathComponent("Tools"), applicationsDirectory: applications, bundleURL: root,
            session: session, fileManager: fileManager, defaults: defaults,
            releaseLoader: load ?? { [self] repository in
                #expect(repository == "qunqin24/Pulse")
                return try release()
            },
            executableResolver: { [self] tool in
                guard tool == .pulse, FileManager.default.fileExists(atPath: executable.path) else { return nil }
                return (executable, external ? .external(executable.path) : .managed)
            },
            homebrewRunner: { _, _ in Issue.record("Pulse 不应调用 Homebrew"); return "" },
            applicationIsRunning: running
        )
    }

    func release() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "tag_name": "v\(version)", "assets": [[
                "name": "Pulse-\(version).zip",
                "browser_download_url": "https://github.com/qunqin24/Pulse/releases/download/v\(version)/Pulse-\(version).zip",
            ]],
        ])
    }

    func minimalArchiveMembers() throws -> [ZipMember] {
        let application = root.appendingPathComponent("ZIPFixture/Pulse.app")
        try writeApplication(at: application, version: version)
        return [
            ZipMember("Pulse.app/Contents/Info.plist", try Data(contentsOf: application.appendingPathComponent("Contents/Info.plist"))),
            ZipMember("Pulse.app/Contents/MacOS/Pulse", try Data(contentsOf: application.appendingPathComponent("Contents/MacOS/Pulse")), mode: 0o100755),
        ]
    }

    func archive(mutate: (URL) throws -> Void = { _ in }) throws -> Data {
        let build = root.appendingPathComponent("Build-\(UUID().uuidString)")
        let application = build.appendingPathComponent("Pulse.app")
        try writeApplication(at: application, version: version)
        try mutate(application)
        let zip = build.appendingPathComponent("Pulse.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", application.path, zip.path]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "无法生成隔离应用包 fixture")
        return try Data(contentsOf: zip)
    }

    func expectClean() {
        let staging = (try? FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)) ?? []
        #expect(!staging.contains { $0.hasPrefix(".Pulse.") }, "安装目录遗留暂存应用")
        let downloads = (try? FileManager.default.contentsOfDirectory(atPath: fileManager.temporaryDirectory.path)) ?? []
        #expect(downloads.isEmpty, "下载与解压目录未清理：\(downloads)")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("was-launched").path), "测试不应启动应用程序")
    }

    func cleanUp() {
        sessions.forEach { $0.invalidateAndCancel() }
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class ApplicationFileManager: FileManager, @unchecked Sendable {
    let root: URL
    var failCopy = false
    var unreadableDirectory: URL?
    var afterCopy: ((URL) throws -> Void)?

    init(root: URL) {
        self.root = root
        super.init()
    }

    override var temporaryDirectory: URL { root.appendingPathComponent("Downloads") }

    override func copyItem(at source: URL, to destination: URL) throws {
        if failCopy {
            try createDirectory(at: destination, withIntermediateDirectories: true)
            try Data("partial".utf8).write(to: destination.appendingPathComponent("partial"))
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try super.copyItem(at: source, to: destination)
        try afterCopy?(destination)
    }

    override func removeItem(at url: URL) throws {
        if let unreadableDirectory {
            try? setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadableDirectory.path)
        }
        try super.removeItem(at: url)
    }
}

private func writeApplication(at application: URL, version: String) throws {
    let fileManager = FileManager.default
    let executable = application.appendingPathComponent("Contents/MacOS/Pulse")
    try fileManager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: application.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
    try writeInfo([
        "CFBundleIdentifier": "io.github.qunqin24.Pulse", "CFBundleShortVersionString": version,
        "CFBundleExecutable": "Pulse", "CFBundlePackageType": "APPL",
    ], to: application.appendingPathComponent("Contents/Info.plist"))
    let root = application.deletingLastPathComponent().deletingLastPathComponent()
    try Data("#!/bin/sh\ntouch '\(root.appendingPathComponent("was-launched").path)'\necho \(version)\n".utf8).write(to: executable)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let framework = application.appendingPathComponent("Contents/Frameworks/Test.framework")
    let resources = framework.appendingPathComponent("Versions/A/Resources")
    try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
    try Data("resource".utf8).write(to: resources.appendingPathComponent("fixture"))
    for (name, target) in [("Versions/Current", "A"), ("Resources", "Versions/Current/Resources")] {
        let link = framework.appendingPathComponent(name)
        if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == nil {
            try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: target)
        }
    }
}

private func appInfo(at application: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: application.appendingPathComponent("Contents/Info.plist"))
    return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
}

private func appVersion(at application: URL) throws -> String? {
    try appInfo(at: application)["CFBundleShortVersionString"] as? String
}

private func writeInfo(_ info: [String: Any], to url: URL) throws {
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url)
}

private struct ZipMember {
    let path: String
    let data: Data
    let mode: UInt32
    let declaredSize: UInt32

    init(_ path: String, _ data: Data, mode: UInt32 = 0o100644, declaredSize: UInt32? = nil) {
        self.path = path
        self.data = data
        self.mode = mode
        self.declaredSize = declaredSize ?? UInt32(data.count)
    }
}

private func storedZIP(_ members: [ZipMember]) -> Data {
    var output = Data()
    var directory = Data()
    for member in members {
        let name = Data(member.path.utf8)
        let offset = UInt32(output.count)
        var crc: UInt32 = 0xffff_ffff
        for byte in member.data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb8_8320) }
        }
        crc ^= 0xffff_ffff
        output.appendLE(UInt32(0x04034b50))
        [UInt16(20), 0x800, 0, 0, 0].forEach { output.appendLE($0) }
        [crc, UInt32(member.data.count), member.declaredSize].forEach { output.appendLE($0) }
        output.appendLE(UInt16(name.count))
        output.appendLE(UInt16(0))
        output.append(name)
        output.append(member.data)

        directory.appendLE(UInt32(0x02014b50))
        [UInt16(0x314), 20, 0x800, 0, 0, 0].forEach { directory.appendLE($0) }
        [crc, UInt32(member.data.count), member.declaredSize].forEach { directory.appendLE($0) }
        [UInt16(name.count), 0, 0, 0, 0].forEach { directory.appendLE($0) }
        directory.appendLE(member.mode << 16)
        directory.appendLE(offset)
        directory.append(name)
    }
    let offset = UInt32(output.count)
    output.append(directory)
    output.appendLE(UInt32(0x06054b50))
    [UInt16(0), 0, UInt16(members.count), UInt16(members.count)].forEach { output.appendLE($0) }
    output.appendLE(UInt32(directory.count))
    output.appendLE(offset)
    output.appendLE(UInt16(0))
    return output
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}

private final class ApplicationArchiveProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var payload = Data()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var failure: URLError?
    nonisolated(unsafe) private static var requestCount = 0

    static var requests: Int { lock.withLock { requestCount } }

    static func configure(data: Data = Data(), status: Int = 200, error: URLError? = nil) {
        lock.withLock {
            payload = data
            self.status = status
            failure = error
            requestCount = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (data, status, error) = Self.lock.withLock {
            Self.requestCount += 1
            return (Self.payload, Self.status, Self.failure)
        }
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/zip", "Content-Length": "\(data.count)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
