#include "zisla/core/QoderSessionScanner.hpp"

#include <atomic>
#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>

namespace {

using namespace zisla::core;
namespace fs = std::filesystem;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        static std::atomic_uint64_t sequence{0};
        const auto timestamp = std::chrono::steady_clock::now()
                                   .time_since_epoch()
                                   .count();
        path_ = fs::temp_directory_path()
            / ("zisla-qoder-scanner-" + std::to_string(timestamp) + "-"
                + std::to_string(sequence.fetch_add(1)));
        fs::create_directories(path_);
    }

    ~TemporaryDirectory() {
        std::error_code error;
        fs::remove_all(path_, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    [[nodiscard]] const fs::path& path() const noexcept {
        return path_;
    }

private:
    fs::path path_;
};

void write_file(const fs::path& path, std::string_view contents, bool append = false) {
    fs::create_directories(path.parent_path());
    std::ofstream stream(
        path,
        std::ios::binary | (append ? std::ios::app : std::ios::trunc));
    if (!stream) {
        throw std::runtime_error("unable to create Qoder fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write Qoder fixture");
    }
}

fs::path structured_log(const fs::path& root, std::string_view session_id) {
    return root / "logs" / "sessions" / std::string(session_id)
        / "segments" / "0001.jsonl";
}

QoderSessionScanOptions structured_options(const fs::path& root) {
    return {.config_roots = {root}, .text_log_roots = {}};
}

void structured_turns_track_running_blocked_error_and_completion() {
    TemporaryDirectory temporary;
    const auto log = structured_log(temporary.path(), "session-1");
    write_file(
        log,
        R"({"ts":"2026-07-19T01:00:00.000Z","type":"turn.started","ids":{"session_id":"session-1"},"data":{"model":"qoder-pro"}})" "\n"
        R"({"ts":"2026-07-19T01:00:01.000Z","type":"permission.requested","ids":{"session_id":"session-1","tool_call_id":"tool-1"},"data":{}})" "\n");

    const QoderSessionScanner scanner(structured_options(temporary.path()));
    auto tasks = scanner.active_tasks();
    expect(tasks.size() == 1, "structured turn should create one task");
    expect(tasks.front().id == "qoder-session-session-1", "session ID should be stable");
    expect(tasks.front().provider == AIProvider::coder, "Qoder should use coder provider");
    expect(tasks.front().detail == "CLI", "structured logs should be marked CLI");
    expect(tasks.front().status == AIProgressStatus::blocked,
        "pending permission should be blocked");

    write_file(
        log,
        R"({"ts":"2026-07-19T01:00:02.000Z","type":"permission.resolved","ids":{"session_id":"session-1","tool_call_id":"tool-1"},"data":{}})" "\n"
        R"({"ts":"2026-07-19T01:00:03.000Z","type":"tool.execution.finished","ids":{"session_id":"session-1"},"data":{"status":"error","is_error":true}})" "\n",
        true);
    tasks = scanner.active_tasks();
    expect(tasks.front().status == AIProgressStatus::error,
        "tool errors should remain visible");

    write_file(
        log,
        R"({"ts":"2026-07-19T01:00:04.000Z","type":"tool.shell.finished","ids":{"session_id":"session-1"},"data":{"exit_code":0}})" "\n"
        R"({"ts":"2026-07-19T01:00:05.000Z","type":"turn.finished","ids":{"session_id":"session-1"},"data":{"reason":"completed"}})" "\n",
        true);
    expect(scanner.active_tasks().empty(), "completed turn should not remain active");
}

void desktop_text_logs_track_blocking_error_and_success() {
    TemporaryDirectory temporary;
    const auto log = temporary.path() / "QoderWork" / "logs" / "qoder-agent-sdk.log";
    write_file(
        log,
        "2026-07-19T01:00:00.000Z [QueryRunner] outbound session_message sent type=user\n");
    const QoderSessionScanner scanner({
        .config_roots = {},
        .text_log_roots = {temporary.path()},
    });

    auto tasks = scanner.active_tasks();
    expect(tasks.size() == 1 && tasks.front().status == AIProgressStatus::running,
        "desktop user request should be running");
    expect(tasks.front().detail == "Desktop", "desktop host should be classified");

    write_file(
        log,
        "2026-07-19T01:00:01.000Z inbound control_request received request_id=req-1 subtype=can_use_tool\n",
        true);
    expect(scanner.active_tasks().front().status == AIProgressStatus::blocked,
        "pending desktop permission should be blocked");

    write_file(
        log,
        "2026-07-19T01:00:02.000Z inbound control_response sent request_id=req-1 subtype=can_use_tool status=denied\n",
        true);
    expect(scanner.active_tasks().front().status == AIProgressStatus::error,
        "denied desktop permission should be an error");

    write_file(
        log,
        "2026-07-19T01:00:03.000Z [QueryRunner] outbound session_message sent type=user\n"
        "2026-07-19T01:00:04.000Z inbound session_message received type=result subtype=success\n",
        true);
    expect(scanner.active_tasks().empty(), "successful desktop result should complete");
}

void merges_only_unambiguous_desktop_and_structured_turns() {
    TemporaryDirectory temporary;
    const auto structured = structured_log(temporary.path() / "config", "session-desktop");
    const auto text = temporary.path() / "logs" / "QoderWork" / "qoder-agent-sdk.log";
    write_file(
        structured,
        R"({"ts":"2026-07-19T01:00:00.453Z","type":"turn.started","ids":{"session_id":"session-desktop"},"data":{}})" "\n");
    write_file(
        text,
        "2026-07-19T01:00:00.000Z [QueryRunner] outbound session_message sent type=user\n"
        "2026-07-19T01:00:01.000Z inbound control_request received request_id=req-1 subtype=can_use_tool\n");

    const QoderSessionScanner scanner({
        .config_roots = {temporary.path() / "config"},
        .text_log_roots = {temporary.path() / "logs"},
    });
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 1, "one unambiguous desktop turn should merge");
    expect(tasks.front().id == "qoder-session-session-desktop", "session task should win");
    expect(tasks.front().detail == "Desktop", "merged task should use desktop detail");
    expect(tasks.front().status == AIProgressStatus::blocked,
        "desktop blocked status should dominate");
    expect(tasks.front().session_uri
            == "qoder-work-cn://notification-click?chatId=session-desktop",
        "merged task should use the documented desktop deep-link shape");
}

void bounds_tails_and_tolerates_missing_roots() {
    TemporaryDirectory temporary;
    const auto log = structured_log(temporary.path(), "old-session");
    write_file(
        log,
        R"({"ts":"2026-07-19T01:00:00.000Z","type":"turn.started","ids":{"session_id":"old-session"},"data":{}})" "\n"
            + std::string(1'024, 'x') + "\n");
    auto options = structured_options(temporary.path());
    options.initial_tail_bytes = 128;
    const QoderSessionScanner bounded(std::move(options));
    expect(bounded.active_tasks().empty(), "state outside bounded tails must be ignored");

    const QoderSessionScanner missing({
        .config_roots = {temporary.path() / "missing"},
        .text_log_roots = {temporary.path() / "missing-text"},
    });
    expect(missing.active_tasks().empty(), "missing Qoder roots should be tolerated");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"structured state", structured_turns_track_running_blocked_error_and_completion},
        {"desktop text state", desktop_text_logs_track_blocking_error_and_success},
        {"desktop merge", merges_only_unambiguous_desktop_and_structured_turns},
        {"bounds and missing", bounds_tails_and_tolerates_missing_roots},
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
