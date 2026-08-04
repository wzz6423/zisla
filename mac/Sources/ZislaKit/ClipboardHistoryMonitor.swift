import AppKit

@MainActor
public final class ClipboardHistoryMonitor {
    public typealias CaptureHandler = @MainActor @Sendable (ClipboardHistoryContent) -> Void

    public private(set) var isEnabled = false
    public var onContentCaptured: CaptureHandler?

    private let pasteboard: NSPasteboard
    private let pollInterval: TimeInterval
    private var lastPasteboardChangeCount: Int?
    private var timer: Timer?

    public init(
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = 1,
        onContentCaptured: CaptureHandler? = nil
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = max(pollInterval, 0.25)
        self.onContentCaptured = onContentCaptured
    }

    isolated deinit {
        timer?.invalidate()
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            lastPasteboardChangeCount = pasteboard.changeCount
            let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollNow() }
            }
            timer.tolerance = min(0.2, pollInterval / 2)
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            timer?.invalidate()
            timer = nil
            lastPasteboardChangeCount = nil
        }
    }

    func pollNow() {
        guard isEnabled else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = changeCount
        guard let content = ClipboardHistoryPasteboard.readContent(from: pasteboard) else { return }
        onContentCaptured?(content)
    }
}
