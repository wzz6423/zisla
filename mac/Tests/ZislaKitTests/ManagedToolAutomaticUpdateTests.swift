import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
struct ManagedToolAutomaticUpdateTests {
    @Test(arguments: ManagedTool.allCases, [(false, false), (true, false), (false, true), (true, true)])
    func schedulerUpdatesOnlyTheEnabledScope(tool: ManagedTool, enabled: (Bool, Bool)) async throws {
        let fixture = Fixture(tool: tool)
        let clock = UpdateClock()
        let service = fixture.service(sleep: { _ in try await clock.sleep() })
        await service.refreshInstalledVersions()
        let originalState = service.states[tool]
        fixture.commands = []
        let dependencies: Set<ManagedTool> = [.ytDLP, .ffmpeg, .libreOffice, .libvips, .libavif]
        let shouldUpdate = dependencies.contains(tool) ? enabled.1 : enabled.0

        service.setAutomaticUpdatesEnabled(recommendedTools: enabled.0, dependencyTools: enabled.1)
        if enabled.0 || enabled.1 { await clock.waitForSleeps(1) }
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        if enabled.0 || enabled.1 { await clock.waitForCancellations(1) }

        if !shouldUpdate {
            #expect(fixture.commands.isEmpty, "Disabled scope issued a package command for \(tool)")
            #expect(fixture.releaseRequests.isEmpty, "Disabled scope requested a release for \(tool)")
            #expect(service.states[tool] == originalState)
        } else if tool.usesHomebrew {
            #expect(fixture.commands.filter { $0.first == "upgrade" } == [["upgrade", fixture.kind, fixture.name]])
            #expect(service.states[tool]?.installedVersion == "2.0.0")
            #expect(service.states[tool]?.errorMessage == nil)
        } else {
            #expect(fixture.releaseRequests == [fixture.name])
            #expect(service.states[tool]?.errorMessage != nil)
        }
        #expect(service.states[tool]?.phase == .idle)
        #expect(!fixture.commands.contains { ["install", "tap"].contains($0.first ?? "") })
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
    }

    @Test(arguments: [ManagedTool.ffmpeg, .libreOffice, .libvips, .libavif])
    func missingDependenciesNeverStartPackageUpdates(tool: ManagedTool) async throws {
        let fixture = Fixture(tool: tool)
        fixture.executableExists = false
        let clock = UpdateClock()
        let service = fixture.service(sleep: { _ in try await clock.sleep() })
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: true)
        await clock.waitForSleeps(1)
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        await clock.waitForCancellations(1)

        #expect(fixture.commands.isEmpty)
        #expect(fixture.releaseRequests.isEmpty)
        #expect(service.states[tool]?.isInstalled == false)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
    }

    @Test
    func dependencySettingPersistsIndependentlyAndResetDisablesUpdates() throws {
        let defaults = InMemoryToolDefaults()
        defaults.set(Data(#"{"recommendedToolsEnabled":false,"recommendedToolsAutomaticUpdatesEnabled":true,"mediaEnabled":false}"#.utf8),
            forKey: "feature-settings-v1")
        let store = FeatureSettingsStore(defaults: defaults)
        #expect(!store.settings.dependencyToolsAutomaticUpdatesEnabled)
        store.settings.dependencyToolsAutomaticUpdatesEnabled = true
        store.flushPendingChanges()

        let restored = FeatureSettingsStore(defaults: defaults)
        #expect(restored.settings.dependencyToolsAutomaticUpdatesEnabled)
        #expect(!restored.settings.recommendedToolsEnabled)
        #expect(restored.settings.recommendedToolsAutomaticUpdatesEnabled)
        #expect(!restored.settings.mediaEnabled)
        restored.settings.recommendedToolsAutomaticUpdatesEnabled = false
        restored.flushPendingChanges()
        let independent = FeatureSettingsStore(defaults: defaults)
        #expect(independent.settings.dependencyToolsAutomaticUpdatesEnabled)
        #expect(!independent.settings.recommendedToolsAutomaticUpdatesEnabled)
        independent.reset()
        independent.flushPendingChanges()
        #expect(!FeatureSettingsStore(defaults: defaults).settings.dependencyToolsAutomaticUpdatesEnabled)
    }

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

    @Test(arguments: [ManagedTool.fzf, .ffmpeg, .libreOffice, .libvips, .libavif], ["info", "upgrade"])
    func dependencyFailureKeepsStateIdleAndCanRecoverOnTheNextCycle(tool: ManagedTool, failedCommand: String) async throws {
        let fixture = Fixture(tool: tool)
        fixture.failedCommand = failedCommand
        let service = fixture.service()

        await service.updateInstalledTools()
        #expect(service.states[tool]?.phase == .idle)
        #expect(service.states[tool]?.installedVersion == "1.0.0")
        #expect(service.states[tool]?.errorMessage != nil)

        fixture.failedCommand = nil
        await service.updateInstalledTools()
        #expect(service.states[tool]?.installedVersion == "2.0.0")
        #expect(service.states[tool]?.errorMessage == nil)
    }

    @Test
    func disablingDependenciesDuringReadPreventsUpgradeWhileRecommendationsContinue() async throws {
        let fixture = Fixture(tool: .ffmpeg)
        let clock = UpdateClock()
        let entered = Gate()
        let resume = Gate()
        fixture.beforeCommand = { arguments in
            if arguments.first == "info" {
                await entered.open()
                await resume.wait()
            }
        }
        let service = fixture.service(sleep: { _ in try await clock.sleep() })
        service.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: true)
        await entered.wait()
        service.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: false)
        await resume.open()
        await clock.waitForSleeps(1)
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        await clock.waitForCancellations(1)

        #expect(fixture.commands == [
            ["list", "--versions", "--formula", "ffmpeg"],
            ["info", "--formula", "--json=v2", "ffmpeg"],
        ])
        #expect(fixture.version == "1.0.0")
        #expect(service.states[.ffmpeg]?.installedVersion == "1.0.0")
        #expect(service.states[.ffmpeg]?.phase == .idle)
        #expect(service.states[.ffmpeg]?.errorMessage == nil)
    }

    @Test
    func applyingTheSameScopeDuringReadDoesNotRestartThePass() async throws {
        let fixture = Fixture(tool: .ffmpeg)
        let clock = UpdateClock()
        let entered = Gate()
        let resume = Gate()
        fixture.beforeCommand = { arguments in
            if arguments.first == "info" {
                await entered.open()
                await resume.wait()
            }
        }
        let service = fixture.service(sleep: { _ in try await clock.sleep() })
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: true)
        await entered.wait()
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: true)
        await resume.open()
        await clock.waitForSleeps(1)
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        await clock.waitForCancellations(1)

        #expect(fixture.commands.filter { $0.first == "info" }.count == 1)
        #expect(fixture.commands.filter { $0.first == "upgrade" }.count == 1)
        #expect(service.states[.ffmpeg]?.installedVersion == "2.0.0")
        #expect(service.states[.ffmpeg]?.phase == .idle)
    }

    @Test
    func enablingDependenciesWaitsForActivePackageTransactionThenUpdatesImmediately() async throws {
        let fixture = Fixture()
        let entered = Gate()
        let resume = Gate()
        let clock = UpdateClock()
        var versions = ["fzf": "1.0.0", "ffmpeg": "1.0.0"]
        var events: [String] = []
        let service = ManagedToolService(
            toolsDirectory: fixture.root, bundleURL: fixture.root, defaults: fixture.defaults,
            executableResolver: { tool in
                [.fzf, .ffmpeg].contains(tool) ? (fixture.root.appendingPathComponent(tool.executableName), .homebrew) : nil
            },
            homebrewRunner: { arguments, _ in
                let name = arguments.last!
                switch arguments.first {
                case "list": return "\(name) \(versions[name]!)"
                case "info": return "{\"formulae\":[{\"name\":\"\(name)\",\"versions\":{\"stable\":\"2.0.0\"}}]}"
                case "upgrade":
                    events.append("\(name)-started")
                    if name == "fzf" { await entered.open(); await resume.wait() }
                    #expect(!Task.isCancelled, "An active package transaction must finish without cancellation")
                    versions[name] = "2.0.0"
                    events.append("\(name)-finished")
                    return ""
                default: Issue.record("Unexpected automatic command: \(arguments)"); return ""
                }
            },
            automaticUpdateSleep: { _ in try await clock.sleep() }
        )
        service.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: false)
        await entered.wait()
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: true)
        await Task.yield()
        await resume.open()
        await clock.waitForSleeps(1)
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        await clock.waitForCancellations(1)

        #expect(events == ["fzf-started", "fzf-finished", "ffmpeg-started", "ffmpeg-finished"])
        #expect(service.states[.fzf]?.installedVersion == "2.0.0")
        #expect(service.states[.ffmpeg]?.installedVersion == "2.0.0")
        #expect(service.states[.fzf]?.phase == .idle)
        #expect(service.states[.ffmpeg]?.phase == .idle)
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
        service.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: false)
        await entered.wait()
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        service.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: false)
        await Task.yield()
        #expect(upgrades == ["fzf"])
        await resume.open()
        await clock.waitForSleeps(1)
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        await clock.waitForCancellations(1)
        #expect(upgrades == ["fzf", "ripgrep"])
        #expect(versions["fzf"] == "2.0.0")
        #expect(versions["ripgrep"] == "2.0.0")
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
        service.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: false)
        service.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: false)
        await clock.waitForSleeps(1)
        #expect(fixture.commands.filter { $0.first == "info" }.count == 1)

        fixture.version = "1.0.0"
        await clock.advance()
        await clock.waitForSleeps(2)
        #expect(fixture.commands.filter { $0.first == "upgrade" }.count == 2)
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        await clock.waitForCancellations(1)
        for _ in 0..<4 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        #expect(await clock.pendingSleeps == 0, "Disabled scheduling must release every daily timer")
        #expect(fixture.commands.filter { $0.first == "info" }.count == 2)

        service.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: false)
        await clock.waitForSleeps(3)
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        await clock.waitForCancellations(2)
        #expect(fixture.commands.filter { $0.first == "info" }.count == 3)
    }

    @Test
    func disablingDependenciesPreservesTheEnabledRecommendationScheduler() async throws {
        let fixture = Fixture()
        let clock = UpdateClock()
        let service = fixture.service(sleep: { _ in try await clock.sleep() })
        service.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: true)
        await clock.waitForSleeps(1)
        fixture.version = "1.0.0"
        service.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: false)
        await clock.waitForSleeps(2)
        #expect(service.states[.fzf]?.installedVersion == "2.0.0")
        #expect(fixture.commands.filter { $0.first == "upgrade" }.count == 2)
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        await clock.waitForCancellations(2)
    }

    @Test
    func releasingTheServiceCancelsItsSleepingScheduler() async throws {
        let fixture = Fixture()
        let clock = UpdateClock()
        var service: ManagedToolService? = fixture.service(sleep: { _ in try await clock.sleep() })
        weak var weakService = service
        service?.setAutomaticUpdatesEnabled(recommendedTools: true, dependencyTools: false)
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
        var releaseRequests: [String] = []
        var failedCommand: String?
        var beforeCommand: (([String]) async -> Void)?

        init(tool: ManagedTool = .fzf) {
            self.tool = tool
            switch tool.installationSource {
            case .homebrewCask(let name): self.name = name; kind = "--cask"
            case .homebrewFormula(let name): self.name = name; kind = "--formula"
            case .githubRelease(let name): self.name = name; kind = ""
            }
        }

        func service(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) -> ManagedToolService {
            ManagedToolService(
                toolsDirectory: root.appendingPathComponent("Tools"), bundleURL: root, defaults: defaults,
                releaseLoader: { [self] repository in
                    releaseRequests.append(repository)
                    throw URLError(.notConnectedToInternet)
                },
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

    var pendingSleeps: Int { sleepers.count }

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
        let clock = UpdateClock()
        let service = fixture.service(sleep: { _ in try await clock.sleep() })

        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: true)
        await clock.waitForSleeps(1)
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        await clock.waitForCancellations(1)

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
        let clock = UpdateClock()
        let service = fixture.service(
            load: { _ in Issue.record("Missing tool triggered a release lookup"); return Data() },
            sleep: { _ in try await clock.sleep() }
        )

        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: true)
        await clock.waitForSleeps(1)
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
        await clock.waitForCancellations(1)

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
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: true)
        await entered.wait()
        service.setAutomaticUpdatesEnabled(recommendedTools: false, dependencyTools: false)
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
            resolve: (() -> (url: URL, location: ManagedToolState.Location)?)? = nil,
            sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
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
                homebrewRunner: { _, _ in Issue.record("GitHub update invoked Homebrew"); return "" },
                automaticUpdateSleep: sleep
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
