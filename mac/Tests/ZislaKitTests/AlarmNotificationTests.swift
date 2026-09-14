import Foundation
import Testing
import UserNotifications
import ZislaCore

@testable import ZislaKit

@MainActor
struct AlarmNotificationTests {
    @Test(arguments: [UNAuthorizationStatus.denied, .notDetermined, .provisional])
    func unavailableAuthorizationExplainsWhyTheAlarmCannotNotify(_ status: UNAuthorizationStatus) async throws {
        try await withService(settings: { (status, .enabled) }) { service in
            await service.refreshNotificationStatus()
            #expect(service.notificationPermissionWarning == AppLocalization.text(
                "闹钟通知未获允许，请在系统设置中开启通知。"
            ))
        }
    }

    @Test(arguments: [UNNotificationSetting.disabled, .notSupported])
    func unavailableSoundExplainsWhyTheAlarmIsSilent(_ sound: UNNotificationSetting) async throws {
        try await withService(settings: { (.authorized, sound) }) { service in
            await service.refreshNotificationStatus()
            #expect(service.notificationPermissionWarning == AppLocalization.text(
                "闹钟通知声音已关闭，请在系统设置中开启声音。"
            ))
        }
    }

    @Test
    func returningFromSettingsClearsThePermissionWarning() async throws {
        var status = UNAuthorizationStatus.denied
        var sound = UNNotificationSetting.disabled
        try await withService(settings: { (status, sound) }) { service in
            await service.refreshNotificationStatus()
            #expect(service.notificationPermissionWarning != nil)
            status = .authorized
            await service.refreshNotificationStatus()
            #expect(service.notificationPermissionWarning == AppLocalization.text(
                "闹钟通知声音已关闭，请在系统设置中开启声音。"
            ))
            sound = .enabled
            await service.refreshNotificationStatus()
            #expect(service.notificationPermissionWarning == nil)
        }
    }

    @Test
    func inspectingPermissionDoesNotRequestIt() async throws {
        var requests = 0
        var status = UNAuthorizationStatus.notDetermined
        try await withService(
            settings: { (status, .disabled) },
            authorize: { requests += 1; status = .denied; return false }
        ) { service in
            await service.refreshNotificationStatus()
            #expect(requests == 0)
            #expect(service.notificationPermissionWarning != nil)
        }
    }

    @Test(arguments: [true, false])
    func authorizationResultIsReflectedInTheWarning(_ granted: Bool) async throws {
        var status = UNAuthorizationStatus.notDetermined
        var requests = 0
        try await withService(
            settings: { (status, .enabled) },
            authorize: {
                requests += 1
                status = granted ? .authorized : .denied
                return granted
            }
        ) { service in
            await service.refreshNotificationStatus(requestAuthorization: true)
            #expect(requests == 1)
            #expect((service.notificationPermissionWarning == nil) == granted)
            await service.refreshNotificationStatus(requestAuthorization: true)
            #expect(requests == 1)
        }
    }

    @Test
    func authorizationFailureIsVisibleAndCanBeRetried() async throws {
        var status = UNAuthorizationStatus.notDetermined
        var requests = 0
        try await withService(
            settings: { (status, .enabled) },
            authorize: {
                requests += 1
                if requests == 1 { throw NotificationFailure() }
                status = .authorized
                return true
            }
        ) { service in
            await service.refreshNotificationStatus(requestAuthorization: true)
            #expect(service.notificationPermissionWarning?.contains("notification test failure") == true)
            await service.refreshNotificationStatus(requestAuthorization: true)
            #expect(requests == 2)
            #expect(service.notificationPermissionWarning == nil)
        }
    }

    @Test
    func anOlderSettingsResponseCannotRestoreADismissedWarning() async throws {
        let firstReadStarted = AlarmNotificationGate<Void>()
        let finishFirstRead = AlarmNotificationGate<Void>()
        var reads = 0
        try await withService(settings: {
            reads += 1
            if reads == 1 {
                firstReadStarted.send(())
                await finishFirstRead.wait()
                return (.denied, .disabled)
            }
            return (.authorized, .enabled)
        }) { service in
            let oldRead = Task { await service.refreshNotificationStatus() }
            await firstReadStarted.wait()
            await service.refreshNotificationStatus()
            finishFirstRead.send(())
            await oldRead.value
            #expect(service.notificationPermissionWarning == nil)
        }
    }

    @Test
    func aNewerReadDoesNotDiscardAnExplicitPermissionRequest() async throws {
        let firstReadStarted = AlarmNotificationGate<Void>()
        let finishFirstRead = AlarmNotificationGate<Void>()
        var status = UNAuthorizationStatus.notDetermined
        var reads = 0
        var requests = 0
        try await withService(settings: {
            reads += 1
            if reads == 1 {
                firstReadStarted.send(())
                await finishFirstRead.wait()
            }
            return (status, .enabled)
        }, authorize: {
            requests += 1
            status = .authorized
            return true
        }) { service in
            let explicitRequest = Task { await service.refreshNotificationStatus(requestAuthorization: true) }
            await firstReadStarted.wait()
            await service.refreshNotificationStatus()
            finishFirstRead.send(())
            await explicitRequest.value
            #expect(requests == 1)
            #expect(service.notificationPermissionWarning == nil)
        }
    }

    @Test
    func anOldAuthorizationFailureDoesNotOverrideNewerSettings() async throws {
        let authorizationStarted = AlarmNotificationGate<Void>()
        let finishAuthorization = AlarmNotificationGate<Void>()
        var status = UNAuthorizationStatus.notDetermined
        try await withService(settings: { (status, .enabled) }, authorize: {
            authorizationStarted.send(())
            await finishAuthorization.wait()
            throw NotificationFailure()
        }) { service in
            let explicitRequest = Task { await service.refreshNotificationStatus(requestAuthorization: true) }
            await authorizationStarted.wait()
            status = .authorized
            await service.refreshNotificationStatus()
            finishAuthorization.send(())
            await explicitRequest.value
            #expect(service.notificationPermissionWarning == nil)
        }
    }

    @Test(arguments: [true, false])
    func concurrentAuthorizationRequestsShareOnePrompt(_ succeeds: Bool) async throws {
        let authorizationStarted = AlarmNotificationGate<Void>()
        let finishAuthorization = AlarmNotificationGate<Void>()
        var status = UNAuthorizationStatus.notDetermined
        var requests = 0
        try await withService(
            settings: { (status, .enabled) },
            authorize: {
                requests += 1
                if requests == 1 {
                    authorizationStarted.send(())
                    await finishAuthorization.wait()
                }
                if !succeeds { throw NotificationFailure() }
                status = .authorized
                return true
            }
        ) { service in
            let first = Task { await service.refreshNotificationStatus(requestAuthorization: true) }
            await authorizationStarted.wait()
            await service.refreshNotificationStatus(requestAuthorization: true)
            #expect(requests == 1)
            finishAuthorization.send(())
            await first.value
            #expect((service.notificationPermissionWarning == nil) == succeeds)
        }
    }

    @Test
    func registrationFailureDoesNotSilentlyClaimTheAlarmWillNotify() async throws {
        try await withService(register: { _ in throw NotificationFailure() }) { service in
            let alarm = service.add(hour: 12, minute: 46, weekdays: [2, 3])
            #expect(service.alarms == [alarm])
            #expect(service.errorMessage?.contains("notification test failure") == true)
            await service.refreshNotificationStatus()
            #expect(service.errorMessage?.contains("notification test failure") == true)
        }
    }

    @Test(arguments: [true, false])
    func errorsFromReplacedRegistrationsDoNotReappear(_ editAlarm: Bool) async throws {
        weak var target: AlarmService?
        var registrations = 0
        try await withService(register: { _ in
            registrations += 1
            if registrations == 1 {
                let service = try #require(target)
                if editAlarm {
                    var alarm = try #require(service.alarms.first)
                    alarm.minute = 47
                    service.update(alarm)
                } else {
                    service.rescheduleAll()
                }
                throw NotificationFailure()
            }
        }) { service in
            target = service
            service.add(hour: 12, minute: 46)
            #expect(registrations == 2)
            #expect(service.errorMessage == nil)
        }
    }

    @Test(arguments: [true, false])
    func errorsForRemovedOrSuspendedAlarmsDoNotReappear(_ remove: Bool) async throws {
        weak var target: AlarmService?
        try await withService(register: { _ in
            if remove, let id = target?.alarms.first?.id {
                target?.remove(id: id)
            } else {
                target?.suspend()
            }
            throw NotificationFailure()
        }) { service in
            target = service
            service.add(hour: 12, minute: 46)
            #expect(service.errorMessage == nil)
        }
    }

    @Test
    func repeatingAlarmsKeepTheirWeekdaysAndRequestSound() async throws {
        var requests: [UNNotificationRequest] = []
        try await withService(register: { requests.append($0) }) { service in
            let alarm = service.add(hour: 12, minute: 46, weekdays: [2, 3])
            #expect(requests.map(\.identifier) == AlarmService.notificationIdentifiers(for: alarm))
            #expect(requests.count == 2)
            for (request, weekday) in zip(requests, [2, 3]) {
                let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
                #expect(trigger.repeats)
                #expect(trigger.dateComponents.hour == 12)
                #expect(trigger.dateComponents.minute == 46)
                #expect(trigger.dateComponents.weekday == weekday)
                #expect(request.content.sound != nil)
            }
            service.suspend()
            service.add(hour: 8, minute: 0)
            #expect(requests.count == 2)
        }
    }

    private func withService(
        settings: @escaping () async -> (UNAuthorizationStatus, UNNotificationSetting) = { (.authorized, .enabled) },
        authorize: @escaping () async throws -> Bool = { false },
        register: @escaping (UNNotificationRequest) throws -> Void = { _ in },
        body: (AlarmService) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-alarm-notifications-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = AlarmService(
            storageURL: directory.appendingPathComponent("alarms.json"),
            notificationRequestHandler: register,
            cancelHandler: { _ in },
            notificationSettingsProvider: settings,
            notificationAuthorizationRequester: authorize
        )
        try await body(service)
    }
}

private struct NotificationFailure: LocalizedError {
    var errorDescription: String? { "notification test failure" }
}

@MainActor
private final class AlarmNotificationGate<Value: Sendable> {
    private var value: Value?
    private var continuation: CheckedContinuation<Value, Never>?

    func wait() async -> Value {
        if let value { return value }
        return await withCheckedContinuation { continuation = $0 }
    }

    func send(_ value: Value) {
        self.value = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}
