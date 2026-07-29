import Foundation

enum ManagedToolInstallationSource: Sendable, Equatable {
    case githubRelease(repository: String)
    case homebrewCask(name: String)
}

/// Command-line tools Zisla can download/upgrade on its own.
public enum ManagedTool: String, CaseIterable, Identifiable, Sendable {
    case ytDLP
    case mas
    case libreOffice

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ytDLP: "yt-dlp"
        case .mas: "mas"
        case .libreOffice: "LibreOffice"
        }
    }

    public var purpose: String {
        switch self {
        case .ytDLP: "视频音频下载"
        case .mas: "App Store 应用更新"
        case .libreOffice: "Office 转 PDF"
        }
    }

    /// The executable's file name under `AppPaths.managedTools`.
    public var executableName: String {
        switch self {
        case .ytDLP: "yt-dlp"
        case .mas: "mas"
        case .libreOffice: "soffice"
        }
    }

    var installationSource: ManagedToolInstallationSource {
        switch self {
        case .ytDLP: .githubRelease(repository: "yt-dlp/yt-dlp")
        case .mas: .githubRelease(repository: "mas-cli/mas")
        case .libreOffice: .homebrewCask(name: "libreoffice")
        }
    }

    var usesHomebrewCask: Bool {
        if case .homebrewCask = installationSource { return true }
        return false
    }

    public var installDetail: String {
        usesHomebrewCask
            ? "通过本机 Homebrew 安装和更新"
            : "点击安装由 Zisla 自动完成"
    }

    public var installHelp: String {
        usesHomebrewCask
            ? "通过本机 Homebrew 安装 \(displayName)"
            : "从 GitHub 官方发布下载并安装 \(displayName)，无需终端"
    }

    public var updateHelp: String {
        usesHomebrewCask
            ? "通过本机 Homebrew 更新 \(displayName)"
            : "下载最新版并替换当前使用的 \(displayName)"
    }

    /// Arguments that print the version. Both tools support it, but the subcommand name differs.
    var versionArguments: [String] {
        switch self {
        case .ytDLP: ["--version"]
        case .mas: ["version"]
        case .libreOffice: ["--version"]
        }
    }

    func normalizedInstalledVersion(from raw: String) -> String? {
        guard let normalized = ManagedToolService.normalizeVersion(raw) else { return nil }
        guard self == .libreOffice else { return normalized }
        guard let range = normalized.range(
            of: #"\d+(?:\.\d+)+"#,
            options: .regularExpression
        ) else { return nil }
        return normalized[range]
            .split(separator: ".")
            .prefix(3)
            .joined(separator: ".")
    }

    /// Matching rule for release asset names. mas only publishes per-architecture .pkg files, so pick by the current architecture.
    func matchesAsset(name: String) -> Bool {
        switch self {
        case .ytDLP:
            return name == "yt-dlp_macos"
        case .mas:
            return name.hasSuffix("-\(Self.currentArchitecture).pkg")
        case .libreOffice:
            return false
        }
    }

    /// Whether the download is a .pkg — it must be extracted before the executable is available.
    var needsPackageExtraction: Bool {
        self == .mas
    }

    /// Relative path to the executable inside an extracted `.pkg`.
    ///
    /// mas's `bin/mas` is only a zsh wrapper script (it relies on jq for output formatting); the real binary
    /// lives at `libexec/bin/mas`, links only system libraries and the system Swift runtime, and runs standalone outside the pkg.
    var payloadExecutablePath: String? {
        switch self {
        case .mas: "Payload/usr/local/opt/mas/libexec/bin/mas"
        case .ytDLP, .libreOffice: nil
        }
    }

    static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}

/// A tool's current install and download state.
public struct ManagedToolState: Sendable, Equatable {
    public enum Location: Sendable, Equatable {
        /// The build Zisla downloaded into Application Support.
        case managed
        /// The build shipped with the app in Contents/Helpers.
        case bundled
        /// One the user installed themselves (Homebrew, etc.).
        case external(String)
        /// Installed and updated through the user's Homebrew cask.
        case homebrew

        public var label: String {
            switch self {
            case .managed: "Zisla 管理"
            case .bundled: "随应用打包"
            case .external: "系统已安装"
            case .homebrew: "Homebrew 管理"
            }
        }
    }

    public enum Phase: Sendable, Equatable {
        case idle
        case checking
        case downloading(Double)
        case installing
    }

    public var installedVersion: String?
    public var location: Location?
    public var latestVersion: String?
    public var phase: Phase = .idle
    public var errorMessage: String?

    public init() {}

    public var isInstalled: Bool { location != nil }

    public var isBusy: Bool {
        phase != .idle
    }

    /// True when the tool is installed and an update is known to exist. Never claims an update when the latest version could not be fetched.
    public var hasUpdate: Bool {
        guard let installedVersion, let latestVersion else { return false }
        return installedVersion != latestVersion
    }
}

public enum ManagedToolError: Error, Sendable, Equatable {
    case releaseUnavailable(String)
    case assetNotFound(tool: String, architecture: String)
    case untrustedHost(String)
    case downloadFailed(String)
    case extractionFailed(String)
    case notExecutable(String)
    case homebrewUnavailable
    case homebrewFailed(String)

    public var message: String {
        switch self {
        case .releaseUnavailable(let value):
            "获取版本信息失败：\(value)"
        case .assetNotFound(let tool, let architecture):
            "\(tool) 没有提供 \(architecture) 架构的下载"
        case .untrustedHost(let host):
            "下载地址不可信：\(host)"
        case .downloadFailed(let value):
            "下载失败：\(value)"
        case .extractionFailed(let value):
            "解包失败：\(value)"
        case .notExecutable(let value):
            "安装后无法执行：\(value)"
        case .homebrewUnavailable:
            "未找到 Homebrew；请先安装 Homebrew 后再管理 LibreOffice"
        case .homebrewFailed(let value):
            "Homebrew 执行失败：\(value)"
        }
    }
}
