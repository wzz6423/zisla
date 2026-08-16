#include "zisla/core/CodexActivityParser.hpp"

#include <array>
#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

std::vector<AIProgressTask> parseOne(
    std::string_view jsonl,
    std::int64_t modified_at_unix_ms = 1'800'000'000'000,
    std::string_view session_index_jsonl = {}) {
    const std::array rollouts = {
        CodexRolloutSnapshot{
            .jsonl = jsonl,
            .modified_at_unix_ms = modified_at_unix_ms,
        },
    };
    return CodexActivityParser::active_tasks(rollouts, session_index_jsonl);
}

void runningTurnCarriesModelSessionAndStableIdentity() {
    constexpr std::string_view rollout =
        R"({"type":"session_meta","payload":{"id":"session-123"}})" "\n"
        R"({"timestamp":"2026-07-19T01:00:00.000Z","type":"turn_context","payload":{"turn_id":"turn-session","model":"gpt-5.6-sol","effort":"xhigh"}})" "\n"
        R"({"timestamp":"2026-07-19T09:00:01.250+08:00","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-session"}})" "\n";
    constexpr std::string_view index =
        R"({"id":"session-123","thread_name":"  Fix session jump  "})" "\n";

    const auto tasks = parseOne(rollout, 1'800'000'125'000, index);

    expect(tasks.size() == 1, "one unpaired task_started event should be active");
    const auto& task = tasks.front();
    expect(task.id == "codex-turn-turn-session", "task id should match macOS persistence");
    expect(task.provider == AIProvider::gpt, "GPT models should use the ChatGPT provider identity");
    expect(task.title == "Fix session jump", "session index title should be trimmed and applied");
    expect(task.detail == "gpt-5.6-sol", "model should be exposed as task detail");
    expect(task.effort == "xhigh", "reasoning effort should be retained");
    expect(task.status == AIProgressStatus::running, "a started turn should be running");
    expect(task.started_at_unix_ms == 1'784'422'801'250,
        "RFC 3339 offsets and fractional seconds should normalize to UTC milliseconds");
    expect(task.updated_at_unix_ms == 1'800'000'125'000,
        "the latest started turn should use the rollout modification time as activity");
    expect(task.session_uri == "codex://threads/session-123",
        "session metadata should produce a stable Codex deep link");
}

void userInputAndApprovalRemainBlockedUntilMatchingOutput() {
    constexpr std::string_view blocked =
        R"({"timestamp":"2026-07-19T01:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-blocked"}})" "\n"
        R"({"timestamp":"2026-07-19T01:00:01.000Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"call-question","internal_chat_message_metadata_passthrough":{"turn_id":"turn-blocked"}}})" "\n"
        R"json({"timestamp":"2026-07-19T01:00:02.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","call_id":"call-approval","input":"tools.exec_command({sandbox_permissions: 'require_escalated'})","internal_chat_message_metadata_passthrough":{"turn_id":"turn-blocked"}}})json" "\n"
        R"({"timestamp":"2026-07-19T01:00:03.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call-question","output":"answered"}})" "\n";

    const auto waiting = parseOne(blocked);
    expect(waiting.size() == 1 && waiting[0].status == AIProgressStatus::blocked,
        "an unresolved approval should keep the turn blocked");

    const std::string resolved = std::string(blocked)
        + R"({"timestamp":"2026-07-19T01:00:04.000Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call-approval","output":"approved"}})"
        + "\n";
    const auto tasks = parseOne(resolved);
    expect(tasks.size() == 1 && tasks[0].status == AIProgressStatus::running,
        "matching outputs should resolve every pending blocking call");
}

void failedToolOutputRecoversAfterSuccessfulOutput() {
    constexpr std::string_view failed =
        R"({"timestamp":"2026-07-19T01:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-error"}})" "\n"
        R"({"timestamp":"2026-07-19T01:00:01.000Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call-error","internal_chat_message_metadata_passthrough":{"turn_id":"turn-error"},"output":[{"type":"input_text","text":"{\"exit_code\":1,\"output\":\"failed\"}"}]}})" "\n";

    const auto errored = parseOne(failed);
    expect(errored.size() == 1 && errored[0].status == AIProgressStatus::error,
        "a nested non-zero exit code should mark the active turn as errored");

    const std::string recovered = std::string(failed)
        + R"({"timestamp":"2026-07-19T01:00:02.000Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call-ok","internal_chat_message_metadata_passthrough":{"turn_id":"turn-error"},"output":{"exitCode":"0"}}})"
        + "\n";
    const auto tasks = parseOne(recovered);
    expect(tasks.size() == 1 && tasks[0].status == AIProgressStatus::running,
        "a later successful output should clear a recoverable tool error");
}

void completionAndAbortRemoveTurnsAcrossRolloutFiles() {
    constexpr std::string_view first =
        R"({"timestamp":"2026-07-19T01:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-done"}})" "\n"
        R"({"timestamp":"2026-07-19T01:02:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-abort"}})" "\n";
    constexpr std::string_view second =
        R"({"timestamp":"2026-07-19T01:01:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-done"}})" "\n"
        R"({"timestamp":"2026-07-19T01:03:00.000Z","type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-abort"}})" "\n"
        R"({"timestamp":"2026-07-19T01:04:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-live"}})" "\n";
    const std::array rollouts = {
        CodexRolloutSnapshot{first, 1'800'000'100'000},
        CodexRolloutSnapshot{second, 1'800'000'200'000},
    };

    const auto tasks = CodexActivityParser::active_tasks(rollouts);

    expect(tasks.size() == 1 && tasks[0].id == "codex-turn-turn-live",
        "completion and abort events should close matching turns across files");
}

void malformedRecordsAndPartialTailAreIgnored() {
    constexpr std::string_view rollout =
        "{not-json\n"
        R"({"timestamp":"2026-07-19T01:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-live"}})" "\n"
        R"({"timestamp":"2026-07-19T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started"}})" "\n"
        R"({"timestamp":"2026-07-19T01:00:02.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"partial"}})";

    const auto tasks = parseOne(rollout);

    expect(tasks.size() == 1 && tasks[0].id == "codex-turn-turn-live",
        "invalid records and an unterminated writer tail should be ignored");
}

void latestRepeatedStartWinsWithoutDuplicatingTheTurn() {
    constexpr std::string_view rollout =
        R"({"timestamp":"2026-07-19T01:00:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-repeat"}})" "\n"
        R"({"timestamp":"2026-07-19T01:00:02.000Z","type":"turn_context","payload":{"turn_id":"turn-repeat","model":"gpt-5.2-codex","reasoning_effort":" high "}})" "\n"
        R"({"timestamp":"2026-07-19T01:00:03.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-repeat"}})" "\n";

    const auto tasks = parseOne(rollout);

    expect(tasks.size() == 1, "repeated starts for one turn should not duplicate tasks");
    expect(tasks[0].provider == AIProvider::codex && tasks[0].title == "Codex",
        "a Codex model should retain the Codex identity");
    expect(tasks[0].effort == "high", "reasoning_effort should be accepted and trimmed");
    expect(tasks[0].started_at_unix_ms == 1'784'422'803'000,
        "the latest start should replace the earlier lifecycle event");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"running turn maps model and session", runningTurnCarriesModelSessionAndStableIdentity},
        {"blocking calls require matching output", userInputAndApprovalRemainBlockedUntilMatchingOutput},
        {"tool error recovers after success", failedToolOutputRecoversAfterSuccessfulOutput},
        {"completion closes turns across files", completionAndAbortRemoveTurnsAcrossRolloutFiles},
        {"malformed and partial records are ignored", malformedRecordsAndPartialTailAreIgnored},
        {"latest repeated start wins", latestRepeatedStartWinsWithoutDuplicatingTheTurn},
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
