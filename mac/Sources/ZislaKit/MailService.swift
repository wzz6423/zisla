import AppKit
import Combine
import Foundation
import ZislaCore

public enum MailOperationResult: Equatable, Sendable {
    case success
    case failed(String)
}

struct MailScriptAccount: Sendable {
    let name: String
    let emailAddresses: [String]
}

struct MailScriptRow: Sendable {
    let accountName: String
    let messageID: String
    let sender: String
    let subject: String
    let body: String
    let receivedAt: Date
    let isRead: Bool
}

struct MailSnapshot: Sendable {
    let accounts: [MailScriptAccount]
    let messages: [MailScriptRow]
}

private enum MailScriptOutput: Sendable {
    case snapshot(MailSnapshot)
    case succeeded
}

private enum MailScriptError: Error, Sendable {
    case failed(String)
}

/// Reads multiple inboxes and performs mail operations via the user's configured Mail.app.
///
/// Mail.app is the sole source of accounts and credentials; Zisla only stores the user-selected account names,
/// and message content is kept in memory only — nothing is written to Zisla's local directory.
@MainActor
public final class MailService: ObservableObject {
    @Published public private(set) var accounts: [MailAccount] = []
    @Published public private(set) var messages: [MailMessage] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var isMutating = false
    @Published public private(set) var errorDescription: String?
    @Published public private(set) var needsMailIndexAccess = false

    private let commandRunner: (String, Bool) async -> Result<MailScriptOutput, MailScriptError>
    private let indexReader: MailIndexReader
    private var pollingTask: Task<Void, Never>?
    private var selectedAccountNames: Set<String> = []

    public convenience init() {
        self.init(commandRunner: Self.runAppleScript, indexReader: MailIndexReader())
    }

    fileprivate init(
        commandRunner: @escaping (String, Bool) async -> Result<MailScriptOutput, MailScriptError>,
        indexReader: MailIndexReader
    ) {
        self.commandRunner = commandRunner
        self.indexReader = indexReader
    }

    deinit {
        pollingTask?.cancel()
    }

    public var unreadCount: Int {
        messages.lazy.filter { !$0.isRead }.count
    }

    /// An empty set means sync all accounts from the system Mail.app.
    public var activeAccounts: [MailAccount] {
        guard !selectedAccountNames.isEmpty else { return accounts }
        return accounts.filter { selectedAccountNames.contains($0.id) }
    }

    public func start(accountNames: Set<String>) {
        let didChangeSelection = selectedAccountNames != accountNames
        selectedAccountNames = accountNames
        guard pollingTask == nil else {
            if didChangeSelection {
                Task { await refresh() }
            }
            return
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isLoading = false
    }

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        needsMailIndexAccess = false

        if Self.isMailRunning() {
            switch await commandRunner(Self.inboxScript(accountNames: selectedAccountNames), true) {
            case let .success(.snapshot(snapshot)):
                apply(snapshot)
            case .success:
                errorDescription = AppLocalization.text("邮件服务返回了无法识别的数据")
            case let .failure(error):
                errorDescription = Self.message(for: error)
            }
        } else {
            let reader = indexReader
            let accountNames = selectedAccountNames
            let result = await Task.detached(priority: .userInitiated) {
                do {
                    return Result<MailSnapshot, MailIndexReaderError>.success(
                        try reader.snapshot(accountNames: accountNames)
                    )
                } catch let error as MailIndexReaderError {
                    return .failure(error)
                } catch {
                    return .failure(.queryFailed)
                }
            }.value
            switch result {
            case let .success(snapshot):
                apply(snapshot)
            case let .failure(error):
                needsMailIndexAccess = error == .unavailable || error == .openFailed
                errorDescription = Self.message(for: error)
            }
        }
    }

    public func markRead(_ message: MailMessage) async -> MailOperationResult {
        markReadLocally(message)
        let result = await perform(Self.markReadScript(message: message))
        switch result {
        case .success:
            markReadLocally(message)
        case .failed:
            setReadLocally(message, isRead: message.isRead)
        }
        return result
    }

    public func markReadLocally(_ message: MailMessage) {
        setReadLocally(message, isRead: true)
    }

    private func setReadLocally(_ message: MailMessage, isRead: Bool) {
        messages = messages.map { current in
            guard current.id == message.id, current.isRead != isRead else { return current }
            return MailMessage(
                accountName: current.accountName,
                messageID: current.messageID,
                sender: current.sender,
                subject: current.subject,
                body: current.body,
                receivedAt: current.receivedAt,
                isRead: isRead
            )
        }
    }

    public func markJunk(_ message: MailMessage) async -> MailOperationResult {
        await perform(Self.markJunkScript(message: message))
    }

    public func delete(_ message: MailMessage) async -> MailOperationResult {
        await perform(Self.deleteScript(message: message))
    }

    /// `fromAddress` is the specific sender address chosen by the user; pass nil to use the system default account.
    public func send(
        fromAddress: String?,
        to recipients: String,
        subject: String,
        body: String
    ) async -> MailOperationResult {
        let addresses = recipients
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !addresses.isEmpty else { return .failed(AppLocalization.text("请填写至少一个收件人")) }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed(AppLocalization.text("邮件正文不能为空"))
        }
        return await perform(Self.composeScript(
            fromAddress: fromAddress,
            to: addresses,
            subject: subject,
            body: body
        ))
    }

    public func reply(to message: MailMessage, body: String) async -> MailOperationResult {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed(AppLocalization.text("回复内容不能为空"))
        }
        return await perform(Self.replyScript(message: message, body: body))
    }

    static func accounts(from rows: [MailScriptAccount]) -> [MailAccount] {
        rows.compactMap { row in
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let addresses = row.emailAddresses
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return MailAccount(name: name, emailAddresses: addresses)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func messages(from rows: [MailScriptRow]) -> [MailMessage] {
        rows.compactMap { row in
            guard
                !row.accountName.isEmpty,
                let messageID = Int(row.messageID)
            else { return nil }
            return MailMessage(
                accountName: row.accountName,
                messageID: messageID,
                sender: row.sender,
                subject: row.subject,
                body: row.body,
                receivedAt: row.receivedAt,
                isRead: row.isRead
            )
        }
        .sorted { $0.receivedAt > $1.receivedAt }
    }

    /// Mail's scripting dictionary exposes `inbox` on the application, not on `account`:
    /// `inbox of <account>` fails with "can't get inbox of account id …" (verified on Mail 16 /
    /// macOS 27), which silently emptied every fetch and made every write-back unreachable.
    /// Address the account's own mailbox named INBOX instead — Mail keeps that name untranslated
    /// even when the surrounding folders are localized.
    static func accountInbox(_ accountExpression: String) -> String {
        "mailbox \"INBOX\" of \(accountExpression)"
    }

    static func inboxScript(accountNames: Set<String>) -> String {
        let accountNames = accountNames
            .sorted()
            .map(appleScriptString)
            .joined(separator: ", ")
        // Fetch per-account using index + try/on error:
        //   1. If any account (commonly #1: not loaded / offline / unauthenticated / On My Mac / RSS etc.)
        //      cannot resolve its inbox, the entire fetch must not fail;
        //   2. Individual message read failures (e.g. huge body, corrupt attachment) must be skipped without affecting subsequent messages;
        //   3. Use count + item i explicit indexing to avoid `repeat with x in every account`
        //      losing references when Mail's internal state changes.
        return """
        tell application "Mail"
            set accountRows to {}
            set messageRows to {}
            set selectedAccountNames to {\(accountNames)}
            set accountList to every account
            set accountCount to count of accountList
            repeat with i from 1 to accountCount
                set mailAccount to item i of accountList
                set accountName to ""
                set accountAddresses to {}
                try
                    set accountName to name of mailAccount as text
                on error
                    set accountName to ""
                end try
                try
                    set rawAddresses to email addresses of mailAccount
                    if (count of rawAddresses) is 0 then
                        set accountAddresses to {}
                    else
                        set accountAddresses to rawAddresses
                    end if
                on error
                    set accountAddresses to {}
                end try
                if accountName is "" then
                    set end of accountRows to {"\(AppLocalization.text("未知账户")) " & i, accountAddresses}
                else
                    set end of accountRows to {accountName, accountAddresses}
                end if
                if (count of selectedAccountNames) is 0 or accountName is in selectedAccountNames then
                    try
                        set inboxMessages to messages of \(accountInbox("mailAccount"))
                        set messageCount to count of inboxMessages
                        set maximumCount to 30
                        if messageCount > maximumCount then set messageCount to maximumCount
                        if messageCount > 0 then
                            repeat with messageIndex from 1 to messageCount
                                try
                                    set mailMessage to item messageIndex of inboxMessages
                                    set messageBody to content of mailMessage
                                    if (count of messageBody) > 1200 then set messageBody to text 1 thru 1200 of messageBody
                                    set end of messageRows to {accountName, id of mailMessage as text, sender of mailMessage as text, subject of mailMessage as text, messageBody, date received of mailMessage, read status of mailMessage}
                                on error
                                    -- Skip unreadable individual messages (corrupt or excessively large).
                                end try
                            end repeat
                        end if
                    on error
                        -- This account's inbox is currently unavailable (still loading, offline, or authenticating).
                        -- Skip this account and continue fetching the others.
                    end try
                end if
            end repeat
            return {accountRows, messageRows}
        end tell
        """
    }

    static func markReadScript(message: MailMessage) -> String {
        """
        tell application "Mail"
            set targetAccount to first account whose name is \(appleScriptString(message.accountName))
            set targetMessage to first message of \(accountInbox("targetAccount")) whose id is \(message.messageID)
            set read status of targetMessage to true
        end tell
        """
    }

    static func markJunkScript(message: MailMessage) -> String {
        """
        tell application "Mail"
            set targetAccount to first account whose name is \(appleScriptString(message.accountName))
            set targetMessage to first message of \(accountInbox("targetAccount")) whose id is \(message.messageID)
            set junk mail status of targetMessage to true
        end tell
        """
    }

    static func deleteScript(message: MailMessage) -> String {
        """
        tell application "Mail"
            set targetAccount to first account whose name is \(appleScriptString(message.accountName))
            set targetMessage to first message of \(accountInbox("targetAccount")) whose id is \(message.messageID)
            delete targetMessage
        end tell
        """
    }

    static func composeScript(
        fromAddress: String?,
        to recipients: [String],
        subject: String,
        body: String
    ) -> String {
        let recipientsScript = recipients.map {
            "make new to recipient at end of to recipients with properties {address:\(appleScriptString($0))}"
        }.joined(separator: "\n            ")
        let senderScript = fromAddress.map {
            "set sender of outgoingMessage to \(appleScriptString($0))"
        } ?? ""
        return """
        tell application "Mail"
            set outgoingMessage to make new outgoing message with properties {subject:\(appleScriptString(subject)), content:\(appleScriptString(body)), visible:false}
            \(senderScript)
            tell outgoingMessage
                \(recipientsScript)
                send
            end tell
        end tell
        """
    }

    static func replyScript(message: MailMessage, body: String) -> String {
        """
        tell application "Mail"
            set targetAccount to first account whose name is \(appleScriptString(message.accountName))
            set targetMessage to first message of \(accountInbox("targetAccount")) whose id is \(message.messageID)
            set replyMessage to reply targetMessage
            set content of replyMessage to \(appleScriptString(body)) & return & return & content of replyMessage
            send replyMessage
        end tell
        """
    }

    static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private func perform(_ script: String) async -> MailOperationResult {
        guard !isMutating else { return .failed(AppLocalization.text("正在处理另一项邮件操作")) }
        guard Self.isMailRunning() else {
            return .failed(Self.mailUnavailableMessage(isRunning: false) ?? AppLocalization.text("Mail.app 当前未运行"))
        }
        isMutating = true
        defer { isMutating = false }

        switch await commandRunner(script, false) {
        case .success:
            await refresh()
            return .success
        case let .failure(error):
            return .failed(Self.message(for: error))
        }
    }

    private static func message(for error: MailScriptError) -> String {
        switch error {
        case let .failed(message):
            let lower = message.lowercased()
            if lower.contains("未获得授权") || lower.contains("not authorized") || lower.contains("not allowed") || lower.contains("permission") || lower.contains("(-1743)") || lower.contains("(-1744)") || lower.contains("(-1745)") {
                return AppLocalization.text("需要授权 zisla 控制 Mail.app\n请打开「系统设置 → 隐私与安全性 → 自动化」，\n在列表中找到并开启 zisla 对 Mail 的访问权限")
            }
            return message
        }
    }

    private static func message(for error: MailIndexReaderError) -> String {
        switch error {
        case .unavailable, .openFailed:
            return AppLocalization.text("无法访问 Mail 的本地邮件索引。请在「系统设置 → 隐私与安全性 → 完全磁盘访问」中允许 zisla，然后重新读取。")
        case .queryFailed:
            return AppLocalization.text("无法解析 Mail 的本地邮件索引，请稍后重新读取")
        }
    }

    private func apply(_ snapshot: MailSnapshot) {
        accounts = Self.accounts(from: snapshot.accounts)
        messages = Self.messages(from: snapshot.messages)
        errorDescription = nil
        needsMailIndexAccess = false
    }

    nonisolated private static func runAppleScript(
        _ source: String,
        expectsSnapshot: Bool
    ) async -> Result<MailScriptOutput, MailScriptError> {
        await Task.detached(priority: .userInitiated) {
            if let message = mailUnavailableMessage(isRunning: isMailRunning()) {
                return .failure(.failed(message))
            }

            if let result = execute(source: source, expectsSnapshot: expectsSnapshot) {
                return result
            }

            // On first failure, if it looks like "Mail isn't ready yet" (reference resolution errors / can't find item inbox / account unavailable),
            // wait 2s and retry once. This transient failure is common during the first fetch right after Mail is woken up,
            // and should not force the user to manually tap "Refresh" every time.
            try? await Task.sleep(for: .seconds(2))
            if let retry = execute(source: source, expectsSnapshot: expectsSnapshot) {
                return retry
            }
            return .failure(.failed(AppLocalization.text("Mail.app 尚未就绪，请稍后再试")))
        }.value
    }

    nonisolated static func mailUnavailableMessage(isRunning: Bool) -> String? {
        guard !isRunning else { return nil }
        return AppLocalization.text("Mail.app 当前未运行。zisla 不会自动打开它；请在需要同步时自行启动 Mail.app 后重试。")
    }

    /// Mail.app's bundle identifier is all-lowercase, and
    /// `runningApplications(withBundleIdentifier:)` compares case-sensitively — the camel-cased
    /// `com.apple.Mail` matched nothing, so Zisla reported "Mail.app isn't running" while Mail was
    /// open and refused every mutation.
    nonisolated static let mailBundleIdentifier = "com.apple.mail"

    nonisolated private static func isMailRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: mailBundleIdentifier).isEmpty
    }

    /// Executes one AppleScript run; returns nil to indicate failure requiring a retry by the caller.
    nonisolated private static func execute(
        source: String,
        expectsSnapshot: Bool
    ) -> Result<MailScriptOutput, MailScriptError>? {
        guard let appleScript = NSAppleScript(source: source) else {
            return .failure(.failed(AppLocalization.text("无法创建 Mail.app 自动化脚本")))
        }
        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                ?? (errorInfo[NSLocalizedDescriptionKey] as? String)
                ?? AppLocalization.text("无法访问 Mail.app，请检查自动化授权")
            let lower = message.lowercased()
            // Typical signs of "Mail still loading": reference resolution failure / can't find inbox for item / account unavailable.
            let looksUnready = lower.contains("inbox") ||
                lower.contains("every account") ||
                lower.contains("item ") ||
                lower.contains("not loaded") ||
                lower.contains("not available") ||
                lower.contains("can't get") ||
                lower.contains("不能获得")
            if looksUnready { return nil }
            return .failure(.failed(message))
        }
        return expectsSnapshot
            ? .success(.snapshot(snapshot(from: descriptor)))
            : .success(.succeeded)
    }

    nonisolated private static func snapshot(from descriptor: NSAppleEventDescriptor) -> MailSnapshot {
        guard
            descriptor.numberOfItems >= 2,
            let accountsDescriptor = descriptor.atIndex(1),
            let messagesDescriptor = descriptor.atIndex(2)
        else {
            return MailSnapshot(accounts: [], messages: [])
        }
        let accounts = values(in: accountsDescriptor).compactMap { row -> MailScriptAccount? in
            guard row.numberOfItems >= 2, let name = row.atIndex(1)?.stringValue else { return nil }
            return MailScriptAccount(
                name: name,
                emailAddresses: strings(in: row.atIndex(2))
            )
        }
        let messages = values(in: messagesDescriptor).compactMap { row -> MailScriptRow? in
            guard row.numberOfItems >= 7 else { return nil }
            guard
                let accountName = row.atIndex(1)?.stringValue,
                let messageID = row.atIndex(2)?.stringValue
            else { return nil }
            return MailScriptRow(
                accountName: accountName,
                messageID: messageID,
                sender: row.atIndex(3)?.stringValue ?? "",
                subject: row.atIndex(4)?.stringValue ?? "",
                body: row.atIndex(5)?.stringValue ?? "",
                receivedAt: row.atIndex(6)?.dateValue ?? Date(),
                isRead: row.atIndex(7)?.booleanValue ?? false
            )
        }
        return MailSnapshot(accounts: accounts, messages: messages)
    }

    nonisolated private static func values(in descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        guard descriptor.numberOfItems > 0 else { return [] }
        return (1...descriptor.numberOfItems).compactMap(descriptor.atIndex)
    }

    nonisolated private static func strings(in descriptor: NSAppleEventDescriptor?) -> [String] {
        guard let descriptor else { return [] }
        let values = values(in: descriptor)
        if !values.isEmpty {
            return values.compactMap(\.stringValue)
        }
        return descriptor.stringValue.map { [$0] } ?? []
    }
}
