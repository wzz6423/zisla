import Combine
import Foundation
import IOKit.pwr_mgt
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@MainActor
struct KeepDisplayAwakeNoticeTests {
    private let enableError = "无法开启合盖亮屏，请检查管理员授权后重试。"
    private let restoreError = "无法恢复休眠设置，请重试关闭保持亮屏。"

    @Test(arguments: [false, true])
    func authorizationOrAssertionFailureReachesTheNoticeWithoutAToolboxView(assertionFails: Bool) async {
        let manager = AssertionManager(fails: assertionFails)
        let controller = PowerAssertionController(manager: manager, startLidClosedSession: {
            throw CocoaError(.userCancelled)
        })
        var messages: [String] = []
        let observation = AppModel.observeDisplayAwakeErrors(controller) { messages.append($0) }
        defer { observation.cancel(); controller.releaseAll() }

        await controller.setKeepDisplayAwakeIncludingLidClose(true)

        #expect(messages == [AppLocalization.text(enableError)], "An operation failure must reach the unified notice once")
        #expect(!controller.keepDisplayAwake)
        #expect(manager.activeIDs.isEmpty)
    }

    @Test
    func failedRestoreShowsANoticeAndSuccessfulRetryDoesNotEraseIt() async {
        let session = SleepSession()
        let controller = PowerAssertionController(manager: AssertionManager(), startLidClosedSession: { session })
        var messages: [String] = []
        let observation = AppModel.observeDisplayAwakeErrors(controller) { messages.append($0) }
        defer { observation.cancel(); controller.releaseAll() }
        await controller.setKeepDisplayAwakeIncludingLidClose(true)
        session.failStop = true

        await controller.setKeepDisplayAwakeIncludingLidClose(false)

        #expect(messages == [AppLocalization.text(restoreError)])
        #expect(controller.keepDisplayAwake, "A failed restore must leave the retry available")
        session.failStop = false
        await controller.setKeepDisplayAwakeIncludingLidClose(false)
        #expect(!controller.keepDisplayAwake)
        #expect(messages == [AppLocalization.text(restoreError)], "Clearing a service error must not dismiss the app's notice")
    }

    @Test
    func successfulOperationsDoNotReplaceAnExistingNotice() async {
        let controller = PowerAssertionController(manager: AssertionManager(), startLidClosedSession: { SleepSession() })
        var messages = ["Existing notice"]
        let observation = AppModel.observeDisplayAwakeErrors(controller) { messages.append($0) }
        defer { observation.cancel(); controller.releaseAll() }

        await controller.setKeepDisplayAwakeIncludingLidClose(true)
        await controller.setKeepDisplayAwakeIncludingLidClose(false)

        #expect(messages == ["Existing notice"], "Initial and successful nil values must not present an empty notice")
        #expect(!controller.keepDisplayAwake)
    }

    @Test
    func eachDeniedRetryRefreshesTheSameNotice() async {
        let controller = PowerAssertionController(manager: AssertionManager(), startLidClosedSession: {
            throw CocoaError(.userCancelled)
        })
        var messages: [String] = []
        let observation = AppModel.observeDisplayAwakeErrors(controller) { messages.append($0) }
        defer { observation.cancel(); controller.releaseAll() }

        await controller.setKeepDisplayAwakeIncludingLidClose(true)
        await controller.setKeepDisplayAwakeIncludingLidClose(true)

        #expect(messages == Array(repeating: AppLocalization.text(enableError), count: 2),
                "Equal errors from separate attempts must refresh the app's notice lifetime")
    }

    @Test
    func cancellationStopsNoticesAndObservationDoesNotRetainTheController() {
        var controller: PowerAssertionController? = PowerAssertionController(manager: AssertionManager())
        weak var weakController = controller
        var messages: [String] = []
        let observation = AppModel.observeDisplayAwakeErrors(controller!) { messages.append($0) }
        controller?.displayAwakeError = enableError
        observation.cancel()

        controller?.displayAwakeError = restoreError
        controller = nil

        #expect(messages == [AppLocalization.text(enableError)])
        #expect(weakController == nil, "The app's error observation must not extend the power-controller lifetime")
    }

    @Test
    func noticesUseTheCurrentLanguageForEveryEmission() {
        let controller = PowerAssertionController(manager: AssertionManager())
        var messages: [String] = []
        let observation = AppModel.observeDisplayAwakeErrors(controller) { messages.append($0) }
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            observation.cancel()
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }

        // Override only this test process's argument domain, without writing user preferences.
        for language in AppLanguage.allCases {
            var localizedArguments = arguments
            localizedArguments[AppLocalization.defaultsKey] = language.rawValue
            defaults.setVolatileDomain(localizedArguments, forName: UserDefaults.argumentDomain)
            for key in [enableError, restoreError] {
                controller.displayAwakeError = key
                #expect(messages.last == AppLocalization.string(key, language: language),
                        "The unified notice must use the active \(language.rawValue) translation")
            }
        }
        #expect(messages.count == AppLanguage.allCases.count * 2)
    }
}

@MainActor
private final class AssertionManager: PowerAssertionManaging {
    let fails: Bool
    private(set) var activeIDs: Set<IOPMAssertionID> = []

    init(fails: Bool = false) { self.fails = fails }

    func create(
        type: CFString,
        name: CFString,
        level: IOPMAssertionLevel,
        assertionID: inout IOPMAssertionID
    ) -> IOReturn {
        guard !fails else { return kIOReturnNotPermitted }
        assertionID = IOPMAssertionID(activeIDs.count + 1)
        activeIDs.insert(assertionID)
        return kIOReturnSuccess
    }

    func release(assertionID: IOPMAssertionID) -> IOReturn {
        activeIDs.remove(assertionID)
        return kIOReturnSuccess
    }
}

private final class SleepSession: LidClosedDisplaySession, @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFailStop = false
    var failStop: Bool {
        get { lock.withLock { shouldFailStop } }
        set { lock.withLock { shouldFailStop = newValue } }
    }

    func stop() throws {
        if failStop { throw CocoaError(.fileWriteNoPermission) }
    }

    func cancel() {}
}
