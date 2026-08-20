import AppKit
import SwiftUI

struct TeleprompterView: View {
    var onClose: () -> Void

    @AppStorage("toolbox.teleprompterScript") private var script = ""
    @AppStorage("toolbox.teleprompterScrollSpeed") private var scrollSpeed = 45.0
    @State private var isAutoScrolling = false
    @State private var isHovering = false
    @State private var scrollResetID = UUID()

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.black

            TeleprompterScrollView(
                script: $script,
                isAutoScrolling: $isAutoScrolling,
                speed: scrollSpeed,
                resetID: scrollResetID
            )

            if script.isEmpty {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            controls
                .opacity(isHovering || script.isEmpty ? 1 : 0)
                .allowsHitTesting(isHovering || script.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                isAutoScrolling.toggle()
            } label: {
                Image(systemName: isAutoScrolling ? "pause.fill" : "play.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(script.isEmpty)
            .help(isAutoScrolling ? "暂停自动滚动" : "开始自动滚动")

            Button {
                isAutoScrolling = false
                scrollResetID = UUID()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(script.isEmpty)
            .help("回到开头")

            Slider(value: $scrollSpeed, in: 15...150, step: 5)
                .frame(width: 132)
                .help("自动滚动速度")

            Text("\(Int(scrollSpeed)) 点/秒")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 58, alignment: .trailing)

            Button {
                pasteFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("从剪贴板粘贴")

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("关闭提词器")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.7), in: Capsule())
        .padding(18)
    }

    private func pasteFromClipboard() {
        guard let pastedText = NSPasteboard.general.string(forType: .string) else { return }
        script = pastedText
    }
}

@MainActor
private struct TeleprompterScrollView: NSViewRepresentable {
    @Binding var script: String
    @Binding var isAutoScrolling: Bool
    let speed: Double
    let resetID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(script: $script, isAutoScrolling: $isAutoScrolling)
    }

    func makeNSView(context: Context) -> TeleprompterScrollContainer {
        let scrollView = TeleprompterScrollContainer()
        scrollView.setTextDelegate(context.coordinator)
        context.coordinator.update(
            scrollView: scrollView,
            script: $script,
            isAutoScrolling: $isAutoScrolling,
            speed: speed,
            resetID: resetID
        )
        return scrollView
    }

    func updateNSView(_ scrollView: TeleprompterScrollContainer, context: Context) {
        context.coordinator.update(
            scrollView: scrollView,
            script: $script,
            isAutoScrolling: $isAutoScrolling,
            speed: speed,
            resetID: resetID
        )
    }

    static func dismantleNSView(_ scrollView: TeleprompterScrollContainer, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private weak var scrollView: TeleprompterScrollContainer?
        private var timer: Timer?
        private var scrollSpeed: CGFloat = 0
        private var script: Binding<String>
        private var isAutoScrolling: Binding<Bool>
        private var resetID: UUID?

        init(script: Binding<String>, isAutoScrolling: Binding<Bool>) {
            self.script = script
            self.isAutoScrolling = isAutoScrolling
            super.init()
        }

        func update(
            scrollView: TeleprompterScrollContainer,
            script: Binding<String>,
            isAutoScrolling: Binding<Bool>,
            speed: Double,
            resetID: UUID
        ) {
            self.scrollView = scrollView
            self.script = script
            self.isAutoScrolling = isAutoScrolling
            scrollSpeed = CGFloat(speed)
            if scrollView.setScript(script.wrappedValue) {
                isAutoScrolling.wrappedValue = false
                scrollView.scrollToTop()
            }

            if self.resetID != resetID {
                self.resetID = resetID
                scrollView.scrollToTop()
            }
            syncTimer()
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        private func syncTimer() {
            guard isAutoScrolling.wrappedValue else {
                stop()
                return
            }
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(
                timeInterval: 1 / 60,
                target: self,
                selector: #selector(advanceScrollPosition),
                userInfo: nil,
                repeats: true
            )
        }

        @objc private func advanceScrollPosition() {
            guard isAutoScrolling.wrappedValue, let scrollView else {
                stop()
                return
            }
            let currentOffset = scrollView.contentView.bounds.origin.y
            let maximumOffset = max(
                0,
                (scrollView.documentView?.frame.height ?? 0) - scrollView.contentView.bounds.height
            )
            guard currentOffset < maximumOffset else {
                isAutoScrolling.wrappedValue = false
                stop()
                return
            }

            scrollView.scroll(toVerticalOffset: min(maximumOffset, currentOffset + scrollSpeed / 60))
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let scrollView,
                  scrollView.recordUserScriptChange(textView.string)
            else { return }
            let newText = textView.string
            isAutoScrolling.wrappedValue = false
            script.wrappedValue = newText
        }
    }
}

@MainActor
private final class TeleprompterScrollContainer: NSScrollView {
    private let textView: NSTextView
    private var renderedScript: String?

    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textView = NSTextView(frame: .zero, textContainer: textContainer)

        super.init(frame: .zero)
        documentView = textView
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        ThinScrollChrome.apply(to: self)
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 48, height: 54)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTextDelegate(_ delegate: NSTextViewDelegate) {
        textView.delegate = delegate
    }

    @discardableResult
    func setScript(_ value: String) -> Bool {
        guard renderedScript != value else { return false }
        renderedScript = value

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineSpacing = 12
        paragraphStyle.paragraphSpacing = 22
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(string: value, attributes: attributes))
        textView.typingAttributes = attributes
        textView.invalidateIntrinsicContentSize()
        return true
    }

    func recordUserScriptChange(_ value: String) -> Bool {
        guard renderedScript != value else { return false }
        renderedScript = value
        return true
    }

    func scrollToTop() {
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
    }

    func scroll(toVerticalOffset offset: CGFloat) {
        contentView.scroll(to: NSPoint(x: 0, y: offset))
        reflectScrolledClipView(contentView)
    }
}
