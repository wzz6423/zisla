import Darwin
import Foundation
import Testing
@testable import ZislaKit

struct ApplicationOpenRepairServiceTests {
    @Test
    func unsignedAppRemovesOnlyQuarantineAndOpens() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let marker = Data("preserve".utf8)
        try Self.setAttribute("dev.zisla.tests", value: marker, at: fixture.app)
        let runner = Runner()
        let before = try Data(contentsOf: fixture.executable)

        try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)

        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) == nil)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.executable) == nil)
        #expect(Self.attribute("dev.zisla.tests", at: fixture.app) == marker)
        #expect(try Data(contentsOf: fixture.executable) == before)
        #expect(await runner.openedPaths == [try Self.physicalPath(fixture.app)])
    }

    @Test
    func validDeveloperSignatureIsNeverReplaced() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(signature: .valid)
        try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        #expect(await runner.openedPaths.count == 1)
        #expect(await runner.signingArguments.allSatisfy { !$0.contains("--sign") && !$0.contains("--force") })
    }

    @Test(arguments: [Int32(0), 3])
    func validSignatureAllowsAcceptedOrUnexplainedAssessment(status: Int32) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(signature: .valid, assessment: "rejected", assessmentStatus: status)
        try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) == nil)
        #expect(await runner.openedPaths.count == 1)
        #expect(await runner.commands.allSatisfy { $0.0 != "/usr/bin/syspolicy_check" })
    }

    @Test
    func adhocSignatureRequiresTheKnownDistributionReport() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(signature: .adhoc, assessment: "rejected")
        try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) == nil)
        #expect(await runner.openedPaths.count == 1)
        #expect(await runner.signingArguments.allSatisfy { !$0.contains("--sign") })
    }

    @Test(arguments: [
        output(status: 0), output(status: 70, data: Data("{}".utf8)),
        output(status: 70, data: Data(#"{"output":[],"output":[]}"#.utf8)),
        output(status: 70, data: Data(#"{"output":[]}"#.utf8), timedOut: true),
    ])
    func inconsistentDistributionCannotRemoveQuarantine(output: AIAgentProcessOutput) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(signature: .adhoc, assessment: "rejected", distributionOverride: output)
        await #expect(throws: ApplicationOpenRepairError.assessmentUnavailable) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test(arguments: [
        (Int32(3), "rejected"), (Int32(1), "internal error in code signing subsystem"),
        (Int32(1), "code has no resources but signature indicates they must be present"),
    ])
    func incompleteLinkerSignatureCanKeepItsVerifiedExecutable(assessment: (Int32, String)) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(signature: .incompleteAdhoc, assessment: assessment.1, assessmentStatus: assessment.0)
        try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) == nil)
        #expect(await runner.openedPaths.count == 1)
        #expect(await runner.signingArguments.allSatisfy { !$0.contains("--sign") })
    }

    @Test(arguments: [
        output(status: 1, error: "invalid executable"), output(timedOut: true),
    ])
    func invalidLinkerExecutableCannotUseQuarantineOnlyRepair(output: AIAgentProcessOutput) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(signature: .incompleteAdhoc, assessment: "rejected", executableVerificationOverride: output)
        await #expect(throws: ApplicationOpenRepairError.signatureInvalid) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test(arguments: [Runner.Signature.unsigned, .adhoc, .incompleteAdhoc, .valid])
    private func explicitSecurityFindingBlocksEverySignature(signature: Runner.Signature) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(signature: signature, assessment: "rejected\nsource=malware")
        await #expect(throws: ApplicationOpenRepairError.assessmentRejected) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test(arguments: [
        "Signature=adhoc", "Info.plist=not bound", "Sealed Resources=none", "Internal requirements=none",
        "CodeDirectory v=20400 flags=0x20002(adhoc,linker-signed)",
    ])
    func incompleteLinkerSignatureRequiresEveryKnownField(field: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let display = Self.linkerDisplay.replacingOccurrences(of: field, with: "unsupported")
        let runner = Runner(signature: .incompleteAdhoc, displayOverride: Self.output(error: display))
        await #expect(throws: ApplicationOpenRepairError.signatureInvalid) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test(arguments: [
        output(status: 1, error: "unrecognized signature"), output(timedOut: true),
    ])
    func unknownOrTimedOutSignatureCannotRepair(output: AIAgentProcessOutput) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(displayOverride: output)
        let expected = output.didTimeout ? ApplicationOpenRepairError.assessmentUnavailable : .signatureInvalid
        await #expect(throws: expected) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test
    func strictSignatureVerificationTimeoutKeepsQuarantine() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(signature: .valid, verificationOverride: Self.output(timedOut: true))
        await #expect(throws: ApplicationOpenRepairError.assessmentUnavailable) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test
    func invalidSignatureStopsBeforeAnyWriteOrOpen() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(signature: .invalid)
        await #expect(throws: ApplicationOpenRepairError.signatureInvalid) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.executable) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test(arguments: ["rejected\nsource=malware", "rejected\norigin=certificate revoked", "rejected\nXProtect finding", "rejected"])
    func rejectedSecurityAssessmentStopsWithoutWriting(diagnostic: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(assessment: diagnostic)
        await #expect(throws: ApplicationOpenRepairError.assessmentRejected) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test
    func assessmentTimeoutKeepsQuarantineAndCanRecover() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(timedOut: true)
        await #expect(throws: ApplicationOpenRepairError.assessmentUnavailable) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        await runner.setTimeout(false)
        try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        #expect(await runner.openedPaths.count == 1)
    }

    @Test
    func executableChangeDuringAssessmentStopsBeforeRemoval() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(changeDuringAssessment: fixture.executable)
        await #expect(throws: ApplicationOpenRepairError.applicationChanged) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test
    func snapshotDetectsChangedContentWithRestoredSizeAndDate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try ApplicationOpenRepairBundle.applicationURL(fixture.app)
        let before = try ApplicationOpenRepairBundle.capture(at: url, isCancelled: { false })
        let descriptor = open(fixture.executable.path, O_WRONLY | O_CLOEXEC)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        var status = stat()
        try #require(fstat(descriptor, &status) == 0)
        let size = try Data(contentsOf: fixture.executable).count
        let replacement = Data(repeating: 0x41, count: size)
        try #require(replacement.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, $0.count, 0) } == size)
        // Date round trips lose nanoseconds and can hide a missing content comparison.
        var times = [status.st_atimespec, status.st_mtimespec]
        try #require(futimens(descriptor, &times) == 0)
        let after = try ApplicationOpenRepairBundle.capture(at: url, isCancelled: { false })
        #expect(!before.matches(after))
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
    }

    @Test
    func extraBundleEntryInvalidatesTheSnapshot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try ApplicationOpenRepairBundle.applicationURL(fixture.app)
        let before = try ApplicationOpenRepairBundle.capture(at: url, isCancelled: { false })
        let date = try #require(FileManager.default.attributesOfItem(atPath: fixture.app.path)[.modificationDate])
        try Data().write(to: fixture.app.appendingPathComponent("zzz"))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fixture.app.path)
        let after = try ApplicationOpenRepairBundle.capture(at: url, isCancelled: { false })
        #expect(!before.matches(after))
    }

    @Test
    func permissionFailureDoesNotOpenAndRetryCompletes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner()
        let service = ApplicationOpenRepairService(runCommand: runner.run, removeQuarantine: { _ in
            throw ApplicationOpenRepairError.quarantineRemovalFailed
        })
        await #expect(throws: ApplicationOpenRepairError.quarantineRemovalFailed) {
            try await service.repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
        try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        #expect(await runner.openedPaths.count == 1)
    }

    @Test
    func failedRemovalVerificationCannotOpen() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner()
        await #expect(throws: ApplicationOpenRepairError.quarantineRemovalFailed) {
            try await ApplicationOpenRepairService(runCommand: runner.run, removeQuarantine: { _ in })
                .repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test
    func partialRemovalFailureDoesNotClaimOpenAndCanRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner()
        let remover = PartialRemover()
        await #expect(throws: ApplicationOpenRepairError.quarantineRemovalFailed) {
            try await ApplicationOpenRepairService(runCommand: runner.run, removeQuarantine: remover.remove)
                .repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) == nil)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.executable) != nil)
        #expect(await runner.openedPaths.isEmpty)
        try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.executable) == nil)
        #expect(await runner.openedPaths.count == 1)
    }

    @Test
    func changeOutsideQuarantineDuringRemovalFailsFinalVerification() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner()
        await #expect(throws: ApplicationOpenRepairError.applicationChanged) {
            try await ApplicationOpenRepairService(runCommand: runner.run, removeQuarantine: { descriptor in
                #expect(fremovexattr(descriptor, "com.apple.quarantine", 0) == 0)
                try Self.setAttribute("dev.zisla.changed", value: Data("changed".utf8), at: fixture.app)
            }).repairAndOpen(at: fixture.app)
        }
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test
    func macOSProvenanceChangesDoNotBlockQuarantineOnlyRepair() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner()
        try await ApplicationOpenRepairService(runCommand: runner.run, removeQuarantine: { descriptor in
            #expect(fremovexattr(descriptor, "com.apple.quarantine", 0) == 0)
            try Self.setAttribute("com.apple.provenance", value: Data("system provenance".utf8), at: fixture.app)
        }).repairAndOpen(at: fixture.app)
        #expect(Self.attribute("com.apple.provenance", at: fixture.app) == Data("system provenance".utf8))
        #expect(Self.attribute("com.apple.quarantine", at: fixture.executable) == nil)
        #expect(await runner.openedPaths.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringAttributeRemovalStopsTheWorkerBeforeOpening() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        let proceed = DispatchSemaphore(value: 0)
        let service = ApplicationOpenRepairService(runCommand: runner.run, removeQuarantine: { descriptor in
            #expect(fremovexattr(descriptor, "com.apple.quarantine", 0) == 0)
            continuation.yield(())
            #expect(proceed.wait(timeout: .now() + 10) == .success)
        })
        let task = Task { try await service.repairAndOpen(at: fixture.app) }
        var events = stream.makeAsyncIterator()
        _ = await events.next()
        task.cancel()
        proceed.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) == nil)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.executable) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test
    func systemOpenFailureIsReportedAfterRepair() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runner = Runner(openFails: true)
        await #expect(throws: ApplicationOpenRepairError.openFailed) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) == nil)
    }

    @Test
    func externalSymlinkCannotModifyItsTarget() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.directory.appendingPathComponent("outside")
        try Data("unchanged".utf8).write(to: outside)
        try Self.setAttribute("com.apple.quarantine", value: Data("keep".utf8), at: outside)
        try FileManager.default.createSymbolicLink(atPath: fixture.app.appendingPathComponent("escape").path, withDestinationPath: outside.path)
        let runner = Runner()
        await #expect(throws: ApplicationOpenRepairError.unsupportedBundle) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(Self.attribute("com.apple.quarantine", at: outside) == Data("keep".utf8))
        #expect(try String(contentsOf: outside, encoding: .utf8) == "unchanged")
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
        #expect(await runner.openedPaths.isEmpty)
    }

    @Test
    func internalFrameworkSymlinkIsPreservedAndNotFollowedForWrites() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let framework = fixture.app.appendingPathComponent("Contents/Frameworks/Example.framework/Versions/A")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        let library = framework.appendingPathComponent("Example")
        try Data("library".utf8).write(to: library)
        try Self.setAttribute("com.apple.quarantine", value: Data("test".utf8), at: library)
        let link = framework.deletingLastPathComponent().appendingPathComponent("Current")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "A")
        try Self.setAttribute("com.apple.quarantine", value: Data("test-link".utf8), at: link, options: XATTR_NOFOLLOW)
        let runner = Runner(signature: .valid)
        try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "A")
        #expect(Self.attribute("com.apple.quarantine", at: link, options: XATTR_NOFOLLOW) == nil)
        #expect(Self.attribute("com.apple.quarantine", at: library) == nil)
        #expect(try String(contentsOf: library, encoding: .utf8) == "library")
    }

    @Test
    func hardLinksAndSpecialFilesAreRejectedWithoutWrites() async throws {
        for special in [false, true] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let path = fixture.app.appendingPathComponent("invalid").path
            if special { #expect(mkfifo(path, 0o600) == 0) }
            else { #expect(link(fixture.executable.path, path) == 0) }
            let runner = Runner()
            await #expect(throws: ApplicationOpenRepairError.unsupportedBundle) {
                try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
            }
            #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
            #expect(await runner.openedPaths.isEmpty)
        }
    }

    @Test
    func craftedApplicationNameRemainsAnArgumentAndCannotForgeAssessment() async throws {
        let fixture = try Fixture(name: "rejected; $(touch marker) ' malware.app")
        defer { fixture.remove() }
        let path = try Self.physicalPath(fixture.app)
        let runner = Runner(signature: .valid, prefixDiagnostics: path)
        try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        #expect(await runner.openedPaths == [path])
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("marker").path))
    }

    @Test(arguments: ["https://example.com/Example.app", "/System/Applications/Example.app", "/tmp/not-app.dmg", "/tmp/bad\nname.app"])
    func invalidTargetsNeverReachCommands(path: String) async throws {
        let runner = Runner()
        let url = path.hasPrefix("https:") ? URL(string: path)! : URL(fileURLWithPath: path)
        await #expect(throws: (any Error).self) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: url)
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test
    func installedSystemApplicationIsRejectedBeforeInspection() throws {
        #expect(throws: ApplicationOpenRepairError.protectedApplication) {
            try ApplicationOpenRepairBundle.applicationURL(URL(fileURLWithPath: "/System/Applications/TextEdit.app"))
        }
    }

    @Test
    func missingExecutableIsRejectedBeforeCommands() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.executable)
        let runner = Runner()
        await #expect(throws: ApplicationOpenRepairError.invalidApplication) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(await runner.commands.isEmpty)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
    }

    @Test(arguments: ["", ".", "..", "../Example", "bad\nname", "Missing"])
    func invalidExecutableMetadataNeverReachesCommands(name: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": name], format: .xml, options: 0)
        try plist.write(to: fixture.app.appendingPathComponent("Contents/Info.plist"))
        let runner = Runner()
        await #expect(throws: ApplicationOpenRepairError.invalidApplication) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(await runner.commands.isEmpty)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
    }

    @Test
    func oversizedPlistIsRejectedBeforeReadingItsContents() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data(repeating: 32, count: 1_024 * 1_024 + 1).write(to: fixture.app.appendingPathComponent("Contents/Info.plist"))
        let runner = Runner()
        await #expect(throws: ApplicationOpenRepairError.inspectionLimit) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(await runner.commands.isEmpty)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
    }

    @Test
    func oversizedSparseExecutableIsRejectedWithoutReadingIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try FileHandle(forWritingTo: fixture.executable)
        try file.truncate(atOffset: 16 * 1_024 * 1_024 * 1_024 + 1)
        try file.close()
        let runner = Runner()
        await #expect(throws: ApplicationOpenRepairError.inspectionLimit) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(await runner.commands.isEmpty)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
    }

    @Test(arguments: ["../outside", "cycle", ""])
    func escapedCyclicAndEmptySymlinksAreRejected(target: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(symlink(target, fixture.app.appendingPathComponent("cycle").path) == 0)
        let runner = Runner()
        await #expect(throws: ApplicationOpenRepairError.unsupportedBundle) {
            try await ApplicationOpenRepairService(runCommand: runner.run).repairAndOpen(at: fixture.app)
        }
        #expect(await runner.commands.isEmpty)
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationDuringAssessmentDoesNotRemoveQuarantine() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        defer { continuation.finish() }
        let service = ApplicationOpenRepairService(runCommand: { tool, _ in
            if tool == "/usr/bin/codesign" { return Self.output(status: 1, error: "code object is not signed at all") }
            continuation.yield(())
            try await Task.sleep(for: .seconds(600))
            return Self.output(status: 0)
        })
        let task = Task { try await service.repairAndOpen(at: fixture.app) }
        var events = stream.makeAsyncIterator()
        _ = await events.next()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Self.attribute("com.apple.quarantine", at: fixture.app) != nil)
    }

    @Test
    func distributionReportRequiresOnlyTheTwoKnownIssues() throws {
        let path = "/tmp/Example.app"
        let valid = Self.report(path: path)
        #expect(ApplicationOpenRepairService.acceptsDistributionReport(valid, path: path))
        let invalid: [Data] = [
            Data(), Data("{}".utf8), Data(valid.dropLast()),
            Self.report(path: "/tmp/Other.app"),
            Data(String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "Warning", with: "Fatal").utf8),
            Data(String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "Adhoc Signed App", with: "Malware").utf8),
            Data(#"{"output":[],"output":[]}"#.utf8),
        ]
        for data in invalid { #expect(!ApplicationOpenRepairService.acceptsDistributionReport(data, path: path)) }
        var bytes = UInt64(0x5045434b)
        for _ in 0..<128 {
            bytes = bytes &* 6_364_136_223_846_793_005 &+ 1
            let unsafePath = path + "-" + String(bytes, radix: 16)
            #expect(!ApplicationOpenRepairService.acceptsDistributionReport(Self.report(path: unsafePath), path: path))
            let mutated = Array("Adhoc Signed App".utf8)
            var name = mutated
            name[Int(bytes % UInt64(name.count))] = UInt8(33 + bytes % 94)
            let replacement = String(decoding: name, as: UTF8.self)
            let text = String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "Adhoc Signed App", with: replacement)
            #expect(ApplicationOpenRepairService.acceptsDistributionReport(Data(text.utf8), path: path) == (name == mutated))
        }
        let text = String(decoding: valid, as: UTF8.self)
        let duplicate = text.replacingOccurrences(of: "\"output\":", with: "\"output\":[],\"output\":")
        #expect(!ApplicationOpenRepairService.acceptsDistributionReport(Data(duplicate.utf8), path: path))
        let escaped = text.replacingOccurrences(of: "\"output\":", with: "\"output\":[],\"out\\u0070ut\":")
        #expect(!ApplicationOpenRepairService.acceptsDistributionReport(Data(escaped.utf8), path: path))
        for key in ["output", "out\\u0070ut"] {
            let repeated = String(text.dropLast()) + ",\"" + key + "\":[]}"
            #expect(!ApplicationOpenRepairService.acceptsDistributionReport(Data(repeated.utf8), path: path))
        }
    }

    private struct Fixture: Sendable {
        let directory: URL
        let app: URL
        let executable: URL

        init(name: String = "Example.app") throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-app-repair-\(UUID().uuidString)")
            app = directory.appendingPathComponent(name)
            executable = app.appendingPathComponent("Contents/MacOS/Example")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Example", "CFBundleIdentifier": "dev.zisla.tests.example"], format: .xml, options: 0)
            try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
            try Data("synthetic executable data".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            try ApplicationOpenRepairServiceTests.setAttribute("com.apple.quarantine", value: Data("0081;00000000;ZislaTest;".utf8), at: app)
            try ApplicationOpenRepairServiceTests.setAttribute("com.apple.quarantine", value: Data("0081;00000000;ZislaTest;".utf8), at: executable)
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    private actor Runner {
        enum Signature: Sendable { case unsigned, valid, invalid, adhoc, incompleteAdhoc }
        let signature: Signature
        let assessment: String
        var timedOut: Bool
        let changeDuringAssessment: URL?
        let openFails: Bool
        let prefixDiagnostics: String?
        let assessmentStatus: Int32
        let distributionOverride: AIAgentProcessOutput?
        let executableVerificationOverride: AIAgentProcessOutput?
        let displayOverride: AIAgentProcessOutput?
        let verificationOverride: AIAgentProcessOutput?
        private(set) var commands: [(String, [String])] = []
        var openedPaths: [String] { commands.filter { $0.0 == "/usr/bin/open" }.map { $0.1.last! } }
        var signingArguments: [[String]] { commands.filter { $0.0 == "/usr/bin/codesign" }.map(\.1) }

        init(signature: Signature = .unsigned, assessment: String = "rejected\nsource=no usable signature", timedOut: Bool = false,
             changeDuringAssessment: URL? = nil, openFails: Bool = false, prefixDiagnostics: String? = nil,
             assessmentStatus: Int32 = 3, distributionOverride: AIAgentProcessOutput? = nil,
             executableVerificationOverride: AIAgentProcessOutput? = nil,
             displayOverride: AIAgentProcessOutput? = nil, verificationOverride: AIAgentProcessOutput? = nil) {
            self.signature = signature
            self.assessment = assessment
            self.timedOut = timedOut
            self.changeDuringAssessment = changeDuringAssessment
            self.openFails = openFails
            self.prefixDiagnostics = prefixDiagnostics
            self.assessmentStatus = assessmentStatus
            self.distributionOverride = distributionOverride
            self.executableVerificationOverride = executableVerificationOverride
            self.displayOverride = displayOverride
            self.verificationOverride = verificationOverride
        }

        func setTimeout(_ value: Bool) { timedOut = value }

        func run(_ tool: String, _ arguments: [String]) async throws -> AIAgentProcessOutput {
            commands.append((tool, arguments))
            if tool == "/usr/bin/codesign" {
                if arguments.contains("--display") {
                    if let displayOverride { return displayOverride }
                    switch signature {
                    case .unsigned: return ApplicationOpenRepairServiceTests.output(status: 1, error: "code object is not signed at all")
                    case .adhoc: return ApplicationOpenRepairServiceTests.output(error: "Signature=adhoc")
                    case .incompleteAdhoc: return ApplicationOpenRepairServiceTests.output(error: ApplicationOpenRepairServiceTests.linkerDisplay)
                    case .valid, .invalid: return ApplicationOpenRepairServiceTests.output(error: "Authority=Developer ID Application")
                    }
                }
                if let verificationOverride { return verificationOverride }
                if signature == .invalid { return ApplicationOpenRepairServiceTests.output(status: 1, error: "a sealed resource is missing") }
                if signature == .incompleteAdhoc, !arguments.contains("--ignore-resources") {
                    return ApplicationOpenRepairServiceTests.output(status: 1, error: "code has no resources but signature indicates they must be present")
                }
                if arguments.contains("--ignore-resources"), let executableVerificationOverride { return executableVerificationOverride }
                return ApplicationOpenRepairServiceTests.output()
            }
            if tool == "/usr/sbin/spctl" {
                if let url = changeDuringAssessment { try Data("changed executable".utf8).write(to: url) }
                let diagnostic = prefixDiagnostics.map { $0 + ": " + assessment } ?? assessment
                return ApplicationOpenRepairServiceTests.output(status: assessmentStatus, error: diagnostic, timedOut: timedOut)
            }
            if tool == "/usr/bin/syspolicy_check" {
                if let distributionOverride { return distributionOverride }
                return ApplicationOpenRepairServiceTests.output(status: 70, data: ApplicationOpenRepairServiceTests.report(path: arguments.last!))
            }
            #expect(tool == "/usr/bin/open")
            return ApplicationOpenRepairServiceTests.output(status: openFails ? 1 : 0)
        }
    }

    private final class PartialRemover: @unchecked Sendable {
        private let lock = NSLock()
        private var removed = false
        func remove(_ descriptor: Int32) throws {
            lock.lock()
            defer { lock.unlock() }
            guard !removed else { throw ApplicationOpenRepairError.quarantineRemovalFailed }
            #expect(fremovexattr(descriptor, "com.apple.quarantine", 0) == 0)
            removed = true
        }
    }

    private static func report(path: String) -> Data {
        Data("""
        {"output":[{"SyspolicyCheckShortError":"Adhoc Signed App","SyspolicyCheckErrorLevel":"Warning","SyspolicyCheckErrorFile":"\(path)"},{"SyspolicyCheckShortError":"Notary Ticket Missing","SyspolicyCheckErrorLevel":"Fatal","SyspolicyCheckErrorFile":"\(path)"}]}
        """.utf8)
    }

    private static let linkerDisplay = "Signature=adhoc\nInfo.plist=not bound\nSealed Resources=none\nInternal requirements=none\nCodeDirectory v=20400 flags=0x20002(adhoc,linker-signed)"

    private static func output(status: Int32 = 0, data: Data = Data(), error: String = "", timedOut: Bool = false) -> AIAgentProcessOutput {
        AIAgentProcessOutput(status: status, standardOutput: data, standardError: error, didTimeout: timedOut)
    }

    private static func physicalPath(_ url: URL) throws -> String {
        let resolved = try #require(realpath(url.path, nil))
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func setAttribute(_ name: String, value: Data, at url: URL, options: Int32 = 0) throws {
        try #require(value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, $0.count, 0, options) } == 0)
    }

    private static func attribute(_ name: String, at url: URL, options: Int32 = 0) -> Data? {
        let count = getxattr(url.path, name, nil, 0, 0, options)
        guard count >= 0 else { return nil }
        var data = [UInt8](repeating: 0, count: count)
        guard getxattr(url.path, name, &data, count, 0, options) >= 0 else { return nil }
        return Data(data)
    }
}
