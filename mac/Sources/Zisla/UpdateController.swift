import Foundation
import ZislaCore
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class UpdateController {
    static let shared = UpdateController()

    var onUpdateAvailabilityChanged: ((Bool) -> Void)? {
        didSet {
#if canImport(Sparkle)
            feedDelegate.onUpdateAvailabilityChanged = onUpdateAvailabilityChanged
#endif
        }
    }

#if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?
    private let feedDelegate = UpdateFeedDelegate()

    var isAvailable: Bool { controller != nil }

    func start(
        automaticallyChecks: Bool,
        automaticallyDownloads: Bool,
        automaticChannel: UpdateChannel
    ) {
        guard controller == nil, canUseSignedUpdates else { return }
        feedDelegate.automaticChannel = automaticChannel
        let value = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: feedDelegate,
            userDriverDelegate: nil
        )
        value.updater.automaticallyChecksForUpdates = automaticallyChecks
        value.updater.automaticallyDownloadsUpdates = automaticallyDownloads
        controller = value
    }

    func configure(
        automaticallyChecks: Bool,
        automaticallyDownloads: Bool,
        automaticChannel: UpdateChannel
    ) {
        guard let updater = controller?.updater else {
            start(
                automaticallyChecks: automaticallyChecks,
                automaticallyDownloads: automaticallyDownloads,
                automaticChannel: automaticChannel
            )
            return
        }
        feedDelegate.automaticChannel = automaticChannel
        updater.automaticallyChecksForUpdates = automaticallyChecks
        updater.automaticallyDownloadsUpdates = automaticallyDownloads
    }

    @discardableResult
    func checkForUpdates(manual: Bool, channel: UpdateChannel? = nil) -> Bool {
        guard let controller else { return false }
        if manual {
            feedDelegate.manualChannel = channel ?? feedDelegate.automaticChannel
            controller.checkForUpdates(nil)
        } else {
            feedDelegate.manualChannel = nil
            controller.updater.checkForUpdatesInBackground()
        }
        return true
    }

    private var canUseSignedUpdates: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return Data(base64Encoded: key)?.count == 32
    }
#else
    var isAvailable: Bool { false }

    func start(
        automaticallyChecks: Bool,
        automaticallyDownloads: Bool,
        automaticChannel: UpdateChannel
    ) {}

    func configure(
        automaticallyChecks: Bool,
        automaticallyDownloads: Bool,
        automaticChannel: UpdateChannel
    ) {}

    @discardableResult
    func checkForUpdates(manual: Bool, channel: UpdateChannel? = nil) -> Bool { false }
#endif
}

#if canImport(Sparkle)
@MainActor
private final class UpdateFeedDelegate: NSObject, SPUUpdaterDelegate {
    var automaticChannel: UpdateChannel = .release
    var manualChannel: UpdateChannel?
    var onUpdateAvailabilityChanged: ((Bool) -> Void)?

    func feedURLString(for updater: SPUUpdater) -> String? {
        switch manualChannel ?? automaticChannel {
        case .release:
            "https://github.com/wzz6423/zisla/releases/latest/download/appcast.xml"
        case .preview:
            "https://github.com/wzz6423/zisla/releases/download/preview/appcast.xml"
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        manualChannel = nil
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onUpdateAvailabilityChanged?(true)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        onUpdateAvailabilityChanged?(false)
    }
}
#endif
