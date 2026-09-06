import AppKit
import ZislaCore
import ZislaKit
import SwiftUI
import UniformTypeIdentifiers

struct MailModuleView: View {
    @ObservedObject var model: AppModel
    /// Holds the island open while the composer is up so an unfinished draft survives the pointer
    /// leaving the island.
    var onTransientInteractionChanged: (Bool) -> Void = { _ in }

    @State private var selectedMessageID: String?
    @State private var selectedAccountName: String?
    @State private var isComposing = false
    @State private var replyTarget: MailMessage?
    @State private var composeRecipient = ""
    @State private var composeRequestID: UUID?

    private var mail: MailService { model.mail }

    private var selectedAccount: MailAccount? {
        guard let selectedAccountName else { return nil }
        return mail.activeAccounts.first { $0.id == selectedAccountName }
    }

    private var visibleMessages: [MailMessage] {
        guard let selectedAccountName else { return mail.messages }
        return mail.messages.filter { $0.accountName == selectedAccountName }
    }

    private var selectedMessage: MailMessage? {
        guard let selectedMessageID else { return visibleMessages.first }
        return visibleMessages.first { $0.id == selectedMessageID } ?? visibleMessages.first
    }

    private var unreadCount: Int {
        visibleMessages.lazy.filter { !$0.isRead }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            messageList
                .frame(width: 232)
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            selectFirstMessageIfNeeded()
            consumeMailComposeRequest()
            Task { await model.refreshMail() }
        }
        .onChange(of: model.mailComposeRequest) { _, _ in
            consumeMailComposeRequest()
        }
        .onChange(of: mail.messages) { _, _ in
            selectFirstMessageIfNeeded()
        }
        .onChange(of: mail.activeAccounts) { _, accounts in
            if let selectedAccountName, !accounts.contains(where: { $0.id == selectedAccountName }) {
                self.selectedAccountName = nil
            }
            selectFirstMessageIfNeeded()
        }
        .onChange(of: isComposing) { _, composing in
            onTransientInteractionChanged(composing)
        }
        .onDisappear {
            onTransientInteractionChanged(false)
        }
    }

    // MARK: - Content Area (switches between detail and compose based on isComposing)

    @ViewBuilder
    private var contentArea: some View {
        if isComposing {
            MailComposerView(
                model: model,
                replyTarget: replyTarget,
                initialRecipients: composeRecipient,
                onCancel: {
                    finishComposing()
                },
                onSent: {
                    finishComposing()
                }
            )
            .id(composeRequestID)
            .padding(.leading, 10)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
            messageDetail
                .padding(.leading, 10)
                .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(AppLocalization.text("邮件"))
                    .font(.system(size: 12, weight: .semibold))
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.islandMicro(weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                accountMenu
                Spacer(minLength: 2)
                IconButton(symbol: "square.and.pencil", help: AppLocalization.text("发邮件"), size: .compact) {
                    beginNewMessage()
                }
                IconButton(symbol: "arrow.clockwise", help: AppLocalization.text("刷新收件箱"), size: .compact) {
                    Task { await model.refreshMail() }
                }
                .disabled(mail.isLoading)
            }
            .frame(height: 28)
            .padding(.horizontal, 4)

            if mail.isLoading && visibleMessages.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = mail.errorDescription, mail.messages.isEmpty {
                VStack(spacing: 10) {
                    Label(AppLocalization.text("无法读取邮件"), systemImage: "envelope.badge.shield.half.filled")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.zislaWarning)
                    Text(error)
                        .font(.islandMicro())
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Button(AppLocalization.text("重新读取")) { Task { await model.refreshMail() } }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        Button {
                            if mail.needsMailIndexAccess {
                                openFullDiskAccessSettings()
                            } else {
                                openAutomationSettings()
                            }
                        } label: {
                            Label(
                                mail.needsMailIndexAccess ? AppLocalization.text("授权磁盘访问") : AppLocalization.text("打开系统设置"),
                                systemImage: mail.needsMailIndexAccess ? "externaldrive.badge.checkmark" : "gear"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleMessages.isEmpty {
                EmptyState(
                    symbol: selectedAccount == nil ? "tray" : "envelope.badge",
                    title: selectedAccount == nil ? AppLocalization.text("收件箱为空") : AppLocalization.text("此账户没有邮件")
                )
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleMessages) { message in
                            messageRow(message)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .thinScrollChrome()
            }
        }
        .padding(.trailing, 8)
    }

    // MARK: - Account Menu

    private var accountMenu: some View {
        Menu {
            Button {
                selectAccount(nil)
            } label: {
                if selectedAccountName == nil {
                    Label(AppLocalization.text("全部已启用账户"), systemImage: "checkmark")
                } else {
                    Text(AppLocalization.text("全部已启用账户"))
                }
            }
            ForEach(mail.activeAccounts) { account in
                Button {
                    selectAccount(account.id)
                } label: {
                    if selectedAccountName == account.id {
                        Label(account.displayName, systemImage: "checkmark")
                    } else {
                        Text(account.displayName)
                    }
                }
            }
        } label: {
            IconButtonLabel(
                symbol: "line.3.horizontal.decrease.circle",
                isActive: selectedAccountName != nil,
                size: .compact
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(selectedAccount?.displayName ?? AppLocalization.text("全部已启用账户"))
    }

    // MARK: - Message Row

    private func messageRow(_ message: MailMessage) -> some View {
        let selected = message.id == selectedMessage?.id && !isComposing
        return Button {
            if isComposing {
                withAnimation(.easeInOut(duration: 0.18)) {
                    finishComposing()
                }
            }
            selectedMessageID = message.id
            if !message.isRead {
                mail.markReadLocally(message)
                Task { await model.markMailRead(message) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(message.isRead ? Color.clear : Color.accentColor)
                        .frame(width: 5, height: 5)
                    Text(message.sender.isEmpty ? AppLocalization.text("未知发件人") : message.sender)
                        .font(.system(size: 10.5, weight: message.isRead ? .medium : .semibold))
                        .fitsSingleLine()
                    Spacer(minLength: 0)
                }
                Text(message.title)
                    .font(.islandMicro(weight: message.isRead ? .regular : .semibold))
                    .foregroundStyle(message.isRead ? .secondary : .primary)
                    .fitsSingleLine()
                Text(message.preview)
                    .font(.islandMicro())
                    .foregroundStyle(.tertiary)
                    .fitsSingleLine()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.16) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message Detail

    private var messageBodyShape: UnevenRoundedRectangle {
        IslandSurfaceGeometry.moduleContentShape(
            bottomTrailingRadius: IslandSurfaceGeometry.moduleOuterBottomCornerRadius
        )
    }

    @ViewBuilder
    private var messageDetail: some View {
        if let message = selectedMessage {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                        Text(message.sender.isEmpty ? AppLocalization.text("未知发件人") : message.sender)
                            .font(.islandMicro())
                            .foregroundStyle(.secondary)
                            .fitsSingleLine()
                        Text("\(message.accountName) · \(message.receivedAt, format: .dateTime.month().day().hour().minute())")
                            .font(.islandMicro())
                            .foregroundStyle(.tertiary)
                            .fitsSingleLine()
                    }
                    Spacer(minLength: 6)
                    actionRail(for: message)
                }
                .frame(minHeight: 42)
                .padding(.bottom, 6)

                ScrollView(.vertical) {
                    Text(message.preview)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .scrollIndicators(.visible)
                .thinScrollChrome()
                .background(Color.fillCard)
                .clipShape(messageBodyShape)
                .overlay {
                    messageBodyShape
                        .strokeBorder(Color.strokeCard, lineWidth: 1)
                }
            }
        } else {
            EmptyState(symbol: "envelope.open", title: AppLocalization.text("选择一封邮件"))
        }
    }

    // MARK: - Action Rail

    private func actionRail(for message: MailMessage) -> some View {
        HStack(spacing: 6) {
            Button {
                beginReply(to: message)
            } label: {
                Label(AppLocalization.text("回复"), systemImage: "arrowshape.turn.up.left")
                    .font(.islandMicro(weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help(AppLocalization.text("打开回复编辑器"))

            Menu {
                Button {
                    Task { await model.markMailJunk(message) }
                } label: {
                    Label(AppLocalization.text("标记为垃圾邮件"), systemImage: "exclamationmark.triangle")
                }
                Divider()
                Button(role: .destructive) {
                    confirmDelete(message)
                } label: {
                    Label(AppLocalization.text("移到废纸篓"), systemImage: "trash")
                }
            } label: {
                Label(AppLocalization.text("其他操作"), systemImage: "ellipsis.circle")
                    .font(.islandMicro(weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .controlSize(.mini)
            .help(AppLocalization.text("标记为垃圾邮件或移到废纸篓"))
        }
    }

    // MARK: - Helpers

    private func selectAccount(_ accountName: String?) {
        selectedAccountName = accountName
        selectedMessageID = visibleMessages.first?.id
    }

    private func consumeMailComposeRequest() {
        guard let request = model.takeMailComposeRequest() else { return }
        replyTarget = nil
        composeRecipient = request.recipient
        composeRequestID = request.id
        withAnimation(.easeInOut(duration: 0.2)) { isComposing = true }
    }

    private func beginNewMessage() {
        replyTarget = nil
        composeRecipient = ""
        composeRequestID = UUID()
        withAnimation(.easeInOut(duration: 0.2)) { isComposing = true }
    }

    private func beginReply(to message: MailMessage) {
        replyTarget = message
        composeRecipient = ""
        composeRequestID = UUID()
        withAnimation(.easeInOut(duration: 0.2)) { isComposing = true }
    }

    private func finishComposing() {
        isComposing = false
        replyTarget = nil
        composeRecipient = ""
        composeRequestID = nil
    }

    private func selectFirstMessageIfNeeded() {
        guard !visibleMessages.contains(where: { $0.id == selectedMessageID }) else { return }
        selectedMessageID = visibleMessages.first?.id
    }

    private func confirmDelete(_ message: MailMessage) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppLocalization.text("将邮件移到废纸篓？")
        alert.informativeText = AppLocalization.text("这封邮件可在 Mail.app 的废纸篓中恢复。")
        alert.addButton(withTitle: AppLocalization.text("移到废纸篓"))
        alert.addButton(withTitle: AppLocalization.text("取消"))
        WindowPlacement.prepareModal(alert.window, on: WindowPlacement.screenUnderMouse())
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await model.deleteMail(message) }
    }

    /// Opens the "Privacy & Security → Automation" page in System Settings to guide the user to authorize Mail.app access.
    private func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    private func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Inline Composer (composing inside the island, not a popover)

private struct MailComposerView: View {
    @ObservedObject var model: AppModel
    let replyTarget: MailMessage?
    let onCancel: () -> Void
    let onSent: () -> Void

    @State private var selectedSenderAddress: String?
    @State private var recipients: String
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var attachmentURLs: [URL] = []

    init(
        model: AppModel,
        replyTarget: MailMessage?,
        initialRecipients: String,
        onCancel: @escaping () -> Void,
        onSent: @escaping () -> Void
    ) {
        self.model = model
        self.replyTarget = replyTarget
        self.onCancel = onCancel
        self.onSent = onSent
        _recipients = State(initialValue: initialRecipients)
    }

    private var isReply: Bool { replyTarget != nil }
    private var availableAccounts: [MailAccount] { model.mail.activeAccounts }

    /// A sender identity = account name + one specific email address under that account.
    private struct SenderIdentity: Identifiable {
        let accountName: String
        let address: String
        var id: String { "\(accountName)\u{1F}\(address)" }
    }

    /// Flattens all email addresses across all accounts; accounts with no addresses fall back to the account name.
    private var senderIdentities: [SenderIdentity] {
        availableAccounts.flatMap { account -> [SenderIdentity] in
            guard !account.emailAddresses.isEmpty else {
                return [SenderIdentity(accountName: account.id, address: account.id)]
            }
            return account.emailAddresses.map {
                SenderIdentity(accountName: account.id, address: $0)
            }
        }
    }

    private var selectedIdentity: SenderIdentity? {
        guard let selectedSenderAddress else { return senderIdentities.first }
        return senderIdentities.first { $0.address == selectedSenderAddress } ?? senderIdentities.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // header bar + close button
            composerHeader

            // form area
            if isReply {
                VStack(alignment: .leading, spacing: 10) {
                    replyInfo
                    bodyEditor
                        .frame(maxHeight: .infinity)

                    if !attachmentURLs.isEmpty {
                        attachmentList
                    }
                }
                .padding(.top, 12)
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    senderPicker
                    recipientField
                    subjectField
                    bodyEditor
                        .frame(maxHeight: .infinity)

                    if !attachmentURLs.isEmpty {
                        attachmentList
                    }
                }
                .padding(.vertical, 12)
                .frame(maxHeight: .infinity)
            }

            // bottom toolbar: attachment buttons + send/cancel
            toolbar
        }
        .onAppear { selectFirstSenderIfNeeded() }
        .onChange(of: availableAccounts) { _, _ in selectFirstSenderIfNeeded() }
    }

    // MARK: Header

    private var composerHeader: some View {
        HStack {
            Label(isReply ? AppLocalization.text("回复邮件") : AppLocalization.text("新邮件"), systemImage: isReply ? "arrowshape.turn.up.left" : "square.and.pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text("关闭"))
        }
        .frame(height: 32)
        .padding(.horizontal, 4)
    }

    // MARK: Reply Info

    @ViewBuilder
    private var replyInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(AppLocalization.text("原始邮件"), systemImage: "envelope.open")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(replyTarget?.title ?? "")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
            Text(AppLocalization.text("通过 %@ 回复给 %@", replyTarget?.accountName ?? "", replyTarget?.sender ?? ""))
                .font(.islandMicro())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.fillControl)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.strokeCard, lineWidth: 1)
        }
    }

    // MARK: Form Fields

    @ViewBuilder
    private var senderPicker: some View {
        if senderIdentities.count > 1 {
            HStack(spacing: 6) {
                Text(AppLocalization.text("发件人"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fitsSingleLine()
                    .frame(width: 52, alignment: .leading)
                Menu {
                    // group by account, show all addresses under each account inline
                    ForEach(availableAccounts) { account in
                        let identities = senderIdentities.filter { $0.accountName == account.id }
                        Section(account.id) {
                            ForEach(identities) { identity in
                                Button {
                                    selectedSenderAddress = identity.address
                                } label: {
                                    if selectedIdentity?.id == identity.id {
                                        Label(identity.address, systemImage: "checkmark")
                                    } else {
                                        Text(identity.address)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(selectedIdentity?.address ?? AppLocalization.text("系统默认账户"))
                            .font(.system(size: 11, weight: .medium))
                            .fitsSingleLine()
                        if let identity = selectedIdentity, identity.accountName != identity.address {
                            Text("· \(identity.accountName)")
                                .font(.islandMicro())
                                .foregroundStyle(.tertiary)
                                .fitsSingleLine()
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
                .menuStyle(.borderlessButton)
                Spacer()
            }
        } else if let identity = senderIdentities.first {
            HStack(spacing: 6) {
                Text(AppLocalization.text("发件人"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fitsSingleLine()
                    .frame(width: 52, alignment: .leading)
                Text(identity.address)
                    .font(.system(size: 11, weight: .medium))
                if identity.accountName != identity.address {
                    Text("· \(identity.accountName)")
                        .font(.islandMicro())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    private var recipientField: some View {
        HStack(spacing: 6) {
            Text(AppLocalization.text("收件人"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fitsSingleLine()
                .frame(width: 52, alignment: .leading)
            TextField(AppLocalization.text("多个地址用逗号分隔"), text: $recipients)
                .font(.system(size: 11))
                .textFieldStyle(.plain)
        }
    }

    private var subjectField: some View {
        HStack(spacing: 6) {
            Text(AppLocalization.text("主题"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fitsSingleLine()
                .frame(width: 52, alignment: .leading)
            TextField(AppLocalization.text("邮件主题"), text: $subject)
                .font(.system(size: 11))
                .textFieldStyle(.plain)
        }
    }

    // MARK: Body Editor

    private var bodyEditor: some View {
        TextEditor(text: $messageBody)
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.fillControl)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.strokeCard, lineWidth: 1)
            }
    }

    // MARK: Attachments

    private var attachmentList: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6)], spacing: 6) {
            ForEach(attachmentURLs.indices, id: \.self) { index in
                AttachmentChip(url: attachmentURLs[index]) {
                    attachmentURLs.remove(at: index)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            // left side: attachment tool buttons
            HStack(spacing: 4) {
                // add file
                Button {
                    chooseAttachments(title: "添加附件", allowedContentTypes: [.item])
                } label: {
                    Label(AppLocalization.text("添加文件"), systemImage: "paperclip")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(AppLocalization.text("添加附件"))

                // add image
                Button {
                    chooseAttachments(title: "添加图片", allowedContentTypes: [.image])
                } label: {
                    Label(AppLocalization.text("添加图片"), systemImage: "photo")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(AppLocalization.text("插入图片"))

                Divider()
                    .frame(height: 16)

                if !attachmentURLs.isEmpty {
                    Text(AppLocalization.text("%ld 个附件", attachmentURLs.count))
                        .font(.islandMicro())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // right side: cancel / send
            HStack(spacing: 8) {
                Button(AppLocalization.text("取消")) { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button {
                    send()
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(AppLocalization.text("发送"), systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSending || messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Logic

    private func chooseAttachments(title: String, allowedContentTypes: [UTType]) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = AppLocalization.text("添加")
        panel.allowedContentTypes = allowedContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK else { return }
        attachmentURLs.append(contentsOf: panel.urls)
    }

    private func selectFirstSenderIfNeeded() {
        guard !isReply else { return }
        guard !senderIdentities.contains(where: { $0.address == selectedSenderAddress }) else { return }
        selectedSenderAddress = senderIdentities.first?.address
    }

    private func send() {
        isSending = true
        Task {
            var body = messageBody

            // Append attachment path info to the body (AppleScript send doesn't support attachments directly;
            // using text as a placeholder for now — can be upgraded to Mail.app's attachment API later)
            if !attachmentURLs.isEmpty {
                let fileNames = attachmentURLs.map { $0.lastPathComponent }.joined(separator: ", ")
                body += "\n\n---\n" + AppLocalization.text("附件：%@", fileNames)
            }

            let sent: Bool
            if let replyTarget {
                sent = await model.replyToMail(replyTarget, body: body)
            } else {
                sent = await model.sendMail(
                    fromAddress: selectedIdentity?.address,
                    to: recipients,
                    subject: subject,
                    body: body
                )
            }
            isSending = false
            if sent { onSent() }
        }
    }
}

// MARK: - Attachment Chip

private struct AttachmentChip: View {
    let url: URL
    let onRemove: () -> Void

    @State private var isImage = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if isImage, let nsImage = NSImage(contentsOf: url) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: iconForExtension(url.pathExtension))
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
            Text(url.lastPathComponent)
                .font(.system(size: 8))
                .fitsSingleLine()
                .foregroundStyle(.secondary)
        }
        .onAppear {
            isImage = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"].contains(url.pathExtension.lowercased())
        }
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.richtext"
        case "zip", "gz", "tar": return "archivebox"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx", "csv": return "tablecells"
        case "ppt", "pptx": return "presentation"
        default: return "document"
        }
    }
}
