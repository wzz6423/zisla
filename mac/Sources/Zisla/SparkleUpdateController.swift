@preconcurrency import Foundation
import Sparkle
import ZislaCore
import ZislaKit

struct SparkleFeedPair: Equatable {
    let gitee: URL
    let github: URL

    func url(
        for source: UpdateFeedSource,
        preference: UpdateFeedPreference = .giteeFirst
    ) -> URL {
        switch (preference, source) {
        case (.giteeFirst, .primary), (.githubFirst, .fallback): gitee
        case (.githubFirst, .primary), (.giteeFirst, .fallback): github
        }
    }
}

struct SparkleUpdateConfiguration: Equatable {
    private let feedURLs: [UpdateChannel: SparkleFeedPair]
    let publicKey: String

    init?(
        infoDictionary: [String: Any],
        architecture: String = SparkleUpdateConfiguration.hostArchitecture,
        installedSliceCount: Int = SparkleUpdateConfiguration.installedSliceCount
    ) {
        guard let releaseFeeds = Self.feedPair(
            giteeKey: "SUFeedURL",
            githubKey: "ZislaReleaseFallbackAppcastURL",
            in: infoDictionary,
            architecture: architecture,
            installedSliceCount: installedSliceCount
        ),
        let previewFeeds = Self.feedPair(
            giteeKey: "ZislaPreviewAppcastURL",
            githubKey: "ZislaPreviewFallbackAppcastURL",
            in: infoDictionary,
            architecture: architecture,
            installedSliceCount: installedSliceCount
        ),
        let publicKey = infoDictionary["SUPublicEDKey"] as? String,
        Data(base64Encoded: publicKey)?.count == 32 else {
            return nil
        }

        feedURLs = [
            .release: releaseFeeds,
            .preview: previewFeeds,
        ]
        self.publicKey = publicKey
    }

    func feedURL(for channel: UpdateChannel, source: UpdateFeedSource) -> URL? {
        feedURLs[channel]?.url(for: source)
    }

    fileprivate func feedPair(for channel: UpdateChannel) -> SparkleFeedPair? {
        feedURLs[channel]
    }

    private static func feedPair(
        giteeKey: String,
        githubKey: String,
        in infoDictionary: [String: Any],
        architecture: String,
        installedSliceCount: Int
    ) -> SparkleFeedPair? {
        guard let giteeURL = feedURL(
                  forKey: giteeKey,
                  in: infoDictionary,
                  architecture: architecture,
                  installedSliceCount: installedSliceCount
              ),
              let githubURL = feedURL(
                  forKey: githubKey,
                  in: infoDictionary,
                  architecture: architecture,
                  installedSliceCount: installedSliceCount
              ) else {
            return nil
        }
        return SparkleFeedPair(gitee: giteeURL, github: githubURL)
    }

    private static func feedURL(
        forKey key: String,
        in infoDictionary: [String: Any],
        architecture: String,
        installedSliceCount: Int
    ) -> URL? {
        guard let value = infoDictionary[key] as? String,
              let url = URL(string: value),
              url.scheme == "https",
              url.host != nil else {
            return nil
        }
        // Every release publishes one appcast per architecture next to the shared
        // appcast.xml, so an install stays on its own slice instead of being replaced by
        // the fat universal build. Info.plist keeps the shared name for both channels.
        // A universal install stays on that shared name: following a slice feed would
        // spend the portability it was installed for on one update's size saving.
        guard installedSliceCount == 1 else {
            return url
        }
        return url.deletingLastPathComponent()
            .appendingPathComponent("appcast-\(architecture).xml")
    }

    // Counts the slices in the running app, not the machine, so a universal install is
    // recognized even on a Mac that can only execute one of them.
    static let installedSliceCount: Int = Bundle.main.executableArchitectures?.count ?? 1

    static let hostArchitecture: String = {
        #if arch(arm64)
        "arm64"
        #else
        // A translated slice runs on Apple silicon, where following the slice would leave
        // this Mac on the Intel build, and therefore on Rosetta, for every later update.
        isTranslatedProcess() ? "arm64" : "x86_64"
        #endif
    }()

    private static func isTranslatedProcess() -> Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 else {
            return false
        }
        return translated == 1
    }
}

@MainActor
final class SparkleFeedDelegate: NSObject, SPUUpdaterDelegate {
    var onFallbackRequested: ((SPUUpdateCheck) -> Void)?
    var onCheckFailed: ((Error) -> Void)?
    var onUpdateSkipped: (() -> Void)?
    var onUpdatePrepared: ((SUAppcastItem) -> Void)?

    private var feeds: SparkleFeedPair
    private var preference: UpdateFeedPreference
    private var fallbackState = UpdateFeedFallbackState()
    private var fallbackRetryCheck: SPUUpdateCheck?

    var shouldSuppressUpdaterError: Bool {
        fallbackState.source == .primary
    }

    init(
        feeds: SparkleFeedPair,
        preference: UpdateFeedPreference = .giteeFirst
    ) {
        self.feeds = feeds
        self.preference = preference
    }

    @discardableResult
    func setFeeds(
        _ feeds: SparkleFeedPair,
        preference: UpdateFeedPreference
    ) -> Bool {
        let previousURL = self.feeds.url(
            for: fallbackState.source,
            preference: self.preference
        )
        self.feeds = feeds
        self.preference = preference
        fallbackState.beginCheck()
        fallbackRetryCheck = nil
        return previousURL != self.feeds.url(
            for: fallbackState.source,
            preference: self.preference
        )
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feeds.url(
            for: fallbackState.source,
            preference: preference
        ).absoluteString
    }

    func updater(
        _ updater: SPUUpdater,
        mayPerformUpdateCheck updateCheck: SPUUpdateCheck,
        error: NSErrorPointer
    ) -> Bool {
        if fallbackRetryCheck == updateCheck {
            fallbackRetryCheck = nil
        } else {
            fallbackState.beginCheck()
        }
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        fallbackState.didLoadAppcast()
    }

    func updater(
        _ updater: SPUUpdater,
        failedToDownloadUpdate item: SUAppcastItem,
        error: Error
    ) {
        fallbackState.didFailDownloadingUpdate()
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        handleUserChoice(choice)
    }

    func handleUserChoice(_ choice: SPUUserUpdateChoice) {
        if choice == .skip {
            onUpdateSkipped?()
        }
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        // Persist before quitting: Sparkle's installer can finish after this process exits.
        onUpdatePrepared?(item)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        let didLoadAppcast = fallbackState.hasLoadedAppcast
        if fallbackState.finishCheck(failed: error != nil) {
            fallbackRetryCheck = updateCheck
            onFallbackRequested?(updateCheck)
            return
        }

        fallbackState.beginCheck()
        fallbackRetryCheck = nil
        if let error, !didLoadAppcast {
            onCheckFailed?(error)
        }
    }
}

@MainActor
class SparkleStandardUserDriver: SPUStandardUserDriver {
    private let shouldSuppressUpdaterError: () -> Bool
    private let languageStore: AppLanguageStore
    let releaseNotesStore: UpdateReleaseNotesStore
    private var releaseNotesWindow: UpdateReleaseNotesWindowController?
    private var installedReleaseNotesWindow: UpdateReleaseNotesWindowController?
    private var releaseNotesModel: UpdateReleaseNotesModel?
    var feedPreference: UpdateFeedPreference = .giteeFirst
    var onUpdaterErrorPresented: ((Error) -> Void)?

    init(
        hostBundle: Bundle,
        shouldSuppressUpdaterError: @escaping () -> Bool,
        onUpdaterErrorPresented: ((Error) -> Void)? = nil,
        languageStore: AppLanguageStore? = nil,
        releaseNotesStore: UpdateReleaseNotesStore? = nil
    ) {
        self.shouldSuppressUpdaterError = shouldSuppressUpdaterError
        self.onUpdaterErrorPresented = onUpdaterErrorPresented
        self.languageStore = languageStore ?? AppLanguageStore()
        self.releaseNotesStore = releaseNotesStore ?? UpdateReleaseNotesStore()
        super.init(hostBundle: hostBundle, delegate: nil)
    }

    override func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        super.dismissUpdateInstallation()
        releaseNotesWindow?.dismiss()
        let release = UpdateRelease(item: appcastItem)
        if releaseNotesModel?.release != release || releaseNotesModel?.preference != feedPreference {
            let model = UpdateReleaseNotesModel(release: release, preference: feedPreference)
            model.onNotesLoaded = { [weak self] notes in
                self?.releaseNotesStore.updateNotes(notes, for: release)
            }
            releaseNotesModel = model
        }
        releaseNotesWindow = UpdateReleaseNotesWindowController(
            model: releaseNotesModel!,
            presentation: .available(
                stage: state.stage,
                critical: appcastItem.isCriticalUpdate && !appcastItem.isMajorUpgrade,
                informationURL: appcastItem.isInformationOnlyUpdate ? appcastItem.infoURL : nil
            ),
            languageStore: languageStore,
            reply: { [weak self] choice in
                self?.releaseNotesWindow = nil
                reply(choice)
            }
        )
        releaseNotesWindow?.show()
    }

    override func showUpdateInFocus() {
        if let releaseNotesWindow {
            releaseNotesWindow.show()
        } else {
            super.showUpdateInFocus()
        }
    }

    override func dismissUpdateInstallation() {
        releaseNotesWindow?.dismiss()
        releaseNotesWindow = nil
        super.dismissUpdateInstallation()
    }

    func recordPendingUpdate(_ item: SUAppcastItem) {
        let release = UpdateRelease(item: item)
        releaseNotesStore.record(
            release,
            preference: feedPreference,
            notes: releaseNotesModel?.release == release ? releaseNotesModel?.notes : nil
        )
    }

    func showInstalledReleaseNotes(_ installed: UpdateReleaseNotesStore.InstalledRelease, preference: UpdateFeedPreference) {
        installedReleaseNotesWindow = UpdateReleaseNotesWindowController(
            model: UpdateReleaseNotesModel(release: installed.release, preference: preference, notes: installed.notes),
            presentation: .installed,
            languageStore: languageStore,
            reply: { [weak self] _ in self?.installedReleaseNotesWindow = nil }
        )
        installedReleaseNotesWindow?.show()
    }

    override func showUpdaterError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        if shouldSuppressUpdaterError() {
            acknowledgement()
        } else {
            onUpdaterErrorPresented?(error)
            super.showUpdaterError(error, acknowledgement: acknowledgement)
        }
    }
}

@MainActor
final class SparkleUpdateController {
    var onUpdateFound: (() -> Void)?
    var onNoUpdateFound: (() -> Void)?
    var onCheckFailed: ((Error) -> Void)?
    var onUpdateSkipped: (() -> Void)?

    private let configuration: SparkleUpdateConfiguration
    private let updaterDelegate: SparkleFeedDelegate
    private let userDriver: SparkleStandardUserDriver
    private let updater: SPUUpdater
    private var notificationObservers: [NSObjectProtocol] = []
    private var didStart = false
    private var installedNotesTask: Task<Void, Never>?

    init?(
        configuration: SparkleUpdateConfiguration? = SparkleUpdateConfiguration(
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        ),
        languageStore: AppLanguageStore? = nil
    ) {
        guard let configuration,
              let releaseFeeds = configuration.feedPair(for: .release) else {
            return nil
        }
        self.configuration = configuration
        let delegate = SparkleFeedDelegate(feeds: releaseFeeds)
        updaterDelegate = delegate
        let userDriver = SparkleStandardUserDriver(
            hostBundle: Bundle.main,
            shouldSuppressUpdaterError: { [weak delegate] in
                delegate?.shouldSuppressUpdaterError == true
            },
            languageStore: languageStore
        )
        self.userDriver = userDriver
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: delegate
        )

        updaterDelegate.onFallbackRequested = { [weak self] updateCheck in
            DispatchQueue.main.async { [weak self] in
                self?.retryCheck(afterFailedCheck: updateCheck)
            }
        }
        updaterDelegate.onCheckFailed = { [weak self] error in
            self?.onCheckFailed?(error)
        }
        updaterDelegate.onUpdateSkipped = { [weak self] in
            self?.userDriver.releaseNotesStore.clear()
            self?.onUpdateSkipped?()
        }
        updaterDelegate.onUpdatePrepared = { [weak self] item in
            self?.userDriver.recordPendingUpdate(item)
        }

        notificationObservers = [
            NotificationCenter.default.addObserver(
                forName: .SUUpdaterDidFindValidUpdate,
                object: updater,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onUpdateFound?()
                }
            },
            NotificationCenter.default.addObserver(
                forName: .SUUpdaterDidNotFindUpdate,
                object: updater,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.onNoUpdateFound?()
                }
            },
        ]
    }

    deinit {
        installedNotesTask?.cancel()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @discardableResult
    func configure(
        channel: UpdateChannel,
        checksEnabled: Bool,
        automaticDownloadEnabled: Bool,
        feedPreference: UpdateFeedPreference
    ) -> Bool {
        guard let feeds = configuration.feedPair(for: channel) else { return false }
        let didChangeFeed = updaterDelegate.setFeeds(
            feeds,
            preference: feedPreference
        )
        let wasStarted = didStart
        guard startIfNeeded() else { return false }
        updater.automaticallyChecksForUpdates = checksEnabled
        updater.automaticallyDownloadsUpdates = checksEnabled && automaticDownloadEnabled
        userDriver.feedPreference = feedPreference
        if wasStarted && didChangeFeed {
            updater.resetUpdateCycle()
        }
        return true
    }

    @discardableResult
    func checkForUpdates(
        channel: UpdateChannel,
        checksEnabled: Bool,
        automaticDownloadEnabled: Bool,
        feedPreference: UpdateFeedPreference
    ) -> Bool {
        guard configure(
            channel: channel,
            checksEnabled: checksEnabled,
            automaticDownloadEnabled: automaticDownloadEnabled,
            feedPreference: feedPreference
        ) else {
            return false
        }
        updater.checkForUpdates()
        return true
    }

    private func retryCheck(afterFailedCheck updateCheck: SPUUpdateCheck) {
        guard didStart else { return }
        switch updateCheck {
        case .updates:
            updater.checkForUpdates()
        case .updatesInBackground:
            updater.checkForUpdatesInBackground()
        case .updateInformation:
            updater.checkForUpdateInformation()
        @unknown default:
            updater.checkForUpdatesInBackground()
        }
    }

    func showInstalledReleaseNotes(
        hasExistingInstallation: Bool,
        loadPreference: @escaping () async -> UpdateFeedPreference?
    ) {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let installed = userDriver.releaseNotesStore.takeInstalledRelease(
                  version: version,
                  build: build,
                  hasExistingInstallation: hasExistingInstallation
              ) else {
            return
        }
        if let preference = installed.preference {
            userDriver.showInstalledReleaseNotes(installed, preference: preference)
        } else {
            installedNotesTask = Task { [weak self] in
                guard let preference = await loadPreference(), !Task.isCancelled else { return }
                self?.userDriver.showInstalledReleaseNotes(installed, preference: preference)
            }
        }
    }

    private func startIfNeeded() -> Bool {
        guard !didStart else { return true }
        do {
            try updater.start()
            didStart = true
            return true
        } catch {
            return false
        }
    }
}
