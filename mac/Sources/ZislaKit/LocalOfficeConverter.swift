import Foundation
import ZislaCore

public enum LocalOfficeConverterError: LocalizedError, Equatable, Sendable {
    case unsupportedInput(URL)
    case converterNotInstalled
    case outputAlreadyExists(URL)
    case cannotPrepareDirectory(String)
    case launchFailed(String)
    case conversionFailed(String)
    case missingConvertedFile

    public var errorDescription: String? {
        switch self {
        case let .unsupportedInput(url): "不支持的 Office 文件：\(url.lastPathComponent)"
        case .converterNotInstalled: "未找到 LibreOffice；请安装 LibreOffice 后重试"
        case let .outputAlreadyExists(url): "输出文件已存在，未覆盖：\(url.lastPathComponent)"
        case let .cannotPrepareDirectory(message): "无法创建转换目录：\(message)"
        case let .launchFailed(message): "无法启动 LibreOffice：\(message)"
        case let .conversionFailed(message): "LibreOffice 转换失败：\(message)"
        case .missingConvertedFile: "LibreOffice 没有生成 PDF 文件"
        }
    }
}

/// Uses a system LibreOffice installation; never ships a development-environment tool as a release dependency.
public struct LocalOfficeConverter: Sendable {
    public static let supportedExtensions: Set<String> = [
        "doc", "docx", "dot", "dotx", "rtf", "odt",
        "ppt", "pptx", "pps", "ppsx", "odp",
        "xls", "xlsx", "xlsm", "ods", "csv",
    ]

    private let executableCandidates: [URL]

    public init() {
        self.init(executableCandidates: Self.defaultExecutableCandidates)
    }

    public init(executableCandidates: [URL]) {
        self.executableCandidates = executableCandidates
    }

    public func convertToPDF(_ inputURL: URL, outputURL: URL) throws {
        let input = inputURL.standardizedFileURL
        let output = outputURL.standardizedFileURL
        guard Self.supportedExtensions.contains(input.pathExtension.lowercased()),
              FileManager.default.fileExists(atPath: input.path)
        else {
            throw LocalOfficeConverterError.unsupportedInput(input)
        }
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw LocalOfficeConverterError.outputAlreadyExists(output)
        }
        guard let executable = executableCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw LocalOfficeConverterError.converterNotInstalled
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla/OfficeConversion/\(UUID().uuidString)", isDirectory: true)
        let profileDirectory = temporaryDirectory
            .appendingPathComponent("LibreOfficeProfile", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw LocalOfficeConverterError.cannotPrepareDirectory(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let processOutput: AIAgentProcessOutput
        do {
            processOutput = try AIAgentProcessRunner.runSynchronously(
                executableURL: executable,
                arguments: Self.conversionArguments(
                    input: input,
                    outputDirectory: temporaryDirectory,
                    profileDirectory: profileDirectory
                ),
                workingDirectoryURL: temporaryDirectory,
                timeout: 5 * 60,
                maximumOutputBytes: 256 * 1_024,
                maximumErrorBytes: 256 * 1_024
            )
        } catch {
            throw LocalOfficeConverterError.launchFailed(error.localizedDescription)
        }
        if processOutput.didTimeout {
            throw LocalOfficeConverterError.conversionFailed(AppLocalization.text("转换超时"))
        }
        guard processOutput.status == 0 else {
            throw LocalOfficeConverterError.conversionFailed(processOutput.standardError)
        }

        let converted = temporaryDirectory
            .appendingPathComponent(input.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("pdf")
        guard FileManager.default.fileExists(atPath: converted.path) else {
            throw LocalOfficeConverterError.missingConvertedFile
        }
        do {
            try FileManager.default.moveItem(at: converted, to: output)
        } catch {
            throw LocalOfficeConverterError.conversionFailed(error.localizedDescription)
        }
    }

    public static func supports(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func conversionArguments(
        input: URL,
        outputDirectory: URL,
        profileDirectory: URL
    ) -> [String] {
        [
            "-env:UserInstallation=\(profileDirectory.absoluteString)",
            "--headless", "--convert-to", "pdf", "--outdir", outputDirectory.path, input.path,
        ]
    }

    private static let defaultExecutableCandidates = [
        URL(fileURLWithPath: "/Applications/LibreOffice.app/Contents/MacOS/soffice"),
        URL(fileURLWithPath: "/Applications/OpenOffice.app/Contents/MacOS/soffice"),
        URL(fileURLWithPath: "/opt/homebrew/bin/soffice"),
        URL(fileURLWithPath: "/usr/local/bin/soffice"),
    ]
}
