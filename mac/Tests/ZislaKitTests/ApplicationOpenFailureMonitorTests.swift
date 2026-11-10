import Foundation
import Testing
@testable import ZislaKit

@MainActor
struct ApplicationOpenFailureMonitorTests {
    @Test
    func disabledOrUntrustedMonitoringSubscribesToNothing() {
        let fixture = Fixture()
        let monitor = ApplicationOpenFailureMonitor(dependencies: fixture.dependencies)
        monitor.setEnabled(false) { _ in Issue.record("Disabled monitoring must not prompt") }
        #expect(fixture.processReads == 0 && fixture.callbacks.isEmpty && fixture.processChanged == nil)
        fixture.trusted = false
        monitor.setEnabled(true) { _ in Issue.record("Untrusted monitoring must not prompt") }
        #expect(fixture.processReads == 0 && fixture.callbacks.isEmpty && fixture.processChanged == nil)
    }

    @Test
    func oneSystemAlertProducesOneApplicationWithoutPolling() throws {
        let fixture = Fixture()
        let monitor = ApplicationOpenFailureMonitor(dependencies: fixture.dependencies)
        defer { monitor.stop() }
        var applications: [URL] = []
        monitor.setEnabled(true) { applications.append($0) }
        let receive = try #require(fixture.callbacks[41])
        #expect(fixture.processReads == 1)
        #expect(applications.isEmpty)
        receive(fixture.alert())
        receive(fixture.alert())
        #expect(applications == [fixture.app])
        #expect(fixture.processReads == 1)
        #expect(fixture.selectionReads == 0)
    }

    @Test
    func callbackCanResolveOneMatchingFinderSelection() throws {
        let fixture = Fixture()
        let monitor = ApplicationOpenFailureMonitor(dependencies: fixture.dependencies)
        defer { monitor.stop() }
        fixture.selection = [fixture.app]
        var applications: [URL] = []
        monitor.setEnabled(true) { applications.append($0) }
        let receive = try #require(fixture.callbacks[41])
        receive(fixture.alert(urls: []))
        #expect(applications == [fixture.app])
        #expect(fixture.selectionReads == 1)
    }

    @Test
    func disablingOrRevokingTrustCleansSubscriptionsAndIgnoresLateEvents() throws {
        let fixture = Fixture()
        let monitor = ApplicationOpenFailureMonitor(dependencies: fixture.dependencies)
        var applications: [URL] = []
        monitor.setEnabled(true) { applications.append($0) }
        let receive = try #require(fixture.callbacks[41])
        monitor.stop()
        receive(fixture.alert())
        #expect(applications.isEmpty)
        #expect(fixture.stopped == [41] && fixture.processChanged == nil)
        monitor.setEnabled(true) { applications.append($0) }
        let resumed = try #require(fixture.callbacks[41])
        fixture.trusted = false
        resumed(fixture.alert())
        #expect(applications.isEmpty)
        #expect(fixture.stopped == [41, 41] && fixture.processChanged == nil)
    }

    @Test
    func releasingTheMonitorCleansEverySubscription() throws {
        let fixture = Fixture()
        var monitor: ApplicationOpenFailureMonitor? = ApplicationOpenFailureMonitor(dependencies: fixture.dependencies)
        weak var released = monitor
        monitor?.setEnabled(true) { _ in Issue.record("A released monitor must not prompt") }
        let receive = try #require(fixture.callbacks[41])
        monitor = nil
        #expect(released == nil)
        released = nil
        #expect(fixture.stopped == [41] && fixture.callbacks.isEmpty && fixture.processChanged == nil)
        receive(fixture.alert())
    }

    @Test
    func systemAgentRelaunchReplacesItsObserver() throws {
        let fixture = Fixture()
        let monitor = ApplicationOpenFailureMonitor(dependencies: fixture.dependencies)
        defer { monitor.stop() }
        var applications: [URL] = []
        monitor.setEnabled(true) { applications.append($0) }
        let oldReceive = try #require(fixture.callbacks[41])
        fixture.processes = [42]
        fixture.processChanged?()
        #expect(fixture.stopped == [41])
        #expect(fixture.callbacks[42] != nil)
        oldReceive(fixture.alert())
        #expect(applications.isEmpty)
        let receive = try #require(fixture.callbacks[42])
        receive(fixture.alert())
        #expect(applications == [fixture.app])
    }

    @Test
    func alertTraversalHasAFixedElementAndTimeBudget() {
        var visited: [Int] = []
        ApplicationOpenFailureMonitor.walk(0, children: { [$0 + 1] }, now: { 0 }) { visited.append($0) }
        #expect(visited == Array(0..<64))
        visited = []
        var time: TimeInterval = 0
        ApplicationOpenFailureMonitor.walk(0, children: { [$0 + 1] }, now: { time }) {
            visited.append($0)
            time += 0.1
        }
        #expect(visited == [0, 1])
        visited = []
        ApplicationOpenFailureMonitor.walk(0, children: { _ in Array(1...1000) }, now: { 0 }) { visited.append($0) }
        #expect(visited == Array(0..<64))
    }

    @Test
    func unsupportedObserverStopsQuietlyAndCanRecoverOnTheNextEvent() throws {
        let fixture = Fixture()
        fixture.observerUnavailable = true
        let monitor = ApplicationOpenFailureMonitor(dependencies: fixture.dependencies)
        defer { monitor.stop() }
        var applications: [URL] = []
        monitor.setEnabled(true) { applications.append($0) }
        #expect(fixture.callbacks.isEmpty && applications.isEmpty)
        fixture.observerUnavailable = false
        fixture.processChanged?()
        let receive = try #require(fixture.callbacks[41])
        receive(fixture.alert())
        #expect(applications == [fixture.app])
    }

    @Test(arguments: [
        [URL(fileURLWithPath: "/tmp/Other.app")],
        [URL(fileURLWithPath: "/tmp/Example.app"), URL(fileURLWithPath: "/tmp/Other.app")],
        [URL(string: "https://example.com/Example.app")!], [],
    ])
    func ambiguousAndUnrelatedPathsDoNotPrompt(urls: [URL]) {
        let fixture = Fixture()
        let result = ApplicationOpenFailureMonitor.application(for: fixture.alert(urls: urls),
            templates: fixture.templates, candidates: [], names: { [$0.deletingPathExtension().lastPathComponent] })
        #expect(result == nil)
    }

    @Test(arguments: [
        "Do you want to open “Example”?", "Malware Blocked", "“Example” was not opened because it contains malware.",
        "“Example” cannot open the specified document.", "", "“Example\nforged” is damaged and can’t be opened.",
    ])
    func unrelatedOrUnsafeMessagesCannotSelectAnApplication(message: String) {
        let fixture = Fixture()
        var alert = fixture.alert()
        alert.messages = [message]
        #expect(ApplicationOpenFailureMonitor.application(for: alert, templates: fixture.templates,
            candidates: [], names: { _ in ["Example"] }) == nil)
    }

    @Test
    func ambiguousNamesAndInvalidTemplatesDoNotPrompt() {
        let fixture = Fixture()
        var alert = fixture.alert()
        alert.messages.append("“Other” is damaged and can’t be opened.")
        #expect(ApplicationOpenFailureMonitor.application(for: alert, templates: fixture.templates,
            candidates: [], names: { _ in ["Example", "Other"] }) == nil)
        for template in ["%@", "%@%@", "missing system catalog key"] {
            #expect(ApplicationOpenFailureMonitor.application(for: fixture.alert(), templates: [template],
                candidates: [], names: { _ in ["Example"] }) == nil)
        }
    }

    @Test(arguments: [
        ("“%@”已损坏，无法打开。", "“Example”已损坏，无法打开。"),
        ("“%@” is damaged and can’t be opened.", "“Example” is damaged and can’t be opened."),
        ("تعذّر فتح «%@».", "تعذّر فتح «Example»."),
    ])
    func alertLanguageIsIndependentOfZislaLanguage(pair: (String, String)) {
        let fixture = Fixture()
        var alert = fixture.alert()
        alert.messages = [pair.1]
        #expect(ApplicationOpenFailureMonitor.application(for: alert, templates: [pair.0],
            candidates: [], names: { _ in ["Example"] }) == fixture.app)
    }

    private final class Fixture {
        let app = URL(fileURLWithPath: "/tmp/Example.app")
        var templates = ["“%@” is damaged and can’t be opened.", "The application “%@” can’t be opened."]
        var trusted = true
        var processes: [pid_t] = [41]
        var processReads = 0
        var processChanged: (@MainActor () -> Void)?
        var callbacks: [pid_t: @MainActor (ApplicationOpenFailureMonitor.Alert) -> Void] = [:]
        var stopped: [pid_t] = []
        var selection: [URL] = []
        var selectionReads = 0
        var observerUnavailable = false

        var dependencies: ApplicationOpenFailureMonitor.Dependencies {
            .init(isTrusted: { self.trusted }, processes: { self.processReads += 1; return self.processes },
                observeProcesses: { changed in self.processChanged = changed; return { self.processChanged = nil } },
                observeAlerts: { pid, receive in
                    guard !self.observerUnavailable else { return nil }
                    self.callbacks[pid] = receive
                    return { self.stopped.append(pid); self.callbacks.removeValue(forKey: pid) }
                },
                finderSelection: { self.selectionReads += 1; return self.selection },
                templates: { self.templates }, applicationNames: { [$0.deletingPathExtension().lastPathComponent] })
        }

        func alert(urls: [URL]? = nil) -> ApplicationOpenFailureMonitor.Alert {
            .init(identifier: 7, messages: ["“Example” is damaged and can’t be opened."], applicationURLs: urls ?? [app])
        }
    }
}
