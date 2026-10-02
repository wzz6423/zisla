import Combine
import Foundation
import Testing
@testable import ZislaKit

@Suite(.timeLimit(.minutes(1)))
struct SignificantEnergyMonitorTests {
    private static let first = SignificantEnergyProcess(
        bundleIdentifier: "com.example.renderer",
        responsibleBundleIdentifier: "com.example.editor",
        displayName: "Example Renderer"
    )
    private static let second = SignificantEnergyProcess(
        bundleIdentifier: "com.example.player",
        responsibleBundleIdentifier: "com.example.player",
        displayName: "Example Player"
    )

    @Test
    func preservesNativeOrderAndResponsibleApplications() throws {
        let payload: NSDictionary = [
            "bundle_identifiers": [Self.first.bundleIdentifier, Self.second.bundleIdentifier],
            "responsible_bundle_identifiers": [
                Self.first.responsibleBundleIdentifier, Self.second.responsibleBundleIdentifier,
            ],
            "display_names": [Self.first.displayName, Self.second.displayName],
            "energy_impacts": [1, 999_999],
        ]

        #expect(try NativeSignificantEnergyReader.parse(payload) == [Self.first, Self.second])
    }

    @Test
    func emptyNativeArraysProduceAnEmptyList() throws {
        #expect(try NativeSignificantEnergyReader.parse([
            "bundle_identifiers": [String](),
            "responsible_bundle_identifiers": [String](),
            "display_names": [String](),
        ]) == [])
    }

    @Test
    func absentDisplayNameKeepsTheSystemIdentifier() throws {
        let processes = try NativeSignificantEnergyReader.parse([
            "bundle_identifiers": [Self.first.bundleIdentifier],
            "responsible_bundle_identifiers": [""],
            "display_names": [""],
        ])

        #expect(processes.first?.displayName == Self.first.bundleIdentifier)
        #expect(processes.first?.responsibleBundleIdentifier == "")
    }

    @Test(arguments: ["bundle_identifiers", "responsible_bundle_identifiers", "display_names"])
    func missingNativeFieldDoesNotLookLikeAnEmptyList(_ field: String) {
        let payload = NSMutableDictionary(dictionary: Self.payload)
        payload.removeObject(forKey: field)

        #expect(throws: SignificantEnergyUnavailableReason.invalidResponse) {
            try NativeSignificantEnergyReader.parse(payload)
        }
    }

    @Test(arguments: ["bundle_identifiers", "responsible_bundle_identifiers", "display_names"])
    func redactedNativeFieldReportsDeniedAccess(_ field: String) {
        let payload = NSMutableDictionary(dictionary: Self.payload)
        payload[field] = ["REDACTED"]

        #expect(throws: SignificantEnergyUnavailableReason.permissionDenied) {
            try NativeSignificantEnergyReader.parse(payload)
        }
    }

    @Test(arguments: ["", " ", "\n\t"])
    func emptyIdentifierIsRejected(_ identifier: String) {
        let payload = NSMutableDictionary(dictionary: Self.payload)
        payload["bundle_identifiers"] = [identifier]

        #expect(throws: SignificantEnergyUnavailableReason.invalidResponse) {
            try NativeSignificantEnergyReader.parse(payload)
        }
    }

    @Test
    func malformedNativeArraysFailWithinAFixedInputBudget() {
        let fields = ["bundle_identifiers", "responsible_bundle_identifiers", "display_names"]
        var seed: UInt64 = 0x6E_6572_6779
        for _ in 0..<64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let count = Int((seed >> 8) % 5) + 1
            let field = fields[Int((seed >> 16) % 3)]
            let strings = (0..<count).map { "com.example.application.\($0)" }
            let payload = NSMutableDictionary(dictionary: [
                fields[0]: strings, fields[1]: strings, fields[2]: strings,
            ])
            switch (seed >> 24) % 4 {
            case 0: payload.removeObject(forKey: field)
            case 1: payload[field] = [1]
            case 2: payload[field] = Array(strings.dropLast())
            default: payload[field] = [NSNull()]
            }

            #expect(throws: SignificantEnergyUnavailableReason.invalidResponse) {
                try NativeSignificantEnergyReader.parse(payload)
            }
        }
    }

    @Test
    @MainActor
    func emptyReadPublishesAvailableRatherThanUnavailable() async {
        let monitor = SignificantEnergyMonitor(reader: { [] })

        await monitor.refresh().value

        #expect(monitor.state == .available([]))
    }

    @Test(arguments: [
        SignificantEnergyUnavailableReason.unsupported, .permissionDenied, .invalidResponse, .readFailed,
    ])
    @MainActor
    func readFailuresPublishTheirSpecificReason(_ reason: SignificantEnergyUnavailableReason) async {
        let monitor = SignificantEnergyMonitor(reader: { throw reason })

        await monitor.refresh().value

        #expect(monitor.state == .unavailable(reason))
    }

    @Test
    @MainActor
    func unexpectedErrorDoesNotExposeItsContents() async {
        let monitor = SignificantEnergyMonitor(reader: {
            throw NSError(domain: "sensitive-native-diagnostic", code: 9)
        })

        await monitor.refresh().value

        #expect(monitor.state == .unavailable(.readFailed))
    }

    @Test
    @MainActor
    func overlappingRefreshesShareOneReadAndPreserveTheLastSnapshot() async {
        let reader = SignificantEnergyReadGate()
        let monitor = SignificantEnergyMonitor(reader: { try await reader.read() })
        let first = monitor.refresh()
        let concurrent = monitor.refresh()
        #expect(monitor.state == .loading)
        await reader.waitForRequest(0)
        reader.finish(0, with: .success([Self.first]))
        await first.value
        await concurrent.value
        #expect(reader.requestCount == 1)
        #expect(monitor.state == .available([Self.first]))

        let next = monitor.refresh()
        await reader.waitForRequest(1)
        #expect(monitor.state == .available([Self.first]))
        reader.finish(1, with: .success([Self.second]))
        await next.value
        #expect(monitor.state == .available([Self.second]))
    }

    @Test
    @MainActor
    func deniedReadCanRecoverOnTheNextRefresh() async {
        let reader = SignificantEnergyReadGate()
        let monitor = SignificantEnergyMonitor(reader: { try await reader.read() })
        let first = monitor.refresh()
        await reader.waitForRequest(0)
        reader.finish(0, with: .failure(SignificantEnergyUnavailableReason.permissionDenied))
        await first.value
        #expect(monitor.state == .unavailable(.permissionDenied))

        let recovered = monitor.refresh()
        await reader.waitForRequest(1)
        reader.finish(1, with: .success([Self.first]))
        await recovered.value
        #expect(monitor.state == .available([Self.first]))
    }

    @Test
    @MainActor
    func stopCancelsReadingAndClearsTheActiveState() async {
        let reader = SignificantEnergyReadGate()
        let monitor = SignificantEnergyMonitor(reader: { try await reader.read() })
        let refresh = monitor.refresh()
        await reader.waitForRequest(0)

        monitor.stop()
        await reader.waitForCancellation(0)
        await refresh.value

        #expect(monitor.state == .idle)
        #expect(reader.pendingRequestCount == 0)
    }

    @Test
    @MainActor
    func cancelledRefreshAllowsAnotherAttempt() async {
        let reader = SignificantEnergyReadGate()
        let monitor = SignificantEnergyMonitor(reader: { try await reader.read() })
        let cancelled = monitor.refresh()
        await reader.waitForRequest(0)
        cancelled.cancel()
        await reader.waitForCancellation(0)
        await cancelled.value
        #expect(monitor.state == .idle)

        let recovered = monitor.refresh()
        await reader.waitForRequest(1)
        reader.finish(1, with: .success([Self.first]))
        await recovered.value
        #expect(monitor.state == .available([Self.first]))
    }

    @Test
    @MainActor
    func lateUncancellableResultCannotReplaceAReopenedSession() async {
        let reader = SignificantEnergyReadGate(honorsCancellation: false)
        let monitor = SignificantEnergyMonitor(reader: { try await reader.read() })
        let stale = monitor.refresh()
        await reader.waitForRequest(0)
        monitor.stop()
        let current = monitor.refresh()
        await reader.waitForRequest(1)
        reader.finish(0, with: .success([Self.first]))
        await stale.value
        let overlapping = monitor.refresh()
        reader.finishAll(with: .success([Self.second]))
        await current.value
        await overlapping.value

        #expect(monitor.state == .available([Self.second]))
        #expect(reader.requestCount == 2)
        #expect(reader.pendingRequestCount == 0)
    }

    @Test
    @MainActor
    func cancelledUncooperativeReadCannotPublishItsResult() async {
        let reader = SignificantEnergyReadGate(honorsCancellation: false)
        let monitor = SignificantEnergyMonitor(reader: { try await reader.read() })
        let refresh = monitor.refresh()
        await reader.waitForRequest(0)
        refresh.cancel()
        reader.finish(0, with: .success([Self.first]))
        await refresh.value

        #expect(monitor.state == .idle)
        #expect(reader.pendingRequestCount == 0)
    }

    @Test
    @MainActor
    func pollingStartsOnceStopsAndCanRestart() async {
        let ticks = PassthroughSubject<Date, Never>()
        let reader = SignificantEnergyReadGate()
        var subscriptions = 0
        var cancellations = 0
        let monitor = SignificantEnergyMonitor(
            reader: { try await reader.read() },
            refreshEvents: ticks.handleEvents(
                receiveSubscription: { _ in subscriptions += 1 },
                receiveCancel: { cancellations += 1 }
            ).eraseToAnyPublisher()
        )
        monitor.start()
        #expect(monitor.state == .loading)
        monitor.start()
        let initial = monitor.refresh()
        await reader.waitForRequest(0)
        reader.finish(0, with: .success([Self.first]))
        await initial.value
        #expect(subscriptions == 1)

        ticks.send(Date(timeIntervalSince1970: 30))
        await reader.waitForRequest(1)
        let periodic = monitor.refresh()
        reader.finish(1, with: .success([Self.second]))
        await periodic.value
        #expect(monitor.state == .available([Self.second]))

        monitor.stop()
        ticks.send(Date(timeIntervalSince1970: 60))
        #expect(monitor.state == .idle)
        #expect(cancellations == 1)
        monitor.start()
        #expect(monitor.state == .loading)
        let restarted = monitor.refresh()
        await reader.waitForRequest(2)
        reader.finish(2, with: .success([]))
        await restarted.value
        #expect(monitor.state == .available([]))
        #expect(subscriptions == 2)
        monitor.stop()
        #expect(cancellations == 2)
    }

    @Test
    @MainActor
    func deinitializationReleasesTheTimerAndCancelsTheRead() async {
        let ticks = PassthroughSubject<Date, Never>()
        let reader = SignificantEnergyReadGate()
        var timerReleased = false
        var monitor: SignificantEnergyMonitor? = SignificantEnergyMonitor(
            reader: { try await reader.read() },
            refreshEvents: ticks.handleEvents(receiveCancel: {
                timerReleased = true
            }).eraseToAnyPublisher()
        )
        weak let releasedMonitor = monitor
        monitor?.start()
        let refresh = monitor?.refresh()
        await reader.waitForRequest(0)

        monitor = nil
        await reader.waitForCancellation(0)
        await refresh?.value

        #expect(releasedMonitor == nil)
        #expect(timerReleased)
        #expect(reader.pendingRequestCount == 0)
    }

    private static var payload: [String: [String]] {
        [
            "bundle_identifiers": [first.bundleIdentifier],
            "responsible_bundle_identifiers": [first.responsibleBundleIdentifier],
            "display_names": [first.displayName],
        ]
    }
}

@MainActor
private final class SignificantEnergyReadGate {
    private let honorsCancellation: Bool
    private var nextRequestID = 0
    private var startedRequests: Set<Int> = []
    private var cancelledRequests: Set<Int> = []
    private var pending: [Int: CheckedContinuation<[SignificantEnergyProcess], any Error>] = [:]
    private var completion: Result<[SignificantEnergyProcess], any Error>?
    private var requestWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var cancellationWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    var requestCount: Int { startedRequests.count }
    var pendingRequestCount: Int { pending.count }

    init(honorsCancellation: Bool = true) {
        self.honorsCancellation = honorsCancellation
    }

    func read() async throws -> [SignificantEnergyProcess] {
        let requestID = nextRequestID
        nextRequestID += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let completion {
                    continuation.resume(with: completion)
                } else if honorsCancellation, cancelledRequests.contains(requestID) {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending[requestID] = continuation
                }
                startedRequests.insert(requestID)
                requestWaiters.removeValue(forKey: requestID)?.forEach { $0.resume() }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in self?.cancel(requestID) }
        }
    }

    func finish(_ requestID: Int, with result: Result<[SignificantEnergyProcess], any Error>) {
        guard let continuation = pending.removeValue(forKey: requestID) else {
            Issue.record("No pending energy request \(requestID) to complete")
            return
        }
        continuation.resume(with: result)
    }

    func finishAll(with result: Result<[SignificantEnergyProcess], any Error>) {
        completion = result
        let continuations = Array(pending.values)
        pending.removeAll()
        continuations.forEach { $0.resume(with: result) }
    }

    func waitForRequest(_ requestID: Int) async {
        if startedRequests.contains(requestID) { return }
        await withCheckedContinuation { requestWaiters[requestID, default: []].append($0) }
    }

    func waitForCancellation(_ requestID: Int) async {
        if cancelledRequests.contains(requestID) { return }
        await withCheckedContinuation { cancellationWaiters[requestID, default: []].append($0) }
    }

    private func cancel(_ requestID: Int) {
        cancelledRequests.insert(requestID)
        if honorsCancellation {
            pending.removeValue(forKey: requestID)?.resume(throwing: CancellationError())
        }
        cancellationWaiters.removeValue(forKey: requestID)?.forEach { $0.resume() }
    }
}
