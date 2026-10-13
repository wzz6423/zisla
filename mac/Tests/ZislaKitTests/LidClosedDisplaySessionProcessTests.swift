import Darwin
import Foundation
import Testing
@testable import ZislaKit

struct LidClosedDisplaySessionProcessTests {
    private static let script = #"""
    printf 'ready\n'
    while IFS= read -r request; do
        [ "$request" = stop ] || exit 1
        printf 'restored\n'
        exit 0
    done
    """#

    @Test
    func immediateRepeatedTogglesWaitForThePreviousProcessToReleaseTheLock() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let launcher = fixture.launcher()

        for _ in 0..<16 {
            let session = try launcher.start()
            try session.stop()
        }
    }

    @Test
    func separateApplicationInstancesCannotChangeTheSameSleepSettingConcurrently() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var first: LidClosedDisplaySessionProcess? = fixture.launcher()
        let session = try first!.start()
        defer { session.cancel() }
        first = nil

        #expect(throws: CocoaError.self) { try fixture.launcher().start() }
        try session.stop()
    }

    @Test
    func closingTheConnectionReleasesTheLeaseForTheNextRequest() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let launcher = fixture.launcher()
        let session = try launcher.start()
        session.cancel()

        let subsequent = try launcher.start()
        try subsequent.stop()
    }

    @Test
    func failedLeaseStartupProducesEOFPromptlyAndReleasesTheLock() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let launcher = fixture.launcher(script: "exit 1")
        for _ in 0..<2 {
            let started = ContinuousClock.now
            #expect(throws: CocoaError.self) { try launcher.start() }
            #expect(started.duration(to: .now) < .seconds(1))
        }
    }

    @Test(arguments: [false, true])
    func completedHelpersReleaseLocksInheritedByOtherProcesses(failsDuringStartup: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gatePath = fixture.directory.appendingPathComponent("release-descendant").path
        let pidPath = fixture.directory.appendingPathComponent("descendant-pid").path
        guard mkfifo(gatePath, 0o600) == 0 else { throw CocoaError(.fileWriteUnknown) }
        let gate = open(gatePath, O_RDWR | O_CLOEXEC)
        guard gate >= 0 else { throw CocoaError(.fileReadUnknown) }
        defer {
            let exited = DispatchGroup()
            var watcher: DispatchSourceProcess?
            if let text = try? String(contentsOfFile: pidPath, encoding: .utf8), let pid = Int32(text) {
                exited.enter()
                let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
                source.setEventHandler { exited.leave() }
                source.activate()
                watcher = source
            }
            #expect("\n".withCString { write(gate, $0, 1) } == 1)
            close(gate)
            #expect(exited.wait(timeout: .now() + 5) == .success)
            watcher?.cancel()
        }
        let launcher = fixture.launcher(script: """
        if [ ! -f '\(pidPath)' ]; then
            ( IFS= read -r release < '\(gatePath)' ) </dev/null >/dev/null 2>&1 &
            printf '%s' "$!" > '\(pidPath)'
            \(failsDuringStartup ? "exit 1" : "")
        fi
        \(Self.script)
        """)
        if failsDuringStartup {
            #expect(throws: CocoaError.self) { try launcher.start() }
        } else {
            let session = try launcher.start()
            defer { session.cancel() }
            #expect(throws: CocoaError.self) { try fixture.launcher().start() }
            try session.stop()
        }
        let descendant = try #require(Int32(String(contentsOfFile: pidPath, encoding: .utf8)))
        #expect(kill(descendant, 0) == 0)

        let subsequent = try launcher.start()
        defer { subsequent.cancel() }
        #expect(kill(descendant, 0) == 0)
        try subsequent.stop()
    }

    @Test
    func leaseProcessesDoNotInheritTheApplicationsCredentials() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let variable = "ZISLA_LEASE_TEST_" + UUID().uuidString.replacingOccurrences(of: "-", with: "_")
        setenv(variable, "fake-test-credential", 1)
        defer { unsetenv(variable) }
        let launcher = fixture.launcher(script: "test -z \"${\(variable)+x}\" || exit 1\n" + Self.script)

        let session = try launcher.start()
        try session.stop()
    }

    private struct Fixture {
        let directory: URL
        let lockPath: String

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-lease-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let file = directory.appendingPathComponent("system-executable")
            try Data().write(to: file)
            lockPath = file.path
        }

        func launcher(script: String = LidClosedDisplaySessionProcessTests.script) -> LidClosedDisplaySessionProcess {
            LidClosedDisplaySessionProcess(script: script, lockPath: lockPath)
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
