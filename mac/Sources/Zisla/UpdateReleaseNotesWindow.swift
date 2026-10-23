import AppKit
import Sparkle
import SwiftUI
import ZislaCore
import ZislaKit

enum UpdateReleaseNotesPresentation: Equatable {
    case available(stage: SPUUserUpdateStage, critical: Bool, informationURL: URL?)
    case installed

    var titleKey: String {
        self == .installed ? "已更新至 %@" : "发现新版本 %@"
    }

    var installKey: String? {
        switch self {
        case .installed: nil
        case .available(_, _, .some): "了解更多"
        case .available(.installing, _, _): "安装并重新启动"
        case .available: "安装更新"
        }
    }

    var dismissKey: String {
        if case .available(.installing, _, _) = self { return "退出时安装" }
        return self == .installed ? "关闭" : "稍后提醒"
    }

    var allowsSkipping: Bool {
        if case .available(_, false, _) = self { return true }
        return false
    }

    var allowsDeferral: Bool {
        if case .available(_, true, _) = self { return false }
        return true
    }
}

@MainActor
final class UpdateReleaseNotesWindowController: NSWindowController, NSWindowDelegate {
    private var reply: ((SPUUserUpdateChoice) -> Void)?

    init(
        model: UpdateReleaseNotesModel,
        presentation: UpdateReleaseNotesPresentation,
        languageStore: AppLanguageStore,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 560, height: 420)
        window.title = AppLocalization.text("更新日志")
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ZislaUpdateReleaseNotes")
        super.init(window: window)
        self.reply = reply
        window.delegate = self
        let view = UpdateReleaseNotesView(
            model: model,
            presentation: presentation,
            onChoice: { [weak self] choice in self?.finish(choice) }
        )
        window.contentView = NSHostingView(rootView: AppLanguageEnvironment(languageStore: languageStore, content: view))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        reply = nil
        close()
    }

    func windowWillClose(_ notification: Notification) {
        let reply = reply
        self.reply = nil
        reply?(.dismiss)
    }

    func finish(_ choice: SPUUserUpdateChoice) {
        let reply = reply
        self.reply = nil
        close()
        reply?(choice)
    }
}

private struct UpdateReleaseNotesView: View {
    @ObservedObject var model: UpdateReleaseNotesModel
    let presentation: UpdateReleaseNotesPresentation
    let onChoice: (SPUUserUpdateChoice) -> Void

    @Environment(\.locale) private var locale
    @State private var loadAttempt = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: presentation == .installed ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(presentation == .installed ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    AppLocalizedFormatText(presentation.titleKey, model.release.version)
                        .font(.title2.weight(.semibold))
                    AppLocalizedText("更新日志")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            Divider()
            Group {
                if let notes = model.notes {
                    MarkdownWebView(
                        html: ReleaseNotesHTML.document(
                            markdown: notes.markdown,
                            language: AppLanguage(rawValue: locale.identifier.replacingOccurrences(of: "_", with: "-")) ?? .english
                        ),
                        baseURL: notes.releaseURL,
                        allowedLinkSchemes: ["https", "http", "mailto"]
                    )
                } else if model.loadFailed {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        AppLocalizedText("无法加载更新日志")
                        Button { loadAttempt += 1 } label: { AppLocalizedText("重试") }
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        AppLocalizedText("正在加载更新日志")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    releasePageButton
                    Spacer()
                    skipButton
                    dismissButton
                    installButton
                }
                VStack(spacing: 12) {
                    HStack {
                        releasePageButton
                        Spacer()
                        skipButton
                    }
                    HStack(spacing: 10) {
                        Spacer()
                        dismissButton
                        installButton
                    }
                }
            }
            .padding(20)
        }
        .task(id: loadAttempt) {
            await model.load()
        }
    }

    @ViewBuilder private var releasePageButton: some View {
        if let notes = model.notes {
            Button { NSWorkspace.shared.open(notes.releaseURL) } label: { AppLocalizedText("查看发布页面") }
                .fixedSize()
        }
    }

    @ViewBuilder private var skipButton: some View {
        if presentation.allowsSkipping {
            Button { onChoice(.skip) } label: { AppLocalizedText("跳过此版本") }
                .fixedSize()
        }
    }

    @ViewBuilder private var dismissButton: some View {
        if presentation.allowsDeferral {
            Button { onChoice(.dismiss) } label: { AppLocalizedText(presentation.dismissKey) }
                .keyboardShortcut(.cancelAction)
                .fixedSize()
        }
    }

    @ViewBuilder private var installButton: some View {
        if let installKey = presentation.installKey {
            Button {
                if case let .available(_, _, .some(url)) = presentation {
                    NSWorkspace.shared.open(url)
                    onChoice(.dismiss)
                } else {
                    onChoice(.install)
                }
            } label: { AppLocalizedText(installKey) }
                .keyboardShortcut(.defaultAction)
                .fixedSize()
        }
    }
}
