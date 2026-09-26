#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
MONITOR_SOURCE="${1:-$ROOT/Sources/ZislaKit/BrowserDownloadMonitor.swift}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-progress-callback-tests.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

python3 - "$MONITOR_SOURCE" "$TEST_ROOT/ProgressCallbackProbe.swift" <<'PYTHON'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
def section(start, end):
    return source.split(start, 1)[1].split(end, 1)[0]

subscribe = "func subscribe(" + section("private func subscribe(", "    public func stop()")
subscribe = subscribe.replace("Progress.addSubscriber", "LegacyProgressSubscriptions.addSubscriber")
lifecycle = "struct BrowserDownloadMonitorLifecycle" + section("struct BrowserDownloadMonitorLifecycle", "/// Monitors")
identity = "struct BrowserDownloadFileIdentity" + section("struct BrowserDownloadFileIdentity", "/// State machine")
box = "private final class ProgressBox" + source.split("private final class ProgressBox", 1)[1]
completed = "nonisolated static func completedSuccessfully" + section(
    "nonisolated static func completedSuccessfully", "    /// Returns nil when total size is unknown"
)

Path(sys.argv[2]).write_text("""
import Darwin
import Foundation

func isolationTrap(_ signal: Int32) { _exit(86) }

// Older SDKs expose these Objective-C callbacks without Sendable annotations.
enum LegacyProgressSubscriptions {
    typealias UnpublishingHandler = @convention(block) () -> Void
    typealias PublishingHandler = @convention(block) (Progress) -> UnpublishingHandler?
    final class Subscription: @unchecked Sendable {
        let publish: PublishingHandler
        init(_ publish: @escaping PublishingHandler) { self.publish = publish }
    }
    static func addSubscriber(forFileURL: URL, withPublishingHandler handler: @escaping PublishingHandler) -> Any {
        Subscription(handler)
    }
}

@MainActor final class BrowserDownloadMonitor {
    struct Event {
        let token: UUID
        let fileURL: URL?
        let succeeded: Bool?
    }
    var subscriberTokens: [URL: Any] = [:]
    var lifecycle = BrowserDownloadMonitorLifecycle()
    var events: [Event] = []
    private func register(token: UUID, box: ProgressBox, directory: URL) {
        dispatchPrecondition(condition: .onQueue(.main))
        events.append(Event(token: token, fileURL: box.publishedFileURL, succeeded: nil))
    }
    private func unregister(token: UUID, succeeded: Bool, publishedFileURL: URL?) {
        dispatchPrecondition(condition: .onQueue(.main))
        events.append(Event(token: token, fileURL: publishedFileURL, succeeded: succeeded))
    }
""" + subscribe + completed + "}\n" + lifecycle + identity + box + """

@main struct ProgressCallbackProbe {
    @MainActor static func main() async {
        signal(SIGTRAP, isolationTrap)
        alarm(10)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = directory.appendingPathComponent("report.pdf")

        for (completed, cancelled) in [(100, false), (100, true), (40, false)] {
            let monitor = BrowserDownloadMonitor()
            monitor.subscribe(to: directory, callbackGeneration: monitor.lifecycle.start())
            let subscription = monitor.subscriberTokens[directory] as! LegacyProgressSubscriptions.Subscription
            await withCheckedContinuation { finished in
                DispatchQueue.global().async {
                    dispatchPrecondition(condition: .notOnQueue(.main))
                    let progress = Progress(totalUnitCount: 100)
                    progress.fileURL = fileURL
                    progress.fileOperationKind = .downloading
                    let unpublish = subscription.publish(progress)!
                    progress.completedUnitCount = Int64(completed)
                    if cancelled { progress.cancel() }
                    unpublish()
                    finished.resume()
                }
            }
            await drainMainQueue()
            require(monitor.events.count == 2, "publication and unpublication must both reach the main actor")
            require(monitor.events[0].succeeded == nil, "registration must precede teardown for a short publication")
            require(monitor.events[0].token == monitor.events[1].token, "teardown must use the publication token")
            require(monitor.events.allSatisfy { $0.fileURL == fileURL }, "both callbacks must preserve the published URL")
            require(monitor.events[1].succeeded == (completed == 100 && !cancelled), "cancelled and incomplete progress cannot succeed")
        }

        let monitor = BrowserDownloadMonitor()
        monitor.subscribe(to: directory, callbackGeneration: monitor.lifecycle.start())
        let subscription = monitor.subscriberTokens[directory] as! LegacyProgressSubscriptions.Subscription
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let progress = Progress(totalUnitCount: 100)
            progress.fileURL = fileURL
            let unpublish = subscription.publish(progress)!
            progress.completedUnitCount = 100
            unpublish()
            finished.signal()
        }
        waitForQueuedCallbacks(finished)
        monitor.lifecycle.stop()
        _ = monitor.lifecycle.start()
        await drainMainQueue()
        require(monitor.events.isEmpty, "queued callbacks from before stop must not mutate the restarted monitor")
        print("PASS: background Progress publication and teardown preserve ordering, success state, URLs, and lifecycle isolation")
    }
    @MainActor static func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    @MainActor static func waitForQueuedCallbacks(_ finished: DispatchSemaphore) {
        // Keep both callbacks queued until the lifecycle generation has changed.
        require(finished.wait(timeout: .now() + 2) == .success, "background callbacks must not wait for the main actor")
    }
    static func require(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL: \\(message)"); _exit(87) }
    }
}
""")
PYTHON

xcrun swiftc -swift-version 6 -parse-as-library -Xfrontend -enable-actor-data-race-checks \
  -module-cache-path "$TEST_ROOT/ModuleCache" \
  "$TEST_ROOT/ProgressCallbackProbe.swift" -o "$TEST_ROOT/ProgressCallbackProbe"

PROBE_RESULT=0
"$TEST_ROOT/ProgressCallbackProbe" "$TEST_ROOT" || PROBE_RESULT=$?
if (( PROBE_RESULT != 0 )); then
  print -u2 "FAIL: Progress callback exited $PROBE_RESULT (86=actor-isolation SIGTRAP, 87=behavior assertion)"
  exit 1
fi
