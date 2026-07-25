import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class UpdateController {
    static let shared = UpdateController()

#if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    func start(automaticallyChecks: Bool, automaticallyDownloads: Bool) {
        guard controller == nil, canUseSignedUpdates else { return }
        let value = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        value.updater.automaticallyChecksForUpdates = automaticallyChecks
        value.updater.automaticallyDownloadsUpdates = automaticallyDownloads
        controller = value
    }

    func configure(automaticallyChecks: Bool, automaticallyDownloads: Bool) {
        guard let updater = controller?.updater else {
            start(
                automaticallyChecks: automaticallyChecks,
                automaticallyDownloads: automaticallyDownloads
            )
            return
        }
        updater.automaticallyChecksForUpdates = automaticallyChecks
        updater.automaticallyDownloadsUpdates = automaticallyDownloads
    }

    @discardableResult
    func checkForUpdates() -> Bool {
        guard let controller else { return false }
        controller.checkForUpdates(nil)
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

    func start(automaticallyChecks: Bool, automaticallyDownloads: Bool) {}

    func configure(automaticallyChecks: Bool, automaticallyDownloads: Bool) {}

    @discardableResult
    func checkForUpdates() -> Bool { false }
#endif
}
