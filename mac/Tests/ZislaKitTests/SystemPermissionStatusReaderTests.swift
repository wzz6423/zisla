import AppKit
import CoreLocation
import Darwin
import Foundation
import Testing

@testable import ZislaKit

private final class PermissionLocationManager: CLLocationManager {
    var reportedStatus: CLAuthorizationStatus = .notDetermined
    override var authorizationStatus: CLAuthorizationStatus { reportedStatus }
    override func requestWhenInUseAuthorization() { Issue.record("A status read must not request access") }
    override func requestLocation() { Issue.record("A status read must not request coordinates") }
}

@MainActor
struct SystemPermissionStatusReaderTests {
    @Test
    func locationReadsUseTheLatestDelegateDecisionWithoutRequestingCoordinatesOrAccess() {
        let manager = PermissionLocationManager()
        let system = OnboardingSystemPermissions(makeLocationManager: { manager }, locationServicesEnabled: { true })
        let decisions: [(CLAuthorizationStatus, OnboardingPermissionStatus)] = [
            (.authorizedAlways, .granted), (.denied, .denied), (.restricted, .restricted), (.notDetermined, .notDetermined),
        ]
        for (native, expected) in decisions {
            var state: OnboardingPermissionStatus?
            system.read(.location) { state = $0 }
            #expect(state == nil)
            manager.reportedStatus = native
            manager.delegate?.locationManagerDidChangeAuthorization?(manager)
            #expect(state == expected)
        }
    }

    @Test
    func aNewLocationReadSupersedesAnOlderOneAndSurvivesUnrelatedRequestCleanup() {
        let old = PermissionLocationManager()
        let current = PermissionLocationManager()
        var nextManager = old
        let system = OnboardingSystemPermissions(makeLocationManager: { nextManager }, locationServicesEnabled: { false })
        var state: OnboardingPermissionStatus?
        system.read(.location) { _ in Issue.record("The superseded read delivered a stale decision") }
        nextManager = current
        system.read(.location) { state = $0 }
        system.cancel()
        old.reportedStatus = .authorizedAlways
        system.locationManagerDidChangeAuthorization(old)
        #expect(state == nil)
        current.reportedStatus = .denied
        current.delegate?.locationManagerDidChangeAuthorization?(current)
        #expect(state == .unavailable)
    }

    @Test(
        arguments: [OnboardingPermissionID.systemAudio, .automation, .files, .fullDiskAccess],
        [OnboardingPermissionStatus.granted, .denied, .unknown, .partiallyGranted]
    )
    func manualPermissionsReachTheActualSystemReader(id: OnboardingPermissionID, expected: OnboardingPermissionStatus) async {
        let system = OnboardingSystemPermissions(manualStatus: { _ in expected })
        defer { system.cancel() }
        let status = await withCheckedContinuation { continuation in
            system.read(id) { continuation.resume(returning: $0) }
        }
        #expect(status == expected, "The permission page must reflect the actual system permission")
    }

    @Test(arguments: [OnboardingPermissionID.systemAudio, .automation, .files, .fullDiskAccess])
    func initialManualPermissionStatusDoesNotInventADenial(id: OnboardingPermissionID) {
        let fake = OnboardingPermissionCoordinator(dependencies: .init(
            read: { _, _ in }, request: { _, _ in Issue.record("Unexpected authorization request") },
            cancel: {}, openSettings: { _ in true }
        ))
        defer { fake.close() }
        #expect(fake.permissions.first(where: { $0.id == id })?.status == .unknown)
        #expect(!fake.request(id))
    }

    @Test
    func systemChecksRunOffTheMainThread() async {
        let system = OnboardingSystemPermissions(manualStatus: { _ in
            #expect(!Thread.isMainThread, "System permission IPC must not block the settings window")
            return .granted
        })
        defer { system.cancel() }
        await withCheckedContinuation { continuation in
            system.read(.fullDiskAccess) { _ in continuation.resume() }
        }
    }

    @Test
    func audioPermissionUsesItsOwnServiceAndCannotBeGrantedByScreenRecording() {
        let reader = SystemPermissionStatusReader(
            preflight: { service in service == "kTCCServiceScreenCapture" ? 0 : 1 },
            automation: { _, _ in Issue.record("Unexpected automation query"); return -1 },
            runningApplications: { Issue.record("Unexpected application query"); return [] },
            fullDiskAccess: { Issue.record("Unexpected file access"); return .granted }
        )
        #expect(reader.read(.systemAudio) == .denied)
    }

    @Test(arguments: [Int?(0), 1, 2, 3, -1, nil])
    func audioPermissionKeepsUnknownNativeResultsUnknown(result: Int?) {
        let reader = SystemPermissionStatusReader(preflight: { _ in result })
        let expected: OnboardingPermissionStatus = result == 0 ? .granted : result == 1 ? .denied : .unknown
        #expect(reader.read(.systemAudio) == expected)
    }

    @Test(arguments: [Int32(noErr), Int32(errAEEventNotPermitted), Int32(errAEEventWouldRequireUserConsent), -600, -1])
    func automationChecksNeverPromptOrQueryClosedAndUnrelatedApplications(result: OSStatus) {
        let reader = SystemPermissionStatusReader(
            preflight: { _ in Issue.record("Unexpected TCC query"); return nil },
            automation: { identifier, askUser in
                #expect(identifier == "com.apple.Music")
                #expect(!askUser, "Refreshing permissions must not ask the user for access")
                return result
            },
            runningApplications: { ["com.apple.Music", "com.example.Unrelated"] },
            fullDiskAccess: { Issue.record("Unexpected file access"); return .granted }
        )
        let expected: OnboardingPermissionStatus = result == noErr ? .granted
            : result == errAEEventNotPermitted ? .denied : .unknown
        #expect(reader.read(.automation) == expected)
    }

    @Test
    func automationWithNoRunningTargetIsUnknown() {
        let reader = SystemPermissionStatusReader(
            automation: { _, _ in Issue.record("Closed applications must not be queried"); return noErr },
            runningApplications: { [] }
        )
        #expect(reader.read(.automation) == .unknown)
    }

    @Test
    func mixedAutomationGrantsAreNotReportedAsAnOverallDenialOrFullGrant() {
        let reader = SystemPermissionStatusReader(
            automation: { identifier, _ in identifier == "com.apple.Music" ? noErr : OSStatus(errAEEventNotPermitted) },
            runningApplications: { ["com.apple.Music", "com.spotify.client"] }
        )
        #expect(reader.read(.automation) == .partiallyGranted)
    }

    @Test(arguments: [Int?(0), 1, 2, nil])
    func folderPermissionStatesMatchKnownAndUnknownSystemResults(result: Int?) {
        let reader = SystemPermissionStatusReader(
            preflight: { $0 == "kTCCServiceSystemPolicyAllFiles" ? 1 : result },
            fullDiskAccess: { .denied }
        )
        let expected: OnboardingPermissionStatus = result == 0 ? .granted : result == 1 ? .denied : .unknown
        #expect(reader.read(.files) == expected)
    }

    @Test(arguments: [Int?(1), 2, nil])
    func oneAllowedFolderDoesNotPretendAllFoldersAreAllowed(other: Int?) {
        let reader = SystemPermissionStatusReader(
            preflight: { $0 == "kTCCServiceSystemPolicyDownloadsFolder" ? 0 : other }, fullDiskAccess: { .denied }
        )
        #expect(reader.read(.files) == .partiallyGranted)
    }

    @Test
    func unknownFolderStatesCannotBeInventedAsADenial() {
        let reader = SystemPermissionStatusReader(
            preflight: { $0 == "kTCCServiceSystemPolicyDownloadsFolder" ? 1 : 2 }, fullDiskAccess: { .unknown }
        )
        #expect(reader.read(.files) == .unknown)
    }

    @Test
    func confirmedFullDiskGrantCoversBothRowsWithoutOpeningPrivateFiles() {
        let reader = SystemPermissionStatusReader(
            preflight: { service in
                #expect(service == "kTCCServiceSystemPolicyAllFiles")
                return 0
            },
            fullDiskAccess: { Issue.record("A confirmed grant needs no file probe"); return .unknown }
        )
        #expect(reader.read(.fullDiskAccess) == .granted)
        #expect(reader.read(.files) == .granted)
    }

    @Test
    func revokedFullDiskAccessKeepsIndependentFolderGrants() {
        let reader = SystemPermissionStatusReader(
            preflight: { $0 == "kTCCServiceSystemPolicyDownloadsFolder" ? 0 : 1 },
            fullDiskAccess: { .granted }
        )
        #expect(reader.read(.fullDiskAccess) == .denied)
        #expect(reader.read(.files) == .partiallyGranted)
    }

    @Test(arguments: [Int?(2), nil])
    func fullDiskAccessAlsoGrantsFilesWithoutReadingFolderContents(inconclusive: Int?) {
        let reader = SystemPermissionStatusReader(
            preflight: { service in
                #expect(service == "kTCCServiceSystemPolicyAllFiles")
                return inconclusive
            },
            fullDiskAccess: { .granted }
        )
        #expect(reader.read(.files) == .granted)
        #expect(reader.read(.fullDiskAccess) == .granted)
    }

    @Test
    func missingUserDatabaseFallsBackToTheProtectedSystemDatabase() {
        let systemPath = "/Library/Application Support/com.apple.TCC/TCC.db"
        var closed: [Int32] = []
        let status = SystemPermissionStatusReader.fullDiskAccessStatus(
            openFile: { path, _ in path == systemPath ? 42 : -1 },
            errorCode: { ENOENT }, closeFile: { closed.append($0) }
        )
        #expect(status == .granted)
        #expect(closed == [42])
    }

    @Test(arguments: [Int32(0), 42])
    func fullDiskAccessProbeClosesItsReadOnlyDescriptorWithoutReading(descriptor: Int32) {
        var closed: [Int32] = []
        let status = SystemPermissionStatusReader.fullDiskAccessStatus(
            paths: ["/fake/permission-canary"],
            openFile: { path, flags in
                #expect(path == "/fake/permission-canary")
                #expect(flags == O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
                return descriptor
            },
            errorCode: { Issue.record("Successful open must not use stale errno"); return EPERM },
            closeFile: { closed.append($0) }
        )
        #expect(status == .granted)
        #expect(closed == [descriptor])
    }

    @Test(arguments: [EACCES, EPERM, ENOENT, EIO, EMFILE, ELOOP])
    func fullDiskAccessProbeDistinguishesDenialFromMissingFilesAndSystemFailures(error: Int32) {
        var closed: [Int32] = []
        let status = SystemPermissionStatusReader.fullDiskAccessStatus(
            paths: ["/fake/permission-canary"], openFile: { _, _ in -1 }, errorCode: { error },
            closeFile: { closed.append($0) }
        )
        #expect(status == (error == EACCES || error == EPERM ? .denied : .unknown))
        #expect(closed.isEmpty, "A failed probe must not close another resource")
    }

    @Test
    func missingPrivateFrameworkOrSymbolIsUnavailableWithoutRequestingAccess() {
        #expect(TCCPermissionPreflight.load(path: "/does/not/exist/TCC") == nil)
        #expect(TCCPermissionPreflight.load(path: "/usr/lib/libSystem.B.dylib", symbol: "ZislaMissingPermissionSymbol") == nil)
    }

    @Test
    func anIsolatedCanaryIsNotReadModifiedCreatedOrFollowedThroughASymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("canary")
        let bytes = Data("private-fixture-content".utf8)
        try bytes.write(to: file)
        #expect(SystemPermissionStatusReader.fullDiskAccessStatus(paths: [file.path]) == .granted)
        #expect(try Data(contentsOf: file) == bytes)
        let missing = root.appendingPathComponent("missing")
        #expect(SystemPermissionStatusReader.fullDiskAccessStatus(paths: [missing.path]) == .unknown)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(SystemPermissionStatusReader.fullDiskAccessStatus(paths: [link.path]) == .unknown)
        #expect(try Data(contentsOf: file) == bytes)
    }
}
