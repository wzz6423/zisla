#include "zisla/core/CLIParser.hpp"

#include <exception>
#include <functional>
#include <initializer_list>
#include <iostream>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <variant>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

CLICommand parse(
    std::initializer_list<std::string_view> arguments,
    std::int64_t now_unix_ms = 42'000,
    std::string generated_id = "generated-id") {
    return CLIParser::parse(
        std::span<const std::string_view>(arguments.begin(), arguments.size()),
        now_unix_ms,
        std::move(generated_id));
}

void expectParseError(
    std::initializer_list<std::string_view> arguments,
    CLIParseErrorCode expected_code,
    std::string_view expected_subject) {
    try {
        (void)parse(arguments);
        throw std::runtime_error("command should fail to parse");
    } catch (const CLIParseError& error) {
        expect(error.code() == expected_code && error.subject() == expected_subject,
            "parse error should expose its stable code and subject");
    }
}

void updateParsesPercentProviderAndActiveStatuses() {
    const auto command = parse({
        "update", "--id", "job-1", "--provider", "qwen-code",
        "--title", "Indexing", "--progress", "42", "--detail", "4/10",
    });
    const auto* update = std::get_if<CLIUpdateCommand>(&command);
    expect(update != nullptr, "update arguments should produce an update command");
    expect(update->task.id == "job-1"
            && update->task.provider == AIProvider::qwen
            && update->task.title == "Indexing"
            && update->task.detail == "4/10"
            && update->task.progress == 0.42
            && update->task.status == AIProgressStatus::running
            && update->task.updated_at_unix_ms == 42'000,
        "update command should normalize its structured task fields");

    for (const auto status : {"queued", "blocked", "error"}) {
        const auto status_command = parse({
            "update", "--id", status, "--provider", "codex",
            "--title", "Task", "--status", status,
        });
        const auto* status_update = std::get_if<CLIUpdateCommand>(&status_command);
        expect(status_update && ai_progress_status_token(status_update->task.status) == status,
            "update should accept every active status");
    }
}

void invalidUpdateArgumentsReportStableErrors() {
    expectParseError({
        "update", "--id", "job", "--provider", "grok",
        "--title", "Run", "--progress", "101",
    }, CLIParseErrorCode::progress_out_of_range, "101");
    expectParseError(
        {"finish", "--id", "job", "--faield"},
        CLIParseErrorCode::unknown_option,
        "--faield");
    expectParseError(
        {"clear", "extra"},
        CLIParseErrorCode::unexpected_argument,
        "extra");
    expectParseError(
        {"update", "--id", "job", "--provider", "unknown", "--title", "Run"},
        CLIParseErrorCode::unknown_provider,
        "unknown");
}

void usageParsesStructuredValuesAndRejectsInvalidCounts() {
    const auto command = parse({
        "usage", "--provider", "coder", "--input-tokens", "300",
        "--output-tokens", "75", "--cost", "0.04", "--model", "coder-pro",
        "--timestamp", "1700000000.25",
    });
    const auto* usage = std::get_if<CLIUsageCommand>(&command);
    expect(usage != nullptr, "usage arguments should produce a usage command");
    expect(usage->sample.provider == AIProvider::coder
            && usage->sample.timestamp_unix_ms == 1'700'000'000'250
            && usage->sample.input_tokens == 300
            && usage->sample.output_tokens == 75
            && usage->sample.cost_usd == 0.04
            && usage->sample.model == "coder-pro",
        "usage command should parse tokens, cost, model, and Unix seconds");

    expectParseError({
        "usage", "--provider", "codex", "--input-tokens", "-1",
        "--output-tokens", "1",
    }, CLIParseErrorCode::invalid_value, "--input-tokens");
    expectParseError({
        "usage", "--provider", "codex",
        "--input-tokens", "9223372036854775808", "--output-tokens", "1",
    }, CLIParseErrorCode::invalid_value, "--input-tokens");
    expectParseError({
        "usage", "--provider", "codex", "--input-tokens", "1",
        "--output-tokens", "1", "--timestamp", "later",
    }, CLIParseErrorCode::invalid_value, "--timestamp");
}

void notifyAndMessageParseDisplayFields() {
    const auto notify_command = parse({
        "notify", "--title", "Ready", "--detail", "Open result",
        "--kind", "success", "--side", "left",
    });
    const auto* notify = std::get_if<CLINotifyCommand>(&notify_command);
    expect(notify != nullptr, "notify arguments should produce a notify command");
    expect(notify->notice.id == "generated-id"
            && notify->notice.title == "Ready"
            && notify->notice.detail == "Open result"
            && notify->notice.kind == NoticeKind::success
            && notify->notice.side == NoticeSide::left
            && notify->notice.created_at_unix_ms == 42'000,
        "notify command should parse its display fields");

    const auto message_command = parse({
        "message", "--app", "Messages", "--sender", "Alice",
        "--content", "Hello\nthere", "--app-bundle-id", "com.example.messages",
    });
    const auto* message = std::get_if<CLIMessageCommand>(&message_command);
    expect(message != nullptr, "message arguments should produce a message command");
    expect(message->message.app_name == "Messages"
            && message->message.sender == "Alice"
            && message->message.content == "Hello there"
            && message->message.app_bundle_identifier == "com.example.messages"
            && message->message.created_at_unix_ms == 42'000
            && message->message.pair_id == "generated-id",
        "message command should normalize and parse its fields");

    expectParseError(
        {"message", "--app", "Messages", "--sender", "Alice"},
        CLIParseErrorCode::missing_option,
        "--content");
}

void lifecycleAndHelpCommandsDispatch() {
    const auto finish = parse({"finish", "--id", "job", "--failed", "--detail", "boom"});
    const auto* finish_value = std::get_if<CLIFinishCommand>(&finish);
    expect(finish_value && finish_value->id == "job" && finish_value->failed
            && finish_value->detail == "boom",
        "finish should parse its id, flag, and detail");

    const auto remove = parse({"remove", "--id", "job"});
    const auto* remove_value = std::get_if<CLIRemoveCommand>(&remove);
    expect(remove_value && remove_value->id == "job",
        "remove should parse its id");
    expect(std::holds_alternative<CLIClearCommand>(parse({"clear"})),
        "clear should dispatch");
    expect(std::holds_alternative<CLIListCommand>(parse({"list"})),
        "list should dispatch");
    expect(std::holds_alternative<CLIHelpCommand>(parse({"--help"})),
        "help alias should dispatch");
    expectParseError({}, CLIParseErrorCode::missing_subcommand, "");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"update parses structured fields", updateParsesPercentProviderAndActiveStatuses},
        {"invalid update arguments report errors", invalidUpdateArgumentsReportStableErrors},
        {"usage parses and validates values", usageParsesStructuredValuesAndRejectsInvalidCounts},
        {"notify and message parse fields", notifyAndMessageParseDisplayFields},
        {"lifecycle and help commands dispatch", lifecycleAndHelpCommandsDispatch},
    };

    std::size_t passed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            ++passed;
        } catch (const std::exception& error) {
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }

    std::cout << passed << '/' << std::size(tests) << " tests passed\n";
    return passed == std::size(tests) ? 0 : 1;
}
