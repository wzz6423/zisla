#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zisla-release-notes-lifecycle.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

# Exercise the production driver with window doubles without activating the user's app.
ruby - "$ROOT" "$TEST_ROOT" <<'RUBY'
root, temporary_root = ARGV
source = File.read(File.join(root, 'Sources/Zisla/SparkleUpdateController.swift'))
feeds = source[/^struct SparkleFeedPair:.*?(?=^struct SparkleUpdateConfiguration)/m]
driver = source[/^@MainActor\nclass SparkleStandardUserDriver:.*?(?=^@MainActor\nfinal class SparkleUpdateController)/m]
abort 'Missing production release-notes driver' unless feeds && driver
notes = File.read(File.join(root, 'Sources/Zisla/UpdateReleaseNotes.swift'))
  .gsub(/^import (Sparkle|ZislaCore)\n/, '')

support = <<'SWIFT'
import Foundation
import Combine

enum SPUUserUpdateChoice { case skip, install, dismiss }
enum SPUUserUpdateStage { case notDownloaded, downloaded, installing }
struct SPUUserUpdateState { let stage: SPUUserUpdateStage }
struct SUAppcastItem {
    let displayVersionString: String
    let versionString: String
    let fileURL: URL?
    var isCriticalUpdate = false
    var isMajorUpgrade = false
    var isInformationOnlyUpdate = false
    var infoURL: URL?
}
@MainActor final class SUStandardVersionComparator {
    static let `default` = SUStandardVersionComparator()
    func compareVersion(_ left: String, toVersion right: String) -> ComparisonResult {
        left.compare(right, options: .numeric)
    }
}
@MainActor final class AppLanguageStore {}
@MainActor class SPUStandardUserDriver {
    var dismissals = 0
    var focusRequests = 0
    init(hostBundle: Bundle, delegate: AnyObject?) {}
    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showUpdateInFocus() { focusRequests += 1 }
    func dismissUpdateInstallation() { dismissals += 1 }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
}
enum UpdateReleaseNotesPresentation: Equatable {
    case available(stage: SPUUserUpdateStage, critical: Bool, informationURL: URL?)
    case installed
}
@MainActor final class UpdateReleaseNotesWindowController {
    static var created: [UpdateReleaseNotesWindowController] = []
    let model: UpdateReleaseNotesModel
    let presentation: UpdateReleaseNotesPresentation
    var shows = 0
    var dismissals = 0
    private var reply: ((SPUUserUpdateChoice) -> Void)?
    init(model: UpdateReleaseNotesModel, presentation: UpdateReleaseNotesPresentation, languageStore: AppLanguageStore, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        self.model = model
        self.presentation = presentation
        self.reply = reply
        Self.created.append(self)
    }
    func show() { shows += 1 }
    func dismiss() { dismissals += 1; reply = nil }
    func choose(_ choice: SPUUserUpdateChoice) {
        let reply = reply
        self.reply = nil
        reply?(choice)
    }
}
SWIFT

probe = <<'SWIFT'
@main struct ReleaseNotesLifecycleProbe {
    @MainActor static func main() {
        let suite = "zisla-release-notes-lifecycle-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UpdateReleaseNotesStore(defaults: defaults)
        let driver = SparkleStandardUserDriver(hostBundle: .main, shouldSuppressUpdaterError: { false }, releaseNotesStore: store)
        driver.feedPreference = .githubFirst
        let release = UpdateRelease(version: "1.2.3", build: "23", tagName: "v1.2.3")
        let notes = UpdateReleaseNotes(markdown: "# Installed changes", releaseURL: URL(string: "https://github.com/wzz6423/zisla/releases/tag/v1.2.3")!)
        driver.showInstalledReleaseNotes(.init(release: release, githubFirst: true, notes: notes), preference: .githubFirst)
        let installed = UpdateReleaseNotesWindowController.created.last!
        require(installed.presentation == .installed && installed.shows == 1, "completed updates must show their cached notes")
        require(installed.model.notes == notes, "completed updates must reuse the downloaded notes offline")

        var choices: [SPUUserUpdateChoice] = []
        let item = SUAppcastItem(displayVersionString: "1.2.4", versionString: "24", fileURL: URL(string: "https://gitee.com/wzz6423/zisla/releases/download/v1.2.4/zisla.zip"))
        driver.showUpdateFound(with: item, state: .init(stage: .notDownloaded)) { choices.append($0) }
        let available = UpdateReleaseNotesWindowController.created.last!
        require(available.presentation == .available(stage: .notDownloaded, critical: false, informationURL: nil), "new updates must show the available presentation")
        require(available.model.preference == .githubFirst, "notes must use the update package's mirror preference")
        require(driver.dismissals == 1, "finding an update must close Sparkle's checking progress")
        require(installed.dismissals == 0, "a new update check must not close the installed-notes window")
        driver.showUpdateInFocus()
        require(available.shows == 2 && driver.focusRequests == 0, "manual checks must focus the active notes")

        driver.recordPendingUpdate(item)
        available.model.onNotesLoaded?(notes)
        let pending = store.takeInstalledRelease(version: "1.2.4", build: "24")!
        require(pending.notes == notes && pending.preference == .githubFirst, "late notes must reach the matching pending installation")
        require(store.takeInstalledRelease(version: "1.2.4", build: "24") == nil, "installed notes must only be consumed once")

        driver.showUpdateFound(with: item, state: .init(stage: .installing)) { choices.append($0) }
        let resumed = UpdateReleaseNotesWindowController.created.last!
        require(resumed.model === available.model, "resumed updates must reuse the same release-notes model")
        require(available.dismissals == 1, "resumed updates must dismiss the previous prompt")
        require(resumed.presentation == .available(stage: .installing, critical: false, informationURL: nil), "resumed updates must preserve the installing stage")
        resumed.choose(.dismiss)
        require(choices == [.dismiss], "deferral must be returned to Sparkle")
        driver.showUpdateInFocus()
        require(driver.focusRequests == 1, "after choosing, Sparkle must regain progress focus")

        driver.feedPreference = .giteeFirst
        driver.showUpdateFound(with: item, state: .init(stage: .downloaded)) { choices.append($0) }
        let reordered = UpdateReleaseNotesWindowController.created.last!
        require(reordered.model !== resumed.model && reordered.model.preference == .giteeFirst, "mirror changes must replace the cached model")
        reordered.choose(.install)
        require(choices == [.dismiss, .install], "installation must be returned to Sparkle")

        var informational = item
        informational.isInformationOnlyUpdate = true
        informational.infoURL = URL(string: "https://github.com/wzz6423/zisla/releases")
        informational.isCriticalUpdate = true
        driver.showUpdateFound(with: informational, state: .init(stage: .notDownloaded)) { choices.append($0) }
        let information = UpdateReleaseNotesWindowController.created.last!
        require(information.presentation == .available(stage: .notDownloaded, critical: true, informationURL: informational.infoURL), "informational and critical flags must reach the prompt")
        driver.dismissUpdateInstallation()
        require(information.dismissals == 1 && choices == [.dismiss, .install], "programmatic dismissal must not choose an update action")
        require(installed.dismissals == 0, "Sparkle teardown must preserve the installed-notes window")
        print("PASS: release-notes driver lifecycle, mirror ordering, cached models, late notes, Sparkle replies and independent completed-update window")
    }
    static func require(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL: \(message)"); exit(1) }
    }
}
SWIFT

File.write(File.join(temporary_root, 'Lifecycle.swift'), support + feeds + notes + driver + probe)
RUBY

xcrun swiftc -swift-version 6 -parse-as-library \
  -module-cache-path "$TEST_ROOT/ModuleCache" \
  "$ROOT/Sources/ZislaCore/UpdateCore.swift" "$TEST_ROOT/Lifecycle.swift" \
  -o "$TEST_ROOT/Lifecycle"
"$TEST_ROOT/Lifecycle"
