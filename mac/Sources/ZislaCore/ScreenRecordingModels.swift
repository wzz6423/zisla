import Foundation

public enum RecordingPhase: String, Equatable, Sendable {
    case idle, preparing, recording, paused, finishing

    public var isActive: Bool { self != .idle }
}

public enum RecordingCaptureMode: String, Codable, CaseIterable, Sendable {
    case display, window, region

    public var title: String {
        switch self {
        case .display: "全屏录制"
        case .window: "窗口录制"
        case .region: "区域录制"
        }
    }
}

public struct RecordingRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }

    public var isNormalized: Bool {
        isValid && x >= 0 && y >= 0 && x + width <= 1.000_001 && y + height <= 1.000_001
    }
}

public struct RecordingCaptureSource: Identifiable, Equatable, Sendable {
    public var id: UInt32
    public var name: String
    public var mode: RecordingCaptureMode
    public var frame: RecordingRect

    public init(id: UInt32, name: String, mode: RecordingCaptureMode, frame: RecordingRect) {
        self.id = id
        self.name = name
        self.mode = mode
        self.frame = frame
    }
}

public struct RecordingDevice: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct RecordingCaptureConfiguration: Equatable, Sendable {
    public var mode: RecordingCaptureMode
    public var sourceID: UInt32
    public var region: RecordingRect?
    public var systemAudio: Bool
    public var microphone: Bool
    public var camera: Bool
    public var microphoneID: String?
    public var cameraID: String?
    public var frameRate: Int

    public init(mode: RecordingCaptureMode = .display, sourceID: UInt32 = 0,
                region: RecordingRect? = nil, systemAudio: Bool = true,
                microphone: Bool = false, camera: Bool = false,
                microphoneID: String? = nil, cameraID: String? = nil, frameRate: Int = 30) {
        self.mode = mode
        self.sourceID = sourceID
        self.region = region
        self.systemAudio = systemAudio
        self.microphone = microphone
        self.camera = camera
        self.microphoneID = microphoneID
        self.cameraID = cameraID
        self.frameRate = frameRate
    }
}

public enum RecordingPointerKind: String, Codable, Sendable {
    case move, leftClick, rightClick
}

public struct RecordingPointer: Codable, Equatable, Sendable {
    public var time: Double
    public var x: Double
    public var y: Double
    public var kind: RecordingPointerKind

    public init(time: Double, x: Double, y: Double, kind: RecordingPointerKind = .move) {
        self.time = time
        self.x = x
        self.y = y
        self.kind = kind
    }
}

public struct ScreenRecordingResult: Equatable, Sendable {
    public var videoFile: String
    public var cameraFile: String?
    public var microphoneFile: String?
    public var duration: Double
    public var width: Int
    public var height: Int
    public var pointers: [RecordingPointer]

    public init(videoFile: String, cameraFile: String? = nil, microphoneFile: String? = nil,
                duration: Double, width: Int, height: Int, pointers: [RecordingPointer] = []) {
        self.videoFile = videoFile
        self.cameraFile = cameraFile
        self.microphoneFile = microphoneFile
        self.duration = duration
        self.width = width
        self.height = height
        self.pointers = pointers
    }
}

public struct RecordingSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var speed: Double

    public init(id: UUID = UUID(), start: Double, end: Double, speed: Double = 1) {
        self.id = id
        self.start = start
        self.end = end
        self.speed = speed
    }

    public var outputDuration: Double { (end - start) / speed }
}

public struct RecordingZoom: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var time: Double
    public var duration: Double
    public var scale: Double
    public var x: Double
    public var y: Double

    public init(id: UUID = UUID(), time: Double, duration: Double = 2, scale: Double = 1.8,
                x: Double = 0.5, y: Double = 0.5) {
        self.id = id
        self.time = time
        self.duration = duration
        self.scale = scale
        self.x = x
        self.y = y
    }
}

public enum RecordingBackground: String, Codable, CaseIterable, Sendable {
    case none, midnight, gradient, white

    public var title: String {
        switch self {
        case .none: "无背景"
        case .midnight: "深色背景"
        case .gradient: "渐变背景"
        case .white: "白色背景"
        }
    }
}

public enum RecordingCameraPosition: String, Codable, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var title: String {
        switch self {
        case .topLeft: "左上"
        case .topRight: "右上"
        case .bottomLeft: "左下"
        case .bottomRight: "右下"
        }
    }
}

public struct RecordingCaption: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String

    public init(id: UUID = UUID(), start: Double, end: Double, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct RecordingEdits: Codable, Equatable, Sendable {
    public var segments: [RecordingSegment]
    public var zoomClips: [RecordingZoom]
    public var background: RecordingBackground
    public var padding: Double
    public var cornerRadius: Double
    public var shadow: Double
    public var cursorSize: Double
    public var showCursor: Bool
    public var clickEffects: Bool
    public var autoZoom: Bool
    public var cameraPosition: RecordingCameraPosition
    public var cameraSize: Double
    public var cameraMirrored: Bool
    public var cameraRound: Bool
    public var cameraCornerRadius: Double?
    public var showCamera: Bool?
    public var screenAudioVolume: Double?
    public var microphoneVolume: Double?
    public var showCaptions: Bool
    public var crop: RecordingRect?
    public var canvasAspectRatio: RecordingCanvasAspectRatio?
    public var backgroundColor: RecordingColor?
    public var annotations: [RecordingAnnotation]?

    public var effectiveCameraCornerRadius: Double { cameraRound ? 0.5 : cameraCornerRadius ?? 0.1 }
    public var effectiveShowCamera: Bool { showCamera ?? true }
    public var effectiveScreenAudioVolume: Double { screenAudioVolume ?? 1 }
    public var effectiveMicrophoneVolume: Double { microphoneVolume ?? 1 }

    public init(segments: [RecordingSegment] = [], zoomClips: [RecordingZoom] = [],
                background: RecordingBackground = .gradient, padding: Double = 0.06,
                cornerRadius: Double = 0.02, shadow: Double = 0.3, cursorSize: Double = 1.5,
                showCursor: Bool = true, clickEffects: Bool = true, autoZoom: Bool = false,
                cameraPosition: RecordingCameraPosition = .bottomRight, cameraSize: Double = 0.25,
                cameraMirrored: Bool = true, cameraRound: Bool = true, cameraCornerRadius: Double? = nil,
                showCamera: Bool? = nil, screenAudioVolume: Double? = nil, microphoneVolume: Double? = nil, showCaptions: Bool = true,
                crop: RecordingRect? = nil, canvasAspectRatio: RecordingCanvasAspectRatio? = nil,
                backgroundColor: RecordingColor? = nil, annotations: [RecordingAnnotation]? = nil) {
        self.segments = segments
        self.zoomClips = zoomClips
        self.background = background
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.cursorSize = cursorSize
        self.showCursor = showCursor
        self.clickEffects = clickEffects
        self.autoZoom = autoZoom
        self.cameraPosition = cameraPosition
        self.cameraSize = cameraSize
        self.cameraMirrored = cameraMirrored
        self.cameraRound = cameraRound
        self.cameraCornerRadius = cameraCornerRadius
        self.showCamera = showCamera
        self.screenAudioVolume = screenAudioVolume
        self.microphoneVolume = microphoneVolume
        self.showCaptions = showCaptions
        self.crop = crop
        self.canvasAspectRatio = canvasAspectRatio
        self.backgroundColor = backgroundColor
        self.annotations = annotations
    }
}

public enum RecordingExportFormat: String, Codable, CaseIterable, Sendable {
    case mp4, gif
}

public enum RecordingExportResolution: String, Codable, CaseIterable, Sendable {
    case source, fullHD, quadHD, ultraHD

    public var title: String {
        switch self {
        case .source: "原始分辨率"
        case .fullHD: "1080p"
        case .quadHD: "1440p"
        case .ultraHD: "4K"
        }
    }
}

public struct RecordingExportConfiguration: Equatable, Sendable {
    public var format: RecordingExportFormat
    public var resolution: RecordingExportResolution
    public var frameRate: Int

    public init(format: RecordingExportFormat = .mp4,
                resolution: RecordingExportResolution = .fullHD, frameRate: Int = 30) {
        self.format = format
        self.resolution = resolution
        self.frameRate = frameRate
    }
}

public enum ScreenRecordingProjectError: LocalizedError, Equatable {
    case invalidProject
    case unsupportedVersion
    case unsafeMediaPath
    case missingMedia

    public var errorDescription: String? {
        switch self {
        case .invalidProject: AppLocalization.text("录屏项目数据无效")
        case .unsupportedVersion: AppLocalization.text("此录屏项目来自更新的版本")
        case .unsafeMediaPath: AppLocalization.text("录屏素材路径超出项目目录")
        case .missingMedia: AppLocalization.text("录屏项目的素材已丢失")
        }
    }
}

public struct ScreenRecordingProject: Codable, Equatable, Identifiable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var videoFile: String
    public var cameraFile: String?
    public var microphoneFile: String?
    public var duration: Double
    public var width: Int
    public var height: Int
    public var pointers: [RecordingPointer]
    public var edits: RecordingEdits
    public var captions: [RecordingCaption]

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), videoFile: String,
                cameraFile: String? = nil, microphoneFile: String? = nil, duration: Double,
                width: Int, height: Int, pointers: [RecordingPointer] = [],
                edits: RecordingEdits? = nil, captions: [RecordingCaption] = []) {
        version = Self.currentVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.videoFile = videoFile
        self.cameraFile = cameraFile
        self.microphoneFile = microphoneFile
        self.duration = duration
        self.width = width
        self.height = height
        self.pointers = pointers
        self.edits = edits ?? RecordingEdits(segments: [.init(start: 0, end: duration)])
        self.captions = captions
    }

    public init(result: ScreenRecordingResult, name: String) {
        self.init(name: name, videoFile: result.videoFile, cameraFile: result.cameraFile,
                  microphoneFile: result.microphoneFile, duration: result.duration,
                  width: result.width, height: result.height, pointers: result.pointers)
    }

    public var outputDuration: Double { edits.segments.reduce(0) { $0 + $1.outputDuration } }

    public func validate() throws {
        guard version == Self.currentVersion else { throw ScreenRecordingProjectError.unsupportedVersion }
        guard duration.isFinite, duration > 0, duration <= 604_800,
              (1...16_384).contains(width), (1...16_384).contains(height),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 512, edits.segments.count <= 2_000,
              edits.zoomClips.count <= 10_000, captions.count <= 100_000,
              pointers.count <= 4_000_000,
              Set(edits.segments.map(\.id)).count == edits.segments.count,
              Set(edits.zoomClips.map(\.id)).count == edits.zoomClips.count,
              Set(captions.map(\.id)).count == captions.count,
              edits.segments.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.speed.isFinite
                  && $0.start >= 0 && $0.end > $0.start && $0.end <= duration + 0.001
                  && (0.1...8).contains($0.speed) }),
              edits.zoomClips.allSatisfy({ $0.time.isFinite && $0.duration.isFinite
                  && $0.time >= 0 && $0.time < duration && $0.duration > 0
                  && $0.duration <= duration && (1...5).contains($0.scale)
                  && (0...1).contains($0.x) && (0...1).contains($0.y) }),
              captions.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0
                  && $0.end > $0.start && $0.end <= duration + 0.001 && $0.text.count <= 4_000 }),
              pointers.allSatisfy({ $0.time.isFinite && $0.time >= 0 && $0.time <= duration + 0.1
                  && (0...1).contains($0.x) && (0...1).contains($0.y) }),
              (0...0.3).contains(edits.padding), (0...0.2).contains(edits.cornerRadius),
              (0...1).contains(edits.shadow), (0.5...4).contains(edits.cursorSize),
              (0.1...0.5).contains(edits.cameraSize),
              edits.cameraCornerRadius.map({ (0...0.5).contains($0) }) != false,
              (0...1).contains(edits.effectiveScreenAudioVolume),
              (0...1).contains(edits.effectiveMicrophoneVolume),
              edits.backgroundColor?.isValid != false,
              edits.annotations.map({ annotations in
                  annotations.count <= RecordingAnnotation.maximumCount
                      && Set(annotations.map(\.id)).count == annotations.count
                      && annotations.allSatisfy { $0.isValid(duration: duration) }
              }) != false,
              edits.crop?.isNormalized != false
        else { throw ScreenRecordingProjectError.invalidProject }
        for path in [videoFile, cameraFile, microphoneFile].compactMap({ $0 }) {
            guard Self.isSafeMediaPath(path) else { throw ScreenRecordingProjectError.unsafeMediaPath }
        }
    }

    public static func isSafeMediaPath(_ path: String) -> Bool {
        !path.isEmpty && path.count <= 255 && path != "." && path != ".."
            && !path.contains("/") && !path.contains("\\") && !path.contains("\0")
    }
}

public enum RecordingShortcutAction: Int, CaseIterable, Identifiable, Sendable {
    case display = 1, window, region, pause, stop, studio, openProject, saveProject, export

    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .display: "全屏录制"
        case .window: "窗口录制"
        case .region: "区域录制"
        case .pause: "暂停或继续录制"
        case .stop: "停止录制"
        case .studio: "录屏工作室"
        case .openProject: "打开录屏项目"
        case .saveProject: "保存录屏项目"
        case .export: "导出录屏"
        }
    }

    public var hotkey: VoiceInputHotkeyPreset {
        let keyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        return .init(keyCode: keyCodes[rawValue - 1], carbonModifiers: 0x1000 | 0x0200,
                     keyDisplayName: String(rawValue))
    }
}

extension FeatureSettings {
    public func screenRecordingHotkey(for action: RecordingShortcutAction) -> VoiceInputHotkeyPreset {
        screenRecordingHotkeys[String(action.rawValue)] ?? action.hotkey
    }

    public func recordingShortcutConflict(for hotkey: VoiceInputHotkeyPreset,
                                          excluding action: RecordingShortcutAction? = nil) -> String? {
        if screenRecordingEnabled,
           let conflict = RecordingShortcutAction.allCases.first(where: {
               $0 != action && hotkey.conflicts(with: screenRecordingHotkey(for: $0))
           }) { return conflict.title }
        if screenshotEnabled {
            if hotkey.conflicts(with: screenshotHotkey) { return "截图" }
            if hotkey.conflicts(with: screenshotLongHotkey) { return "长截图" }
        }
        if voiceInputEnabled && hotkey.conflicts(with: voiceInputHotkeyPreset) { return "语音输入" }
        if clipboardAssistantEnabled {
            if let trigger = clipboardAssistantTriggerConfiguration.hotkey, hotkey.conflicts(with: trigger) {
                return "快速触发快捷键"
            }
            if let dismiss = clipboardAssistantDismissConfiguration.hotkey, hotkey.conflicts(with: dismiss) {
                return "关闭弹窗快捷键"
            }
        }
        return nil
    }
}
