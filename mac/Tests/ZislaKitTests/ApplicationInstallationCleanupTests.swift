import Foundation
import Testing

@testable import ZislaKit

struct ApplicationInstallationCleanupTests {
    @Test
    func duplicateInstallationsKeepTheNewestApplication() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let old = try fixture.application(name: "Google Chrome 2.app", version: "157.0.8103.52")
        let current = try fixture.application(name: "Google Chrome.app", version: "157.0.8103.79")

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual])

        #expect(candidates.map(\.url) == [old])
        #expect(candidates.first?.safetyLevel == .requiresManualReview)
        #expect(candidates.first?.detail?.contains(current.path) == true)
        #expect(candidates.first?.byteSize ?? 0 > 0)
        #expect(fixture.files.trashedURLs.isEmpty)
        #expect(SystemDiskCleanup.scanCandidatesWithProgress(fileManager: fixture.files, kinds: [.applicationResidual], onProgress: { _ in }).map(\.url) == [old])
    }

    @Test
    func chromeFrameworkUpdateLeavesOnlyThePreviousVersionAsACandidate() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let app = try fixture.application(name: "Google Chrome.app", version: "157.0.8103.79")
        let versions = try fixture.frameworkVersions(in: app)
        let old = try fixture.version("157.0.8103.52", in: versions)
        _ = try fixture.version("157.0.8103.79", in: versions)
        try fixture.currentVersion("157.0.8103.79", in: versions)

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual])

        #expect(candidates.map(\.url) == [old])
        #expect(candidates.first?.safetyLevel == .requiresManualReview)
        #expect(candidates.first?.detail?.contains("157.0.8103.79") == true)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func sameVersionCopiesPreferTheInstalledCanonicalNameAndNewestBuild() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let downloads = fixture.root.appendingPathComponent("Downloads")
        try fixture.directory(downloads)
        fixture.files.searchPathResults[.downloadsDirectory] = [downloads]
        let current = try fixture.application(name: "Google Chrome.app", version: "10.0", build: "10")
        let renamed = try fixture.application(name: "Google Chrome 2.app", version: "10.0", build: "10")
        let downloaded = try fixture.application(name: "Google Chrome.app", version: "10.0", at: downloads, build: "10")
        let oldBuild = try fixture.application(name: "Google Chrome 3.app", version: "10.0", build: "9")
        _ = try fixture.application(name: "Chrome Beta.app", version: "10.0", identifier: "com.google.Chrome.beta")

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual])

        #expect(Set(candidates.map(\.url)) == Set([renamed, downloaded, oldBuild]))
        #expect(candidates.allSatisfy { $0.detail?.contains(current.path) == true })
    }

    @Test
    func runningCopiesAreKeptAndProcessLookupFailureProducesNoCandidates() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let old = try fixture.application(name: "Google Chrome 2.app", version: "9.0")
        _ = try fixture.application(name: "Google Chrome.app", version: "10.0")
        fixture.files.applicationProcesses = [old.appendingPathComponent("Contents/MacOS/Google Chrome").path]
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)

        fixture.files.applicationProcesses = nil
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func runningSameVersionCopyWinsEvenWhenItIsInDownloads() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let downloads = fixture.root.appendingPathComponent("Downloads")
        try fixture.directory(downloads)
        fixture.files.searchPathResults[.downloadsDirectory] = [downloads]
        let installed = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let running = try fixture.application(name: "Google Chrome.app", version: "10.0", at: downloads)
        fixture.files.applicationProcesses = [running.appendingPathComponent("Contents/MacOS/Google Chrome").path]

        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).map(\.url) == [installed])
    }

    @Test(arguments: ["", "1..2", "../2", "2-beta", String(repeating: "1", count: 129), "٢.٣"])
    func uncertainVersionsNeverClassifyAGroupAsDuplicates(version: String) throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        _ = try fixture.application(name: "Google Chrome.app", version: "10.0")
        _ = try fixture.application(name: "Google Chrome 2.app", version: version)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func unreadableApplicationsAndIncompleteBundlesAreIgnored() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let app = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let duplicate = try fixture.application(name: "Google Chrome 2.app", version: "9.0")
        fixture.files.fileContentsData[duplicate.appendingPathComponent("Contents/Info.plist").path] = Data("broken".utf8)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        fixture.files.directoryErrors[fixture.applications.path] = .fileReadNoPermission
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        fixture.files.directoryErrors = [:]
        fixture.files.fileContentsData[app.appendingPathComponent("Contents/Info.plist").path] = Data()
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func embeddedHelpersAndSymlinksCannotBecomeDuplicateInstallations() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let app = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let frameworks = app.appendingPathComponent("Contents/Frameworks")
        try fixture.directory(frameworks)
        _ = try fixture.application(name: "Google Chrome Helper.app", version: "9.0", at: frameworks)
        let alias = fixture.applications.appendingPathComponent("Chrome Link.app")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: app)
        fixture.files.existingPaths.insert(alias.path)
        fixture.files.fileAttributes[alias.path] = [.type: FileAttributeType.typeSymbolicLink]
        fixture.files.directoryContents[fixture.applications.path, default: []].append(alias)

        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func updateScanKeepsRunningVersionsAndFutureVersions() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let app = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let versions = try fixture.frameworkVersions(in: app)
        let old = try fixture.version("8.0", in: versions)
        let running = try fixture.version("9.0", in: versions)
        _ = try fixture.version("10.0", in: versions)
        _ = try fixture.version("11.0", in: versions)
        try fixture.directory(versions.appendingPathComponent("A"))
        try fixture.currentVersion("10.0", in: versions)
        fixture.files.applicationProcesses = [running.appendingPathComponent("Helpers/Chrome Helper").path]

        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).map(\.url) == [old])
    }

    @Test
    func missingOrEscapingCurrentVersionIsNeverCleaned() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let app = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let versions = try fixture.frameworkVersions(in: app)
        _ = try fixture.version("9.0", in: versions)
        _ = try fixture.version("10.0", in: versions)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        try fixture.currentVersion("../10.0", in: versions)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        try fixture.currentVersion("11.0", in: versions)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func bundleVersionDirectoriesUseTheCurrentApplicationVersion() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let app = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let versions = app.appendingPathComponent("Contents/Versions")
        try fixture.directory(versions)
        let old = try fixture.version("9.0", in: versions)
        let current = try fixture.version("10.0", in: versions)

        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).map(\.url) == [old])
        fixture.files.existingPaths.remove(current.path)
        fixture.files.fileAttributes.removeValue(forKey: current.path)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func userFileScanningNeverOffersFilesInsideAnApplication() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let downloads = fixture.root.appendingPathComponent("Downloads")
        try fixture.directory(downloads)
        fixture.files.searchPathResults[.downloadsDirectory] = [downloads]
        let app = try fixture.application(name: "Google Chrome.app", version: "10.0", at: downloads)
        let resources = app.appendingPathComponent("Contents/Resources")
        try fixture.directory(resources)
        let payload = resources.appendingPathComponent("payload.bin")
        fixture.file(payload, data: Data(repeating: 4, count: 8192))
        fixture.files.fileAttributes[payload.path]?[.modificationDate] = Date(timeIntervalSince1970: 0)
        let installer = downloads.appendingPathComponent("Chrome.dmg")
        fixture.file(installer, data: Data(repeating: 3, count: 8192))

        let candidates = SystemDiskCleanup.scanCandidates(
            fileManager: fixture.files, kinds: [.largeFile, .diskImage, .duplicateFile],
            options: DiskCleanupScanOptions(largeFileThreshold: 1)
        )
        #expect(candidates.map(\.url) == [installer])
    }

    @Test
    func cleanupRechecksTheKeeperAndRejectsForgedApplicationTargets() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let old = try fixture.application(name: "Google Chrome 2.app", version: "9.0")
        let current = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual])
        #expect(candidates.map(\.url) == [old])
        fixture.files.directoryContents[fixture.applications.path] = [old]
        let stale = SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files)
        #expect(stale.successCount == 0)
        #expect(stale.failures.map(\.url) == [old])
        #expect(stale.failures.first?.message == DiskCleanupError.applicationInstallationChanged.localizedDescription)
        #expect(fixture.files.trashedURLs.isEmpty)

        fixture.files.directoryContents[fixture.applications.path] = [old, current]
        let forged = DiskCleanupCandidate(url: current, kind: .applicationResidual, byteSize: 1, displayName: "forged")
        #expect(SystemDiskCleanup.trashSelected(candidates: [forged], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
        fixture.files.trashResults[old] = .success(fixture.root.appendingPathComponent(".Trash/Chrome.app"))
        let result = SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files)
        #expect(result.successCount == 1)
        #expect(result.failures.isEmpty)
        #expect(fixture.files.trashedURLs == [old])
    }

    @Test
    func cleanupRechecksRunningProcessesAndUpdatedCurrentPointers() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let app = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let versions = try fixture.frameworkVersions(in: app)
        let old = try fixture.version("9.0", in: versions)
        _ = try fixture.version("10.0", in: versions)
        try fixture.currentVersion("10.0", in: versions)
        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual])
        #expect(candidates.map(\.url) == [old])
        fixture.files.applicationProcesses = [old.appendingPathComponent("Helpers/Chrome Helper").path]
        #expect(SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files).successCount == 0)
        fixture.files.applicationProcesses = []
        try fixture.currentVersion("9.0", in: versions)
        #expect(SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func trashPermissionFailureIsReturnedWithoutADeletion() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        _ = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let old = try fixture.application(name: "Google Chrome 2.app", version: "9.0")
        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual])
        fixture.files.trashResults[old] = .failure(CocoaError(.fileWriteNoPermission))
        let result = SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files)
        #expect(result.successCount == 0)
        #expect(result.freedBytes == 0)
        #expect(result.failures.map(\.url) == [old])
        #expect(fixture.files.existingPaths.contains(old.path))
    }

    @Test
    func missingBuildVersionsKeepSortingDeterministic() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let current = try fixture.application(name: "Google Chrome.app", version: "10.0", build: "9")
        let missing = try fixture.application(name: "Google Chrome 2.app", version: "10.0", build: "invalid")
        let newerBuild = try fixture.application(name: "Google Chrome 3.app", version: "10.0", build: "10")
        for order in [[current, missing, newerBuild], [newerBuild, current, missing], [missing, newerBuild, current]] {
            fixture.files.directoryContents[fixture.applications.path] = order
            let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual])
            #expect(Set(candidates.map(\.url)) == Set([missing, newerBuild]))
            #expect(candidates.allSatisfy { $0.detail?.contains(current.path) == true })
        }
    }

    @Test(arguments: ["files", "files2"])
    func sealedOldVersionsRemainInTheSignedApplication(sealKey: String) throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let app = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let versions = try fixture.frameworkVersions(in: app)
        let old = try fixture.version("9.0", in: versions)
        _ = try fixture.version("10.0", in: versions)
        try fixture.currentVersion("10.0", in: versions)
        let signature = app.appendingPathComponent("Contents/_CodeSignature")
        try fixture.directory(signature)
        let seal = signature.appendingPathComponent("CodeResources")
        try fixture.plist(seal, [sealKey: [
            "Frameworks/Google Chrome Framework.framework/Versions/9.0/framework": Data([1]),
        ]])
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        try fixture.plist(seal, ["files2": ["Frameworks/Google Chrome Framework.framework": ["cdhash": Data([1])]]])
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).map(\.url) == [old])
        fixture.files.fileContentsData[seal.path] = Data("corrupt signature".utf8)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func linkedInfoFilesAndBundleContentsCannotEscapeTheApplication() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        _ = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let app = try fixture.application(name: "Google Chrome 2.app", version: "9.0")
        fixture.files.fileAttributes[app.appendingPathComponent("Contents").path] = [.type: FileAttributeType.typeSymbolicLink]
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        fixture.files.fileAttributes[app.appendingPathComponent("Contents").path] = [.type: FileAttributeType.typeDirectory]
        fixture.files.fileAttributes[app.appendingPathComponent("Contents/Info.plist").path] = [.type: FileAttributeType.typeSymbolicLink]
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func oversizedAndInvalidBundleMetadataCannotProduceCandidates() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        _ = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let app = try fixture.application(name: "Google Chrome 2.app", version: "9.0")
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        let original = try #require(fixture.files.fileContentsData[infoURL.path])
        var info = try #require(try PropertyListSerialization.propertyList(from: original, options: [], format: nil) as? [String: Any])
        info["Padding"] = String(repeating: "x", count: 1_048_577)
        try fixture.plist(infoURL, info)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        info.removeValue(forKey: "Padding")
        let escaped = fixture.root.appendingPathComponent("outside")
        fixture.file(escaped, data: Data([1]))
        for executable in ["../outside", "", "/usr/bin/true"] {
            info["CFBundleExecutable"] = executable
            try fixture.plist(infoURL, info)
            #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        }
        info["CFBundleExecutable"] = "../../../../outside"
        try fixture.plist(infoURL, info)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        info["CFBundleExecutable"] = "Google Chrome"
        info["CFBundlePackageType"] = "FMWK"
        try fixture.plist(infoURL, info)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        info["CFBundlePackageType"] = "APPL"
        info["CFBundleIdentifier"] = "com.apple.Chrome"
        try fixture.plist(infoURL, info)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func frameworksWithMismatchedMetadataOrLinkedVersionRootsAreKept() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let app = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let versions = try fixture.frameworkVersions(in: app)
        _ = try fixture.version("9.0", in: versions)
        let current = try fixture.version("10.0", in: versions)
        try fixture.currentVersion("10.0", in: versions)
        try fixture.plist(current.appendingPathComponent("Resources/Info.plist"), ["CFBundleShortVersionString": "9.0"])
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
        try fixture.plist(current.appendingPathComponent("Resources/Info.plist"), ["CFBundleShortVersionString": "10.0"])
        fixture.files.fileAttributes[versions.path] = [.type: FileAttributeType.typeSymbolicLink]
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func rootVersionPointersMustAgreeWithApplicationMetadata() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let app = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let versions = app.appendingPathComponent("Contents/Versions")
        try fixture.directory(versions)
        _ = try fixture.version("8.0", in: versions)
        _ = try fixture.version("9.0", in: versions)
        _ = try fixture.version("10.0", in: versions)
        try fixture.currentVersion("9.0", in: versions)
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func zeroSizeCopiesRemainOutsideTheCleanupList() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        _ = try fixture.application(name: "Google Chrome.app", version: "10.0")
        let old = try fixture.application(name: "Google Chrome 2.app", version: "9.0")
        for path in fixture.files.fileAttributes.keys where path.hasPrefix(old.path + "/") {
            if fixture.files.fileAttributes[path]?[.type] as? FileAttributeType == .typeRegular {
                fixture.files.fileAttributes[path]?[.size] = NSNumber(value: 0)
            }
        }
        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual]).isEmpty)
    }

    @Test
    func higherBuildWinsEvenWhenTheOlderBuildHasTheCanonicalName() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        let old = try fixture.application(name: "Google Chrome.app", version: "10.0", build: "9")
        let current = try fixture.application(name: "Google Chrome 2.app", version: "10.0", build: "10")
        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual])
        #expect(candidates.map(\.url) == [old])
        #expect(candidates.first?.detail?.contains(current.path) == true)
    }

    @Test
    func scanDepthIsBoundedAndOverlappingRootsVisitEachApplicationOnce() throws {
        let fixture = try InstallationCleanupFixture()
        defer { fixture.remove() }
        _ = try fixture.application(name: "Google Chrome.app", version: "10.0")
        fixture.files.searchPathResults[.documentDirectory] = [fixture.root, fixture.applications]
        let one = fixture.applications.appendingPathComponent("one")
        let two = one.appendingPathComponent("two")
        let three = two.appendingPathComponent("three")
        for url in [one, two, three] { try fixture.directory(url) }
        let old = try fixture.application(name: "Chrome 2.app", version: "9.0", at: two)
        _ = try fixture.application(name: "Chrome 3.app", version: "8.0", at: three)
        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.applicationResidual])
        #expect(candidates.map(\.url) == [old])
    }
}

private final class InstallationCleanupFixture {
    let files = MockFileManager()
    let root: URL
    let applications: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-installation-test-\(UUID().uuidString)")
        applications = root.appendingPathComponent("Applications")
        files.homeDirectory = root
        try directory(root)
        try directory(applications)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func directory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        files.existingPaths.insert(url.path)
        files.fileAttributes[url.path] = [.type: FileAttributeType.typeDirectory]
        files.directoryContents[url.path] = files.directoryContents[url.path] ?? []
        let parent = url.deletingLastPathComponent().path
        if files.directoryContents[parent]?.contains(url) == false {
            files.directoryContents[parent, default: []].append(url)
        }
    }

    func file(_ url: URL, data: Data) {
        files.existingPaths.insert(url.path)
        files.fileAttributes[url.path] = [.type: FileAttributeType.typeRegular, .size: NSNumber(value: data.count)]
        files.fileContentsData[url.path] = data
        files.directoryContents[url.deletingLastPathComponent().path, default: []].append(url)
    }

    func plist(_ url: URL, _ values: [String: Any]) throws {
        file(url, data: try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0))
    }

    func application(
        name: String,
        version: String,
        identifier: String = "com.google.Chrome",
        at parent: URL? = nil,
        build: String = "1"
    ) throws -> URL {
        let app = (parent ?? applications).appendingPathComponent(name, isDirectory: true).standardizedFileURL
        try directory(app)
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try directory(contents)
        try directory(macOS)
        file(macOS.appendingPathComponent("Google Chrome"), data: Data(repeating: 1, count: 4096))
        try plist(contents.appendingPathComponent("Info.plist"), [
            "CFBundleIdentifier": identifier,
            "CFBundleName": "Google Chrome",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "Google Chrome",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
        ])
        return app
    }

    func frameworkVersions(in app: URL) throws -> URL {
        let frameworks = app.appendingPathComponent("Contents/Frameworks")
        try directory(frameworks)
        let framework = frameworks.appendingPathComponent("Google Chrome Framework.framework")
        try directory(framework)
        let versions = framework.appendingPathComponent("Versions")
        try directory(versions)
        return versions
    }

    func version(_ name: String, in versions: URL) throws -> URL {
        let version = versions.appendingPathComponent(name, isDirectory: true).standardizedFileURL
        try directory(version)
        let resources = version.appendingPathComponent("Resources")
        try directory(resources)
        try plist(resources.appendingPathComponent("Info.plist"), ["CFBundleShortVersionString": name])
        file(version.appendingPathComponent("framework"), data: Data(repeating: 2, count: 4096))
        return version
    }

    func currentVersion(_ name: String, in versions: URL) throws {
        let current = versions.appendingPathComponent("Current")
        if (try? FileManager.default.attributesOfItem(atPath: current.path)) != nil {
            try FileManager.default.removeItem(at: current)
        } else {
            files.directoryContents[versions.path, default: []].append(current)
        }
        try FileManager.default.createSymbolicLink(atPath: current.path, withDestinationPath: name)
        files.existingPaths.insert(current.path)
        files.fileAttributes[current.path] = [.type: FileAttributeType.typeSymbolicLink]
    }
}
