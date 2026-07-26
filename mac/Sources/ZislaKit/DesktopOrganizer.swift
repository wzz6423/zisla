import AppKit
import Foundation

/// Bulk operations for the desktop and Trash, plus an App Store update entry point.
///
/// All implemented via Finder's AppleScript interface (same pattern as `NotesAppBridge` —
/// in-process `NSAppleScript` ensures correct TCC attribution). The first call prompts
/// the user to authorize Zisla to control Finder.
public enum DesktopOrganizerError: Error, Sendable, Equatable {
    case failed(String)

    public var message: String {
        if case .failed(let value) = self { return value }
        return "未知错误"
    }
}

@MainActor
public enum DesktopOrganizer {
    /// Result of a single desktop tidy operation, surfaced to the UI for user feedback.
    public struct TidyOutcome: Sendable, Equatable {
        /// Number of items re-snapped to the grid.
        public let arrangedCount: Int
        /// The user has Stacks enabled; the desktop is managed by the system, so no files were moved.
        public let skippedForStacks: Bool

        public init(arrangedCount: Int, skippedForStacks: Bool) {
            self.arrangedCount = arrangedCount
            self.skippedForStacks = skippedForStacks
        }
    }

    // MARK: - Stacks detection

    /// Whether desktop Stacks is enabled.
    ///
    /// Finder stores the Stacks grouping in `com.apple.finder`'s `DesktopViewSettings.GroupBy`;
    /// it is `None` when Stacks is off, and a grouping key such as `Kind` or `DateAdded` when on.
    /// When Stacks is active the desktop layout is fully managed by the system, and manual
    /// `desktop position` changes are ignored, so we leave all files untouched in that case.
    public static func isStacksEnabled(
        defaults: UserDefaults? = UserDefaults(suiteName: "com.apple.finder")
    ) -> Bool {
        guard let settings = defaults?.dictionary(forKey: "DesktopViewSettings") else { return false }
        return isStacksEnabled(groupBy: settings["GroupBy"] as? String)
    }

    /// Pure-logic seam: makes it easy to unit-test all `GroupBy` values.
    public static func isStacksEnabled(groupBy: String?) -> Bool {
        guard let groupBy, !groupBy.isEmpty else { return false }
        return groupBy.caseInsensitiveCompare("None") != .orderedSame
    }

    // MARK: - Tidy desktop

    /// Re-snaps desktop icons to the grid.
    ///
    /// Returns `skippedForStacks` immediately when Stacks is enabled, without touching any files.
    public static func tidyDesktop() async -> Result<TidyOutcome, DesktopOrganizerError> {
        if isStacksEnabled() {
            return .success(TidyOutcome(arrangedCount: 0, skippedForStacks: true))
        }

        let script = """
        tell application "Finder"
            set itemCount to count of items of desktop
            clean up desktop
            return itemCount
        end tell
        """
        switch await runAppleScriptReturningString(script) {
        case .success(let value):
            let count = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return .success(TidyOutcome(arrangedCount: count, skippedForStacks: false))
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Trash

    /// Number of items in the Trash; used to show a confirmation message before emptying.
    public static func trashItemCount() async -> Result<Int, DesktopOrganizerError> {
        let script = """
        tell application "Finder"
            return count of items of trash
        end tell
        """
        switch await runAppleScriptReturningString(script) {
        case .success(let value):
            return .success(Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Empties the Trash. Irreversible — the caller must obtain user confirmation first.
    public static func emptyTrash() async -> Result<Void, DesktopOrganizerError> {
        // With `warns before emptying` disabled, Finder skips its own second confirmation; Zisla handles that step itself.
        let script = """
        tell application "Finder"
            set warnsSetting to warns before emptying of trash
            try
                set warns before emptying of trash to false
                empty trash
            end try
            set warns before emptying of trash to warnsSetting
        end tell
        """
        return await runAppleScriptVoid(script)
    }

    // MARK: - App Store updates

    /// One-tap App Store app update.
    ///
    /// macOS has no public App Store update API: `CommerceKit`'s `CKUpdateController`
    /// requires a private entitlement, and an unauthorized process cannot even establish the XPC
    /// connection. Therefore:
    /// - If `mas` is available, run `mas upgrade` for a true one-tap experience.
    /// - Otherwise open the App Store Updates page and let the user click "Update All".
    ///
    /// Locating `mas` is delegated to `ManagedToolService` (the download page can install/upgrade it);
    /// this only consumes the result, so the search paths are not maintained in two places.
    public static func updateAppStoreApps(
        masExecutable: URL?
    ) async -> Result<String, DesktopOrganizerError> {
        guard let mas = masExecutable else {
            openAppStoreUpdatesPage()
            return .success("未安装 mas，已打开 App Store 更新页")
        }
        switch await run(mas, arguments: ["upgrade"]) {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.localizedCaseInsensitiveContains("everything is up-to-date") {
                return .success("App Store 应用均已是最新")
            }
            let updated = trimmed
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .count
            return .success("已通过 mas 更新 \(updated) 项")
        case .failure(let error):
            return .failure(error)
        }
    }

    public static func openAppStoreUpdatesPage() {
        if let url = URL(string: "macappstore://showUpdatesPage") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/App Store.app"))
        }
    }

    // MARK: - Execution

    private static func run(
        _ executable: URL,
        arguments: [String]
    ) async -> Result<String, DesktopOrganizerError> {
        await Task.detached(priority: .userInitiated) { () -> Result<String, DesktopOrganizerError> in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                return .failure(.failed("无法启动 \(executable.lastPathComponent)：\(error.localizedDescription)"))
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let message = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.failed(
                    [message, fallback].compactMap { $0 }.first { !$0.isEmpty }
                        ?? "\(executable.lastPathComponent) 执行失败"
                ))
            }
            return .success(String(data: data, encoding: .utf8) ?? "")
        }.value
    }

    private static func runAppleScriptReturningString(
        _ source: String
    ) async -> Result<String, DesktopOrganizerError> {
        await Task.detached(priority: .userInitiated) { () -> Result<String, DesktopOrganizerError> in
            let appleScript = NSAppleScript(source: source)
            var errorInfo: NSDictionary?
            let descriptor = appleScript?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                return .failure(.failureMessage(from: errorInfo))
            }
            guard let descriptor else {
                return .failure(.failed("访达没有返回内容"))
            }
            return .success(descriptor.stringValue ?? "")
        }.value
    }

    private static func runAppleScriptVoid(
        _ source: String
    ) async -> Result<Void, DesktopOrganizerError> {
        await Task.detached(priority: .userInitiated) { () -> Result<Void, DesktopOrganizerError> in
            let appleScript = NSAppleScript(source: source)
            var errorInfo: NSDictionary?
            _ = appleScript?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                return .failure(.failureMessage(from: errorInfo))
            }
            return .success(())
        }.value
    }
}

private extension DesktopOrganizerError {
    static func failureMessage(from errorInfo: NSDictionary) -> DesktopOrganizerError {
        let message = (errorInfo[NSAppleScript.errorMessage] as? String)
            ?? (errorInfo[NSLocalizedDescriptionKey] as? String)
            ?? "访达操作失败，请检查自动化授权"
        return .failed(message)
    }
}
