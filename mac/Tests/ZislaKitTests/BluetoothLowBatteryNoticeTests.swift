import Combine
import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
struct BluetoothLowBatteryNoticeTests {
    @Test(arguments: [
        (id: "battery-low", expected: true),
        (id: "battery-low:bluetooth:keyboard", expected: true),
        (id: "battery-lowest", expected: false),
        (id: "battery-low-other", expected: false),
    ])
    func onlyBatteryWarningIDsUseTheCompactBatteryPresentation(sample: (id: String, expected: Bool)) {
        #expect(LowBatteryNoticeController.isLowBatteryNotice(
            IslandNotice(id: sample.id, title: "Test")
        ) == sample.expected)
    }

    @Test(arguments: [0.0, 0.05, 0.19, 0.2, 0.201, 1.0])
    func readableDevicesWarnAtOrBelowTwentyPercent(level: Double) throws {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let device = device(level)
        LowBatteryNoticeController(queue: queue).update(devices: [device], enabled: true)

        if level > 0.2 {
            #expect(queue.left.isEmpty)
            return
        }
        let notice = try #require(queue.left.first)
        #expect(queue.left.count == 1)
        #expect(queue.right.isEmpty)
        #expect(notice.id == "battery-low:bluetooth:keyboard")
        #expect(notice.title == "电池电量低")
        #expect(notice.detail == "\(device.batteryPercentInt)%")
        #expect(notice.batteryLevels == [NoticeBatteryLevel(label: device.name, level: device.batteryPercentInt)])
        #expect(notice.kind == .warning)
        #expect(notice.style == .status)
    }

    @Test(arguments: [BatteryLevelComponent.Kind.left, .right, .caseBattery])
    func lowComponentWarnsEvenWhenTheMainReadingIsHealthy(kind: BatteryLevelComponent.Kind) {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var device = device(0.8)
        device.deviceType = .airPods
        device.components = [BatteryLevelComponent(kind: kind, level: 0.2)]
        let controller = LowBatteryNoticeController(queue: queue)
        controller.update(devices: [device], enabled: true)
        #expect(queue.left.first?.detail == "20%")

        device.batteryLevel = 0.1
        device.components[0].level = 0.9
        controller.update(devices: [device], enabled: true)
        #expect(queue.left.first?.detail == "10%")
    }

    @Test
    func devicesWithTheSameNameHaveIndependentWarningsAndRecovery() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let controller = LowBatteryNoticeController(queue: queue)
        var first = device(0.2)
        var second = device(0.8, identifier: "bluetooth:second-keyboard")
        controller.update(devices: [first, second], enabled: true)
        #expect(queue.left.map(\.id) == ["battery-low:bluetooth:keyboard"])
        queue.removeAll()

        second.batteryLevel = 0.1
        controller.update(devices: [first, second], enabled: true)
        #expect(queue.left.map(\.id) == ["battery-low:bluetooth:second-keyboard"])

        first.batteryLevel = 0.21
        controller.update(devices: [first, second], enabled: true)
        first.batteryLevel = 0.19
        controller.update(devices: [first, second], enabled: true)
        #expect(Set(queue.left.map(\.id)) == [
            "battery-low:bluetooth:keyboard", "battery-low:bluetooth:second-keyboard",
        ])
    }

    @Test
    func nonBluetoothDevicesDoNotConsumeTheFirstBluetoothWarning() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let controller = LowBatteryNoticeController(queue: queue)
        var device = device(0.1)
        device.source = .iDevice
        controller.update(devices: [device], enabled: true)
        #expect(queue.left.isEmpty)

        device.source = .bluetooth
        controller.update(devices: [device], enabled: true)
        #expect(queue.left.first?.detail == "10%")
    }

    @Test(arguments: [false, true])
    func disabledOrChargingReadingsDoNotConsumeOrRepeatAnAlert(charging: Bool) {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let controller = LowBatteryNoticeController(queue: queue)
        var device = device(0.2)
        device.isCharging = charging
        controller.update(devices: [device], enabled: charging)
        #expect(queue.left.isEmpty)

        device.isCharging = false
        controller.update(devices: [device], enabled: true)
        #expect(queue.left.count == 1)
        device.isCharging = charging
        controller.update(devices: [device], enabled: charging)
        #expect(queue.left.isEmpty)
        device.isCharging = false
        controller.update(devices: [device], enabled: true)
        #expect(queue.left.isEmpty)

        device.batteryLevel = 0.5
        device.isCharging = charging
        controller.update(devices: [device], enabled: charging)
        device.batteryLevel = 0.2
        device.isCharging = false
        controller.update(devices: [device], enabled: true)
        #expect(queue.left.first?.detail == "20%")
    }

    @Test
    func missingDevicesClearOnlyTheirWarningsAndDoNotRearm() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let ordinary = IslandNotice(id: "ordinary", title: "Other event", side: .left)
        queue.enqueue(ordinary, expiresAfter: nil)
        let controller = LowBatteryNoticeController(queue: queue)
        controller.update(snapshot: BatterySnapshot(
            level: 0.1, isCharging: false, isPluggedIn: false,
            isCharged: false, timeRemainingMinutes: nil
        ), enabled: true)
        controller.update(devices: [device(0.2)], enabled: true)
        #expect(queue.left.count == 3)

        controller.update(devices: [], enabled: true)
        #expect(queue.left.map(\.id) == [ordinary.id, LowBatteryNoticeController.noticeID])
        controller.update(devices: [device(0.19)], enabled: true)
        #expect(queue.left.map(\.id) == [ordinary.id, LowBatteryNoticeController.noticeID])
    }

    @Test
    func invalidReadingsDoNotCreateOrRearmWarnings() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        let controller = LowBatteryNoticeController(queue: queue)
        let invalid = [Double.nan, Double.infinity, -Double.infinity, -0.1, 1.1]
        for level in invalid {
            controller.update(devices: [device(level)], enabled: true)
            #expect(queue.left.isEmpty)
        }
        controller.update(devices: [device(0.1)], enabled: true)
        #expect(queue.left.count == 1)
        for level in invalid {
            controller.update(devices: [device(level)], enabled: true)
            #expect(queue.left.isEmpty)
            controller.update(devices: [device(0.1)], enabled: true)
            #expect(queue.left.isEmpty)
        }
    }

    @Test
    func validComponentRemainsUsableWhenOtherReadingsAreInvalid() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        var device = device(.nan)
        var invalidComponent = BatteryLevelComponent(kind: .right, level: 0.5)
        invalidComponent.level = .nan
        device.components = [
            invalidComponent,
            BatteryLevelComponent(kind: .left, level: 0.2),
        ]
        LowBatteryNoticeController(queue: queue).update(devices: [device], enabled: true)
        #expect(queue.left.first?.detail == "20%")
    }

    @Test
    func duplicateReadingsKeepTheOriginalExpiryAndDoNotReappear() async throws {
        let (scheduled, scheduledContinuation) = AsyncStream<Duration>.makeStream()
        let (expiry, expiryContinuation) = AsyncStream<Void>.makeStream()
        let queue = SideNoticeQueue(capacityPerSide: 3, expirySleeper: { duration in
            scheduledContinuation.yield(duration)
            var iterator = expiry.makeAsyncIterator()
            _ = await iterator.next()
        })
        defer {
            queue.removeAll()
            scheduledContinuation.finish()
            expiryContinuation.finish()
        }
        let controller = LowBatteryNoticeController(queue: queue)
        let began = Date(timeIntervalSince1970: 1_000)
        controller.update(devices: [device(0.2)], enabled: true, at: began)
        try #require(queue.left.first != nil)
        var scheduledIterator = scheduled.makeAsyncIterator()
        #expect(await scheduledIterator.next() == .seconds(6))

        controller.update(devices: [device(0.18)], enabled: true, at: began.addingTimeInterval(3))
        #expect(queue.left.count == 1)
        #expect(queue.left.first?.detail == "18%")
        #expect(queue.left.first?.batteryLevels?.first?.level == 18)
        #expect(queue.left.first?.createdAt == began)

        expiryContinuation.yield(())
        for await notices in queue.$left.values {
            if notices.isEmpty { break }
        }
        controller.update(devices: [device(0.17)], enabled: true)
        #expect(queue.left.isEmpty)
    }

    @Test
    func bluetoothWarningsUseCompactPriorityWithoutEvictingOrdinaryNotices() throws {
        let queue = SideNoticeQueue(capacityPerSide: 1)
        defer { queue.removeAll() }
        let ordinary = IslandNotice(id: "ordinary", title: "Other event", side: .left)
        queue.enqueue(ordinary, expiresAfter: nil)
        LowBatteryNoticeController(queue: queue).update(devices: [device(0.2)], enabled: true)
        #expect(queue.left.count == 2)
        var settings = FeatureSettings.default
        settings.compactStatusPriority = [.media, .transient]
        let media = IslandNotice(id: "media-active-left", title: "Music", side: .left)
        #expect(SideNoticeLayoutEngine.selectedCompactStatusPriority(
            for: [media] + queue.left, settings: settings
        ) == .transient)
        #expect(SideNoticeLayoutEngine().presentation(for: queue.left).ordinaryNotices == [ordinary])

        let physical = ScreenSnapshot(
            displayID: 42,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
            safeAreaInsets: ScreenInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
            auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
        )
        let frame = try #require(SideNoticeLayoutEngine().compactBarFrame(
            for: physical, notices: queue.left, settings: settings
        ))
        #expect(frame.width == 380)
    }

    @Test
    func monitorPublishesWarningsWithoutALocalBatteryOrAnOpenDetailView() async {
        let queue = SideNoticeQueue()
        let controller = LowBatteryNoticeController(queue: queue)
        let reading = device(0.2)
        let monitor = NetworkBatteryMonitor(accessoryReader: { [reading] })
        let subscription = monitor.$devices.sink { devices in
            controller.update(devices: devices, enabled: true)
        }
        defer {
            subscription.cancel()
            monitor.stop()
            queue.removeAll()
        }

        monitor.start()
        for await devices in monitor.$devices.values {
            if !devices.isEmpty { break }
        }
        #expect(queue.left.first?.detail == "20%")
    }

    private func device(_ level: Double, identifier: String = "bluetooth:keyboard") -> NetworkBatteryDevice {
        var device = NetworkBatteryDevice(
            identifier: identifier,
            name: "Magic Keyboard",
            deviceType: .keyboard,
            batteryLevel: 0.5,
            isCharging: false,
            lastSeen: Date(timeIntervalSince1970: 1_000)
        )
        device.batteryLevel = level
        return device
    }
}
