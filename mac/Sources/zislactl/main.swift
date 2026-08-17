import Foundation
import ZislaCore

/// State directory: prefers Application Support/zisla, and migrates data directories from earlier versions.
func defaultStateDirectory() -> URL {
    LegacyAppDataMigration.applicationSupportDirectory()
}

let helpText = """
zislactl — 向灵动岛推送 AI 进度、用量与通知

用法：
  update  --id <id> --provider <claude|codex|gemini|grok|gpt|copilot|qwen|coder> --title <标题>
          [--progress <0-100>] [--detail <文本>] [--pid <进程 PID>]
          [--status <running|queued|blocked|error>] [--queued]
  finish  --id <id> [--failed] [--detail <文本>]
  remove  --id <id>
  clear
  list
  usage   --provider <名> --input-tokens <n> --output-tokens <n>
          [--cost <美元>] [--model <名>]
  notify  --title <标题> [--detail <文本>] [--kind <info|success|warning|error>]
          [--side <left|right>]
  message --app <应用名> --sender <发件人> --content <正文>
          [--app-bundle-id <bundle id>]
  help

状态数据库：\(defaultStateDirectory().appendingPathComponent("ai-state.sqlite").path)
"""

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Returns the process exit code: 0 on success, non-zero on failure with an actionable message printed to stderr.
func run(arguments: [String]) -> Int32 {
    let command: CLICommand
    do {
        command = try CLIParser.parse(arguments: arguments)
    } catch let error as CLIParseError {
        printError("错误：\(error.description)")
        return 64  // EX_USAGE
    } catch {
        printError("错误：\(error.localizedDescription)")
        return 64
    }

    if case .help = command {
        print(helpText)
        return 0
    }

    let repository = AIStateRepository(directoryURL: defaultStateDirectory())
    do {
        switch command {
        case let .update(task):
            try repository.upsert(task)
            let pct = task.progress.map { " \(Int(($0 * 100).rounded()))%" } ?? ""
            print("已更新任务 \(task.id)（\(task.provider.rawValue)）\(task.title)\(pct)")

        case let .finish(id, failed, detail):
            try repository.finish(id: id, failed: failed, detail: detail, at: Date())
            print("任务 \(id) 已标记为\(failed ? "失败" : "完成")")

        case let .remove(id):
            let removed = try repository.remove(id: id)
            if removed {
                print("已移除任务 \(id)")
            } else {
                printError("错误：未找到任务 \(id)")
                return 65  // EX_DATAERR
            }

        case .clear:
            try repository.clearTasks()
            print("已清空所有任务")

        case .list:
            let state = try repository.load()
            if state.tasks.isEmpty {
                print("（无进行中的任务）")
            } else {
                for task in state.tasks {
                    let pct = task.progress.map { "\(Int(($0 * 100).rounded()))%" } ?? "--"
                    print("[\(task.status.rawValue)] \(task.id) \(task.provider.rawValue) \(task.title) \(pct)")
                }
            }

        case let .usage(sample):
            try repository.recordUsage(sample)
            print("已记录用量：\(sample.provider.rawValue) \(sample.totalTokens) tokens")

        case let .notify(notice):
            try repository.enqueueNotice(notice)
            print("已发送通知：\(notice.title)")

        case let .message(message):
            let pair = message.makeNotices()
            try repository.enqueueNotices([pair.left, pair.right])
            print("已发送消息通知：\(message.appName) · \(message.sender)")

        case .help:
            print(helpText)
        }
        return 0
    } catch let error as AIStateRepositoryError {
        switch error {
        case .corruptedState:
            printError("错误：AI 状态数据库中存在无法解析的数据")
        case let .taskNotFound(id):
            printError("错误：未找到任务 \(id)")
        case let .storageFailure(message):
            printError("错误：AI 状态数据库操作失败：\(message)")
        }
        return 65
    } catch {
        printError("错误：\(error.localizedDescription)")
        return 70  // EX_SOFTWARE
    }
}

exit(run(arguments: Array(CommandLine.arguments.dropFirst())))
