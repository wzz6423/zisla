import Foundation

public enum DownloadMode: String, Codable, Sendable {
    case video
    case audio
}

public enum DownloadBrowserCookieSource: String, CaseIterable, Codable, Hashable, Sendable {
    case safari
    case chrome
    case firefox
}

public struct DownloadFormatSelection: Equatable, Hashable, Sendable {
    public let formatID: String
    public let audioFormatID: String?

    public init?(formatID: String, audioFormatID: String? = nil) {
        guard Self.isSafeFormatID(formatID),
              audioFormatID.map(Self.isSafeFormatID) ?? true else {
            return nil
        }
        self.formatID = formatID
        self.audioFormatID = audioFormatID
    }

    public var ytDLPExpression: String {
        guard let audioFormatID else { return formatID }
        return "\(formatID)+\(audioFormatID)"
    }

    static func isSafeFormatID(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("-") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

public struct DownloadFormat: Decodable, Equatable, Hashable, Sendable, Identifiable {
    public let formatID: String
    public let fileExtension: String?
    public let width: Int?
    public let height: Int?
    public let fps: Double?
    public let videoCodec: String?
    public let audioCodec: String?
    public let totalBitrate: Double?
    public let audioBitrate: Double?
    public let fileSize: Double?
    public let approximateFileSize: Double?
    public let dynamicRange: String?

    public init(
        formatID: String,
        fileExtension: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        fps: Double? = nil,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        totalBitrate: Double? = nil,
        audioBitrate: Double? = nil,
        fileSize: Double? = nil,
        approximateFileSize: Double? = nil,
        dynamicRange: String? = nil
    ) {
        self.formatID = formatID
        self.fileExtension = fileExtension
        self.width = width
        self.height = height
        self.fps = fps
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.totalBitrate = totalBitrate
        self.audioBitrate = audioBitrate
        self.fileSize = fileSize
        self.approximateFileSize = approximateFileSize
        self.dynamicRange = dynamicRange
    }

    public var id: String { formatID }

    public var hasVideo: Bool { hasCodec(videoCodec) }
    public var hasAudio: Bool { hasCodec(audioCodec) }
    public var estimatedFileSize: Double? { fileSize ?? approximateFileSize }

    public var resolution: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width)×\(height)"
    }

    private enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case fileExtension = "ext"
        case width, height, fps
        case videoCodec = "vcodec"
        case audioCodec = "acodec"
        case totalBitrate = "tbr"
        case audioBitrate = "abr"
        case fileSize = "filesize"
        case approximateFileSize = "filesize_approx"
        case dynamicRange = "dynamic_range"
    }

    private func hasCodec(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && normalized != "none"
    }
}

public struct DownloadFormatOption: Equatable, Hashable, Sendable, Identifiable {
    public let format: DownloadFormat
    public let audioCompanion: DownloadFormat?
    public let selection: DownloadFormatSelection

    public init?(
        format: DownloadFormat,
        audioCompanion: DownloadFormat? = nil
    ) {
        guard let selection = DownloadFormatSelection(
            formatID: format.formatID,
            audioFormatID: audioCompanion?.formatID
        ) else {
            return nil
        }
        self.format = format
        self.audioCompanion = audioCompanion
        self.selection = selection
    }

    public var id: String { selection.ytDLPExpression }
}

public enum DownloadFormatCatalog {
    public static func options(
        for mode: DownloadMode,
        formats: [DownloadFormat]
    ) -> [DownloadFormatOption] {
        let safeFormats = formats.filter { DownloadFormatSelection.isSafeFormatID($0.formatID) }
        switch mode {
        case .video:
            let audioCompanion = safeFormats
                .filter { $0.hasAudio && !$0.hasVideo }
                .sorted(by: audioOrder)
                .first
            return safeFormats
                .filter(\.hasVideo)
                .compactMap { format in
                    guard format.hasAudio || audioCompanion != nil else { return nil }
                    return DownloadFormatOption(
                        format: format,
                        audioCompanion: format.hasAudio ? nil : audioCompanion
                    )
                }
                .sorted(by: videoOrder)
        case .audio:
            let audioOnly = safeFormats.filter { $0.hasAudio && !$0.hasVideo }
            let candidates = audioOnly.isEmpty
                ? safeFormats.filter(\.hasAudio)
                : audioOnly
            return candidates
                .compactMap { DownloadFormatOption(format: $0) }
                .sorted { audioOrder($0.format, $1.format) }
        }
    }

    private static func videoOrder(_ lhs: DownloadFormatOption, _ rhs: DownloadFormatOption) -> Bool {
        videoOrder(lhs.format, rhs.format)
    }

    private static func videoOrder(_ lhs: DownloadFormat, _ rhs: DownloadFormat) -> Bool {
        let lhsPixels = (lhs.width ?? 0) * (lhs.height ?? 0)
        let rhsPixels = (rhs.width ?? 0) * (rhs.height ?? 0)
        if lhsPixels != rhsPixels { return lhsPixels > rhsPixels }
        if lhs.fps != rhs.fps { return (lhs.fps ?? 0) > (rhs.fps ?? 0) }
        if lhs.totalBitrate != rhs.totalBitrate {
            return (lhs.totalBitrate ?? 0) > (rhs.totalBitrate ?? 0)
        }
        return lhs.formatID < rhs.formatID
    }

    private static func audioOrder(_ lhs: DownloadFormat, _ rhs: DownloadFormat) -> Bool {
        if lhs.audioBitrate != rhs.audioBitrate {
            return (lhs.audioBitrate ?? 0) > (rhs.audioBitrate ?? 0)
        }
        if lhs.totalBitrate != rhs.totalBitrate {
            return (lhs.totalBitrate ?? 0) > (rhs.totalBitrate ?? 0)
        }
        return lhs.formatID < rhs.formatID
    }
}

public struct DownloadFormatProbeResult: Equatable, Sendable {
    public let title: String?
    public let formats: [DownloadFormat]
    public let canSelectFormats: Bool

    public init(
        title: String?,
        formats: [DownloadFormat],
        canSelectFormats: Bool = true
    ) {
        self.title = title
        self.formats = formats
        self.canSelectFormats = canSelectFormats
    }
}

public enum DownloadFormatProbeError: Error, Equatable, Sendable {
    case invalidResponse
}

public enum DownloadFormatProbe {
    public static func arguments(
        urlString: String,
        browserCookieSource: DownloadBrowserCookieSource?
    ) -> [String] {
        var arguments = [
            "--ignore-config",
            "--no-plugin-dirs",
            "--no-playlist",
            "--skip-download",
            "--dump-single-json",
            "--no-warnings",
        ]
        if let browserCookieSource {
            arguments += ["--cookies-from-browser", browserCookieSource.rawValue]
        }
        arguments += ["--", urlString]
        return arguments
    }

    public static func result(from output: String) throws -> DownloadFormatProbeResult {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = (try? JSONDecoder().decode(Response.self, from: Data(trimmedOutput.utf8)))
            ?? output.split(whereSeparator: \.isNewline)
                .reversed()
                .compactMap { line in
                    try? JSONDecoder().decode(Response.self, from: Data(line.utf8))
                }
                .first
        guard let response else {
            throw DownloadFormatProbeError.invalidResponse
        }
        return DownloadFormatProbeResult(
            title: response.title,
            formats: response.formats.filter { $0.hasVideo || $0.hasAudio },
            canSelectFormats: true
        )
    }

    private struct Response: Decodable {
        let title: String?
        let formats: [DownloadFormat]
    }
}

public enum DownloadRequestError: Error, Equatable, Sendable {
    case unsupportedURL
    case invalidOutputDirectory
}

public struct DownloadRequest: Equatable, Sendable {
    public static var defaultOutputDirectory: URL {
        let fileManager = FileManager.default
        return (fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true))
            .standardizedFileURL
    }

    public let urlString: String
    public let mode: DownloadMode
    public let outputDirectory: URL
    public let formatSelection: DownloadFormatSelection?
    public let browserCookieSource: DownloadBrowserCookieSource?

    public init(
        urlString: String,
        mode: DownloadMode,
        outputDirectory: URL? = nil,
        formatSelection: DownloadFormatSelection? = nil,
        browserCookieSource: DownloadBrowserCookieSource? = nil
    ) throws {
        guard
            let url = HTTPURLParser.url(from: urlString)
        else {
            throw DownloadRequestError.unsupportedURL
        }

        let destination = outputDirectory ?? Self.defaultOutputDirectory
        guard destination.isFileURL else {
            throw DownloadRequestError.invalidOutputDirectory
        }

        self.urlString = url.absoluteString
        self.mode = mode
        self.outputDirectory = destination.standardizedFileURL
        self.formatSelection = formatSelection
        self.browserCookieSource = browserCookieSource
    }
}

public struct DownloadCapabilities: Equatable, Sendable {
    public var hasFFmpeg: Bool

    public init(hasFFmpeg: Bool) {
        self.hasFFmpeg = hasFFmpeg
    }
}

public enum DownloadExecutionStrategy: Equatable, Sendable {
    case direct
    case nativePackaging
}

public enum YTDLPArgumentBuilder {
    public static func strategy(
        for request: DownloadRequest,
        capabilities: DownloadCapabilities
    ) -> DownloadExecutionStrategy {
        request.mode == .video && !capabilities.hasFFmpeg ? .nativePackaging : .direct
    }

    public static func arguments(
        for request: DownloadRequest,
        capabilities: DownloadCapabilities,
        taskTemporaryDirectory: URL? = nil,
        ffmpegExecutableURL: URL? = nil
    ) -> [String] {
        let temporaryDirectory = (taskTemporaryDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("ZislaDownload-\(UUID().uuidString)", isDirectory: true))
            .standardizedFileURL
        let strategy = strategy(for: request, capabilities: capabilities)
        let outputDirectory = strategy == .nativePackaging
            ? temporaryDirectory
            : request.outputDirectory
        let outputTemplate = strategy == .nativePackaging
            ? "%(title)s [%(id)s].%(format_id)s.%(ext)s"
            : "%(title)s [%(id)s].%(ext)s"
        var arguments = [
            "--ignore-config",
            "--no-plugin-dirs",
            "--no-exec",
            "--no-playlist",
            "--no-overwrites",
            "--no-color",
            "--newline",
            "--no-simulate",
            "--progress",
            "--paths", "home:\(outputDirectory.path)",
            "--paths", "temp:\(temporaryDirectory.path)",
            "-o", outputTemplate,
        ]

        if let ffmpegExecutableURL, capabilities.hasFFmpeg {
            arguments += ["--ffmpeg-location", ffmpegExecutableURL.standardizedFileURL.path]
        }

        if let browserCookieSource = request.browserCookieSource {
            arguments += ["--cookies-from-browser", browserCookieSource.rawValue]
        }

        let selectedFormat = capabilities.hasFFmpeg ? request.formatSelection : nil

        switch request.mode {
        case .video:
            if capabilities.hasFFmpeg {
                arguments += [
                    "-f", selectedFormat?.ytDLPExpression ?? "bv*+ba/b",
                    "--merge-output-format", "mp4",
                ]
            } else {
                arguments += [
                    "-f",
                    "(bv*[ext=mp4][vcodec^=avc1][acodec=none]/bv*[ext=mp4][acodec=none],ba[ext=m4a][vcodec=none])/b[ext=mp4]/b",
                ]
            }
        case .audio:
            if capabilities.hasFFmpeg {
                arguments += [
                    "-f", selectedFormat?.ytDLPExpression ?? "ba/b",
                    "--extract-audio",
                    "--audio-format", "m4a",
                ]
            } else {
                arguments += ["-f", "ba[ext=m4a]/ba"]
            }
        }

        let completedTemplate: String
        switch strategy {
        case .direct:
            completedTemplate = "after_move:\(YTDLPOutputParser.sentinel){\"event\":\"completed\",\"filepath\":%(filepath)j}"
        case .nativePackaging:
            completedTemplate = "after_move:\(YTDLPOutputParser.sentinel){\"event\":\"component\",\"filepath\":%(filepath)j,\"format_id\":%(format_id)j,\"vcodec\":%(vcodec)j,\"acodec\":%(acodec)j}"
        }
        arguments += [
            "--progress-template",
            "download:\(YTDLPOutputParser.sentinel){\"event\":\"progress\",\"percent\":%(progress._percent_str)j,\"speed\":%(progress._speed_str)j,\"eta\":%(progress._eta_str)j}",
            "--print",
            completedTemplate,
            "--",
            request.urlString,
        ]
        return arguments
    }
}
