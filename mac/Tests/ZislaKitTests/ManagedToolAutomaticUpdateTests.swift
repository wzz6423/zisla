import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
struct ManagedToolAutomaticUpdateTests {
    @Test(arguments: [ManagedTool.fzf, .kaku, .openScreen])
    func updatesOnlyRegisteredPackagesWithoutInstallingOrTapping(_ tool: ManagedTool) async throws {
        let fixture = Fixture(tool: tool)
        let service = fixture.service()
        service.setNetworkProxy(url: "http://127.0.0.1:7890", enabled: true)

        await service.updateInstalledTools()

        #expect(fixture.commands.filter { $0.first == "upgrade" } == [["upgrade", fixture.kind, fixture.name]])
        #expect(!fixture.commands.contains { ["install", "tap"].contains($0.first ?? "") })
        #expect(service.states[tool]?.installedVersion == "2.0.0")
        #expect(service.states[tool]?.phase == .idle)
        #expect(fixture.environments.allSatisfy { $0["https_proxy"] == "http://127.0.0.1:7890" })
    }

    @Test(arguments: [false, true])
    func missingAndUnregisteredToolsAreNeverInstalled(_ executableExists: Bool) async throws {
        let fixture = Fixture()
        fixture.executableExists = executableExists
        fixture.registered = false
        let service = fixture.service()

        await service.updateInstalledTools()

        #expect(!fixture.commands.contains { $0.first == "info" })
        #expect(!fixture.commands.contains { ["upgrade", "install", "tap"].contains($0.first ?? "") })
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Tools").path))
    }

    @Test
    func removalDuringVersionLookupPreventsUpgrade() async throws {
        let fixture = Fixture()
        fixture.beforeCommand = { arguments in
            if arguments.first == "info" { fixture.registered = false }
        }
        let service = fixture.service()

        await service.updateInstalledTools()

        #expect(!fixture.commands.contains { $0.first == "upgrade" })
        #expect(service.states[.fzf]?.phase == .idle)
    }

    @Test
    func executableRemovalWithStalePackageRegistrationPreventsUpgrade() async throws {
        let fixture = Fixture()
        fixture.beforeCommand = { arguments in
            if arguments.first == "info" { fixture.executableExists = false }
        }
        let service = fixture.service()

        await service.updateInstalledTools()

        #expect(!fixture.commands.contains { $0.first == "upgrade" })
    }

    @Test
    func anExternalUpgradeDuringLookupIsNotRepeated() async throws {
        let fixture = Fixture()
        fixture.beforeCommand = { arguments in
            if arguments.first == "info" { fixture.version = "3.0.0" }
        }
        let service = fixture.service()
        await service.updateInstalledTools()
        #expect(!fixture.commands.contains { $0.first == "upgrade" })
        #expect(service.states[.fzf]?.installedVersion == "3.0.0")
    }

    @Test(arguments: ["2.0.0", "3.0.0"])
    func currentAndNewerVersionsAreNotReplaced(_ version: String) async throws {
        let fixture = Fixture()
        fixture.version = version
        let service = fixture.service()

        await service.updateInstalledTools()

        #expect(fixture.commands.filter { $0.first == "list" }.count == 1)
        #expect(!fixture.commands.contains { $0.first == "upgrade" })
        #expect(service.states[.fzf]?.installedVersion == version)
    }

    @Test(arguments: ["info", "upgrade"])
    func dependencyFailureKeepsStateIdleAndCanRecoverOnTheNextCycle(_ failedCommand: String) async throws {
        let fixture = Fixture()
        fixture.failedCommand = failedCommand
        let service = fixture.service()

        await service.updateInstalledTools()
        #expect(service.states[.fzf]?.phase == .idle)
        #expect(service.states[.fzf]?.installedVersion == "1.0.0")
        #expect(service.states[.fzf]?.errorMessage != nil)

        fixture.failedCommand = nil
        await service.updateInstalledTools()
        #expect(service.states[.fzf]?.installedVersion == "2.0.0")
        #expect(service.states[.fzf]?.errorMessage == nil)
    }

    @Test(arguments: [1, 2, 3])
    func cancellationDuringReadPreventsTheNextCommand(_ cancelledRead: Int) async throws {
        let fixture = Fixture()
        let entered = Gate()
        let resume = Gate()
        fixture.beforeCommand = { _ in
            if fixture.commands.count == cancelledRead {
                await entered.open()
                await resume.wait()
            }
        }
        let service = fixture.service()
        let cycle = Task { await service.updateInstalledTools() }
        await entered.wait()
        cycle.cancel()
        await resume.open()
        await cycle.value

        #expect(fixture.commands.count == cancelledRead)
        #expect(!fixture.commands.contains { $0.first == "upgrade" })
        #expect(service.states[.fzf]?.phase == .idle)
    }

    @Test
    func disablingLetsAnActivePackageTransactionFinishAndSkipsRemainingTools() async throws {
        let fixture = Fixture()
        let entered = Gate()
        let resume = Gate()
        var transactionWasCancelled = false
        fixture.beforeCommand = { arguments in
            if arguments.first == "upgrade" {
                await entered.open()
                await resume.wait()
                transactionWasCancelled = Task.isCancelled
            }
            if arguments.first == "list", fixture.version == "2.0.0" {
                transactionWasCancelled = transactionWasCancelled || Task.isCancelled
            }
        }
        let service = fixture.service()
        let cycle = Task { await service.updateInstalledTools() }
        await entered.wait()
        cycle.cancel()
        await resume.open()
        await cycle.value

        #expect(!transactionWasCancelled)
        #expect(service.states[.fzf]?.installedVersion == "2.0.0")
        #expect(service.states[.fzf]?.phase == .idle)
    }

    @Test
    func concurrentPassesSkipAnAlreadyUpdatingTool() async throws {
        let fixture = Fixture()
        let entered = Gate()
        let resume = Gate()
        fixture.beforeCommand = { arguments in
            if arguments.first == "install" {
                await entered.open()
                await resume.wait()
            }
        }
        let service = fixture.service()
        let first = Task { await service.install(.fzf) }
        await entered.wait()
        await service.updateInstalledTools()
        await resume.open()
        await first.value

        #expect(fixture.commands.filter { $0.first == "install" }.count == 1)
        #expect(!fixture.commands.contains { $0.first == "upgrade" })
        #expect(service.states[.fzf]?.installedVersion == "2.0.0")
    }

    @Test
    func disablingAndImmediatelyReenablingDoesNotOverlapDifferentPackageTransactions() async throws {
        let fixture = Fixture()
        let entered = Gate()
        let resume = Gate()
        let clock = UpdateClock()
        var versions = ["fzf": "1.0.0", "ripgrep": "1.0.0"]
        var upgrades: [String] = []
        let service = ManagedToolService(
            toolsDirectory: fixture.root, bundleURL: fixture.root, defaults: fixture.defaults,
            executableResolver: { tool in
                [.fzf, .ripgrep].contains(tool) ? (fixture.root.appendingPathComponent(tool.executableName), .homebrew) : nil
            },
            homebrewRunner: { arguments, _ in
                let name = arguments.last!
                switch arguments.first {
                case "list": return "\(name) \(versions[name]!)"
                case "info": return "{\"formulae\":[{\"name\":\"\(name)\",\"versions\":{\"stable\":\"2.0.0\"}}]}"
                case "upgrade":
                    upgrades.append(name)
                    if name == "fzf" { await entered.open(); await resume.wait() }
                    versions[name] = "2.0.0"
                    return ""
                default: Issue.record("Unexpected automatic command: \(arguments)"); return ""
                }
            },
            automaticUpdateSleep: { _ in try await clock.sleep() }
        )
        service.setAutomaticUpdatesEnabled(true)
        await entered.wait()
        service.setAutomaticUpdatesEnabled(false)
        service.setAutomaticUpdatesEnabled(true)
        await clock.waitForSleeps(1)
        #expect(upgrades == ["fzf"])
        service.setAutomaticUpdatesEnabled(false)
        await clock.waitForCancellations(1)
        await resume.open()
        for await states in service.$states.values {
            if states[.fzf]?.phase == .idle { break }
        }
        #expect(versions["fzf"] == "2.0.0")
        #expect(versions["ripgrep"] == "1.0.0")
    }

    @Test
    func schedulerStartsOnceStopsAndCanBeEnabledAgain() async throws {
        let fixture = Fixture()
        let clock = UpdateClock()
        let service = fixture.service(sleep: { duration in
            #expect(duration == .seconds(86_400))
            try await clock.sleep()
        })
        #expect(fixture.commands.isEmpty)
        service.setAutomaticUpdatesEnabled(true)
        service.setAutomaticUpdatesEnabled(true)
        await clock.waitForSleeps(1)
        #expect(fixture.commands.filter { $0.first == "info" }.count == 1)

        fixture.version = "1.0.0"
        await clock.advance()
        await clock.waitForSleeps(2)
        #expect(fixture.commands.filter { $0.first == "upgrade" }.count == 2)
        service.setAutomaticUpdatesEnabled(false)
        await clock.waitForCancellations(1)
        #expect(fixture.commands.filter { $0.first == "info" }.count == 2)

        service.setAutomaticUpdatesEnabled(true)
        await clock.waitForSleeps(3)
        service.setAutomaticUpdatesEnabled(false)
        await clock.waitForCancellations(2)
        #expect(fixture.commands.filter { $0.first == "info" }.count == 3)
    }

    @Test
    func releasingTheServiceCancelsItsSleepingScheduler() async throws {
        let fixture = Fixture()
        let clock = UpdateClock()
        var service: ManagedToolService? = fixture.service(sleep: { _ in try await clock.sleep() })
        weak var weakService = service
        service?.setAutomaticUpdatesEnabled(true)
        await clock.waitForSleeps(1)
        service = nil
        await clock.waitForCancellations(1)
        #expect(weakService == nil)
    }

    @Test
    func removedToolIsNotReinstalledFromCachedState() async throws {
        let fixture = Fixture()
        await fixture.service().updateInstalledTools()
        fixture.executableExists = false
        fixture.commands = []
        let restored = fixture.service()
        #expect(restored.states[.fzf]?.isInstalled == true)

        await restored.updateInstalledTools()

        #expect(fixture.commands.isEmpty)
        #expect(restored.states[.fzf]?.isInstalled == false)
    }

    @Test
    func cancelledPassDoesNotStartAnyLookup() async throws {
        let fixture = Fixture()
        let service = fixture.service()
        let cycle = Task { await service.updateInstalledTools() }
        cycle.cancel()
        await cycle.value
        #expect(fixture.commands.isEmpty)
    }

    @MainActor
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-auto-tools-\(UUID().uuidString)")
        let defaults = InMemoryToolDefaults()
        let tool: ManagedTool
        let name: String
        let kind: String
        var version = "1.0.0"
        var registered = true
        var executableExists = true
        var commands: [[String]] = []
        var environments: [[String: String]] = []
        var failedCommand: String?
        var beforeCommand: (([String]) async -> Void)?

        init(tool: ManagedTool = .fzf) {
            self.tool = tool
            switch tool.installationSource {
            case .homebrewCask(let name): self.name = name; kind = "--cask"
            case .homebrewFormula(let name): self.name = name; kind = "--formula"
            case .githubRelease: preconditionFailure("Use a Homebrew tool fixture")
            }
        }

        func service(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) -> ManagedToolService {
            ManagedToolService(
                toolsDirectory: root.appendingPathComponent("Tools"), bundleURL: root, defaults: defaults,
                releaseLoader: { _ in Issue.record("Unexpected GitHub request"); return Data() },
                executableResolver: { [self] candidate in
                    candidate == tool && executableExists ? (root.appendingPathComponent(tool.executableName), .homebrew) : nil
                },
                homebrewRunner: { [self] arguments, environment in
                    commands.append(arguments)
                    environments.append(environment)
                    await beforeCommand?(arguments)
                    if arguments.first == failedCommand { throw ManagedToolError.homebrewFailed("injected failure") }
                    switch arguments.first {
                    case "list": return registered ? "\(name) \(version)\n" : ""
                    case "info":
                        return kind == "--cask"
                            ? "{\"casks\":[{\"full_token\":\"\(name)\",\"version\":\"2.0.0\"}]}"
                            : "{\"formulae\":[{\"name\":\"\(name)\",\"versions\":{\"stable\":\"2.0.0\"}}]}"
                    case "upgrade", "install": version = "2.0.0"; return ""
                    default: Issue.record("Automatic updates issued an unsafe command: \(arguments)"); return ""
                    }
                },
                automaticUpdateSleep: sleep
            )
        }

    }
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor UpdateClock {
    private var sleeps = 0
    private var cancellations = 0
    private var sleepers: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var observers: [(Int, Bool, CheckedContinuation<Void, Never>)] = []

    func sleep() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = continuation
                sleeps += 1
                notifyObservers()
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func advance() {
        let pending = sleepers.values
        sleepers.removeAll()
        pending.forEach { $0.resume() }
    }

    func waitForSleeps(_ count: Int) async { await waitFor(count, cancellation: false) }
    func waitForCancellations(_ count: Int) async { await waitFor(count, cancellation: true) }

    private func waitFor(_ count: Int, cancellation: Bool) async {
        if (cancellation ? cancellations : sleeps) >= count { return }
        await withCheckedContinuation { observers.append((count, cancellation, $0)) }
    }

    private func cancel(_ id: UUID) {
        sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError())
        cancellations += 1
        notifyObservers()
    }

    private func notifyObservers() {
        observers.removeAll { count, cancellation, continuation in
            guard (cancellation ? cancellations : sleeps) >= count else { return false }
            continuation.resume()
            return true
        }
    }
}

@MainActor
@Suite(.serialized)
struct ManagedToolGitHubAutomaticUpdateTests {
    @Test
    func networkFailureDoesNotReplaceTheBinaryAndRemainsVisible() async throws {
        let fixture = try GitHubFixture()
        defer { fixture.cleanUp() }
        let previous = try Data(contentsOf: fixture.executable)
        let service = fixture.service(load: { _ in throw URLError(.notConnectedToInternet) })

        await service.updateInstalledTools()

        #expect(service.states[.ytDLP]?.phase == .idle)
        #expect(service.states[.ytDLP]?.location == .managed)
        #expect(service.states[.ytDLP]?.errorMessage != nil)
        #expect(try Data(contentsOf: fixture.executable) == previous)
        #expect(AutomaticToolDownloadProtocol.requests == 0)
    }

    @Test
    func replacesAnInstalledBinaryAndCleansStagingFiles() async throws {
        let fixture = try GitHubFixture()
        defer { fixture.cleanUp() }
        let service = fixture.service()

        await service.updateInstalledTools()

        #expect(service.states[.ytDLP]?.installedVersion == "2.0.0")
        #expect(service.states[.ytDLP]?.location == .managed)
        #expect(try Data(contentsOf: fixture.executable) == AutomaticToolDownloadProtocol.payload)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.tools.path) == ["yt-dlp"])
    }

    @Test
    func uninstallDuringDownloadDoesNotRecreateTheTool() async throws {
        let fixture = try GitHubFixture()
        defer { fixture.cleanUp() }
        var resolutions = 0
        let service = fixture.service(resolve: {
            resolutions += 1
            if resolutions == 3 { try? FileManager.default.removeItem(at: fixture.executable) }
            return FileManager.default.fileExists(atPath: fixture.executable.path) ? (fixture.executable, .managed) : nil
        })

        await service.updateInstalledTools()

        #expect(!FileManager.default.fileExists(atPath: fixture.executable.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.tools.path).isEmpty)
        #expect(service.states[.ytDLP]?.phase == .idle)
    }

    @Test
    func invalidDownloadPreservesTheInstalledBinary() async throws {
        let fixture = try GitHubFixture()
        defer { fixture.cleanUp() }
        AutomaticToolDownloadProtocol.payload = Data("not an executable".utf8)
        let previous = try Data(contentsOf: fixture.executable)
        let service = fixture.service()

        await service.updateInstalledTools()

        #expect(try Data(contentsOf: fixture.executable) == previous)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.tools.path) == ["yt-dlp"])
        #expect(service.states[.ytDLP]?.phase == .idle)
    }

    @Test(arguments: ["2.0.0", "3.0.0"])
    func skipsCurrentAndNewerGitHubBinaries(_ installed: String) async throws {
        let fixture = try GitHubFixture(version: installed)
        defer { fixture.cleanUp() }
        let previous = try Data(contentsOf: fixture.executable)
        let service = fixture.service()

        await service.updateInstalledTools()

        #expect(AutomaticToolDownloadProtocol.requests == 0)
        #expect(try Data(contentsOf: fixture.executable) == previous)
    }

    @Test
    func missingGitHubToolNeverRequestsAReleaseOrDownload() async throws {
        let fixture = try GitHubFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.removeItem(at: fixture.executable)
        let service = fixture.service(load: { _ in Issue.record("Missing tool triggered a release lookup"); return Data() })

        await service.updateInstalledTools()

        #expect(AutomaticToolDownloadProtocol.requests == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.executable.path))
    }

    @Test
    func disablingDuringReleaseLookupPreventsTheDownload() async throws {
        let fixture = try GitHubFixture()
        defer { fixture.cleanUp() }
        let entered = Gate()
        let resume = Gate()
        let service = fixture.service(load: { _ in
            await entered.open()
            await resume.wait()
            return GitHubFixture.release
        })
        service.setAutomaticUpdatesEnabled(true)
        await entered.wait()
        service.setAutomaticUpdatesEnabled(false)
        await resume.open()
        // The idle transition is the completion event for a cancellation-resistant loader.
        for await states in service.$states.values {
            if states[.ytDLP]?.phase == .idle { break }
        }

        #expect(AutomaticToolDownloadProtocol.requests == 0)
        #expect(try String(contentsOf: fixture.executable, encoding: .utf8).contains("1.0.0"))
    }

    @MainActor
    private final class GitHubFixture {
        static let release = Data("""
        {"tag_name":"v2.0.0","assets":[{"name":"yt-dlp_macos","browser_download_url":"https://github.com/o/r/releases/download/v2/yt-dlp_macos"}]}
        """.utf8)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-auto-github-\(UUID().uuidString)")
        let defaults = InMemoryToolDefaults()
        var tools: URL { root.appendingPathComponent("Tools") }
        var executable: URL { tools.appendingPathComponent("yt-dlp") }

        init(version: String = "1.0.0") throws {
            try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
            try Data("#!/bin/sh\necho \(version)\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            AutomaticToolDownloadProtocol.payload = Data("#!/bin/sh\necho 2.0.0\n".utf8)
            AutomaticToolDownloadProtocol.requests = 0
        }

        func service(
            load: ((String) async throws -> Data)? = nil,
            resolve: (() -> (url: URL, location: ManagedToolState.Location)?)? = nil
        ) -> ManagedToolService {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AutomaticToolDownloadProtocol.self]
            return ManagedToolService(
                toolsDirectory: tools, bundleURL: root,
                session: URLSession(configuration: configuration), defaults: defaults,
                releaseLoader: load ?? { _ in Self.release },
                executableResolver: { [self] tool in
                    guard tool == .ytDLP else { return nil }
                    if let resolve { return resolve() }
                    return FileManager.default.fileExists(atPath: executable.path) ? (executable, .managed) : nil
                },
                homebrewRunner: { _, _ in Issue.record("GitHub update invoked Homebrew"); return "" }
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private final class AutomaticToolDownloadProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class InMemoryToolDefaults: UserDefaults {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    override func data(forKey defaultName: String) -> Data? {
        lock.withLock { values[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value as? Data }
    }
}
