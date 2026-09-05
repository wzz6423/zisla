@preconcurrency import Foundation
import Sparkle
import ZislaCore

struct SparkleFeedPair: Equatable {
    let gitee: URL
    let github: URL

    func url(for source: UpdateFeedSource) -> URL {
        switch source {
        case .primary: gitee
        case .fallback: github
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

    private var feeds: SparkleFeedPair
    private var fallbackState = UpdateFeedFallbackState()
    private var fallbackRetryCheck: SPUUpdateCheck?

    var shouldSuppressUpdaterError: Bool {
        fallbackState.source == .primary
    }

    init(feeds: SparkleFeedPair) {
        self.feeds = feeds
    }

    @discardableResult
    func setFeeds(_ feeds: SparkleFeedPair) -> Bool {
        let previousURL = self.feeds.url(for: fallbackState.source)
        self.feeds = feeds
        fallbackState.beginCheck()
        fallbackRetryCheck = nil
        return previousURL != self.feeds.url(for: fallbackState.source)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feeds.url(for: fallbackState.source).absoluteString
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
    var onUpdaterErrorPresented: ((Error) -> Void)?

    init(
        hostBundle: Bundle,
        shouldSuppressUpdaterError: @escaping () -> Bool,
        onUpdaterErrorPresented: ((Error) -> Void)? = nil
    ) {
        self.shouldSuppressUpdaterError = shouldSuppressUpdaterError
        self.onUpdaterErrorPresented = onUpdaterErrorPresented
        super.init(hostBundle: hostBundle, delegate: nil)
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

    private let configuration: SparkleUpdateConfiguration
    private let updaterDelegate: SparkleFeedDelegate
    private let userDriver: SparkleStandardUserDriver
    private let updater: SPUUpdater
    private var notificationObservers: [NSObjectProtocol] = []
    private var didStart = false

    init?(configuration: SparkleUpdateConfiguration? = SparkleUpdateConfiguration(
        infoDictionary: Bundle.main.infoDictionary ?? [:]
    )) {
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
            }
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
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @discardableResult
    func configure(
        channel: UpdateChannel,
        checksEnabled: Bool,
        automaticDownloadEnabled: Bool
    ) -> Bool {
        guard let feeds = configuration.feedPair(for: channel) else { return false }
        let didChangeFeed = updaterDelegate.setFeeds(feeds)
        let wasStarted = didStart
        guard startIfNeeded() else { return false }
        updater.automaticallyChecksForUpdates = checksEnabled
        updater.automaticallyDownloadsUpdates = checksEnabled && automaticDownloadEnabled
        if wasStarted && didChangeFeed {
            updater.resetUpdateCycle()
        }
        return true
    }

    @discardableResult
    func checkForUpdates(
        channel: UpdateChannel,
        checksEnabled: Bool,
        automaticDownloadEnabled: Bool
    ) -> Bool {
        guard configure(
            channel: channel,
            checksEnabled: checksEnabled,
            automaticDownloadEnabled: automaticDownloadEnabled
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
