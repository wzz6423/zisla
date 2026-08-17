import Foundation

enum ManagedToolInstallationSource: Sendable, Equatable {
    case githubRelease(repository: String)
    case homebrewCask(name: String)
    case homebrewFormula(name: String)
}

public enum ManagedToolRecommendationGroup: Sendable, Equatable {
    case terminalEfficiency
    case networkAndData
    case developmentToolchain
    case utility
    case desktopApplication

    public var title: String {
        switch self {
        case .terminalEfficiency: "终端效率"
        case .networkAndData: "网络与数据"
        case .developmentToolchain: "开发工具链"
        case .utility: "实用组件"
        case .desktopApplication: "桌面应用"
        }
    }
}

/// Command-line tools Zisla can download/upgrade on its own.
public enum ManagedTool: String, CaseIterable, Identifiable, Sendable {
    case fzf
    case ripgrep
    case delta
    case lazygit
    case githubCLI
    case neovim
    case yazi
    case starship
    case tldr
    case jq
    case tree
    case curl
    case wget
    case rclone
    case posting
    case poppler
    case wireshark
    case mysql
    case cmake
    case gnuMake
    case ninja
    case gcc
    case go
    case rust
    case nodeJS
    case deno
    case python
    case ruby
    case openJDK17
    case maven
    case groovy
    case cocoaPods
    case pyenv
    case pipx
    case uv
    case pnpm
    case tectonic
    case packer
    case ytt
    case ytDLP
    case libreOffice
    case keka
    case kaku
    case kero
    case markdownPreview

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fzf: "fzf"
        case .ripgrep: "ripgrep"
        case .delta: "delta"
        case .lazygit: "lazygit"
        case .githubCLI: "GitHub CLI"
        case .neovim: "Neovim"
        case .yazi: "Yazi"
        case .starship: "Starship"
        case .tldr: "tldr"
        case .jq: "jq"
        case .tree: "tree"
        case .curl: "curl"
        case .wget: "wget"
        case .rclone: "rclone"
        case .posting: "Posting"
        case .poppler: "Poppler"
        case .wireshark: "Wireshark"
        case .mysql: "MySQL"
        case .cmake: "CMake"
        case .gnuMake: "GNU Make"
        case .ninja: "Ninja"
        case .gcc: "GCC"
        case .go: "Go"
        case .rust: "Rust"
        case .nodeJS: "Node.js"
        case .deno: "Deno"
        case .python: "Python"
        case .ruby: "Ruby"
        case .openJDK17: "OpenJDK 17"
        case .maven: "Maven"
        case .groovy: "Groovy"
        case .cocoaPods: "CocoaPods"
        case .pyenv: "pyenv"
        case .pipx: "pipx"
        case .uv: "uv"
        case .pnpm: "pnpm"
        case .tectonic: "Tectonic"
        case .packer: "Packer"
        case .ytt: "ytt"
        case .ytDLP: "yt-dlp"
        case .libreOffice: "LibreOffice"
        case .keka: "Keka"
        case .kaku: "Kaku"
        case .kero: "Kero"
        case .markdownPreview: "Markdown Preview"
        }
    }

    public var purpose: String {
        switch self {
        case .fzf: "模糊查找工具"
        case .ripgrep: "快速文本搜索"
        case .delta: "Git 差异高亮"
        case .lazygit: "Git 可视化界面"
        case .githubCLI: "GitHub 命令行管理"
        case .neovim: "现代化编辑器"
        case .yazi: "终端文件管理器"
        case .starship: "跨 Shell 提示符"
        case .tldr: "简化版命令手册"
        case .jq: "JSON 处理工具"
        case .tree: "目录树展示"
        case .curl: "网络请求工具"
        case .wget: "文件下载工具"
        case .rclone: "云存储同步"
        case .posting: "终端 API 客户端"
        case .poppler: "PDF 处理工具集"
        case .wireshark: "网络数据包分析"
        case .mysql: "关系数据库与客户端"
        case .cmake: "跨平台构建配置"
        case .gnuMake: "GNU 构建工具"
        case .ninja: "高速构建系统"
        case .gcc: "GNU 编译器套件"
        case .go: "Go 开发工具链"
        case .rust: "Rust 开发工具链"
        case .nodeJS: "JavaScript 运行时"
        case .deno: "JavaScript 与 TypeScript 运行时"
        case .python: "Python 运行时"
        case .ruby: "Ruby 运行时"
        case .openJDK17: "Java 17 开发工具链"
        case .maven: "Java 构建与依赖管理"
        case .groovy: "JVM 动态语言"
        case .cocoaPods: "Apple 平台依赖管理"
        case .pyenv: "Python 版本管理"
        case .pipx: "隔离安装 Python CLI"
        case .uv: "Python 包与项目管理"
        case .pnpm: "Node.js 包管理"
        case .tectonic: "现代 TeX 排版引擎"
        case .packer: "机器镜像构建"
        case .ytt: "YAML 模板工具"
        case .ytDLP: "视频音频下载"
        case .libreOffice: "Office 转 PDF"
        case .keka: "压缩与解压"
        case .kaku: "面向 AI 编码的终端"
        case .kero: "终端工作区"
        case .markdownPreview: "Markdown 预览"
        }
    }

    /// The executable's file name under `AppPaths.managedTools`.
    public var executableName: String {
        switch self {
        case .fzf: "fzf"
        case .ripgrep: "rg"
        case .delta: "delta"
        case .lazygit: "lazygit"
        case .githubCLI: "gh"
        case .neovim: "nvim"
        case .yazi: "yazi"
        case .starship: "starship"
        case .tldr: "tldr"
        case .jq: "jq"
        case .tree: "tree"
        case .curl: "curl"
        case .wget: "wget"
        case .rclone: "rclone"
        case .posting: "posting"
        case .poppler: "pdftotext"
        case .wireshark: "tshark"
        case .mysql: "mysql"
        case .cmake: "cmake"
        case .gnuMake: "gmake"
        case .ninja: "ninja"
        case .gcc: "gcc-16"
        case .go: "go"
        case .rust: "rustc"
        case .nodeJS: "node"
        case .deno: "deno"
        case .python: "python3"
        case .ruby: "ruby"
        case .openJDK17: "java"
        case .maven: "mvn"
        case .groovy: "groovy"
        case .cocoaPods: "pod"
        case .pyenv: "pyenv"
        case .pipx: "pipx"
        case .uv: "uv"
        case .pnpm: "pnpm"
        case .tectonic: "tectonic"
        case .packer: "packer"
        case .ytt: "ytt"
        case .ytDLP: "yt-dlp"
        case .libreOffice: "soffice"
        case .keka: "keka"
        case .kaku: "kaku"
        case .kero: "kero"
        case .markdownPreview: "mdp"
        }
    }

    var installationSource: ManagedToolInstallationSource {
        switch self {
        case .fzf: .homebrewFormula(name: "fzf")
        case .ripgrep: .homebrewFormula(name: "ripgrep")
        case .delta: .homebrewFormula(name: "git-delta")
        case .lazygit: .homebrewFormula(name: "lazygit")
        case .githubCLI: .homebrewFormula(name: "gh")
        case .neovim: .homebrewFormula(name: "neovim")
        case .yazi: .homebrewFormula(name: "yazi")
        case .starship: .homebrewFormula(name: "starship")
        case .tldr: .homebrewFormula(name: "tldr")
        case .jq: .homebrewFormula(name: "jq")
        case .tree: .homebrewFormula(name: "tree")
        case .curl: .homebrewFormula(name: "curl")
        case .wget: .homebrewFormula(name: "wget")
        case .rclone: .homebrewFormula(name: "rclone")
        case .posting: .homebrewFormula(name: "posting")
        case .poppler: .homebrewFormula(name: "poppler")
        case .wireshark: .homebrewFormula(name: "wireshark")
        case .mysql: .homebrewFormula(name: "mysql")
        case .cmake: .homebrewFormula(name: "cmake")
        case .gnuMake: .homebrewFormula(name: "make")
        case .ninja: .homebrewFormula(name: "ninja")
        case .gcc: .homebrewFormula(name: "gcc")
        case .go: .homebrewFormula(name: "go")
        case .rust: .homebrewFormula(name: "rust")
        case .nodeJS: .homebrewFormula(name: "node")
        case .deno: .homebrewFormula(name: "deno")
        case .python: .homebrewFormula(name: "python")
        case .ruby: .homebrewFormula(name: "ruby")
        case .openJDK17: .homebrewFormula(name: "openjdk@17")
        case .maven: .homebrewFormula(name: "maven")
        case .groovy: .homebrewFormula(name: "groovy")
        case .cocoaPods: .homebrewFormula(name: "cocoapods")
        case .pyenv: .homebrewFormula(name: "pyenv")
        case .pipx: .homebrewFormula(name: "pipx")
        case .uv: .homebrewFormula(name: "uv")
        case .pnpm: .homebrewFormula(name: "pnpm")
        case .tectonic: .homebrewFormula(name: "tectonic")
        case .packer: .homebrewFormula(name: "hashicorp/tap/packer")
        case .ytt: .homebrewFormula(name: "ytt")
        case .ytDLP: .githubRelease(repository: "yt-dlp/yt-dlp")
        case .libreOffice: .homebrewCask(name: "libreoffice")
        case .keka: .homebrewCask(name: "keka")
        case .kaku: .homebrewCask(name: "tw93/tap/kakuku")
        case .kero: .homebrewCask(name: "egoist/tap/kero")
        case .markdownPreview: .homebrewCask(name: "markdown-preview")
        }
    }

    var requiredHomebrewTap: String? {
        switch self {
        case .kaku: "tw93/tap"
        case .kero: "egoist/tap"
        case .packer: "hashicorp/tap"
        default: nil
        }
    }

    public var recommendationGroup: ManagedToolRecommendationGroup {
        switch self {
        case .fzf, .ripgrep, .delta, .lazygit, .githubCLI, .neovim, .yazi, .starship, .tldr, .jq, .tree:
            .terminalEfficiency
        case .curl, .wget, .rclone, .posting, .poppler, .wireshark, .mysql:
            .networkAndData
        case .cmake, .gnuMake, .ninja, .gcc, .go, .rust, .nodeJS, .deno, .python, .ruby,
             .openJDK17, .maven, .groovy, .cocoaPods, .pyenv, .pipx, .uv, .pnpm, .tectonic,
             .packer, .ytt:
            .developmentToolchain
        case .ytDLP, .libreOffice, .keka:
            .utility
        case .kaku, .kero, .markdownPreview:
            .desktopApplication
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
        usesHomebrew
            ? "通过本机 Homebrew 安装和更新"
            : "点击安装由 Zisla 自动完成"
    }

    public var installHelp: String {
        usesHomebrew
            ? "通过本机 Homebrew 安装 \(displayName)"
            : "从 GitHub 官方发布下载并安装 \(displayName)，无需终端"
    }

    public var updateHelp: String {
        usesHomebrew
            ? "通过本机 Homebrew 更新 \(displayName)"
            : "下载最新版并替换当前使用的 \(displayName)"
    }

    /// Arguments that print the installed version.
    var versionArguments: [String] {
        switch self {
        case .go: ["version"]
        case .poppler: ["-v"]
        default: ["--version"]
        }
    }

    func normalizedInstalledVersion(from raw: String) -> String? {
        guard let normalized = ManagedToolService.normalizeVersion(raw) else { return nil }

        // LibreOffice uses a special version format.
        if self == .libreOffice {
            guard let range = normalized.range(
                of: #"\d+(?:\.\d+)+"#,
                options: .regularExpression
            ) else { return nil }
            return normalized[range]
                .split(separator: ".")
                .prefix(3)
                .joined(separator: ".")
        }

        guard let range = normalized.range(
            of: #"\d+(?:\.\d+)+(?:_\d+)?"#,
            options: .regularExpression
        ) else { return normalized }
        return String(normalized[range])
    }

    /// Matching rule for release asset names.
    func matchesAsset(name: String) -> Bool {
        switch self {
        case .ytDLP:
            return name == "yt-dlp_macos"
        default: return false
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
            "未找到 Homebrew；请先安装 Homebrew 后再管理推荐工具"
        case .homebrewFailed(let value):
            "Homebrew 执行失败：\(value)"
        }
    }
}
