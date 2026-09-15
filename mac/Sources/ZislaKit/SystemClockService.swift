import AppKit
import Darwin
import Foundation
import ObjectiveC.runtime
import UserNotifications
import ZislaCore

public enum SystemClockServiceError: LocalizedError, Equatable, Sendable {
    case unavailable
    case requestFailed

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            AppLocalization.text("操作失败：%@", AppLocalization.text("打开系统「时钟」App"))
        case .requestFailed:
            AppLocalization.text("操作失败")
        }
    }
}

@MainActor
public enum SystemClockService {
    public enum Destination: String, Sendable {
        case timer = "clock-timer://"
        case alarm = "clock-alarm://"
    }

    public enum TimerAction: Equatable, Sendable {
        case start(duration: TimeInterval)
        case pause
        case resume
        case cancel
    }

    public static func requestTimer(
        _ action: TimerAction,
        requester: (@MainActor (TimerAction) throws -> Bool)? = nil
    ) throws {
        if case .start(let duration) = action, !duration.isFinite || duration <= 0 {
            throw SystemClockServiceError.requestFailed
        }
        let request = requester ?? NativeClockTimerRequester.request
        guard try request(action) else {
            throw SystemClockServiceError.requestFailed
        }
    }

    public static func cancelLegacyAlarmNotifications(
        pendingRequests: @MainActor () async -> [UNNotificationRequest] = {
            await UNUserNotificationCenter.current().pendingNotificationRequests()
        },
        cancel: @MainActor ([String]) -> Void = {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: $0)
        }
    ) async {
        let requests = await pendingRequests()
        cancel(requests.map(\.identifier).filter { $0.hasPrefix("zisla.alarm.") })
    }

    public static func open(
        _ destination: Destination,
        opener: @MainActor ([URL], URL, NSWorkspace.OpenConfiguration) async throws -> Void = {
            urls, application, configuration in
            _ = try await NSWorkspace.shared.open(
                urls,
                withApplicationAt: application,
                configuration: configuration
            )
        }
    ) async throws {
        try await opener(
            [URL(string: destination.rawValue)!],
            URL(fileURLWithPath: "/System/Applications/Clock.app"),
            NSWorkspace.OpenConfiguration()
        )
    }
}

@MainActor
enum NativeClockTimerRequester {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer"
    private static let managerClassName = "MTTimerManager"

    static func request(_ action: SystemClockService.TimerAction) throws -> Bool {
        guard dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) != nil,
              let managerType = NSClassFromString(managerClassName) as? NSObject.Type else {
            throw SystemClockServiceError.unavailable
        }

        return request(action, manager: managerType.init())
    }

    static func request(_ action: SystemClockService.TimerAction, manager: NSObject) -> Bool {
        switch action {
        case .start(let duration):
            return invoke(
                manager,
                selector: NSSelectorFromString("startCurrentTimerWithDurationSync:"),
                duration: duration
            )
        case .pause:
            return invoke(manager, selector: NSSelectorFromString("pauseCurrentTimerSync"))
        case .resume:
            return invoke(manager, selector: NSSelectorFromString("resumeCurrentTimerSync"))
        case .cancel:
            return invoke(manager, selector: NSSelectorFromString("stopCurrentTimerSync"))
        }
    }

    private static func invoke(_ target: NSObject, selector: Selector) -> Bool {
        guard let method = class_getInstanceMethod(type(of: target), selector) else { return false }
        typealias Function = @convention(c) (AnyObject, Selector) -> Bool
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        return function(target, selector)
    }

    private static func invoke(
        _ target: NSObject,
        selector: Selector,
        duration: TimeInterval
    ) -> Bool {
        guard let method = class_getInstanceMethod(type(of: target), selector) else { return false }
        typealias Function = @convention(c) (AnyObject, Selector, TimeInterval) -> Bool
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        return function(target, selector, duration)
    }
}
