import AppKit
import ZislaCore
import ZislaKit
import SwiftUI
import UniformTypeIdentifiers

struct MailModuleView: View {
    @ObservedObject var model: AppModel

    @State private var selectedMessageID: String?
    @State private var selectedAccountName: String?
    @State private var isComposing = false
    @State private var replyTarget: MailMessage?
    @State private var deleteTarget: MailMessage?

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
            Hairline()
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            selectFirstMessageIfNeeded()
            Task { await model.refreshMail() }
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
        .confirmationDialog(
            "将邮件移到废纸篓？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移到废纸篓", role: .destructive) {
                guard let deleteTarget else { return }
                self.deleteTarget = nil
                Task { await model.deleteMail(deleteTarget) }
            }
        } message: {
            Text("这封邮件可在 Mail.app 的废纸篓中恢复。")
        }
    }

    // MARK: - Content Area（根据 isComposing 切换详情/撰写）

    @ViewBuilder
    private var contentArea: some View {
        if isComposing {
            MailComposerView(
                model: model,
                replyTarget: replyTarget,
                onCancel: {
                    isComposing = false
                    replyTarget = nil
                },
                onSent: {
                    isComposing = false
                    replyTarget = nil
                }
            )
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
                Text("邮件")
                    .font(.system(size: 12, weight: .semibold))
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.islandMicro(weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                accountMenu
                Spacer(minLength: 2)
                IconButton(symbol: "square.and.pencil", help: "发邮件", size: .compact) {
                    replyTarget = nil
                    withAnimation(.easeInOut(duration: 0.2)) { isComposing = true }
                }
                IconButton(symbol: "arrow.clockwise", help: "刷新收件箱", size: .compact) {
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
                    Label("无法读取邮件", systemImage: "envelope.badge.shield.half.filled")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.zislaWarning)
                    Text(error)
                        .font(.islandMicro())
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Button("重新读取") { Task { await model.refreshMail() } }
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
                                mail.needsMailIndexAccess ? "授权磁盘访问" : "打开系统设置",
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
                    title: selectedAccount == nil ? "收件箱为空" : "此账户没有邮件"
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
                    Label("全部已启用账户", systemImage: "checkmark")
                } else {
                    Text("全部已启用账户")
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
        .help(selectedAccount?.displayName ?? "全部已启用账户")
    }

    // MARK: - Message Row

    private func messageRow(_ message: MailMessage) -> some View {
        let selected = message.id == selectedMessage?.id && !isComposing
        return Button {
            if isComposing {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isComposing = false
                    replyTarget = nil
                }
            }
            selectedMessageID = message.id
            if !message.isRead {
                Task { await model.markMailRead(message) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(message.isRead ? Color.clear : Color.accentColor)
                        .frame(width: 5, height: 5)
                    Text(message.sender.isEmpty ? "未知发件人" : message.sender)
                        .font(.system(size: 10.5, weight: message.isRead ? .medium : .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(message.title)
                    .font(.islandMicro(weight: message.isRead ? .regular : .semibold))
                    .foregroundStyle(message.isRead ? .secondary : .primary)
                    .lineLimit(1)
                Text(message.preview)
                    .font(.islandMicro())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
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

    @ViewBuilder
    private var messageDetail: some View {
        if let message = selectedMessage {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                        Text(message.sender.isEmpty ? "未知发件人" : message.sender)
                            .font(.islandMicro())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("\(message.accountName) · \(message.receivedAt, format: .dateTime.month().day().hour().minute())")
                            .font(.islandMicro())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.strokeCard, lineWidth: 1)
                }
            }
        } else {
            EmptyState(symbol: "envelope.open", title: "选择一封邮件")
        }
    }

    // MARK: - Action Rail

    private func actionRail(for message: MailMessage) -> some View {
        HStack(spacing: 3) {
            IconButton(symbol: "arrowshape.turn.up.left", help: "回复", size: .compact) {
                replyTarget = message
                withAnimation(.easeInOut(duration: 0.2)) { isComposing = true }
            }
            IconButton(symbol: "envelope.open", help: "标记已读", size: .compact) {
                Task { await model.markMailRead(message) }
            }
            .disabled(message.isRead || mail.isMutating)
            IconButton(symbol: "exclamationmark.triangle", help: "标记为垃圾邮件", size: .compact) {
                Task { await model.markMailJunk(message) }
            }
            .disabled(mail.isMutating)
            IconButton(symbol: "trash", help: "移到废纸篓", size: .compact) {
                deleteTarget = message
            }
            .disabled(mail.isMutating)
        }
    }

    // MARK: - Helpers

    private func selectAccount(_ accountName: String?) {
        selectedAccountName = accountName
        selectedMessageID = visibleMessages.first?.id
    }

    private func selectFirstMessageIfNeeded() {
        guard !visibleMessages.contains(where: { $0.id == selectedMessageID }) else { return }
        selectedMessageID = visibleMessages.first?.id
    }

    /// 打开系统偏好设置的「隐私与安全性 → 自动化」页面，引导用户授权 Mail.app 访问。
    private func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    private func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Inline Composer（岛内撰写，非弹窗）

private struct MailComposerView: View {
    @ObservedObject var model: AppModel
    let replyTarget: MailMessage?
    let onCancel: () -> Void
    let onSent: () -> Void

    @State private var selectedSenderAddress: String?
    @State private var recipients = ""
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var attachmentURLs: [URL] = []
    @State private var showsFileImporter = false
    @State private var showsImagePicker = false

    private var isReply: Bool { replyTarget != nil }
    private var availableAccounts: [MailAccount] { model.mail.activeAccounts }

    /// 一个可选的发件身份 = 账户名 + 该账户下的一个具体邮箱地址。
    private struct SenderIdentity: Identifiable {
        let accountName: String
        let address: String
        var id: String { "\(accountName)\u{1F}\(address)" }
    }

    /// 平铺所有账户下的全部邮箱地址；没有地址的账户以账户名兜底展示。
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
            // 标题栏 + 关闭按钮
            composerHeader

            Divider()

            // 表单区域
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if replyTarget != nil {
                        replyInfo
                    } else {
                        senderPicker
                        recipientField
                        subjectField
                    }

                    // 正文编辑器
                    bodyEditor

                    // 附件列表
                    if !attachmentURLs.isEmpty {
                        attachmentList
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollIndicators(.visible)
            .thinScrollChrome()

            Divider()

            // 底部工具栏：附件按钮 + 发送/取消
            toolbar
        }
        .background(Color.fillCard)
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            attachmentURLs.append(contentsOf: urls)
        }
        .onAppear { selectFirstSenderIfNeeded() }
        .onChange(of: availableAccounts) { _, _ in selectFirstSenderIfNeeded() }
    }

    // MARK: Header

    private var composerHeader: some View {
        HStack {
            Label(isReply ? "回复邮件" : "新邮件", systemImage: isReply ? "arrowshape.turn.up.left" : "square.and.pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .frame(height: 32)
        .padding(.horizontal, 4)
    }

    // MARK: Reply Info

    @ViewBuilder
    private var replyInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("原始邮件", systemImage: "envelope.open")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(replyTarget?.title ?? "")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
            Text("通过 \(replyTarget?.accountName ?? "") 回复给 \(replyTarget?.sender ?? "")")
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
                Text("发件人")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
                Menu {
                    // 按账户分组，账户内平铺其所有邮箱地址
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
                        Text(selectedIdentity?.address ?? "系统默认账户")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        if let identity = selectedIdentity, identity.accountName != identity.address {
                            Text("· \(identity.accountName)")
                                .font(.islandMicro())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
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
                Text("发件人")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
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
            Text("收件人")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            TextField("多个地址用逗号分隔", text: $recipients)
                .font(.system(size: 11))
                .textFieldStyle(.plain)
        }
    }

    private var subjectField: some View {
        HStack(spacing: 6) {
            Text("主题")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            TextField("邮件主题", text: $subject)
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
            // 左侧：附件工具按钮
            HStack(spacing: 4) {
                // 添加文件
                Button {
                    showsFileImporter = true
                } label: {
                    Label("添加文件", systemImage: "paperclip")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.borderless)
                .help("添加附件")

                // 添加图片
                Button {
                    showsImagePicker = true
                } label: {
                    Label("添加图片", systemImage: "photo")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.borderless)
                .help("插入图片")

                Divider()
                    .frame(height: 16)

                if !attachmentURLs.isEmpty {
                    Text("\(attachmentURLs.count) 个附件")
                        .font(.islandMicro())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // 右侧：取消 / 发送
            HStack(spacing: 8) {
                Button("取消") { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button {
                    send()
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("发送", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSending || messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.fillControl)
    }

    // MARK: Logic

    private func selectFirstSenderIfNeeded() {
        guard !isReply else { return }
        guard !senderIdentities.contains(where: { $0.address == selectedSenderAddress }) else { return }
        selectedSenderAddress = senderIdentities.first?.address
    }

    private func send() {
        isSending = true
        Task {
            var body = messageBody

            // 将附件路径信息追加到正文（AppleScript 发送不直接支持附件，
            // 这里用文本方式提示用户；后续可升级为 Mail.app 的 attachment API）
            if !attachmentURLs.isEmpty {
                let fileNames = attachmentURLs.map { $0.lastPathComponent }.joined(separator: ", ")
                body += "\n\n---\n附件：\(fileNames)"
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
                .lineLimit(1)
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
