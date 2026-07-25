import Foundation
import Testing

@testable import ZislaKit

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus = .notRegistered
    var registerError: Error?
    var unregisterError: Error?
    var statusAfterRegister: LaunchAtLoginStatus = .enabled
    var statusAfterUnregister: LaunchAtLoginStatus = .notRegistered
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSettingsCallCount = 0

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        status = statusAfterUnregister
    }

    func openSystemSettingsLoginItems() {
        openSettingsCallCount += 1
    }
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "模拟失败" }
}

@MainActor
struct LaunchAtLoginControllerTests {
    @Test
    func refreshMapsServiceStatusToToggleAndMessage() {
        let service = FakeLaunchAtLoginService()
        service.status = .enabled
        let controller = LaunchAtLoginController(service: service)

        #expect(controller.isEnabled)
        #expect(controller.status == .enabled)
        #expect(controller.statusMessage == "已在登录时自动启动")
        #expect(controller.showsOpenLoginItemsButton == false)
        #expect(controller.errorMessage == nil)

        service.status = .requiresApproval
        controller.refresh()

        #expect(controller.isEnabled == false)
        #expect(controller.status == .requiresApproval)
        #expect(controller.statusMessage == "需要在系统设置中批准登录项")
        #expect(controller.showsOpenLoginItemsButton)
        #expect(controller.errorMessage == nil)
    }

    @Test
    func setEnabledRegistersAndReflectsEnabledStatus() throws {
        let service = FakeLaunchAtLoginService()
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        #expect(service.registerCallCount == 1)
        #expect(controller.isEnabled)
        #expect(controller.status == .enabled)
        #expect(controller.errorMessage == nil)
    }

    @Test
    func setEnabledUnregisterReflectsDisabledStatus() {
        let service = FakeLaunchAtLoginService()
        service.status = .enabled
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(false)

        #expect(service.unregisterCallCount == 1)
        #expect(controller.isEnabled == false)
        #expect(controller.status == .notRegistered)
        #expect(controller.errorMessage == nil)
    }

    @Test
    func registerFailureRevertsToRealStatusAndShowsChineseError() {
        let service = FakeLaunchAtLoginService()
        service.registerError = TestError()
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        #expect(service.registerCallCount == 1)
        #expect(controller.isEnabled == false)
        #expect(controller.status == .notRegistered)
        #expect(controller.errorMessage == "无法开启登录时启动：模拟失败")
    }

    @Test
    func unregisterFailureRevertsToRealStatusAndShowsChineseError() {
        let service = FakeLaunchAtLoginService()
        service.status = .enabled
        service.unregisterError = TestError()
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(false)

        #expect(service.unregisterCallCount == 1)
        #expect(controller.isEnabled)
        #expect(controller.status == .enabled)
        #expect(controller.errorMessage == "无法关闭登录时启动：模拟失败")
    }

    @Test
    func registerRequiringApprovalDoesNotEnableToggle() {
        let service = FakeLaunchAtLoginService()
        service.statusAfterRegister = .requiresApproval
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        #expect(service.registerCallCount == 1)
        #expect(controller.isEnabled == false)
        #expect(controller.status == .requiresApproval)
        #expect(controller.showsOpenLoginItemsButton)
        #expect(controller.statusMessage == "需要在系统设置中批准登录项")
        #expect(controller.errorMessage == nil)
    }

    @Test
    func openLoginItemsSettingsForwardsToService() {
        let service = FakeLaunchAtLoginService()
        let controller = LaunchAtLoginController(service: service)

        controller.openLoginItemsSettings()

        #expect(service.openSettingsCallCount == 1)
    }

    @Test
    func smAppStatusMappingCoversKnownCases() {
        #expect(SMAppLaunchAtLoginService.map(.notRegistered) == .notRegistered)
        #expect(SMAppLaunchAtLoginService.map(.enabled) == .enabled)
        #expect(SMAppLaunchAtLoginService.map(.requiresApproval) == .requiresApproval)
        #expect(SMAppLaunchAtLoginService.map(.notFound) == .notFound)
    }
}
