import AppKit
import ApplicationServices
import Darwin
import Foundation

struct SystemPermissionStatusReader: Sendable {
    private let preflight: @Sendable (String) -> Int?
    private let automation: @Sendable (String, Bool) -> OSStatus
    private let runningApplications: @Sendable () -> Set<String>
    private let fullDiskAccess: @Sendable () -> OnboardingPermissionStatus

    init(
        preflight: @escaping @Sendable (String) -> Int? = TCCPermissionPreflight.read,
        automation: @escaping @Sendable (String, Bool) -> OSStatus = Self.automationPermission,
        runningApplications: @escaping @Sendable () -> Set<String> = {
            Set(Self.automationTargets.filter {
                !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
            })
        },
        fullDiskAccess: @escaping @Sendable () -> OnboardingPermissionStatus = { Self.fullDiskAccessStatus() }
    ) {
        self.preflight = preflight
        self.automation = automation
        self.runningApplications = runningApplications
        self.fullDiskAccess = fullDiskAccess
    }

    func read(_ id: OnboardingPermissionID) -> OnboardingPermissionStatus {
        switch id {
        case .systemAudio:
            return Self.preflightStatus(preflight("kTCCServiceAudioCapture"))
        case .automation:
            let running = runningApplications()
            return Self.combinedStatus(Self.automationTargets.filter { running.contains($0) }.map {
                switch automation($0, false) {
                case noErr: return .granted
                case OSStatus(errAEEventNotPermitted): return .denied
                default: return .unknown
                }
            })
        case .files:
            if fullDiskAccess() == .granted { return .granted }
            return Self.combinedStatus(Self.fileServices.map { Self.preflightStatus(preflight($0)) })
        case .fullDiskAccess:
            return fullDiskAccess()
        default:
            return .unknown
        }
    }

    private static let automationTargets = [
        "com.apple.Music", "com.spotify.client", "com.apple.finder", "com.apple.Notes",
        "com.apple.mail", "com.apple.Terminal", "com.googlecode.iterm2",
    ]
    static let fileServices = [
        "kTCCServiceSystemPolicyDesktopFolder", "kTCCServiceSystemPolicyDocumentsFolder",
        "kTCCServiceSystemPolicyDownloadsFolder", "kTCCServiceSystemPolicyNetworkVolumes",
        "kTCCServiceSystemPolicyRemovableVolumes",
    ]

    private static func preflightStatus(_ result: Int?) -> OnboardingPermissionStatus {
        switch result {
        case 0: .granted
        case 1: .denied
        default: .unknown
        }
    }

    private static func combinedStatus(_ statuses: [OnboardingPermissionStatus]) -> OnboardingPermissionStatus {
        guard !statuses.isEmpty else { return .unknown }
        if statuses.allSatisfy({ $0 == .granted }) { return .granted }
        if statuses.contains(.granted) { return .partiallyGranted }
        if statuses.contains(.unknown) { return .unknown }
        return .denied
    }

    private static func automationPermission(_ identifier: String, askUser: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: identifier)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, askUser)
    }

    static func fullDiskAccessStatus(
        path: String = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path,
        openFile: (String, Int32) -> Int32 = { Darwin.open($0, $1) },
        errorCode: () -> Int32 = { errno },
        closeFile: (Int32) -> Void = { _ = Darwin.close($0) }
    ) -> OnboardingPermissionStatus {
        // Open and immediately close a protected canary; never inspect the user's permission records.
        let descriptor = openFile(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if descriptor >= 0 {
            closeFile(descriptor)
            return .granted
        }
        let error = errorCode()
        return error == EACCES || error == EPERM ? .denied : .unknown
    }
}

enum TCCPermissionPreflight {
    typealias Function = @convention(c) (CFString, CFDictionary?) -> Int
    private static let function = load()

    static func read(_ service: String) -> Int? {
        function?(service as CFString, nil)
    }

    static func load(
        path: String = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC",
        symbol: String = "TCCAccessPreflight"
    ) -> Function? {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { return nil }
        guard let address = dlsym(handle, symbol) else { dlclose(handle); return nil }
        return unsafeBitCast(address, to: Function.self)
    }
}
