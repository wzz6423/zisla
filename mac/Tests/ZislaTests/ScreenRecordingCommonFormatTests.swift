import AVFoundation
import CoreImage
import Darwin
import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized, .timeLimit(.minutes(2)))
struct ScreenRecordingCommonFormatTests {
    @Test(arguments: [RecordingExportFormat.mov, .m4v], [false, true])
    func nativeContainersPreserveCutsSpeedCropAndAudio(_ format: RecordingExportFormat, _ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        _ = try fixture.createTone()
        var project = fixture.project()
        project.microphoneFile = "tone.wav"
        project.edits.segments = [.init(start: 1, end: 1.5, speed: 2), .init(start: 0, end: 1, speed: 2)]
        project.edits.crop = .init(x: 0, y: 0, width: 0.5, height: 1)
        if multitrack { project.timeline = .migrating(project) }
        let output = fixture.root.appendingPathComponent("native." + format.fileExtension)
        let exporter = ScreenRecordingExporter(resolveFFmpeg: { throw ScreenRecordingExportError.missingFFmpeg })
        try await exporter.export(project: project, directory: fixture.directory, to: output,
            configuration: .init(format: format, resolution: .source, frameRate: 24))
        #expect(!exporter.isExporting && exporter.progress == 1)
        let data = try Data(contentsOf: output)
        #expect(String(decoding: data[4..<8], as: UTF8.self) == "ftyp")
        if format == .mov { #expect(String(decoding: data[8..<12], as: UTF8.self) == "qt  ") }
        if format == .m4v { #expect(String(decoding: data[8..<12], as: UTF8.self) == "M4V ") }
        let asset = AVURLAsset(url: output)
        #expect(abs(try await asset.load(.duration).seconds - 0.75) < 0.03)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await video.load(.naturalSize) == CGSize(width: 32, height: 48))
        #expect(abs(try await video.load(.nominalFrameRate) - 24) < 0.1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        let frames = try await RecordingMultitrackTestFixture.decode(asset)
        #expect(frames.count == 18)
        let first = try RecordingMultitrackTestFixture.pixel(try #require(frames.first).1, x: 16, y: 24)
        let last = try RecordingMultitrackTestFixture.pixel(try #require(frames.last).1, x: 16, y: 24)
        #expect(first[2] > 180 && first[0] < 60)
        #expect(last[0] > 180 && last[2] < 60)
        #expect(try stagingFiles(fixture.root).isEmpty)
    }

    @Test(arguments: [false, true])
    func missingFFmpegKeepsExistingOutputAndDoesNotCommitAReplacement(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        if multitrack { project.timeline = .migrating(project) }
        let output = fixture.root.appendingPathComponent("old.mkv")
        try Data([7, 8]).write(to: output)
        let exporter = ScreenRecordingExporter(resolveFFmpeg: { throw ScreenRecordingExportError.missingFFmpeg })
        await #expect(throws: ScreenRecordingExportError.missingFFmpeg) {
            try await exporter.export(project: project, directory: fixture.directory, to: output,
                configuration: .init(format: .mkv, resolution: .source))
        }
        #expect(try Data(contentsOf: output) == Data([7, 8]))
        #expect(!exporter.isExporting && exporter.progress < 1)
        #expect(try stagingFiles(fixture.root).isEmpty)
    }

    @Test func resolverRejectsUntrustedAndMissingExecutablesAndSelectsTheManagedTool() throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let managed = fixture.root.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
        let executable = managed.appendingPathComponent("ffmpeg")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        #expect(try ScreenRecordingFFmpegTranscoder.resolveExecutable(bundle: fixture.root,
            managedTools: managed, candidates: []) == executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o702], ofItemAtPath: executable.path)
        #expect(throws: ScreenRecordingExportError.missingFFmpeg) {
            try ScreenRecordingFFmpegTranscoder.resolveExecutable(bundle: fixture.root, managedTools: managed, candidates: [])
        }
        try FileManager.default.removeItem(at: executable)
        #expect(throws: ScreenRecordingExportError.missingFFmpeg) {
            try ScreenRecordingFFmpegTranscoder.resolveExecutable(bundle: fixture.root, managedTools: managed, candidates: [])
        }
    }

    @Test(arguments: RecordingExportFormat.allCases.filter { $0.isVideo && $0.requiresFFmpeg })
    func transcoderArgumentsUseOnlyTheRenderedFileAndCannotInterpretNamesAsCommands(_ format: RecordingExportFormat) throws {
        let input = URL(fileURLWithPath: "/private/rendered '-i http://example.invalid;$(touch bad).mp4")
        let output = URL(fileURLWithPath: "/private/final --help." + format.fileExtension)
        let progress = URL(fileURLWithPath: "/private/progress.txt")
        let arguments = try ScreenRecordingFFmpegTranscoder.arguments(input: input, output: output, format: format, progress: progress)
        #expect(arguments.last == output.path)
        #expect(arguments.filter { $0 == input.path }.count == 1)
        #expect(arguments.filter { $0 == "-i" }.count == 1)
        #expect(arguments.contains("-nostdin"))
        #expect(arguments[try #require(arguments.firstIndex(of: "-protocol_whitelist")) + 1] == "file")
        #expect(arguments[try #require(arguments.firstIndex(of: "-i")) - 1] == "mov")
        #expect(arguments.contains("0:a:0?"), "Silent renders must remain valid optional-audio exports")
    }

    @Test func progressParsingBoundsFiniteTimestampsAndUsesTheLatestCompleteReport() {
        #expect(ScreenRecordingFFmpegTranscoder.progressFraction(Data("out_time_us=250000\nprogress=continue\n".utf8), duration: 1) == 0.25)
        #expect(ScreenRecordingFFmpegTranscoder.progressFraction(Data("out_time_us=-1\nout_time_us=400000\nout_time_us=200000\n".utf8), duration: 1) == 0.4)
        #expect(ScreenRecordingFFmpegTranscoder.progressFraction(Data("out_time_us=2000000\n".utf8), duration: 1) == 1)
        #expect(ScreenRecordingFFmpegTranscoder.progressFraction(Data("out_time_us=nan\nout_time_us=inf\nmalformed\n".utf8), duration: 1) == nil)
        #expect(ScreenRecordingFFmpegTranscoder.progressFraction(Data(), duration: 1) == nil)
        var seed: UInt64 = 81
        for _ in 0..<256 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let value = Int64(bitPattern: seed) % 10_000_000
            let data = Data("out_time_us=\(value)\nprogress=continue\n".utf8)
            let fraction = ScreenRecordingFFmpegTranscoder.progressFraction(data, duration: 2)
            #expect(fraction == min(1, max(0, Double(value) / 2_000_000)))
        }
    }

    @Test func transcodeReportsMonotonicProgressAndRemovesItsOwnProgressFile() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let script = fixture.root.appendingPathComponent("ffmpeg-progress")
        let body = """
        #!/bin/sh
        preceding=''
        for arg; do
            if [ "$preceding" = '-progress' ]; then progress="$arg"; fi
            preceding="$arg"
            target="$arg"
        done
        printf 'out_time_us=250000\nprogress=continue\n' > "$progress"
        /bin/sleep 0.15
        printf 'out_time_us=100000\nprogress=continue\n' >> "$progress"
        /bin/sleep 0.15
        printf 'out_time_us=750000\nprogress=continue\n' >> "$progress"
        /bin/sleep 0.15
        printf complete > "$target"
        """
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let output = fixture.root.appendingPathComponent("synthetic.mkv")
        let input = fixture.root.appendingPathComponent("rendered.mp4")
        try Data([1]).write(to: input)
        let fractions = FractionCollector()
        try await ScreenRecordingFFmpegTranscoder.run(input: input, output: output, format: .mkv, duration: 1,
            executable: script, checkpoint: { _ in }) { await fractions.append($0) }
        let values = await fractions.values
        #expect(values == values.sorted())
        #expect(values.contains(0.25) && values.contains(0.75) && values.last == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).allSatisfy { !$0.hasPrefix("ffmpeg-progress-") })
    }

    @Test(arguments: [false, true])
    func aSuccessfulProcessCannotCommitAnEmptyOutputOrSymlink(_ symlink: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        let output = fixture.root.appendingPathComponent("preserved.mkv")
        try Data([6, 5]).write(to: output)
        let script = fixture.root.appendingPathComponent("ffmpeg-invalid")
        let creation = symlink ? "/bin/ln -s '\(output.path)' \"$target\"" : ": > \"$target\""
        try Data(("#!/bin/sh\nfor arg; do target=\"$arg\"; done\n" + creation + "\nexit 0\n").utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let exporter = ScreenRecordingExporter(resolveFFmpeg: { script })
        await #expect(throws: ScreenRecordingExportError.transcodingFailure) {
            try await exporter.export(project: fixture.project(), directory: fixture.directory, to: output,
                configuration: .init(format: .mkv, resolution: .source, frameRate: 12))
        }
        #expect(try Data(contentsOf: output) == Data([6, 5]))
        #expect(!exporter.isExporting && exporter.progress < 1)
        #expect(try stagingFiles(fixture.root).isEmpty)
    }

    @Test func aMissingOrNonExecutableEncoderFailsWithoutChangingTheTarget() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        let output = fixture.root.appendingPathComponent("preserved.mkv")
        try Data([5]).write(to: output)
        let missing = fixture.root.appendingPathComponent("missing-ffmpeg")
        let exporter = ScreenRecordingExporter(resolveFFmpeg: { missing })
        await #expect(throws: CocoaError.self) {
            try await exporter.export(project: fixture.project(), directory: fixture.directory, to: output,
                configuration: .init(format: .mkv, resolution: .source, frameRate: 12))
        }
        #expect(try Data(contentsOf: output) == Data([5]))
        #expect(!exporter.isExporting && exporter.progress < 1)
        #expect(try stagingFiles(fixture.root).isEmpty)
    }

    @Test(arguments: [false, true])
    func failedSubprocessAndFailureBeforeCommitKeepTheDestinationAndRemoveStaging(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        project.edits.segments = [.init(start: 0, end: 0.25)]
        if multitrack { project.timeline = .migrating(project) }
        let script = fixture.root.appendingPathComponent("ffmpeg-failure")
        try Data("#!/bin/sh\nfor arg; do target=\"$arg\"; done\nprintf partial > \"$target\"\nexit 1\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let output = fixture.root.appendingPathComponent("preserved.mkv")
        try Data([4, 2]).write(to: output)
        let exporter = ScreenRecordingExporter(resolveFFmpeg: { script })
        await #expect(throws: ScreenRecordingExportError.transcodingFailure) {
            try await exporter.export(project: project, directory: fixture.directory, to: output,
                configuration: .init(format: .mkv, resolution: .source, frameRate: 12))
        }
        #expect(try Data(contentsOf: output) == Data([4, 2]))
        #expect(try stagingFiles(fixture.root).isEmpty)
        #expect(!exporter.isExporting && exporter.progress < 1)
        let cancelled = ScreenRecordingExporter(resolveFFmpeg: { script }, checkpoint: {
            if $0 == .beforeTranscode { throw CancellationError() }
        })
        await #expect(throws: CancellationError.self) {
            try await cancelled.export(project: project, directory: fixture.directory, to: output,
                configuration: .init(format: .mkv, resolution: .source, frameRate: 12))
        }
        #expect(try Data(contentsOf: output) == Data([4, 2]))
        #expect(try stagingFiles(fixture.root).isEmpty)
    }

    @Test(arguments: [false, true])
    func cancellingTheExternalEncoderStopsItsOwnedProcessAndPreservesTheTarget(_ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        project.edits.segments = [.init(start: 0, end: 0.25)]
        if multitrack { project.timeline = .migrating(project) }
        let pidFile = fixture.root.appendingPathComponent("encoder.pid")
        let gate = fixture.root.appendingPathComponent("encoder.gate")
        #expect(mkfifo(gate.path, 0o600) == 0)
        let script = fixture.root.appendingPathComponent("ffmpeg-gated")
        let body = """
        #!/bin/sh
        trap 'exit 143' TERM
        for arg; do target="$arg"; done
        printf partial > "$target"
        printf '%s' "$$" > '\(pidFile.path)'
        read -r line < '\(gate.path)'
        """
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let output = fixture.root.appendingPathComponent("preserved.mkv")
        try Data([1, 2, 3]).write(to: output)
        let exporter = ScreenRecordingExporter(resolveFFmpeg: { script })
        let task = Task {
            try await exporter.export(project: project, directory: fixture.directory, to: output,
                configuration: .init(format: .mkv, resolution: .source, frameRate: 12))
        }
        let deadline = ContinuousClock.now + .seconds(15)
        while !FileManager.default.fileExists(atPath: pidFile.path) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)))
        exporter.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Darwin.kill(pid, 0) == -1 && errno == ESRCH, "The export-owned encoder must exit before cleanup completes")
        #expect(try Data(contentsOf: output) == Data([1, 2, 3]))
        #expect(!exporter.isExporting && exporter.progress < 1)
        #expect(try stagingFiles(fixture.root).isEmpty)
    }

    private func stagingFiles(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".zisla-recording-export-") }
    }

    private actor FractionCollector {
        var values: [Double] = []
        func append(_ value: Double) { values.append(value) }
    }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(2)), .enabled(if: ProcessInfo.processInfo.environment["ZISLA_RUN_FFMPEG_EXPORT_TESTS"] == "1"))
struct ScreenRecordingCommonFormatIntegrationTests {
    @Test(arguments: RecordingExportFormat.allCases.filter { $0.isVideo && $0.requiresFFmpeg }, [false, true])
    func encodedCommonContainersPreserveTimelineDimensionsAndMixedAudio(_ format: RecordingExportFormat, _ multitrack: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        _ = try fixture.createTone()
        var project = fixture.project()
        project.microphoneFile = "tone.wav"
        project.edits.segments = [.init(start: 1, end: 1.5, speed: 2), .init(start: 0, end: 1, speed: 2)]
        project.edits.crop = .init(x: 0, y: 0, width: 0.5, height: 1)
        if multitrack { project.timeline = .migrating(project) }
        let output = fixture.root.appendingPathComponent("common." + format.fileExtension)
        let executable = try ScreenRecordingFFmpegTranscoder.resolveExecutable()
        let probe = executable.deletingLastPathComponent().appendingPathComponent("ffprobe")
        try #require(YTDLPResolver.isTrustedExecutable(probe))
        let exporter = ScreenRecordingExporter()
        try await exporter.export(project: project, directory: fixture.directory, to: output,
            configuration: .init(format: format, resolution: .source, frameRate: 30))
        let result = try await AIAgentProcessRunner.run(executableURL: probe,
            arguments: ["-v", "error", "-protocol_whitelist", "file", "-show_streams", "-show_format", "-of", "json", output.path],
            timeout: 15, maximumOutputBytes: 32_768, maximumErrorBytes: 8_192)
        #expect(result.status == 0 && !result.didTimeout)
        let json = try #require(JSONSerialization.jsonObject(with: result.standardOutput) as? [String: Any])
        let streams = try #require(json["streams"] as? [[String: Any]])
        let video = try #require(streams.first { $0["codec_type"] as? String == "video" })
        #expect(video["width"] as? Int == 32 && video["height"] as? Int == 48)
        #expect(video["r_frame_rate"] as? String == "30/1")
        let expectedVideo: String = switch format {
        case .mkv, .flv, .ts: "h264"
        case .webm: "vp9"
        case .avi, .threeGP: "mpeg4"
        case .wmv: "wmv2"
        case .mpeg: "mpeg2video"
        default: ""
        }
        #expect(video["codec_name"] as? String == expectedVideo)
        let audio = try #require(streams.first { $0["codec_type"] as? String == "audio" })
        #expect(audio["sample_rate"] as? String == "48000")
        let container = try #require(json["format"] as? [String: Any])
        let containerName = try #require(container["format_name"] as? String)
        let expectedContainer: String = switch format {
        case .mkv, .webm: "matroska"
        case .avi: "avi"
        case .wmv: "asf"
        case .flv: "flv"
        case .mpeg: "mpeg"
        case .ts: "mpegts"
        case .threeGP: "3gp"
        default: ""
        }
        #expect(containerName.split(separator: ",").contains(Substring(expectedContainer)))
        let durationString = try #require(container["duration"] as? String)
        let duration = try #require(Double(durationString))
        #expect(abs(duration - 0.75) < 0.15)
        for (time, blue) in [(0.1, true), (0.5, false)] {
            let decode = try await AIAgentProcessRunner.run(executableURL: executable,
                arguments: ["-v", "error", "-protocol_whitelist", "file,pipe", "-i", output.path,
                            "-ss", String(time), "-map", "0:v:0", "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"],
                timeout: 15, maximumOutputBytes: 32 * 48 * 3 + 1, maximumErrorBytes: 8_192)
            #expect(decode.status == 0 && decode.standardOutput.count == 32 * 48 * 3)
            let offset = (24 * 32 + 16) * 3
            #expect(decode.standardOutput[offset + (blue ? 2 : 0)] > 170)
            #expect(decode.standardOutput[offset + (blue ? 0 : 2)] < 75)
        }
        #expect(!exporter.isExporting && exporter.progress == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).allSatisfy { !$0.hasPrefix(".zisla-recording-export-") })
    }
}
