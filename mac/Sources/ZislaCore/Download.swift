import Foundation

public enum DownloadMode: String, Codable, Sendable {
    case video
    case audio
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

    public init(
        urlString: String,
        mode: DownloadMode,
        outputDirectory: URL? = nil
    ) throws {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedURL.isEmpty,
            let url = URL(string: trimmedURL),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host?.isEmpty == false
        else {
            throw DownloadRequestError.unsupportedURL
        }

        let destination = outputDirectory ?? Self.defaultOutputDirectory
        guard destination.isFileURL else {
            throw DownloadRequestError.invalidOutputDirectory
        }

        self.urlString = trimmedURL
        self.mode = mode
        self.outputDirectory = destination.standardizedFileURL
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

        switch request.mode {
        case .video:
            if capabilities.hasFFmpeg {
                arguments += [
                    "-f", "bv*+ba/b",
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
                    "-f", "ba/b",
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
