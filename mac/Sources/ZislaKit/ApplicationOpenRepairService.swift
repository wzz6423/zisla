import Darwin
import Foundation
import ZislaCore

public enum ApplicationOpenRepairError: Error, Equatable, LocalizedError {
    case invalidApplication, protectedApplication, readOnly, unsupportedBundle, inspectionLimit
    case readFailed, applicationChanged, signatureInvalid, assessmentRejected, assessmentUnavailable
    case quarantineRemovalFailed, openFailed

    public var localizationKey: String {
        switch self {
        case .invalidApplication: "请选择完整的本地 .app 应用"
        case .protectedApplication: "不能处理系统目录中的应用"
        case .readOnly: "请先将应用复制到应用程序或下载文件夹"
        case .unsupportedBundle: "应用包含不支持的链接或特殊文件，请重新下载完整应用"
        case .inspectionLimit: "应用超出检查范围，无法处理"
        case .readFailed: "无法读取应用，请检查文件和权限"
        case .applicationChanged: "应用在检查后发生变化，请重新复制或拖入"
        case .signatureInvalid: "应用签名校验失败，请从开发者处重新下载"
        case .assessmentRejected: "应用未通过 macOS 安全评估，已停止处理"
        case .assessmentUnavailable: "macOS 安全评估暂不可用，请稍后重试"
        case .quarantineRemovalFailed: "无法移除隔离标记，请检查写入权限"
        case .openFailed: "系统未接受打开应用的请求"
        }
    }

    public var errorDescription: String? { AppLocalization.text(localizationKey) }
}

// Swift adaptation of Peck's default quarantine-only flow; developer signatures are preserved.
public struct ApplicationOpenRepairService: Sendable {
    typealias CommandRunner = @Sendable (String, [String]) async throws -> AIAgentProcessOutput
    private let runCommand: CommandRunner
    private let removeQuarantine: @Sendable (Int32) throws -> Void

    public init() {
        self.init(runCommand: { tool, arguments in
            try await AIAgentProcessRunner.run(
                executableURL: URL(fileURLWithPath: tool), arguments: arguments, standardInput: Data(),
                environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"],
                workingDirectoryURL: URL(fileURLWithPath: "/"), timeout: 30,
                maximumOutputBytes: 1_024 * 1_024, maximumErrorBytes: 1_024 * 1_024
            )
        })
    }

    init(
        runCommand: @escaping CommandRunner,
        removeQuarantine: @escaping @Sendable (Int32) throws -> Void = { descriptor in
            guard fremovexattr(descriptor, ApplicationOpenRepairBundle.quarantineAttribute, 0) == 0 else {
                throw ApplicationOpenRepairError.quarantineRemovalFailed
            }
        }
    ) {
        self.runCommand = runCommand
        self.removeQuarantine = removeQuarantine
    }

    public static func needsRepair(at input: URL) -> Bool {
        guard !Task.isCancelled else { return false }
        guard let url = try? ApplicationOpenRepairBundle.applicationURL(input) else { return false }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { return false }
        func hasQuarantine(_ path: String) -> Bool {
            getxattr(path, ApplicationOpenRepairBundle.quarantineAttribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
        if hasQuarantine(url.path) { return true }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return false }
        var count = 0
        for case let child as URL in enumerator {
            count += 1
            guard !Task.isCancelled, count <= 100_000 else { return false }
            if hasQuarantine(child.path) { return true }
        }
        return false
    }

    public func repairAndOpen(at input: URL) async throws {
        let cancellation = ApplicationOpenRepairCancellation()
        try await withTaskCancellationHandler {
            try await repairAndOpen(at: input, cancellation: cancellation)
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func repairAndOpen(at input: URL, cancellation: ApplicationOpenRepairCancellation) async throws {
        let url = try ApplicationOpenRepairBundle.applicationURL(input)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let before = try await capture(url, cancellation: cancellation)
        try await checkSignatureAndAssessment(url)
        let current = try await capture(url, cancellation: cancellation)
        guard before.matches(current) else { throw ApplicationOpenRepairError.applicationChanged }
        let removeQuarantine = self.removeQuarantine
        let expected = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ApplicationOpenRepairBundle, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try current.removeQuarantine(isCancelled: { cancellation.isCancelled }, remove: removeQuarantine)
                })
            }
        }
        let after = try await capture(url, cancellation: cancellation)
        guard expected.matches(after) else { throw ApplicationOpenRepairError.applicationChanged }
        try Task.checkCancellation()
        let result = try await runCommand("/usr/bin/open", ["-a", url.path])
        guard !result.didTimeout, result.status == 0 else { throw ApplicationOpenRepairError.openFailed }
    }

    private func capture(_ url: URL, cancellation: ApplicationOpenRepairCancellation) async throws -> ApplicationOpenRepairBundle {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            // Hashing and file reads run on a dispatch worker, not Swift's cooperative pool.
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result {
                    try ApplicationOpenRepairBundle.capture(at: url, isCancelled: { cancellation.isCancelled })
                })
            }
        }
    }

    private func checkSignatureAndAssessment(_ url: URL) async throws {
        let display = try await runCommand("/usr/bin/codesign", ["--display", "--verbose=4", url.path])
        guard !display.didTimeout else { throw ApplicationOpenRepairError.assessmentUnavailable }
        let displayText = Self.diagnostic(display, path: url.path)
        let signature: Signature
        if display.status != 0 {
            guard displayText.contains("code object is not signed at all") else {
                throw ApplicationOpenRepairError.signatureInvalid
            }
            signature = .unsigned
        } else {
            let verification = try await runCommand("/usr/bin/codesign", ["--verify", "--strict", "--verbose=2", url.path])
            guard !verification.didTimeout else { throw ApplicationOpenRepairError.assessmentUnavailable }
            if verification.status == 0 {
                signature = displayText.components(separatedBy: "\n").contains("Signature=adhoc") ? .adhoc : .valid
            } else {
                let lines = displayText.components(separatedBy: "\n")
                guard lines.contains("Signature=adhoc"), lines.contains("Info.plist=not bound"),
                      lines.contains("Sealed Resources=none"), lines.contains("Internal requirements=none"),
                      lines.contains(where: { $0.hasPrefix("CodeDirectory ") && $0.contains("flags=0x20002(adhoc,linker-signed)") }),
                      Self.diagnostic(verification, path: url.path) == "code has no resources but signature indicates they must be present" else {
                    throw ApplicationOpenRepairError.signatureInvalid
                }
                let executable = try await runCommand("/usr/bin/codesign", ["--verify", "--strict", "--ignore-resources", url.path])
                guard !executable.didTimeout, executable.status == 0 else { throw ApplicationOpenRepairError.signatureInvalid }
                signature = .incompleteAdhoc
            }
        }
        try Task.checkCancellation()
        let assessment = try await runCommand("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=4", url.path])
        guard !assessment.didTimeout else { throw ApplicationOpenRepairError.assessmentUnavailable }
        if assessment.status == 0 { return }
        let diagnostic = Self.diagnostic(assessment, path: url.path).lowercased()
        if ["revoked", "malware", "malicious", "xprotect", "resource envelope is obsolete", "invalid signature",
            "a sealed resource is missing", "resource is missing", "resource missing"].contains(where: diagnostic.contains) {
            throw ApplicationOpenRepairError.assessmentRejected
        }
        if signature == .incompleteAdhoc,
           diagnostic == "code has no resources but signature indicates they must be present"
            || (assessment.status == 1 && diagnostic == "internal error in code signing subsystem")
            || (assessment.status == 3 && diagnostic == "rejected") { return }
        if assessment.status == 3, diagnostic == "rejected" {
            if signature == .valid { return }
            if signature == .adhoc {
                let distribution = try await runCommand("/usr/bin/syspolicy_check", ["distribution", "--json", url.path])
                guard !distribution.didTimeout, distribution.status == 70,
                      Self.acceptsDistributionReport(distribution.standardOutput, path: url.path) else {
                    throw ApplicationOpenRepairError.assessmentUnavailable
                }
                return
            }
        }
        if diagnostic.contains("rejected"),
           diagnostic.contains("no usable signature") || diagnostic.contains("unnotarized developer id") { return }
        throw assessment.status == 3 && diagnostic.contains("rejected")
            ? ApplicationOpenRepairError.assessmentRejected : ApplicationOpenRepairError.assessmentUnavailable
    }

    private enum Signature { case unsigned, adhoc, incompleteAdhoc, valid }

    private static func diagnostic(_ output: AIAgentProcessOutput, path: String) -> String {
        (String(decoding: output.standardOutput, as: UTF8.self) + "\n" + output.standardError)
            .components(separatedBy: "\n").map { line in
                line.hasPrefix(path + ": ") ? String(line.dropFirst(path.count + 2)) : line
            }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func acceptsDistributionReport(_ data: Data, path: String) -> Bool {
        guard data.count < 1_024 * 1_024, let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              uniqueJSONKeys(data), Set(report.keys) == ["output"],
              let issues = report["output"] as? [[String: String]], issues.count == 2 else { return false }
        let fields: Set<String> = ["SyspolicyCheckShortError", "SyspolicyCheckErrorLevel", "SyspolicyCheckLongError",
            "SyspolicyCheckAdditionalInformation", "SyspolicyCheckAdvice", "SyspolicyCheckDocumentationLink", "SyspolicyCheckErrorFile"]
        var expected = ["Adhoc Signed App": "Warning", "Notary Ticket Missing": "Fatal"]
        for issue in issues {
            guard Set(issue.keys).isSubset(of: fields), let name = issue["SyspolicyCheckShortError"],
                  let level = expected.removeValue(forKey: name), issue["SyspolicyCheckErrorLevel"] == level,
                  issue["SyspolicyCheckErrorFile"].map({ $0.isEmpty || $0 == path }) ?? true else { return false }
        }
        return expected.isEmpty
    }

    private static func uniqueJSONKeys(_ data: Data) -> Bool {
        // Foundation accepts duplicate JSON keys; ambiguous policy reports must not authorize a write.
        let bytes = Array(data)
        var objects: [Set<String>?] = []
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 123: objects.append([])
            case 91: objects.append(nil)
            case 125, 93: objects.removeLast()
            case 34:
                let start = index
                index += 1
                while index < bytes.count, bytes[index] != 34 {
                    if bytes[index] == 92 { index += 1 }
                    index += 1
                }
                let end = index + 1
                var next = end
                while next < bytes.count, [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
                if next < bytes.count, bytes[next] == 58 {
                    guard var keys = objects.last ?? nil,
                          let key = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<end])),
                          keys.insert(key.lowercased()).inserted else { return false }
                    objects[objects.count - 1] = keys
                }
            default: break
            }
            index += 1
        }
        return true
    }
}

private final class ApplicationOpenRepairCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }
}
