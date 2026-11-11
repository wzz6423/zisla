import Foundation
import ZislaCore

public enum AudioToolOperation: String, CaseIterable, Identifiable, Sendable {
    case convert, compress, trim, removeSegment, split, merge, mix, extract
    case volume, normalize, fade, speed, pitch, reverse, denoise, removeSilence
    case equalizer, dynamics, echo, channels, splitChannels, vocalReduction
    case metadata, repeatAudio, insertSilence, generateSilence, generateTone

    public var id: Self { self }

    public var title: String {
        switch self {
        case .convert: "格式转换"
        case .compress: "音频压缩"
        case .trim: "裁剪音频"
        case .removeSegment: "删除片段"
        case .split: "分段导出"
        case .merge: "拼接音频"
        case .mix: "混合音轨"
        case .extract: "视频提取音频"
        case .volume: "调整音量"
        case .normalize: "响度标准化"
        case .fade: "淡入淡出"
        case .speed: "变速不变调"
        case .pitch: "变调不变速"
        case .reverse: "倒放音频"
        case .denoise: "音频降噪"
        case .removeSilence: "移除静音"
        case .equalizer: "均衡器"
        case .dynamics: "压缩与限幅"
        case .echo: "添加回声"
        case .channels: "声道处理"
        case .splitChannels: "拆分声道"
        case .vocalReduction: "削弱居中人声"
        case .metadata: "音频标签"
        case .repeatAudio: "循环拼接"
        case .insertSilence: "插入静音"
        case .generateSilence: "生成静音"
        case .generateTone: "生成测试音"
        }
    }

    public var detail: String {
        switch self {
        case .convert: "转换常用音频格式，可批量处理"
        case .compress: "降低码率、采样率或声道数；已压缩的文件可能不会变小"
        case .trim: "保留指定时间范围"
        case .removeSegment: "删除指定时间范围并连接剩余部分"
        case .split: "按固定时长分段，保留最后不足一段的音频"
        case .merge: "按列表顺序连接音频，自动统一采样率与声道"
        case .mix: "同时叠加多条音轨，按最长音轨导出"
        case .extract: "导出视频中的第一条音轨"
        case .volume: "以分贝调整音量，过度放大可能失真"
        case .normalize: "按 LUFS 统一响度并限制峰值"
        case .fade: "分别设置开头淡入与结尾淡出的时长"
        case .speed: "改变播放时长并保留音高"
        case .pitch: "以半音调整音高并保留播放时长"
        case .reverse: "从结尾向开头播放；长音频请先分段"
        case .denoise: "使用频谱降噪减少稳定背景噪声"
        case .removeSilence: "移除开头、结尾与中间超过阈值时长的静音"
        case .equalizer: "分别调整低频、中频和高频"
        case .dynamics: "压缩动态范围并限制输出峰值"
        case .echo: "设置回声延迟与衰减"
        case .channels: "转为单声道或立体声，提取或交换左右声道"
        case .splitChannels: "将每个声道导出为独立的单声道文件"
        case .vocalReduction: "通过左右声道相减削弱居中声音，效果取决于原始混音"
        case .metadata: "修改标题、艺人、专辑与备注，或清除全部标签"
        case .repeatAudio: "将整段音频重复连接指定次数"
        case .insertSilence: "在指定时间点插入静音"
        case .generateSilence: "生成指定时长的静音文件"
        case .generateTone: "生成指定频率与时长的正弦测试音"
        }
    }

    public var symbol: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .trim, .removeSegment: "scissors"
        case .split: "rectangle.split.3x1"
        case .merge: "link"
        case .mix: "slider.horizontal.3"
        case .extract: "film"
        case .volume: "speaker.wave.2"
        case .normalize: "waveform.path"
        case .fade: "chart.line.uptrend.xyaxis"
        case .speed: "speedometer"
        case .pitch: "music.note"
        case .reverse: "backward.end"
        case .denoise: "waveform.badge.minus"
        case .removeSilence: "speaker.slash"
        case .equalizer: "slider.vertical.3"
        case .dynamics: "waveform.path.ecg"
        case .echo: "dot.radiowaves.left.and.right"
        case .channels, .splitChannels: "hifispeaker.2"
        case .vocalReduction: "mic.slash"
        case .metadata: "tag"
        case .repeatAudio: "repeat"
        case .insertSilence, .generateSilence: "pause"
        case .generateTone: "waveform"
        }
    }

    public var generatesAudio: Bool { self == .generateSilence || self == .generateTone }
    public var allowsMultipleInputs: Bool { [.convert, .compress, .merge, .mix].contains(self) }
    public var requiresMultipleInputs: Bool { self == .merge || self == .mix }
    public var exportFormats: [AudioExportFormat] {
        AudioExportFormat.allCases.filter {
            if self == .compress { return !$0.isLossless }
            if self == .splitChannels || self == .vocalReduction { return $0 != .ogg }
            return true
        }
    }
    public func exportsToDirectory(inputCount: Int) -> Bool {
        self == .split || self == .splitChannels || (allowsMultipleInputs && !requiresMultipleInputs && inputCount > 1)
    }
}

public enum AudioExportFormat: String, CaseIterable, Identifiable, Sendable {
    case m4a, mp3, wav, aiff, flac, alac, aac, ogg, opus, caf, wma

    public var id: Self { self }
    public var title: String { self == .alac ? "ALAC (M4A)" : rawValue.uppercased() }
    public var fileExtension: String { self == .alac ? "m4a" : rawValue }
    public var isLossless: Bool { [.wav, .aiff, .flac, .alac, .caf].contains(self) }

    public var sampleRates: [Int] {
        switch self {
        case .opus: [48_000]
        case .mp3, .wma: [16_000, 22_050, 32_000, 44_100, 48_000]
        default: [8_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000, 96_000]
        }
    }
}

public enum AudioChannelMode: String, CaseIterable, Identifiable, Sendable {
    case preserve, mono, stereo, left, right, swap
    public var id: Self { self }
    public var title: String {
        switch self {
        case .preserve: "保留声道"
        case .mono: "单声道"
        case .stereo: "立体声"
        case .left: "仅左声道"
        case .right: "仅右声道"
        case .swap: "交换左右声道"
        }
    }
}

public struct AudioFileSummary: Equatable, Sendable {
    public let duration: Double
    public let sampleRate: Int
    public let channels: Int
    public let codec: String
    public let fileSize: Int64
    public let metadata: [String: String]
}

public struct AudioProcessingOptions: Sendable {
    public var format: AudioExportFormat = .m4a
    public var bitrateKbps = 192
    public var sampleRate = 48_000
    public var bitDepth = 16
    public var channelMode: AudioChannelMode = .preserve
    public var startTime = 0.0
    public var endTime: Double?
    public var segmentDuration = 60.0
    public var volumeDB = 3.0
    public var targetLoudness = -16.0
    public var fadeInDuration = 1.0
    public var fadeOutDuration = 1.0
    public var speed = 1.25
    public var pitchSemitones = 2.0
    public var noiseReductionDB = 12.0
    public var silenceThresholdDB = -40.0
    public var silenceDuration = 0.3
    public var bassDB = 0.0
    public var midDB = 0.0
    public var trebleDB = 0.0
    public var compressorThresholdDB = -18.0
    public var compressorRatio = 4.0
    public var peakLimitDB = -1.0
    public var echoDelay = 0.25
    public var echoDecay = 0.4
    public var repeatCount = 2
    public var generatedDuration = 5.0
    public var toneFrequency = 440.0
    public var metadata: [String: String] = [:]
    public var clearMetadata = false

    public init() {}
}

public struct AudioProcessingRequest: Sendable {
    public let operation: AudioToolOperation
    public let inputURLs: [URL]
    public var options: AudioProcessingOptions

    public init(operation: AudioToolOperation, inputURLs: [URL], options: AudioProcessingOptions = .init()) {
        self.operation = operation
        self.inputURLs = inputURLs
        self.options = options
    }
}

public enum AudioProcessingError: LocalizedError, Equatable, Sendable {
    case missingTools
    case invalidInput(URL)
    case unsupportedInput(URL)
    case noAudio(URL)
    case invalidParameter(String)
    case invalidInputCount
    case invalidTimeRange
    case tooManyOutputs
    case reverseTooLarge
    case stereoRequired
    case outputMatchesInput(URL)
    case outputAlreadyExists(URL)
    case cannotWriteOutput(URL)
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingTools: AppLocalization.text("需要 FFmpeg 与 ffprobe，请安装音频处理组件后重试")
        case .invalidInput(let url): AppLocalization.text("无法访问本地音频文件：%@", url.lastPathComponent)
        case .unsupportedInput(let url): AppLocalization.text("不支持此音频或视频格式：%@", url.lastPathComponent)
        case .noAudio(let url): AppLocalization.text("文件没有可读取的音轨：%@", url.lastPathComponent)
        case .invalidParameter(let title): AppLocalization.text("音频参数无效：%@", AppLocalization.text(title))
        case .invalidInputCount: AppLocalization.text("请选择与当前操作匹配的文件数量，最多 32 个")
        case .invalidTimeRange: AppLocalization.text("时间范围无效，请输入音频时长内的起止时间")
        case .tooManyOutputs: AppLocalization.text("单次最多导出 1000 个片段，请增加分段时长")
        case .reverseTooLarge: AppLocalization.text("倒放最多处理 256 MB 的解码音频，请先裁剪或分段")
        case .stereoRequired: AppLocalization.text("此操作需要立体声音轨")
        case .outputMatchesInput(let url): AppLocalization.text("输出文件不能覆盖输入文件：%@", url.lastPathComponent)
        case .outputAlreadyExists(let url): AppLocalization.text("输出文件已存在，未覆盖：%@", url.lastPathComponent)
        case .cannotWriteOutput(let url): AppLocalization.text("无法写入音频：%@", url.lastPathComponent)
        case .processFailed(let message): AppLocalization.text("音频处理失败：%@", message)
        }
    }
}
