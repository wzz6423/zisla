import Combine
import Foundation
import ZislaCore
import ZislaKit

@MainActor
final class ImmediateCleanupController: ObservableObject {
    struct Outcome: Equatable {
        var didSucceed: Bool
        var errors: [String]
        var permissions: Set<OnboardingPermissionID> = []

        var noticeKey: String {
            if errors.isEmpty { return "清理完成" }
            return didSucceed
                ? "清理部分失败，如需查看详细信息请去设置-系统状态与清理页面查看"
                : "清理失败，如需查看详细信息请去设置-系统状态与清理页面查看"
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var errors: [String] = []
    private(set) var task: Task<Void, Never>?
    private let operation: (FeatureSettings) async -> Outcome?
    private let onMessage: (String?) -> Void
    private let requestPermission: (OnboardingPermissionID) -> Bool

    init(
        operation: @escaping (FeatureSettings) async -> Outcome?,
        onMessage: @escaping (String?) -> Void,
        requestPermission: @escaping (OnboardingPermissionID) -> Bool
    ) {
        self.operation = operation
        self.onMessage = onMessage
        self.requestPermission = requestPermission
    }

    static func canCleanNow(settings: FeatureSettings) -> Bool {
        (settings.systemMonitorEnabled && settings.systemCleanupPolicy != .never)
            || settings.trashCleanupPolicy != .never
            || (settings.clipboardHistoryEnabled && settings.clipboardHistoryCleanupPolicy != .never)
            || settings.voiceRecordingCleanupPolicy != .never
    }

    func start(settings: FeatureSettings) {
        guard !isRunning, Self.canCleanNow(settings: settings) else { return }
        isRunning = true
        errors = []
        onMessage(AppLocalization.text("正在清理"))
        task = Task {
            let outcome = await operation(settings)
            isRunning = false
            task = nil
            guard !Task.isCancelled, let outcome else { onMessage(nil); return }
            errors = outcome.errors
            for permission in outcome.permissions {
                if !requestPermission(permission) {
                    errors.append(AppLocalization.text("无法打开系统设置，请手动打开。"))
                }
            }
            onMessage(AppLocalization.text(outcome.noticeKey))
        }
    }

    func cancel() {
        task?.cancel()
    }

    static func cleanConfiguredItems(
        settings: FeatureSettings,
        systemCleanup: SystemAutoCleanupService,
        clipboardHistory: ClipboardHistoryStore,
        voiceHistory: VoiceHistoryStore,
        now: Date = Date()
    ) async -> Outcome? {
        guard !Task.isCancelled else { return nil }
        let result = await systemCleanup.runNow(settings: settings)
        guard !Task.isCancelled else { return nil }
        var outcome = Outcome(didSucceed: false, errors: [])
        if let system = result.system {
            outcome.didSucceed = system.successCount > 0 || system.failures.isEmpty
            outcome.errors = system.failures.map { "\($0.url.path): \($0.message)" }
            if system.failures.contains(where: \.isPermissionDenied) {
                outcome.permissions.insert(.fullDiskAccess)
            }
        }
        switch result.trash {
        case .success: outcome.didSucceed = true
        case .failure(let error):
            outcome.errors.append(AppLocalization.text("定时倾倒废纸篓") + ": " + error.message)
            if error.isPermissionDenied { outcome.permissions.insert(.automation) }
        case nil: break
        }
        if settings.clipboardHistoryEnabled && settings.clipboardHistoryCleanupPolicy != .never {
            if let error = await clipboardHistory.cleanupOldHistoryNow(policy: settings.clipboardHistoryCleanupPolicy, now: now) {
                outcome.errors.append(AppLocalization.text("自动删除剪贴板历史") + ": " + error)
            } else { outcome.didSucceed = true }
        }
        guard !Task.isCancelled else { return nil }
        if settings.voiceRecordingCleanupPolicy != .never {
            let result = voiceHistory.cleanupOldRecordings(policy: settings.voiceRecordingCleanupPolicy, now: now)
            outcome.didSucceed = outcome.didSucceed || result.successCount > 0 || result.error == nil
            if let error = result.error {
                outcome.errors.append(AppLocalization.text("自动清理录音") + ": " + error)
            }
        }
        return outcome
    }
}
