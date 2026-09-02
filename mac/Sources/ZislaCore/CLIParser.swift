import Foundation

public enum CLICommand: Sendable {
    case update(AIProgressTask)
    case finish(id: String, failed: Bool, detail: String?)
    case remove(id: String)
    case clear
    case list
    case usage(AIUsageSample)
    case notify(IslandNotice)
    case message(MessageNotification)
    case help
}

public enum CLIParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case unexpectedArgument(String)
    case unknownOption(String)
    case missingOption(String)
    case invalidValue(option: String, value: String)
    case progressOutOfRange(Double)
    case unknownProvider(String)
    case unknownNoticeKind(String)
    case unknownNoticeSide(String)

    public var description: String {
        switch self {
        case .missingSubcommand:
            return "缺少子命令。可用：update/finish/remove/clear/list/usage/notify/message/help"
        case let .unknownSubcommand(name):
            return "未知子命令 '\(name)'。运行 `zislactl help` 查看用法。"
        case let .unexpectedArgument(value):
            return "不支持的位置参数 '\(value)'。"
        case let .unknownOption(option):
            return "当前子命令不支持参数 \(option)。"
        case let .missingOption(option):
            return "缺少必填参数 \(option)。"
        case let .invalidValue(option, value):
            return "参数 \(option) 的值 '\(value)' 非法。"
        case let .progressOutOfRange(value):
            return "进度 \(value) 超出范围，应在 0–100 之间。"
        case let .unknownProvider(value):
            return "未知的 provider '\(value)'。支持：claude/codex/gemini/grok/gpt/copilot/qwen/coder。"
        case let .unknownNoticeKind(value):
            return "未知的 kind '\(value)'。支持：info/success/warning/error。"
        case let .unknownNoticeSide(value):
            return "未知的 side '\(value)'。支持：left/right。"
        }
    }
}

public enum CLIParser {
    public static func parse(arguments: [String], now: Date = Date()) throws -> CLICommand {
        guard let subcommand = arguments.first else { throw CLIParseError.missingSubcommand }
        let tokens = Array(arguments.dropFirst())

        switch subcommand {
        case "update":
            return try parseUpdate(
                parseOptions(tokens, allowed: ["--id", "--provider", "--title", "--progress", "--detail", "--status", "--queued", "--pid"]),
                now: now
            )
        case "finish":
            return try parseFinish(parseOptions(tokens, allowed: ["--id", "--failed", "--detail"]))
        case "remove":
            return .remove(id: try require(parseOptions(tokens, allowed: ["--id"]), "--id"))
        case "clear":
            _ = try parseOptions(tokens, allowed: [])
            return .clear
        case "list":
            _ = try parseOptions(tokens, allowed: [])
            return .list
        case "usage":
            return try parseUsage(
                parseOptions(tokens, allowed: ["--provider", "--input-tokens", "--output-tokens", "--cost", "--model", "--timestamp"]),
                now: now
            )
        case "notify":
            return try parseNotify(parseOptions(tokens, allowed: ["--title", "--detail", "--kind", "--side"]), now: now)
        case "message":
            return try parseMessage(
                parseOptions(tokens, allowed: ["--app", "--sender", "--content", "--app-bundle-id"]),
                now: now
            )
        case "help", "--help", "-h":
            _ = try parseOptions(tokens, allowed: [])
            return .help
        default: throw CLIParseError.unknownSubcommand(subcommand)
        }
    }

    /// Folds a `--key value` sequence into a dictionary; valueless flags (e.g. --failed) are stored as "".
    private static func parseOptions(
        _ tokens: [String],
        allowed: Set<String>
    ) throws -> [String: String] {
        var options: [String: String] = [:]
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            guard token.hasPrefix("--") else { throw CLIParseError.unexpectedArgument(token) }
            guard allowed.contains(token) else { throw CLIParseError.unknownOption(token) }
            if index + 1 < tokens.count, !tokens[index + 1].hasPrefix("--") {
                options[token] = tokens[index + 1]
                index += 2
            } else {
                options[token] = ""
                index += 1
            }
        }
        return options
    }

    private static func parseUpdate(_ options: [String: String], now: Date) throws -> CLICommand {
        let id = try require(options, "--id")
        let provider = try requireProvider(options)
        let title = try require(options, "--title")

        var progress: Double?
        if let raw = options["--progress"], !raw.isEmpty {
            guard let percent = Double(raw) else {
                throw CLIParseError.invalidValue(option: "--progress", value: raw)
            }
            guard (0...100).contains(percent) else {
                throw CLIParseError.progressOutOfRange(percent)
            }
            progress = percent / 100
        }

        let status: AIProgressStatus
        if let raw = options["--status"] {
            guard let parsed = AIProgressStatus(rawValue: raw.lowercased()), parsed.isActive else {
                throw CLIParseError.invalidValue(option: "--status", value: raw)
            }
            status = parsed
        } else {
            status = options["--queued"] != nil ? .queued : .running
        }
        return .update(AIProgressTask(
            id: id, provider: provider, title: title,
            detail: options["--detail"], progress: progress,
            status: status,
            updatedAt: now,
            processIdentifier: try optionalProcessIdentifier(options["--pid"])
        ))
    }

    private static func parseFinish(_ options: [String: String]) throws -> CLICommand {
        let id = try require(options, "--id")
        let failed = options["--failed"].map { $0.isEmpty || $0 == "true" } ?? false
        return .finish(id: id, failed: failed, detail: options["--detail"])
    }

    private static func parseUsage(_ options: [String: String], now: Date) throws -> CLICommand {
        let provider = try requireProvider(options)
        let input = try requireNonNegativeInt(options, "--input-tokens")
        let output = try requireNonNegativeInt(options, "--output-tokens")
        guard !input.addingReportingOverflow(output).overflow else {
            throw CLIParseError.invalidValue(option: "--output-tokens", value: "\(output)")
        }
        var cost: Double?
        if let raw = options["--cost"], !raw.isEmpty {
            guard let value = Double(raw), value.isFinite, value >= 0 else {
                throw CLIParseError.invalidValue(option: "--cost", value: raw)
            }
            cost = value
        }
        let timestamp: Date
        if let raw = options["--timestamp"] {
            guard let value = Double(raw), value.isFinite, value >= 0 else {
                throw CLIParseError.invalidValue(option: "--timestamp", value: raw)
            }
            let parsed = Date(timeIntervalSince1970: value)
            guard parsed.timeIntervalSinceReferenceDate.isFinite else {
                throw CLIParseError.invalidValue(option: "--timestamp", value: raw)
            }
            timestamp = parsed
        } else {
            timestamp = now
        }
        return .usage(AIUsageSample(
            provider: provider, timestamp: timestamp,
            inputTokens: input, outputTokens: output,
            costUSD: cost, model: options["--model"]
        ))
    }

    private static func parseNotify(_ options: [String: String], now: Date) throws -> CLICommand {
        let title = try require(options, "--title")
        let kind: NoticeKind
        if let raw = options["--kind"], !raw.isEmpty {
            guard let parsed = NoticeKind(token: raw) else { throw CLIParseError.unknownNoticeKind(raw) }
            kind = parsed
        } else {
            kind = .info
        }
        let side: NoticeSide
        if let raw = options["--side"], !raw.isEmpty {
            guard let parsed = NoticeSide(token: raw) else { throw CLIParseError.unknownNoticeSide(raw) }
            side = parsed
        } else {
            side = .right
        }
        return .notify(IslandNotice(
            title: title, detail: options["--detail"],
            kind: kind, side: side, createdAt: now
        ))
    }


    private static func parseMessage(_ options: [String: String], now: Date) throws -> CLICommand {
        let app = try require(options, "--app")
        let sender = try require(options, "--sender")
        let content = try require(options, "--content")
        let bundleID = options["--app-bundle-id"]
        return .message(MessageNotification(
            appName: app,
            sender: sender,
            content: content,
            appBundleIdentifier: bundleID,
            createdAt: now
        ))
    }

    // MARK: - Value helpers

    private static func require(_ options: [String: String], _ key: String) throws -> String {
        guard let value = options[key], !value.isEmpty else {
            throw CLIParseError.missingOption(key)
        }
        return value
    }

    private static func requireInt(_ options: [String: String], _ key: String) throws -> Int {
        let raw = try require(options, key)
        guard let value = Int(raw) else {
            throw CLIParseError.invalidValue(option: key, value: raw)
        }
        return value
    }

    private static func requireNonNegativeInt(_ options: [String: String], _ key: String) throws -> Int {
        let raw = try require(options, key)
        guard let value = Int(raw), value >= 0 else {
            throw CLIParseError.invalidValue(option: key, value: raw)
        }
        return value
    }

    private static func optionalProcessIdentifier(_ raw: String?) throws -> Int32? {
        guard let raw else { return nil }
        guard let value = Int32(raw), value > 0 else {
            throw CLIParseError.invalidValue(option: "--pid", value: raw)
        }
        return value
    }

    private static func requireProvider(_ options: [String: String]) throws -> AIProvider {
        let raw = try require(options, "--provider")
        guard let provider = AIProvider(token: raw) else {
            throw CLIParseError.unknownProvider(raw)
        }
        return provider
    }
}
