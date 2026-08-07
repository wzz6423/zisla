#include "zisla/core/CLIApplication.hpp"

#include "zisla/core/AIStateRepository.hpp"
#include "zisla/core/CLIParser.hpp"

#include <array>
#include <cmath>
#include <exception>
#include <string>
#include <utility>
#include <variant>

namespace zisla::core {
namespace {

constexpr int ex_usage = 64;
constexpr int ex_dataerr = 65;
constexpr int ex_software = 70;

std::string path_as_utf8(const std::filesystem::path& path) {
    const auto encoded = path.u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size(),
    };
}

std::string with_newline(std::string value) {
    value.push_back('\n');
    return value;
}

std::string parse_error_text(const CLIParseError& error) {
    const auto& subject = error.subject();
    switch (error.code()) {
    case CLIParseErrorCode::missing_subcommand:
        return "缺少子命令。可用：update/finish/remove/clear/list/usage/notify/message/help";
    case CLIParseErrorCode::unknown_subcommand:
        return "未知子命令 '" + subject + "'。运行 `zislactl help` 查看用法。";
    case CLIParseErrorCode::unexpected_argument:
        return "不支持的位置参数 '" + subject + "'。";
    case CLIParseErrorCode::unknown_option:
        return "当前子命令不支持参数 " + subject + "。";
    case CLIParseErrorCode::missing_option:
        return "缺少必填参数 " + subject + "。";
    case CLIParseErrorCode::invalid_value:
        return "参数 " + subject + " 的值非法。";
    case CLIParseErrorCode::progress_out_of_range:
        return "进度 " + subject + " 超出范围，应在 0-100 之间。";
    case CLIParseErrorCode::unknown_provider:
        return "未知的 provider '" + subject + "'。";
    case CLIParseErrorCode::unknown_notice_kind:
        return "未知的 kind '" + subject + "'。支持：info/success/warning/error。";
    case CLIParseErrorCode::unknown_notice_side:
        return "未知的 side '" + subject + "'。支持：left/right。";
    }
    return error.what();
}

std::string help_text(const std::filesystem::path& state_directory) {
    return
        "zislactl - 向 Zisla 推送 AI 进度、用量与通知\n\n"
        "用法：\n"
        "  update  --id <id> --provider <名称> --title <标题>\n"
        "          [--progress <0-100>] [--detail <文本>]\n"
        "          [--status <running|queued|blocked|error>] [--queued]\n"
        "  finish  --id <id> [--failed] [--detail <文本>]\n"
        "  remove  --id <id>\n"
        "  clear\n"
        "  list\n"
        "  usage   --provider <名称> --input-tokens <n> --output-tokens <n>\n"
        "          [--cost <美元>] [--model <名称>] [--timestamp <Unix 秒>]\n"
        "  notify  --title <标题> [--detail <文本>]\n"
        "          [--kind <info|success|warning|error>] [--side <left|right>]\n"
        "  message --app <应用名> --sender <发件人> --content <正文>\n"
        "          [--app-bundle-id <包标识>]\n"
        "  help\n\n"
        "状态数据库：" + path_as_utf8(state_directory / "ai-state.sqlite") + "\n";
}

CLIResult repository_error(const AIStateRepositoryError& error) {
    switch (error.code()) {
    case AIStateRepositoryErrorCode::corrupted_state:
        return {ex_dataerr, {}, with_newline("错误：AI 状态数据库中存在无法解析的数据")};
    case AIStateRepositoryErrorCode::task_not_found:
        return {ex_dataerr, {}, with_newline("错误：未找到任务 " + error.subject())};
    case AIStateRepositoryErrorCode::storage_failure:
        return {
            ex_dataerr,
            {},
            with_newline("错误：AI 状态数据库操作失败：" + std::string(error.what())),
        };
    }
    return {ex_dataerr, {}, with_newline("错误：AI 状态数据库操作失败")};
}

}  // namespace

CLIResult run_cli(
    std::span<const std::string_view> arguments,
    const std::filesystem::path& state_directory,
    std::int64_t now_unix_ms,
    std::string generated_id) {
    CLICommand command;
    try {
        command = CLIParser::parse(
            arguments,
            now_unix_ms,
            std::move(generated_id));
    } catch (const CLIParseError& error) {
        return {ex_usage, {}, with_newline("错误：" + parse_error_text(error))};
    } catch (const std::exception& error) {
        return {ex_software, {}, with_newline("错误：" + std::string(error.what()))};
    }

    if (std::holds_alternative<CLIHelpCommand>(command)) {
        return {0, help_text(state_directory), {}};
    }

    const AIStateRepository repository(state_directory);
    try {
        if (const auto* update = std::get_if<CLIUpdateCommand>(&command)) {
            repository.upsert(update->task);
            const auto percent = update->task.progress
                ? " " + std::to_string(static_cast<long long>(
                    std::llround(*update->task.progress * 100.0))) + "%"
                : std::string{};
            return {
                0,
                with_newline(
                    "已更新任务 " + update->task.id + "（"
                    + std::string(ai_provider_token(update->task.provider)) + "）"
                    + update->task.title + percent),
                {},
            };
        }
        if (const auto* finish = std::get_if<CLIFinishCommand>(&command)) {
            repository.finish(
                finish->id,
                finish->failed,
                finish->detail,
                now_unix_ms);
            return {
                0,
                with_newline(
                    "任务 " + finish->id + " 已标记为"
                    + (finish->failed ? "失败" : "完成")),
                {},
            };
        }
        if (const auto* remove = std::get_if<CLIRemoveCommand>(&command)) {
            if (!repository.remove(remove->id)) {
                return {
                    ex_dataerr,
                    {},
                    with_newline("错误：未找到任务 " + remove->id),
                };
            }
            return {0, with_newline("已移除任务 " + remove->id), {}};
        }
        if (std::holds_alternative<CLIClearCommand>(command)) {
            repository.clear_tasks();
            return {0, with_newline("已清空所有任务"), {}};
        }
        if (std::holds_alternative<CLIListCommand>(command)) {
            const auto state = repository.load();
            if (state.tasks.empty()) {
                return {0, with_newline("（无进行中的任务）"), {}};
            }
            std::string output;
            for (const auto& task : state.tasks) {
                const auto percent = task.progress
                    ? std::to_string(static_cast<long long>(
                        std::llround(*task.progress * 100.0))) + "%"
                    : "--";
                output += "[" + std::string(ai_progress_status_token(task.status)) + "] "
                    + task.id + " " + std::string(ai_provider_token(task.provider)) + " "
                    + task.title + " " + percent + "\n";
            }
            return {0, std::move(output), {}};
        }
        if (const auto* usage = std::get_if<CLIUsageCommand>(&command)) {
            (void)repository.record_usage(usage->sample);
            return {
                0,
                with_newline(
                    "已记录用量：" + std::string(ai_provider_token(usage->sample.provider))
                    + " " + std::to_string(usage->sample.total_tokens()) + " tokens"),
                {},
            };
        }
        if (const auto* notify = std::get_if<CLINotifyCommand>(&command)) {
            repository.enqueue_notice(notify->notice);
            return {0, with_newline("已发送通知：" + notify->notice.title), {}};
        }
        if (const auto* message = std::get_if<CLIMessageCommand>(&command)) {
            const auto pair = message->message.make_notices();
            const std::array notices{pair.first, pair.second};
            repository.enqueue_notices(notices);
            return {
                0,
                with_newline(
                    "已发送消息通知：" + message->message.app_name + " · "
                    + message->message.sender),
                {},
            };
        }
    } catch (const AIStateRepositoryError& error) {
        return repository_error(error);
    } catch (const std::exception& error) {
        return {ex_software, {}, with_newline("错误：" + std::string(error.what()))};
    }

    return {ex_software, {}, with_newline("错误：无法执行命令")};
}

}  // namespace zisla::core
