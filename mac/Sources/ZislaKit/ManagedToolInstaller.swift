import Foundation

enum ManagedToolInstallationSource: Sendable, Equatable {
    case githubRelease(repository: String)
    case homebrewCask(name: String)
    case homebrewFormula(name: String)
}

/// Command-line tools Zisla can download/upgrade on its own.
public enum ManagedTool: String, CaseIterable, Identifiable, Sendable {
    case ytDLP
    case libreOffice
    case fzf
    case ripgrep
    case lazygit
    case neovim
    case yazi
    case starship
    case tldr
    case jq
    case tree
    case kaku
    case kero
    case markdownPreview
    case keka

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ytDLP: "yt-dlp"
        case .libreOffice: "LibreOffice"
        case .fzf: "fzf"
        case .ripgrep: "ripgrep"
        case .lazygit: "lazygit"
        case .neovim: "Neovim"
        case .yazi: "Yazi"
        case .starship: "Starship"
        case .tldr: "tldr"
        case .jq: "jq"
        case .tree: "tree"
        case .kaku: "Kaku"
        case .kero: "Kero"
        case .markdownPreview: "Markdown Preview"
        case .keka: "Keka"
        }
    }

    public var purpose: String {
        switch self {
        case .ytDLP: "视频音频下载"
        case .libreOffice: "Office 转 PDF"
        case .fzf: "模糊查找工具"
        case .ripgrep: "快速文本搜索"
        case .lazygit: "Git 可视化界面"
        case .neovim: "现代化编辑器"
        case .yazi: "终端文件管理器"
        case .starship: "跨 Shell 提示符"
        case .tldr: "简化版命令手册"
        case .jq: "JSON 处理工具"
        case .tree: "目录树展示"
        case .kaku: "面向 AI 编码的终端"
        case .kero: "终端工作区"
        case .markdownPreview: "Markdown 预览"
        case .keka: "压缩与解压"
        }
    }

    /// The executable's file name under `AppPaths.managedTools`.
    public var executableName: String {
        switch self {
        case .ytDLP: "yt-dlp"
        case .libreOffice: "soffice"
        case .fzf: "fzf"
        case .ripgrep: "rg"
        case .lazygit: "lazygit"
        case .neovim: "nvim"
        case .yazi: "yazi"
        case .starship: "starship"
        case .tldr: "tldr"
        case .jq: "jq"
        case .tree: "tree"
        case .kaku: "kaku"
        case .kero: "kero"
        case .markdownPreview: "mdp"
        case .keka: "keka"
        }
    }

    var installationSource: ManagedToolInstallationSource {
        switch self {
        case .ytDLP: .githubRelease(repository: "yt-dlp/yt-dlp")
        case .libreOffice: .homebrewCask(name: "libreoffice")
        case .fzf: .homebrewFormula(name: "fzf")
        case .ripgrep: .homebrewFormula(name: "ripgrep")
        case .lazygit: .homebrewFormula(name: "lazygit")
        case .neovim: .homebrewFormula(name: "neovim")
        case .yazi: .homebrewFormula(name: "yazi")
        case .starship: .homebrewFormula(name: "starship")
        case .tldr: .homebrewFormula(name: "tldr")
        case .jq: .homebrewFormula(name: "jq")
        case .tree: .homebrewFormula(name: "tree")
        case .kaku: .homebrewCask(name: "kakuku")
        case .kero: .homebrewCask(name: "kero")
        case .markdownPreview: .homebrewCask(name: "markdown-preview")
        case .keka: .homebrewCask(name: "keka")
        }
    }

    var usesNativeApplicationVersion: Bool {
        switch self {
        case .kaku, .kero, .markdownPreview, .keka: true
        default: false
        }
    }

    var usesHomebrewCask: Bool {
        if case .homebrewCask = installationSource { return true }
        return false
    }

    var usesHomebrewFormula: Bool {
        if case .homebrewFormula = installationSource { return true }
        return false
    }

    var usesHomebrew: Bool {
        usesHomebrewCask || usesHomebrewFormula
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

    /// Arguments that print the installed version.
    var versionArguments: [String] {
        switch self {
        case .ytDLP: ["--version"]
        case .libreOffice: ["--version"]
        case .fzf: ["--version"]
        case .ripgrep: ["--version"]
        case .lazygit: ["--version"]
        case .neovim: ["--version"]
        case .yazi: ["--version"]
        case .starship: ["--version"]
        case .tldr: ["--version"]
        case .jq: ["--version"]
        case .tree: ["--version"]
        case .kaku: ["--version"]
        case .kero: ["--version"]
        case .markdownPreview: ["--version"]
        case .keka: ["--version"]
        }
    }

    func normalizedInstalledVersion(from raw: String) -> String? {
        guard let normalized = ManagedToolService.normalizeVersion(raw) else { return nil }
        switch self {
        case .libreOffice:
            return Self.dottedVersion(in: normalized)?
                .split(separator: ".")
                .prefix(3)
                .joined(separator: ".")
        case .fzf, .ripgrep, .lazygit, .neovim, .yazi, .starship, .tldr, .jq, .tree:
            return Self.dottedVersion(in: normalized)
        default:
            return normalized
        }
    }

    private static func dottedVersion(in text: String) -> String? {
        text.range(of: #"\d+(?:\.\d+)+"#, options: .regularExpression)
            .map { String(text[$0]) }
    }

    /// Matching rule for release asset names.
    func matchesAsset(name: String) -> Bool {
        switch self {
        case .ytDLP:
            return name == "yt-dlp_macos"
        case .libreOffice, .fzf, .ripgrep, .lazygit, .neovim, .yazi, .starship, .tldr, .jq, .tree, .kaku, .kero, .markdownPreview, .keka:
            return false
        }
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
    case assetNotFound(tool: String)
    case untrustedHost(String)
    case downloadFailed(String)
    case notExecutable(String)
    case homebrewUnavailable
    case homebrewFailed(String)

    public var message: String {
        switch self {
        case .releaseUnavailable(let value):
            "获取版本信息失败：\(value)"
        case .assetNotFound(let tool):
            "\(tool) 没有可用下载"
        case .untrustedHost(let host):
            "下载地址不可信：\(host)"
        case .downloadFailed(let value):
            "下载失败：\(value)"
        case .notExecutable(let value):
            "安装后无法执行：\(value)"
        case .homebrewUnavailable:
            "未找到 Homebrew；请先安装 Homebrew 后再管理 LibreOffice"
        case .homebrewFailed(let value):
            "Homebrew 执行失败：\(value)"
        }
    }
}
