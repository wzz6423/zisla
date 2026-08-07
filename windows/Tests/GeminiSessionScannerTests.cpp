#include "zisla/core/GeminiSessionScanner.hpp"

#include <algorithm>
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
            / ("zisla-gemini-scanner-" + std::to_string(timestamp) + "-"
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

void write_file(const fs::path& path, std::string_view contents) {
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) {
        throw std::runtime_error("unable to create Gemini fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write Gemini fixture");
    }
}

void append_file(const fs::path& path, std::string_view contents) {
    std::ofstream stream(path, std::ios::binary | std::ios::app);
    if (!stream) {
        throw std::runtime_error("unable to append Gemini fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to append Gemini fixture");
    }
}

std::string metadata_line(std::string_view session_id) {
    return R"({"sessionId":")" + std::string(session_id)
        + R"(","startTime":"2026-07-19T01:00:00.000Z"})";
}

std::string user_line(std::string_view timestamp = "2026-07-19T01:00:01.000Z") {
    return R"({"type":"user","timestamp":")" + std::string(timestamp)
        + R"(","content":"ignored"})";
}

void user_turn_is_running() {
    TemporaryDirectory temporary;
    const auto root = temporary.path() / "tmp";
    const auto session = root / "project" / "chats" / "session-running.jsonl";
    write_file(session, metadata_line("gem-running") + "\n" + user_line() + "\n");

    const GeminiSessionScanner scanner({.sessions_directory = root});
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "a Gemini user turn should create one task");
    expect(tasks.front().id == "gemini-session-gem-running", "session ID should be stable");
    expect(tasks.front().provider == AIProvider::gemini, "provider should be Gemini");
    expect(tasks.front().status == AIProgressStatus::running, "user turn should run");
}

void approval_block_and_recovery_are_reflected() {
    TemporaryDirectory temporary;
    const auto root = temporary.path() / "tmp";
    const auto session = root / "project" / "chats" / "session-blocked.jsonl";
    write_file(
        session,
        metadata_line("gem-blocked") + "\n" + user_line() + "\n"
            + R"({"type":"gemini","timestamp":"2026-07-19T01:00:02.000Z","model":"gemini-2.5-pro","toolCalls":[{"status":"awaiting_approval"}]})"
            + "\n");

    GeminiSessionScanner scanner({.sessions_directory = root});
    const auto blocked = scanner.active_tasks();
    expect(blocked.size() == 1 && blocked.front().status == AIProgressStatus::blocked,
        "awaiting approval should block the task");

    append_file(
        session,
        R"({"type":"gemini","timestamp":"2026-07-19T01:00:03.000Z","model":"gemini-2.5-pro","toolCalls":[{"status":"executing"}]})"
            "\n");
    const auto resumed = scanner.active_tasks();
    expect(resumed.size() == 1 && resumed.front().status == AIProgressStatus::running,
        "executing should resume the task");
    expect(resumed.front().detail == "gemini-2.5-pro", "model should be retained");
}

void tool_error_and_later_success_recover() {
    TemporaryDirectory temporary;
    const auto root = temporary.path() / "tmp";
    const auto session = root / "project" / "chats" / "session-error.jsonl";
    write_file(
        session,
        metadata_line("gem-error") + "\n" + user_line() + "\n"
            + R"({"type":"gemini","timestamp":"2026-07-19T01:00:02.000Z","toolCalls":[{"status":"error"}]})"
            + "\n");

    GeminiSessionScanner scanner({.sessions_directory = root});
    const auto errored = scanner.active_tasks();
    expect(errored.size() == 1 && errored.front().status == AIProgressStatus::error,
        "tool errors should surface as errors");

    append_file(
        session,
        R"({"type":"gemini","timestamp":"2026-07-19T01:00:03.000Z","toolCalls":[{"status":"success"}]})"
            "\n");
    const auto recovered = scanner.active_tasks();
    expect(recovered.size() == 1 && recovered.front().status == AIProgressStatus::running,
        "a later tool update should clear a recoverable error");
}

void final_assistant_reply_completes_the_turn() {
    TemporaryDirectory temporary;
    const auto root = temporary.path() / "tmp";
    const auto session = root / "project" / "chats" / "session-complete.jsonl";
    write_file(
        session,
        metadata_line("gem-complete") + "\n" + user_line() + "\n"
            + R"({"type":"gemini","timestamp":"2026-07-19T01:00:02.000Z","model":"gemini-2.5-flash","content":"done"})"
            + "\n");

    const GeminiSessionScanner scanner({.sessions_directory = root});
    expect(scanner.active_tasks().empty(), "a final assistant reply should end the turn");
}

void legacy_json_and_corrupt_jsonl_are_tolerated() {
    TemporaryDirectory temporary;
    const auto root = temporary.path() / "tmp";
    write_file(
        root / "legacy" / "chats" / "session-legacy.json",
        R"({"sessionId":"gem-legacy","startTime":"2026-07-19T01:00:00.000Z","messages":[{"type":"user","timestamp":"2026-07-19T01:00:01.000Z"},{"type":"error","timestamp":"2026-07-19T01:00:02.000Z"}]})");
    write_file(
        root / "noisy" / "chats" / "session-noisy.jsonl",
        metadata_line("gem-noisy") + "\n{bad\n" + user_line() + "\n{\"partial\"");

    const GeminiSessionScanner scanner({.sessions_directory = root});
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 2, "corrupt and partial records should not discard valid tasks");
    const auto legacy = std::find_if(tasks.begin(), tasks.end(), [](const auto& task) {
        return task.id == "gemini-session-gem-legacy";
    });
    expect(legacy != tasks.end() && legacy->status == AIProgressStatus::error,
        "legacy JSON should preserve explicit errors");
}

void bounded_tail_and_missing_directory_are_safe() {
    TemporaryDirectory temporary;
    const auto root = temporary.path() / "tmp";
    const auto session = root / "project" / "chats" / "session-old.jsonl";
    write_file(
        session,
        metadata_line("gem-old") + "\n" + user_line() + "\n"
            + std::string(4'096, 'x') + "\n");

    const GeminiSessionScanner bounded({
        .sessions_directory = root,
        .initial_tail_bytes = 128,
    });
    expect(bounded.active_tasks().empty(),
        "records outside the complete bounded tail must not stay active");

    const GeminiSessionScanner missing({
        .sessions_directory = temporary.path() / "missing",
    });
    expect(missing.active_tasks().empty(), "missing Gemini directory should be tolerated");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"user turn is running", user_turn_is_running},
        {"approval block and recovery", approval_block_and_recovery_are_reflected},
        {"tool error recovery", tool_error_and_later_success_recover},
        {"final reply completes", final_assistant_reply_completes_the_turn},
        {"legacy and corrupt records", legacy_json_and_corrupt_jsonl_are_tolerated},
        {"bounded tail and missing directory", bounded_tail_and_missing_directory_are_safe},
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
