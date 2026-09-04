import Combine
import Foundation
import ServiceManagement
import ZislaCore

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown
}

@MainActor
protocol LaunchAtLoginService: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

@MainActor
final class SMAppLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus {
        Self.map(SMAppService.mainApp.status)
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }
}

@MainActor
public final class LaunchAtLoginController: ObservableObject {
    @Published public private(set) var isEnabled = false
    @Published public private(set) var status: LaunchAtLoginStatus = .notRegistered
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var showsOpenLoginItemsButton = false

    private let service: any LaunchAtLoginService

    public convenience init() {
        self.init(service: SMAppLaunchAtLoginService())
    }

    init(service: any LaunchAtLoginService) {
        self.service = service
        refresh()
    }

    public func refresh() {
        errorMessage = nil
        apply(status: service.status)
    }

    public func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            apply(status: service.status)
        } catch {
            apply(status: service.status)
            errorMessage = Self.chineseError(from: error, enabling: enabled)
        }
    }

    public func openLoginItemsSettings() {
        service.openSystemSettingsLoginItems()
    }

    private func apply(status: LaunchAtLoginStatus) {
        self.status = status
        isEnabled = status == .enabled
        showsOpenLoginItemsButton = status == .requiresApproval
        statusMessage = Self.message(for: status)
    }

    private static func message(for status: LaunchAtLoginStatus) -> String? {
        switch status {
        case .enabled:
            return AppLocalization.text("已在登录时自动启动")
        case .notRegistered:
            return "开机或登录后自动在后台运行"
        case .requiresApproval:
            return AppLocalization.text("需要在系统设置中批准登录项")
        case .notFound:
            return AppLocalization.text("找不到登录项，请确认应用已正确安装到“应用程序”文件夹")
        case .unknown:
            return AppLocalization.text("无法读取登录项状态")
        }
    }

    private static func chineseError(from error: Error, enabling: Bool) -> String {
        let action = enabling ? "开启" : "关闭"
        let detail = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "无法\(action)登录时启动，请稍后重试。"
        }
        return "无法\(action)登录时启动：\(detail)"
    }
}
