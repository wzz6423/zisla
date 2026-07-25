import AppKit
import ZislaCore

@MainActor
protocol ClipboardStringReading: AnyObject {
    var changeCount: Int { get }
    func string(forType type: NSPasteboard.PasteboardType) -> String?
}

extension NSPasteboard: ClipboardStringReading {}

@MainActor
public final class ClipboardLinkMonitor {
    public typealias DetectionHandler = @MainActor @Sendable (URL) -> Void

    public private(set) var isEnabled = false
    public var onLinkDetected: DetectionHandler?

    private let source: any ClipboardStringReading
    private let pollInterval: TimeInterval
    private var detector = ClipboardLinkDetector()
    private var lastPasteboardChangeCount: Int?
    private var timer: Timer?

    public init(
        pasteboard: NSPasteboard = .general,
        pollInterval: TimeInterval = 0.8,
        onLinkDetected: DetectionHandler? = nil
    ) {
        self.source = pasteboard
        self.pollInterval = max(pollInterval, 0.25)
        self.onLinkDetected = onLinkDetected
    }

    init(
        source: any ClipboardStringReading,
        pollInterval: TimeInterval = 0.8,
        onLinkDetected: DetectionHandler? = nil
    ) {
        self.source = source
        self.pollInterval = max(pollInterval, 0.25)
        self.onLinkDetected = onLinkDetected
    }

    isolated deinit {
        timer?.invalidate()
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            let changeCount = source.changeCount
            lastPasteboardChangeCount = changeCount
            detector.begin(atChangeCount: changeCount)
            let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pollNow()
                }
            }
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
        let changeCount = source.changeCount
        guard changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = changeCount

        guard let url = detector.detect(
            changeCount: changeCount,
            string: source.string(forType: .string)
        ) else {
            return
        }
        onLinkDetected?(url)
    }
}
