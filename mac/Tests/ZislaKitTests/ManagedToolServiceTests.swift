import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct ManagedToolServiceTests {
    private func releaseJSON(tag: String, assets: [String]) -> Data {
        let assetObjects = assets.map { name in
            """
            {"name":"\(name)","browser_download_url":"https://github.com/o/r/releases/download/\(tag)/\(name)"}
            """
        }.joined(separator: ",")
        return Data("""
        {"tag_name":"\(tag)","assets":[\(assetObjects)]}
        """.utf8)
    }

    @Test
    func ytDLPMatchesOnlyTheMacOSBinaryAsset() {
        #expect(ManagedTool.ytDLP.matchesAsset(name: "yt-dlp_macos"))
        #expect(ManagedTool.ytDLP.matchesAsset(name: "yt-dlp_linux") == false)
        // A same-named variant with a suffix must not match, otherwise the zip or checksum file would get installed.
        #expect(ManagedTool.ytDLP.matchesAsset(name: "yt-dlp_macos.zip") == false)
        #expect(ManagedTool.ytDLP.matchesAsset(name: "SHA2-256SUMS") == false)
    }

    @Test
    func libreOfficeUsesTheHomebrewCaskAndExpectedExecutablePaths() {
        #expect(ManagedTool.libreOffice.installationSource == .homebrewCask(name: "libreoffice"))
        #expect(ManagedTool.libreOffice.executableName == "soffice")
        #expect(ManagedToolService.externalPaths(for: .libreOffice).contains(
            "/Applications/LibreOffice.app/Contents/MacOS/soffice"
        ))
    }

    @Test
    func fzfUsesTheHomebrewFormulaAndExpectedExecutablePaths() {
        #expect(ManagedTool.fzf.installationSource == .homebrewFormula(name: "fzf"))
        #expect(ManagedTool.fzf.executableName == "fzf")
        #expect(ManagedToolService.externalPaths(for: .fzf).contains("/opt/homebrew/bin/fzf"))
    }

    @Test
    func ripgrepUsesTheHomebrewFormulaAndExpectedExecutablePaths() {
        #expect(ManagedTool.ripgrep.installationSource == .homebrewFormula(name: "ripgrep"))
        #expect(ManagedTool.ripgrep.executableName == "rg")
        #expect(ManagedToolService.externalPaths(for: .ripgrep).contains("/opt/homebrew/bin/rg"))
    }

    @Test
    func kakuUsesTheHomebrewCaskAndExpectedExecutablePaths() {
        #expect(ManagedTool.kaku.installationSource == .homebrewCask(name: "tw93/tap/kakuku"))
        #expect(ManagedTool.kaku.requiredHomebrewTap == "tw93/tap")
        #expect(ManagedTool.kaku.executableName == "kaku")
        #expect(ManagedToolService.externalPaths(for: .kaku).contains(
            "/Applications/Kaku.app/Contents/MacOS/kaku"
        ))
    }

    @Test
    func kekaUsesTheHomebrewCaskAndExpectedExecutablePaths() {
        #expect(ManagedTool.keka.installationSource == .homebrewCask(name: "keka"))
        #expect(ManagedTool.keka.executableName == "keka")
        #expect(ManagedTool.keka.usesNativeApplicationVersion)
        #expect(ManagedToolService.externalPaths(for: .keka).contains(
            "/Applications/Keka.app/Contents/MacOS/Keka"
        ))
    }

    @Test
    func recommendedCatalogIncludesEveryVerifiedHomebrewTool() {
        let expected: [(ManagedTool, ManagedToolInstallationSource, String)] = [
            (.delta, .homebrewFormula(name: "git-delta"), "delta"),
            (.githubCLI, .homebrewFormula(name: "gh"), "gh"),
            (.curl, .homebrewFormula(name: "curl"), "curl"),
            (.wget, .homebrewFormula(name: "wget"), "wget"),
            (.rclone, .homebrewFormula(name: "rclone"), "rclone"),
            (.posting, .homebrewFormula(name: "posting"), "posting"),
            (.poppler, .homebrewFormula(name: "poppler"), "pdftotext"),
            (.wireshark, .homebrewFormula(name: "wireshark"), "tshark"),
            (.mysql, .homebrewFormula(name: "mysql"), "mysql"),
            (.cmake, .homebrewFormula(name: "cmake"), "cmake"),
            (.gnuMake, .homebrewFormula(name: "make"), "gmake"),
            (.ninja, .homebrewFormula(name: "ninja"), "ninja"),
            (.gcc, .homebrewFormula(name: "gcc"), "gcc-16"),
            (.go, .homebrewFormula(name: "go"), "go"),
            (.rust, .homebrewFormula(name: "rust"), "rustc"),
            (.nodeJS, .homebrewFormula(name: "node"), "node"),
            (.deno, .homebrewFormula(name: "deno"), "deno"),
            (.python, .homebrewFormula(name: "python"), "python3"),
            (.ruby, .homebrewFormula(name: "ruby"), "ruby"),
            (.openJDK17, .homebrewFormula(name: "openjdk@17"), "java"),
            (.maven, .homebrewFormula(name: "maven"), "mvn"),
            (.groovy, .homebrewFormula(name: "groovy"), "groovy"),
            (.cocoaPods, .homebrewFormula(name: "cocoapods"), "pod"),
            (.pyenv, .homebrewFormula(name: "pyenv"), "pyenv"),
            (.pipx, .homebrewFormula(name: "pipx"), "pipx"),
            (.uv, .homebrewFormula(name: "uv"), "uv"),
            (.pnpm, .homebrewFormula(name: "pnpm"), "pnpm"),
            (.tectonic, .homebrewFormula(name: "tectonic"), "tectonic"),
            (.packer, .homebrewFormula(name: "hashicorp/tap/packer"), "packer"),
            (.ytt, .homebrewFormula(name: "ytt"), "ytt"),
            (.kero, .homebrewCask(name: "egoist/tap/kero"), "kero"),
        ]

        #expect(ManagedTool.allCases.count == 45)
        for (tool, source, executableName) in expected {
            #expect(tool.installationSource == source)
            #expect(tool.executableName == executableName)
        }
        #expect(ManagedTool.kero.requiredHomebrewTap == "egoist/tap")
        #expect(ManagedTool.packer.requiredHomebrewTap == "hashicorp/tap")
    }

    @Test
    func everyManagedToolAppearsInARecommendationGroup() {
        func count(_ group: ManagedToolRecommendationGroup) -> Int {
            ManagedTool.allCases.filter { $0.recommendationGroup == group }.count
        }

        #expect(count(.terminalEfficiency) == 11)
        #expect(count(.networkAndData) == 7)
        #expect(count(.developmentToolchain) == 21)
        #expect(count(.utility) == 3)
        #expect(count(.desktopApplication) == 3)
    }

    @Test
    func kegOnlyAndVersionedFormulaeUseDiscoverableExecutablePaths() {
        #expect(ManagedToolService.externalPaths(for: .curl).contains(
            "/opt/homebrew/opt/curl/bin/curl"
        ))
        #expect(ManagedToolService.externalPaths(for: .openJDK17).contains(
            "/opt/homebrew/opt/openjdk@17/bin/java"
        ))
        #expect(ManagedToolService.externalPaths(for: .gcc).contains(
            "/opt/homebrew/bin/gcc-16"
        ))
    }

    @Test
    func parsesTheStableVersionFromHomebrewCaskMetadata() throws {
        let data = Data("""
        {"casks":[{"token":"libreoffice","version":"26.2.5.2"}]}
        """.utf8)

        let version = try ManagedToolService.parseHomebrewCaskInfo(
            data,
            caskName: "libreoffice",
            tool: .libreOffice
        )

        #expect(version == "26.2.5")
        #expect(ManagedTool.libreOffice.normalizedInstalledVersion(from: "LibreOffice 26.2.5.2") == "26.2.5")
    }

    @Test
    func parsesTheStableVersionFromHomebrewFormulaMetadata() throws {
        let data = Data("""
        {"formulae":[{"name":"fzf","versions":{"stable":"0.55.0"}}]}
        """.utf8)

        let version = try ManagedToolService.parseHomebrewFormulaInfo(
            data,
            formulaName: "fzf",
            tool: .fzf
        )

        #expect(version == "0.55.0")
    }

    @Test
    func parseHomebrewFormulaInfoHandlesMultipleFormulae() throws {
        let data = Data("""
        {"formulae":[{"name":"other","versions":{"stable":"1.0.0"}},{"name":"jq","versions":{"stable":"1.7.1"}}]}
        """.utf8)

        let version = try ManagedToolService.parseHomebrewFormulaInfo(
            data,
            formulaName: "jq",
            tool: .jq
        )

        #expect(version == "1.7.1")
    }

    @Test
    func parsesFormulaAliasesAndHomebrewRevisions() throws {
        let pythonData = Data("""
        {"formulae":[{"name":"python@3.14","aliases":["python","python3"],"versions":{"stable":"3.14.7"},"revision":0}]}
        """.utf8)
        let postingData = Data("""
        {"formulae":[{"name":"posting","versions":{"stable":"2.10.0"},"revision":2}]}
        """.utf8)

        #expect(try ManagedToolService.parseHomebrewFormulaInfo(
            pythonData,
            formulaName: "python",
            tool: .python
        ) == "3.14.7")
        #expect(try ManagedToolService.parseHomebrewFormulaInfo(
            postingData,
            formulaName: "posting",
            tool: .posting
        ) == "2.10.0_2")
    }

    @Test
    func parsesTappedCaskMetadataByFullToken() throws {
        let data = Data("""
        {"casks":[{"token":"kero","full_token":"egoist/tap/kero","version":"0.1.47"}]}
        """.utf8)

        #expect(try ManagedToolService.parseHomebrewCaskInfo(
            data,
            caskName: "egoist/tap/kero",
            tool: .kero
        ) == "0.1.47")
    }

    @Test
    func parsesInstalledHomebrewFormulaVersions() {
        #expect(ManagedToolService.parseHomebrewInstalledVersion(
            "posting 2.10.0_2\n",
            tool: .posting
        ) == "2.10.0_2")
        #expect(ManagedToolService.parseHomebrewInstalledVersion(
            "python@3.14 3.14.6\n",
            tool: .python
        ) == "3.14.6")
        #expect(ManagedToolService.parseHomebrewInstalledVersion("", tool: .fzf) == nil)
    }

    @Test
    func parseHomebrewFormulaInfoFailsWhenFormulaNotFound() {
        let data = Data("""
        {"formulae":[{"name":"other","versions":{"stable":"1.0.0"}}]}
        """.utf8)

        #expect(throws: ManagedToolError.homebrewFailed("无法读取 fzf 的版本信息")) {
            try ManagedToolService.parseHomebrewFormulaInfo(data, formulaName: "fzf", tool: .fzf)
        }
    }

    @Test
    func parseReleaseStripsLeadingVAndPicksTheMatchingAsset() throws {
        let data = releaseJSON(tag: "v7.0.0", assets: [
            "yt-dlp_macos.zip",
            "yt-dlp_macos",
        ])
        let release = try ManagedToolService.parseRelease(data, tool: .ytDLP)
        #expect(release.version == "7.0.0")
        #expect(release.assetURL.lastPathComponent == "yt-dlp_macos")
    }

    @Test
    func parseReleaseFailsWhenNoAssetMatches() {
        let data = releaseJSON(tag: "v7.0.0", assets: ["yt-dlp_linux"])
        #expect(throws: ManagedToolError.assetNotFound(tool: "yt-dlp")) {
            try ManagedToolService.parseRelease(data, tool: .ytDLP)
        }
    }

    @Test
    func parseReleaseRejectsMalformedResponses() {
        #expect(throws: ManagedToolError.self) {
            try ManagedToolService.parseRelease(Data("not json".utf8), tool: .ytDLP)
        }
        #expect(throws: ManagedToolError.self) {
            try ManagedToolService.parseRelease(Data(#"{"assets":[]}"#.utf8), tool: .ytDLP)
        }
    }

    @Test
    func downloadHostsAreRestrictedToGitHub() throws {
        // Without checksum verification, provenance rests on TLS plus the host allowlist alone, so this constraint must hold.
        try ManagedToolService.validate(
            #require(URL(string: "https://github.com/o/r/releases/download/v1/tool"))
        )
        try ManagedToolService.validate(
            #require(URL(string: "https://objects.githubusercontent.com/x"))
        )

        for rejected in [
            "http://github.com/o/r/releases/download/v1/tool",
            "https://evil.example.com/tool",
            "https://github.com.evil.example.com/tool",
            "file:///tmp/tool",
        ] {
            let url = try #require(URL(string: rejected))
            #expect(throws: ManagedToolError.self) {
                try ManagedToolService.validate(url)
            }
        }
    }

    @Test
    func parseReleaseRejectsAnAssetOnAnUntrustedHost() {
        let data = Data("""
        {"tag_name":"v1.0.0","assets":[{"name":"yt-dlp_macos","browser_download_url":"https://evil.example.com/yt-dlp_macos"}]}
        """.utf8)
        #expect(throws: ManagedToolError.untrustedHost("evil.example.com")) {
            try ManagedToolService.parseRelease(data, tool: .ytDLP)
        }
    }

    @Test
    func versionNormalizationKeepsOnlyTheFirstLine() {
        #expect(ManagedToolService.normalizeVersion("7.0.0\n") == "7.0.0")
        #expect(ManagedToolService.normalizeVersion("v7.0.0") == "7.0.0")
        #expect(ManagedToolService.normalizeVersion("2026.06.09\nextra") == "2026.06.09")
        #expect(ManagedToolService.normalizeVersion("   ") == nil)
        #expect(ManagedToolService.normalizeVersion("") == nil)
    }

    @Test
    func executableVersionNormalizationExtractsTheSemanticVersion() {
        #expect(ManagedTool.fzf.normalizedInstalledVersion(from: "0.74.2 (Homebrew)") == "0.74.2")
        #expect(ManagedTool.lazygit.normalizedInstalledVersion(
            from: "commit=, build date=, build source=homebrew, version=0.64.1, os=darwin"
        ) == "0.64.1")
        #expect(ManagedTool.yazi.normalizedInstalledVersion(
            from: "Yazi 26.1.22 (Homebrew 2026-01-22)"
        ) == "26.1.22")
        #expect(ManagedTool.starship.normalizedInstalledVersion(from: "starship 1.26.0") == "1.26.0")
        #expect(ManagedTool.tldr.normalizedInstalledVersion(from: "tldr 3.4.0") == "3.4.0")
        #expect(ManagedTool.tree.normalizedInstalledVersion(from: "tree v2.3.2 (c) 1996") == "2.3.2")
        #expect(ManagedTool.delta.normalizedInstalledVersion(from: "delta 0.19.2") == "0.19.2")
        #expect(ManagedTool.fzf.installDetail.contains("Homebrew"))
    }

    @Test
    func processRunnerDrainsLargeStandardErrorWithoutBlocking() async {
        let result = await ManagedToolService.runProcess(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "i=0; while [ $i -lt 2048 ]; do printf xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx >&2; i=$((i + 1)); done; printf ready"]
        )

        switch result {
        case .success(let output):
            #expect(output == "ready")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test
    func updateIsOnlyReportedWhenBothVersionsAreKnown() {
        var state = ManagedToolState()
        #expect(state.hasUpdate == false)

        state.installedVersion = "7.0.0"
        #expect(state.hasUpdate == false, "只知已装版本时不该谎报有更新")

        state.latestVersion = "7.0.0"
        #expect(state.hasUpdate == false)

        state.latestVersion = "7.1.0"
        #expect(state.hasUpdate)
    }

    @Test
    func checkLatestSurfacesLoaderFailuresAsMessages() async {
        let service = ManagedToolService(
            toolsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            releaseLoader: { _ in throw ManagedToolError.releaseUnavailable("HTTP 503") }
        )
        let version = await service.checkLatest(.ytDLP)
        #expect(version == nil)
        #expect(service.states[.ytDLP]?.errorMessage == "获取版本信息失败：HTTP 503")
        #expect(service.states[.ytDLP]?.phase == .idle)
    }

    @Test
    func checkLatestRecordsTheLatestVersion() async {
        let payload = releaseJSON(tag: "2026.06.09", assets: ["yt-dlp_macos"])
        let service = ManagedToolService(
            toolsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            releaseLoader: { _ in payload }
        )
        let version = await service.checkLatest(.ytDLP)
        #expect(version == "2026.06.09")
        #expect(service.states[.ytDLP]?.latestVersion == "2026.06.09")
        #expect(service.states[.ytDLP]?.errorMessage == nil)
    }

    @Test
    func failedDownloadedToolValidationKeepsExistingManagedExecutable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-managed-tool-update-\(UUID().uuidString)", isDirectory: true)
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        let executable = tools.appendingPathComponent("yt-dlp", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let previousContents = Data("#!/bin/sh\necho 2026.06.08\n".utf8)
        try previousContents.write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        ManagedToolDownloadURLProtocol.responseData = Data("not an executable".utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManagedToolDownloadURLProtocol.self]
        let service = ManagedToolService(
            toolsDirectory: tools,
            bundleURL: root,
            session: URLSession(configuration: configuration),
            releaseLoader: { [payload = releaseJSON(tag: "2026.06.09", assets: ["yt-dlp_macos"])] _ in
                payload
            }
        )

        await service.install(.ytDLP)

        #expect(try Data(contentsOf: executable) == previousContents)
        #expect(service.states[.ytDLP]?.errorMessage != nil)
    }

    @Test
    func restoresCachedInstallAndLatestVersionsBeforeRefreshingAgain() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        let executable = tools.appendingPathComponent("yt-dlp", isDirectory: false)
        let suiteName = "ManagedToolServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho 2026.07.04\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let payload = releaseJSON(tag: "2026.07.05", assets: ["yt-dlp_macos"])
        let initial = ManagedToolService(
            toolsDirectory: tools,
            bundleURL: root,
            defaults: defaults,
            releaseLoader: { _ in payload }
        )
        await initial.refreshInstalledVersions()
        let latest = await initial.checkLatest(.ytDLP, quietly: true)
        #expect(latest == "2026.07.05")

        let restored = ManagedToolService(
            toolsDirectory: tools,
            bundleURL: root,
            defaults: defaults,
            releaseLoader: { _ in throw ManagedToolError.releaseUnavailable("不应请求网络") }
        )
        #expect(restored.states[.ytDLP]?.installedVersion == "2026.07.04")
        #expect(restored.states[.ytDLP]?.location == .managed)
        let restoredLatest = await restored.checkLatest(.ytDLP, quietly: true)
        #expect(restoredLatest == "2026.07.05")
    }

    @Test
    func unresolvedToolReportsNotInstalled() async {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = ManagedToolService(
            toolsDirectory: empty,
            bundleURL: empty,
            releaseLoader: { _ in Data() }
        )
        // This directory holds no executables, and yt-dlp is not necessarily installed system-wide, so only the directory resolution part is asserted here.
        #expect(service.resolvedExecutable(for: .ytDLP)?.location != .managed)
    }

    @Test
    func managedExecutableTakesPrecedenceOverBundled() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tools = root.appendingPathComponent("Tools", isDirectory: true)
        let helpers = root.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for directory in [tools, helpers] {
            let executable = directory.appendingPathComponent("yt-dlp")
            try Data("#!/bin/sh\necho 1.0.0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executable.path
            )
        }

        let service = ManagedToolService(
            toolsDirectory: tools,
            bundleURL: root,
            releaseLoader: { _ in Data() }
        )
        let resolved = try #require(service.resolvedExecutable(for: .ytDLP))
        #expect(resolved.location == .managed)
        #expect(resolved.url.path.hasPrefix(tools.resolvingSymlinksInPath().path))
    }
}

private final class ManagedToolDownloadURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/octet-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
