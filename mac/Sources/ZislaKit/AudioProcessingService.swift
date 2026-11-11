import Darwin
import Foundation
import ZislaCore

public struct AudioProcessingTools: Equatable, Sendable {
    public let ffmpeg: URL
    public let ffprobe: URL

    public init(ffmpeg: URL, ffprobe: URL) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
    }
}

public struct AudioProcessingService: Sendable {
    typealias Runner = @Sendable (URL, [String]) async throws -> AIAgentProcessOutput
    private let tools: @Sendable () throws -> AudioProcessingTools
    private let run: Runner

    public init() {
        self.init(tools: { try Self.resolveTools() }, run: Self.runProcess)
    }

    init(tools: @escaping @Sendable () throws -> AudioProcessingTools, run: @escaping Runner) {
        self.tools = tools
        self.run = run
    }

    public static func resolveTools(
        bundle: URL = Bundle.main.bundleURL,
        managedTools: URL = AppPaths.managedTools,
        candidates: [URL] = YTDLPResolver.defaultFFmpegCandidates
    ) throws -> AudioProcessingTools {
        let candidates = [managedTools.appendingPathComponent("ffmpeg"),
                          bundle.appendingPathComponent("Contents/Helpers/ffmpeg")] + candidates
        guard let ffmpeg = candidates.first(where: YTDLPResolver.isTrustedExecutable) else {
            throw AudioProcessingError.missingTools
        }
        let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard YTDLPResolver.isTrustedExecutable(ffprobe) else { throw AudioProcessingError.missingTools }
        return AudioProcessingTools(ffmpeg: ffmpeg.resolvingSymlinksInPath(), ffprobe: ffprobe.resolvingSymlinksInPath())
    }

    public func inspect(_ input: URL) async throws -> AudioFileSummary {
        try await inspect(input, tools: tools())
    }

    public func process(
        _ request: AudioProcessingRequest,
        outputURL: URL,
        progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async throws -> [URL] {
        try Task.checkCancellation()
        try validateInputCount(request)
        let tools = try tools()
        var summaries: [AudioFileSummary] = []
        for input in request.inputURLs { summaries.append(try await inspect(input, tools: tools)) }
        try validateOptions(request, summaries: summaries)
        let jobs = try jobs(request, summaries: summaries, output: outputURL)
        let directory = outputURL.deletingLastPathComponent()
        let outputDirectory = request.operation.exportsToDirectory(inputCount: request.inputURLs.count) ? outputURL : directory
        let inputs = Set(request.inputURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath() })
        for job in jobs {
            let destination = job.output.standardizedFileURL.resolvingSymlinksInPath()
            guard !inputs.contains(destination) else { throw AudioProcessingError.outputMatchesInput(job.output) }
            guard !Self.outputExists(job.output) else { throw AudioProcessingError.outputAlreadyExists(job.output) }
        }

        let staging = outputDirectory.appendingPathComponent(".zisla-audio-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false) }
        catch { throw AudioProcessingError.cannotWriteOutput(outputURL) }
        var published: [URL] = []
        var committed = false
        defer {
            if !committed {
                for output in published { try? FileManager.default.removeItem(at: output) }
            }
            try? FileManager.default.removeItem(at: staging)
        }

        var staged: [URL] = []
        for (index, job) in jobs.enumerated() {
            try Task.checkCancellation()
            let temporary = staging.appendingPathComponent("\(index).\(request.options.format.fileExtension)")
            let result = try await run(tools.ffmpeg, arguments(request, job: job, summaries: summaries, output: temporary))
            try Task.checkCancellation()
            guard result.status == 0 else { throw AudioProcessingError.processFailed(result.standardError) }
            // Probe the staged result before publishing, including successful encodes that contain no audio.
            _ = try await inspect(temporary, tools: tools)
            staged.append(temporary)
            await progress(index + 1, jobs.count)
        }
        for (index, job) in jobs.enumerated() {
            try Task.checkCancellation()
            // Exclusive rename also supports volumes without hard links and preserves destinations created after the preflight.
            guard Darwin.renamex_np(staged[index].path, job.output.path, UInt32(RENAME_EXCL)) == 0 else {
                if errno == EEXIST { throw AudioProcessingError.outputAlreadyExists(job.output) }
                throw AudioProcessingError.cannotWriteOutput(job.output)
            }
            published.append(job.output)
        }
        try Task.checkCancellation()
        committed = true
        return published
    }

    static func runProcess(_ executable: URL, _ arguments: [String]) async throws -> AIAgentProcessOutput {
        try await AIAgentProcessRunner.run(
            executableURL: executable, arguments: arguments, standardInput: Data(),
            environment: ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") },
            timeout: nil, maximumOutputBytes: 65_536, maximumErrorBytes: 8_192
        )
    }

    private struct Probe: Decodable {
        struct Stream: Decodable {
            let codec_name: String
            let sample_rate: String
            let channels: Int
            let duration: String?
        }
        struct Format: Decodable {
            let duration: String?
            let tags: [String: String]?
        }
        let streams: [Stream]
        let format: Format?
    }

    private func inspect(_ input: URL, tools: AudioProcessingTools) async throws -> AudioFileSummary {
        try Task.checkCancellation()
        guard input.isFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: input.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              FileManager.default.isReadableFile(atPath: input.path)
        else { throw AudioProcessingError.invalidInput(input) }
        let format = try Self.inputFormat(input)
        let result = try await run(tools.ffprobe, [
            "-v", "error", "-protocol_whitelist", "file", "-f", format, "-i", input.path,
            "-select_streams", "a:0", "-show_entries",
            "stream=codec_name,sample_rate,channels,duration:format=duration:format_tags", "-of", "json",
        ])
        try Task.checkCancellation()
        guard result.status == 0,
              let probe = try? JSONDecoder().decode(Probe.self, from: result.standardOutput),
              let stream = probe.streams.first,
              let rate = Int(stream.sample_rate), rate > 0,
              (1...32).contains(stream.channels),
              let duration = Double(stream.duration ?? probe.format?.duration ?? ""), duration.isFinite, duration > 0
        else { throw AudioProcessingError.noAudio(input) }
        return AudioFileSummary(duration: duration, sampleRate: rate, channels: stream.channels, codec: stream.codec_name,
                                fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                                metadata: probe.format?.tags ?? [:])
    }

    static func inputFormat(_ input: URL) throws -> String {
        switch input.pathExtension.lowercased() {
        case "mp3": "mp3"
        case "wav": "wav"
        case "aif", "aiff": "aiff"
        case "flac": "flac"
        case "m4a", "m4b", "m4v", "mp4", "mov", "3gp": "mov"
        case "aac": "aac"
        case "ogg", "oga", "opus": "ogg"
        case "caf": "caf"
        case "wma", "wmv", "asf": "asf"
        case "mkv", "webm": "matroska"
        case "avi": "avi"
        case "flv": "flv"
        case "mpg", "mpeg": "mpeg"
        case "ts": "mpegts"
        case "ac3": "ac3"
        case "eac3": "eac3"
        default: throw AudioProcessingError.unsupportedInput(input)
        }
    }

    private static func outputExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
            || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func validateInputCount(_ request: AudioProcessingRequest) throws {
        let count = request.inputURLs.count
        if request.operation.generatesAudio {
            guard count == 0 else { throw AudioProcessingError.invalidInputCount }
        } else if request.operation.requiresMultipleInputs {
            guard (2...32).contains(count) else { throw AudioProcessingError.invalidInputCount }
        } else if request.operation.allowsMultipleInputs {
            guard (1...32).contains(count) else { throw AudioProcessingError.invalidInputCount }
        } else {
            guard count == 1 else { throw AudioProcessingError.invalidInputCount }
        }
    }

    private func validateOptions(_ request: AudioProcessingRequest, summaries: [AudioFileSummary]) throws {
        let options = request.options
        if options.format == .ogg {
            guard request.operation.exportFormats.contains(.ogg),
                  ![AudioChannelMode.mono, .left, .right].contains(options.channelMode)
            else { throw AudioProcessingError.invalidParameter("输出格式") }
        }
        func check(_ value: Double, _ range: ClosedRange<Double>, _ title: String) throws {
            guard value.isFinite, range.contains(value) else { throw AudioProcessingError.invalidParameter(title) }
        }
        guard options.format.sampleRates.contains(options.sampleRate) else { throw AudioProcessingError.invalidParameter("采样率") }
        if !options.format.isLossless {
            guard (32...320).contains(options.bitrateKbps) else { throw AudioProcessingError.invalidParameter("码率") }
        } else {
            let depths = [.flac, .alac].contains(options.format) ? [16, 24] : [16, 24, 32]
            guard depths.contains(options.bitDepth) else { throw AudioProcessingError.invalidParameter("位深") }
        }
        if options.channelMode == .right || options.channelMode == .swap || request.operation == .vocalReduction {
            guard summaries.allSatisfy({ $0.channels == 2 }) else { throw AudioProcessingError.stereoRequired }
        }
        let duration = summaries.first?.duration ?? options.generatedDuration
        switch request.operation {
        case .trim, .removeSegment:
            guard options.startTime.isFinite, let end = options.endTime, end.isFinite,
                  options.startTime >= 0, options.startTime < end, end <= duration,
                  request.operation != .removeSegment || options.startTime > 0 || end < duration
            else { throw AudioProcessingError.invalidTimeRange }
        case .split: try check(options.segmentDuration, 0.01...86_400, "分段时长（秒）")
        case .volume: try check(options.volumeDB, -96...24, "音量（dB）")
        case .normalize: try check(options.targetLoudness, -36 ... -5, "目标响度（LUFS）")
        case .fade:
            try check(options.fadeInDuration, 0...duration, "淡入（秒）")
            try check(options.fadeOutDuration, 0...duration, "淡出（秒）")
            guard options.fadeInDuration + options.fadeOutDuration <= duration,
                  options.fadeInDuration + options.fadeOutDuration > 0 else { throw AudioProcessingError.invalidTimeRange }
        case .speed: try check(options.speed, 0.25...4, "速度倍数")
        case .pitch: try check(options.pitchSemitones, -12...12, "音高（半音）")
        case .reverse:
            guard duration * Double(summaries[0].sampleRate) * Double(summaries[0].channels) * 8 <= 256 * 1_024 * 1_024
            else { throw AudioProcessingError.reverseTooLarge }
        case .denoise: try check(options.noiseReductionDB, 0.01...40, "降噪强度（dB）")
        case .removeSilence:
            try check(options.silenceThresholdDB, -80 ... -10, "静音阈值（dB）")
            try check(options.silenceDuration, 0.01...10, "最短静音（秒）")
        case .equalizer:
            try check(options.bassDB, -20...20, "低频（dB）")
            try check(options.midDB, -20...20, "中频（dB）")
            try check(options.trebleDB, -20...20, "高频（dB）")
        case .dynamics:
            try check(options.compressorThresholdDB, -60...0, "压缩阈值（dB）")
            try check(options.compressorRatio, 1...20, "压缩比")
            try check(options.peakLimitDB, -24...0, "峰值上限（dB）")
        case .echo:
            try check(options.echoDelay, 0.001...2, "回声延迟（秒）")
            try check(options.echoDecay, 0.01...0.9, "回声衰减")
        case .repeatAudio:
            guard (2...100).contains(options.repeatCount) else { throw AudioProcessingError.invalidParameter("重复次数") }
        case .insertSilence:
            guard options.startTime.isFinite, (0...duration).contains(options.startTime) else { throw AudioProcessingError.invalidTimeRange }
            try check(options.generatedDuration, 0.01...86_400, "静音时长（秒）")
        case .generateSilence, .generateTone:
            try check(options.generatedDuration, 0.01...86_400, "生成时长（秒）")
            if request.operation == .generateTone { try check(options.toneFrequency, 20...Double(options.sampleRate) / 2, "频率（Hz）") }
        case .compress:
            guard !options.format.isLossless else { throw AudioProcessingError.invalidParameter("输出格式") }
        case .metadata:
            guard options.metadata.keys.allSatisfy({ ["title", "artist", "album", "comment"].contains($0) }),
                  options.metadata.values.allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 4_096 })
            else { throw AudioProcessingError.invalidParameter("音频标签") }
        default: break
        }
    }

    private struct Job {
        let inputIndexes: [Int]
        let output: URL
        var start: Double?
        var duration: Double?
        var channel: Int?
    }

    private func jobs(_ request: AudioProcessingRequest, summaries: [AudioFileSummary], output: URL) throws -> [Job] {
        let operation = request.operation
        let suffix = request.options.format.fileExtension
        switch operation {
        case .split:
            let frames = (summaries[0].duration * Double(summaries[0].sampleRate)).rounded()
            let framesPerSegment = (request.options.segmentDuration * Double(summaries[0].sampleRate)).rounded()
            let count = ceil(frames / framesPerSegment)
            guard count <= 1_000 else { throw AudioProcessingError.tooManyOutputs }
            let name = request.inputURLs[0].deletingPathExtension().lastPathComponent
            return (0..<Int(count)).map { index in
                let startFrame = Double(index) * framesPerSegment
                let start = startFrame / Double(summaries[0].sampleRate)
                return Job(inputIndexes: [0], output: output.appendingPathComponent("\(name)-\(String(format: "%03d", index + 1)).\(suffix)"),
                           start: start, duration: min(framesPerSegment, frames - startFrame) / Double(summaries[0].sampleRate))
            }
        case .splitChannels:
            let name = request.inputURLs[0].deletingPathExtension().lastPathComponent
            return (0..<summaries[0].channels).map {
                Job(inputIndexes: [0], output: output.appendingPathComponent("\(name)-ch\($0 + 1).\(suffix)"), channel: $0)
            }
        default:
            if operation.exportsToDirectory(inputCount: request.inputURLs.count) {
                return request.inputURLs.enumerated().map { index, input in
                    Job(inputIndexes: [index], output: output.appendingPathComponent("\(index + 1)-\(input.deletingPathExtension().lastPathComponent).\(suffix)"))
                }
            }
            return [Job(inputIndexes: Array(request.inputURLs.indices), output: output)]
        }
    }

    private func arguments(_ request: AudioProcessingRequest, job: Job, summaries: [AudioFileSummary], output: URL) throws -> [String] {
        let options = request.options
        let operation = request.operation
        let rate = options.sampleRate
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-filter_threads", "2", "-filter_complex_threads", "2"]
        if operation.generatesAudio {
            let generator = operation == .generateSilence
                ? "anullsrc=r=\(rate):cl=stereo:d=\(options.generatedDuration)"
                : "sine=frequency=\(options.toneFrequency):sample_rate=\(rate):duration=\(options.generatedDuration)"
            args += ["-f", "lavfi", "-i", generator]
        } else {
            for index in job.inputIndexes {
                if operation == .repeatAudio { args += ["-stream_loop", String(options.repeatCount - 1)] }
                args += ["-protocol_whitelist", "file", "-f", try Self.inputFormat(request.inputURLs[index]), "-i", request.inputURLs[index].path]
            }
        }
        var filters: [String] = []
        var graph: String?
        let duration = summaries.first?.duration ?? options.generatedDuration
        switch operation {
        case .trim: filters.append("atrim=start=\(options.startTime):end=\(options.endTime!),asetpts=PTS-STARTPTS")
        case .split: filters.append("atrim=start=\(job.start!):duration=\(job.duration!),asetpts=PTS-STARTPTS")
        case .removeSegment:
            graph = "[0:a:0]asplit=2[a][b];[a]atrim=end=\(options.startTime),asetpts=PTS-STARTPTS[x];[b]atrim=start=\(options.endTime!),asetpts=PTS-STARTPTS[y];[x][y]concat=n=2:v=0:a=1[edited]"
        case .insertSilence:
            let channels = summaries[0].channels
            graph = "[0:a:0]asplit=2[a][b];[a]atrim=end=\(options.startTime),asetpts=PTS-STARTPTS[x];[b]atrim=start=\(options.startTime),asetpts=PTS-STARTPTS[y];anullsrc=r=\(summaries[0].sampleRate):cl=\(channels)c:d=\(options.generatedDuration)[s];[x][s][y]concat=n=3:v=0:a=1[edited]"
        case .merge, .mix:
            let count = job.inputIndexes.count
            graph = (0..<count).map { index in
                let mono = summaries[index].channels == 1 ? "pan=stereo|c0=c0|c1=c0," : ""
                return "[\(index):a:0]" + mono + "aresample=\(rate),aformat=sample_fmts=fltp:channel_layouts=stereo,asetpts=PTS-STARTPTS[a\(index)]"
            }.joined(separator: ";")
            let labels = (0..<count).map { "[a\($0)]" }.joined()
            graph! += ";" + labels + (operation == .merge ? "concat=n=\(count):v=0:a=1" : "amix=inputs=\(count):duration=longest:dropout_transition=0:normalize=1") + "[edited]"
        case .volume: filters.append("volume=\(options.volumeDB)dB")
        case .normalize: filters.append("loudnorm=I=\(options.targetLoudness):TP=-1.5:LRA=11")
        case .fade:
            if options.fadeInDuration > 0 { filters.append("afade=t=in:st=0:d=\(options.fadeInDuration)") }
            if options.fadeOutDuration > 0 { filters.append("afade=t=out:st=\(duration - options.fadeOutDuration):d=\(options.fadeOutDuration)") }
        case .speed: filters += Self.tempoFilters(options.speed)
        case .pitch:
            let factor = pow(2, options.pitchSemitones / 12)
            filters.append("asetrate=\(Double(summaries[0].sampleRate) * factor),aresample=\(summaries[0].sampleRate)")
            filters += Self.tempoFilters(1 / factor)
        case .reverse: filters.append("areverse")
        case .denoise: filters.append("afftdn=nr=\(options.noiseReductionDB):nf=-50:tn=1")
        case .removeSilence:
            filters.append("silenceremove=start_periods=1:start_duration=0:start_threshold=\(options.silenceThresholdDB)dB:stop_periods=-1:stop_duration=\(options.silenceDuration):stop_threshold=\(options.silenceThresholdDB)dB")
        case .equalizer:
            filters += ["bass=g=\(options.bassDB):f=200", "equalizer=f=1000:t=q:w=1:g=\(options.midDB)", "treble=g=\(options.trebleDB):f=4000"]
        case .dynamics:
            filters.append("acompressor=threshold=\(pow(10, options.compressorThresholdDB / 20)):ratio=\(options.compressorRatio):attack=20:release=250")
            filters.append("alimiter=limit=\(pow(10, options.peakLimitDB / 20)):level=0:latency=1")
        case .echo: filters.append("aecho=0.8:0.9:\(options.echoDelay * 1000):\(options.echoDecay)")
        case .splitChannels: filters.append("pan=mono|c0=c\(job.channel!)")
        case .vocalReduction: filters.append("pan=mono|c0=0.5*c0-0.5*c1")
        default: break
        }
        if operation != .splitChannels && operation != .vocalReduction {
            switch options.channelMode {
            case .preserve: break
            case .mono: filters.append("aformat=channel_layouts=mono")
            case .stereo: filters.append("aformat=channel_layouts=stereo")
            case .left: filters.append("pan=mono|c0=c0")
            case .right: filters.append("pan=mono|c0=c1")
            case .swap: filters.append("pan=stereo|c0=c1|c1=c0")
            }
        }
        if let graph {
            args += ["-filter_complex", graph + ";[edited]" + (filters.isEmpty ? "anull" : filters.joined(separator: ",")) + "[out]", "-map", "[out]"]
        } else {
            args += ["-map", "0:a:0"]
            if !filters.isEmpty { args += ["-af", filters.joined(separator: ",")] }
        }
        args += ["-vn", "-sn", "-dn", "-threads", "2", "-ar", String(rate), "-map_metadata", options.clearMetadata ? "-1" : "0"]
        if options.format == .ogg { args += ["-ac", "2"] }
        if operation == .metadata && !options.clearMetadata {
            for key in options.metadata.keys.sorted() { args += ["-metadata", "\(key)=\(options.metadata[key]!)"] }
        }
        args += Self.encoding(options) + [output.path]
        return args
    }

    static func tempoFilters(_ factor: Double) -> [String] {
        if factor < 0.5 { return ["atempo=0.5", "atempo=\(factor / 0.5)"] }
        if factor > 2 { return ["atempo=2", "atempo=\(factor / 2)"] }
        return ["atempo=\(factor)"]
    }

    private static func encoding(_ options: AudioProcessingOptions) -> [String] {
        let codec: String
        let container: String
        switch options.format {
        case .m4a: codec = "aac"; container = "ipod"
        case .mp3: codec = "libmp3lame"; container = "mp3"
        case .wav: codec = "pcm_s\(options.bitDepth)le"; container = "wav"
        case .aiff: codec = "pcm_s\(options.bitDepth)be"; container = "aiff"
        case .flac: codec = "flac"; container = "flac"
        case .alac: codec = "alac"; container = "ipod"
        case .aac: codec = "aac"; container = "adts"
        case .ogg: codec = "vorbis"; container = "ogg"
        case .opus: codec = "libopus"; container = "opus"
        case .caf: codec = "pcm_s\(options.bitDepth)le"; container = "caf"
        case .wma: codec = "wmav2"; container = "asf"
        }
        var args = ["-c:a", codec, "-f", container]
        if options.format == .flac {
            args += ["-sample_fmt", options.bitDepth == 16 ? "s16" : "s32"]
        }
        if options.format == .alac { args += ["-sample_fmt", options.bitDepth == 16 ? "s16p" : "s32p"] }
        if options.format == .ogg { args += ["-strict", "experimental"] }
        if !options.format.isLossless { args += ["-b:a", "\(options.bitrateKbps)k"] }
        return args
    }
}
