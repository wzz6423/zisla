#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-update-scheduling.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

# Compile the production update entry points with isolated settings and a fake
# Sparkle endpoint; constructing AppModel.shared would start unrelated services.
ruby - "$ROOT" "$TEST_ROOT" <<'RUBY'
root, temporary_root = ARGV
source = File.read(File.join(root, 'Sources/Zisla/AppModel.swift'))
check = source[/^  func checkForUpdates\(manual:.*?(?=^  func selectSystemMonitor)/m]
polling = source[/^  private func configureUpdatePolling\(enabled:.*?(?=^    guard isUpdatePollingEnabled)/m]
abort 'Missing production update entry points' unless check && polling
resolver = File.read(File.join(root, 'Sources/Zisla/UpdateFeedResolver.swift')).sub("import ZislaCore\n", '')

support = <<'SWIFT'
import Foundation
import Darwin

enum UpdateChannel: Equatable { case release, preview }
enum UpdateState { case idle, checking, failed(String) }
enum AppLocalization { static func text(_ text: String) -> String { text } }
struct Settings {
    var updateChannel: UpdateChannel = .release
    var updateChecksEnabled = true
    var automaticDownloadEnabled = false
}
@MainActor final class SettingsStore { var settings = Settings() }
@MainActor final class SparkleUpdateController {
    struct Event: Equatable {
        let manual: Bool
        let channel: UpdateChannel
        let checksEnabled: Bool
        let automaticDownloadEnabled: Bool
        let preference: UpdateFeedPreference
    }
    var events: [Event] = []
    var completion: CheckedContinuation<Void, Never>?
    func configure(channel: UpdateChannel, checksEnabled: Bool, automaticDownloadEnabled: Bool, feedPreference: UpdateFeedPreference) -> Bool {
        events.append(Event(manual: false, channel: channel, checksEnabled: checksEnabled, automaticDownloadEnabled: automaticDownloadEnabled, preference: feedPreference))
        return true
    }
    func checkForUpdates(channel: UpdateChannel, checksEnabled: Bool, automaticDownloadEnabled: Bool, feedPreference: UpdateFeedPreference) -> Bool {
        events.append(Event(manual: true, channel: channel, checksEnabled: checksEnabled, automaticDownloadEnabled: automaticDownloadEnabled, preference: feedPreference))
        completion?.resume()
        completion = nil
        return true
    }
    func waitForManualCheck(release: () -> Void) async {
        await withCheckedContinuation { completion = $0; release() }
    }
}
@MainActor final class LookupGate {
    var requests = 0
    var started: CheckedContinuation<Void, Never>?
    var pending: CheckedContinuation<UpdateFeedPreference, Never>?
    func load() async -> UpdateFeedPreference {
        requests += 1
        started?.resume()
        started = nil
        return await withCheckedContinuation { pending = $0 }
    }
    func waitUntilStarted() async {
        if requests == 0 { await withCheckedContinuation { started = $0 } }
    }
    func release(_ preference: UpdateFeedPreference) {
        pending?.resume(returning: preference)
        pending = nil
    }
}
@MainActor final class AppModel {
    let settingsStore = SettingsStore()
    let sparkleUpdateController: SparkleUpdateController? = SparkleUpdateController()
    let updateFeedResolver: UpdateFeedResolver
    var updateState = UpdateState.idle
    init(gate: LookupGate) {
        updateFeedResolver = UpdateFeedResolver { await gate.load() }
    }
    func applySettings() { configureUpdatePolling(enabled: settingsStore.settings.updateChecksEnabled) }
SWIFT

probe = <<'SWIFT'
@main struct UpdateSchedulingProbe {
    @MainActor static func main() async {
        alarm(15)
        for countryCode: String? in ["CN", "US", nil] {
            let preference = UpdateFeedPreference(countryCode: countryCode)
            for automaticEnabled in [false, true] {
                let gate = LookupGate()
                let model = AppModel(gate: gate)
                let controller = model.sparkleUpdateController!
                model.checkForUpdates(manual: true)
                await gate.waitUntilStarted()
                model.settingsStore.settings.updateChannel = .preview
                model.settingsStore.settings.updateChecksEnabled = automaticEnabled
                model.settingsStore.settings.automaticDownloadEnabled = true
                model.applySettings()

                await controller.waitForManualCheck { gate.release(preference) }

                require(controller.events.count == 2, "settings configuration and manual check must both run")
                require(controller.events.map(\.manual) == [false, true], "settings must not replace the manual request")
                require(controller.events.allSatisfy { $0.channel == .preview }, "waiting checks must use the current channel")
                require(controller.events.allSatisfy { $0.checksEnabled == automaticEnabled && $0.automaticDownloadEnabled }, "waiting checks must use current settings")
                require(controller.events.last?.preference == preference, "manual check must receive the resolved preference")
                if automaticEnabled {
                    require(controller.events.first?.preference == preference, "automatic check must receive the same preference")
                }

                model.settingsStore.settings.updateChannel = .release
                model.checkForUpdates(manual: true)
                require(controller.events.count == 3 && controller.events.last?.channel == .release, "cached checks must use current settings immediately")
                require(gate.requests == 1, "manual and automatic checks must share one lookup")
                model.updateFeedResolver.cancel()
            }
        }
        print("PASS: 6 production AppModel scheduling scenarios (CN/US/unknown, automatic enabled/disabled)")
    }
    static func require(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL: \(message)"); exit(1) }
    }
}
SWIFT

File.write(File.join(temporary_root, 'UpdateSchedulingProbe.swift'), support + check + polling + "  }\n}\n" + resolver + probe)
RUBY

xcrun swiftc -swift-version 6 -parse-as-library \
  -module-cache-path "$TEST_ROOT/ModuleCache" \
  "$ROOT/Sources/ZislaCore/UpdateCore.swift" \
  "$TEST_ROOT/UpdateSchedulingProbe.swift" -o "$TEST_ROOT/UpdateSchedulingProbe"
"$TEST_ROOT/UpdateSchedulingProbe"
