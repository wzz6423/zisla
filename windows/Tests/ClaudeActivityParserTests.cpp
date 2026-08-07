#include "zisla/core/ClaudeActivityParser.hpp"

#include <array>
#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

std::vector<AIProgressTask> parse_one(
    std::string_view jsonl,
    std::int64_t modified_at_unix_ms = 1'900'000'000'000,
    std::string_view fallback_session_id = {}) {
    const std::array transcripts = {
        ClaudeTranscriptSnapshot{
            .jsonl = jsonl,
            .modified_at_unix_ms = modified_at_unix_ms,
            .fallback_session_id = fallback_session_id,
        },
    };
    return ClaudeActivityParser::active_tasks(transcripts);
}

void running_tool_use_carries_model_and_identity() {
    constexpr std::string_view transcript =
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z","sessionId":"sess-a","message":{"content":[{"type":"text","text":"private prompt"}]}})" "\n"
        R"({"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","sessionId":"sess-a","message":{"model":"claude-sonnet-4","stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Bash"}]}})" "\n";

    const auto tasks = parse_one(transcript, 1'900'000'100'000);

    expect(tasks.size() == 1, "active Claude transcript should produce one task");
    const auto& task = tasks.front();
    expect(task.id == "claude-session-sess-a", "task id should remain stable per session");
    expect(task.provider == AIProvider::claude, "task should keep the Claude provider");
    expect(task.title == "Claude", "CLI sessions should use the Claude title");
    expect(task.detail == "claude-sonnet-4", "model should be preserved without transcript text");
    expect(task.status == AIProgressStatus::running, "ordinary tool use should remain running");
    expect(task.started_at_unix_ms.has_value(), "task should retain its start timestamp");
    expect(task.updated_at_unix_ms == 1'900'000'100'000,
        "file modification time should keep a recently written transcript fresh");
}

void ask_user_question_stays_blocked_until_its_result() {
    constexpr std::string_view blocked =
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z","sessionId":"sess-b","message":{"content":[{"type":"text"}]}})" "\n"
        R"({"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","sessionId":"sess-b","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"ask-1","name":"AskUserQuestion"}]}})" "\n";

    const auto waiting = parse_one(blocked);
    expect(waiting.size() == 1 && waiting.front().status == AIProgressStatus::blocked,
        "AskUserQuestion should expose a blocked task");

    const auto resolved = std::string(blocked)
        + R"({"type":"user","timestamp":"2026-07-19T01:00:02.000Z","sessionId":"sess-b","message":{"content":[{"type":"tool_result","tool_use_id":"ask-1","is_error":false}]}})"
        + "\n";
    const auto running = parse_one(resolved);
    expect(running.size() == 1 && running.front().status == AIProgressStatus::running,
        "matching tool_result should resolve the blocked state");
}

void tool_result_error_can_recover() {
    constexpr std::string_view errored =
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z","sessionId":"sess-c","message":{"content":[{"type":"text"}]}})" "\n"
        R"({"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","sessionId":"sess-c","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Bash"}]}})" "\n"
        R"({"type":"user","timestamp":"2026-07-19T01:00:02.000Z","sessionId":"sess-c","message":{"content":[{"type":"tool_result","tool_use_id":"tool-1","isError":true}]}})" "\n";

    const auto failed = parse_one(errored);
    expect(failed.size() == 1 && failed.front().status == AIProgressStatus::error,
        "failed tool_result should make a live task errored");

    const auto recovered = std::string(errored)
        + R"({"type":"user","timestamp":"2026-07-19T01:00:03.000Z","sessionId":"sess-c","message":{"content":[{"type":"tool_result","tool_use_id":"tool-2","is_error":false}]}})"
        + "\n";
    const auto running = parse_one(recovered);
    expect(running.size() == 1 && running.front().status == AIProgressStatus::running,
        "a later successful result should clear a recoverable error");
}

void completion_and_api_error_follow_claude_lifecycle() {
    constexpr std::string_view complete =
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z","sessionId":"sess-d","message":{"content":[{"type":"text"}]}})" "\n"
        R"({"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","sessionId":"sess-d","message":{"stop_reason":"end_turn","content":[]}})" "\n";
    expect(parse_one(complete).empty(), "end_turn should remove a completed task");

    constexpr std::string_view api_error =
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z","sessionId":"sess-e","message":{"content":[{"type":"text"}]}})" "\n"
        R"({"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","sessionId":"sess-e","isApiErrorMessage":true,"apiErrorStatus":502,"error":"upstream","message":{"stop_reason":"stop_sequence","content":[]}})" "\n";
    const auto tasks = parse_one(api_error);
    expect(tasks.size() == 1 && tasks.front().status == AIProgressStatus::error,
        "API errors should stay visible as errored activity");
}

void vscode_sessions_have_their_deep_link() {
    constexpr std::string_view transcript =
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z","session_id":"sess-vs","entrypoint":"claude-vscode","message":{"content":[{"type":"text"}]}})" "\n"
        R"({"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","session_id":"sess-vs","message":{"model":"claude-opus","stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Read"}]}})" "\n";

    const auto tasks = parse_one(transcript);
    expect(tasks.size() == 1, "VS Code transcript should be recognized");
    expect(tasks.front().title == "Claude Code (VS Code)",
        "VS Code entrypoint should change the title");
    expect(tasks.front().session_uri
            == "vscode://anthropic.claude-code/open?session=sess-vs",
        "VS Code sessions should expose their deep link");
}

void malformed_partial_and_fallback_records_are_safe() {
    constexpr std::string_view transcript =
        "{not-json\n"
        R"({"type":"user","timestamp":1784422800,"message":{"content":[{"type":"text"}]}})" "\n"
        R"({"type":"assistant","timestamp":1784422801,"message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Edit"}]}})" "\n"
        R"({"type":"assistant","timestamp":"2026-07-19T01:00:02.000Z")";

    const auto tasks = parse_one(transcript, 1'900'000'000'000, "fallback-session");
    expect(tasks.size() == 1, "corrupt lines and partial tails should be ignored");
    expect(tasks.front().id == "claude-session-fallback-session",
        "the scanner fallback should keep transcripts without a sessionId identifiable");
    expect(tasks.front().status == AIProgressStatus::running,
        "ordinary tool use should remain running after malformed input");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"running task carries model", running_tool_use_carries_model_and_identity},
        {"AskUserQuestion is blocked", ask_user_question_stays_blocked_until_its_result},
        {"tool error recovers", tool_result_error_can_recover},
        {"completion and API error", completion_and_api_error_follow_claude_lifecycle},
        {"VS Code deep link", vscode_sessions_have_their_deep_link},
        {"malformed and fallback input", malformed_partial_and_fallback_records_are_safe},
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
