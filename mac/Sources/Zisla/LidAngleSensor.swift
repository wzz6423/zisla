import Foundation
import IOKit
import IOKit.hid

/// Reads the hinge angle exposed by compatible MacBook orientation sensors.
///
/// `AppleSPUHIDDevice` devices expose either report 7 (hundredths of a degree)
/// or report 1 (whole degrees). The sensor is not present on every MacBook,
/// so callers must treat `angle()` as optional.
///
/// Adapted for Zisla from Mac Duo's Apache-2.0 `LidAngleKit` reader.
final class LidAngleSensor {
    private enum Resolution {
        case hundredthsOfADegree
        case wholeDegrees

        var reportID: Int {
            switch self {
            case .hundredthsOfADegree: 7
            case .wholeDegrees: 1
            }
        }
    }

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var resolution: Resolution?
    private var buffer = [UInt8](repeating: 0, count: 32)

    var isAvailable: Bool {
        device != nil && resolution != nil
    }

    init() {
        open()
    }

    deinit {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    /// Returns the lid angle in degrees. Zero is closed; an opened MacBook is
    /// typically between 100 and 140 degrees.
    func angle() -> Double? {
        guard let resolution, let bytes = read(reportID: resolution.reportID) else {
            return nil
        }

        let degrees: Double
        switch resolution {
        case .hundredthsOfADegree:
            guard bytes.count >= 5 else { return nil }
            let raw = UInt32(bytes[1])
                | UInt32(bytes[2]) << 8
                | UInt32(bytes[3]) << 16
                | UInt32(bytes[4]) << 24
            degrees = Double(raw) / 100
        case .wholeDegrees:
            guard bytes.count >= 3 else { return nil }
            degrees = Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
        }

        return (0...360).contains(degrees) ? degrees : nil
    }

    private func open() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return
        }
        self.manager = manager

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return
        }
        for candidate in devices {
            device = candidate
            if let bytes = read(reportID: 7), bytes.count >= 5 {
                resolution = .hundredthsOfADegree
                return
            }
            if let bytes = read(reportID: 1), bytes.count >= 3 {
                resolution = .wholeDegrees
                return
            }
        }
        device = nil
    }

    private func read(reportID: Int) -> [UInt8]? {
        guard let device else { return nil }
        var length = CFIndex(buffer.count)
        let result = buffer.withUnsafeMutableBufferPointer { pointer -> IOReturn in
            guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeFeature,
                CFIndex(reportID),
                baseAddress,
                &length
            )
        }
        guard result == kIOReturnSuccess, length > 0 else { return nil }
        return Array(buffer.prefix(Int(length)))
    }
}
