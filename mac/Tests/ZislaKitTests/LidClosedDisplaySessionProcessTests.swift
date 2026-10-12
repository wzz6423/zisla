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
