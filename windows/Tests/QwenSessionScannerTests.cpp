#include "zisla/core/QwenSessionScanner.hpp"

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
            / ("zisla-qwen-scanner-" + std::to_string(timestamp) + "-"
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
        throw std::runtime_error("unable to create Qwen fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write Qwen fixture");
    }
}

void append_file(const fs::path& path, std::string_view contents) {
    std::ofstream stream(path, std::ios::binary | std::ios::app);
    if (!stream) {
        throw std::runtime_error("unable to append Qwen fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to append Qwen fixture");
    }
}

struct RuntimeFixture {
    fs::path runtime_path;
    fs::path transcript_path;
};

RuntimeFixture write_runtime_and_transcript(
    const fs::path& root,
    std::string_view base_name,
    std::uint32_t pid,
    std::string_view session_id,
    std::string_view transcript,
    std::string_view qwen_version = {}) {
    const auto directory = root / "project";
    const auto runtime_path = directory / (std::string(base_name) + ".runtime.json");
    const auto transcript_path = directory / (std::string(base_name) + ".jsonl");
    auto runtime = std::string{"{\"pid\":"} + std::to_string(pid)
        + ",\"session_id\":\"" + std::string(session_id)
        + "\",\"started_at\":\"2026-07-19T00:59:00.000Z\"";
    if (!qwen_version.empty()) {
        runtime += ",\"qwen_version\":\"" + std::string(qwen_version) + "\"";
    }
    runtime += "}";
    write_file(runtime_path, runtime);
    write_file(transcript_path, transcript);
    return {runtime_path, transcript_path};
}

QwenSessionScanOptions scan_options(
    const fs::path& root,
    std::function<bool(std::uint32_t)> process_alive) {
    return {
        .projects_directory = root,
        .is_process_alive = std::move(process_alive),
    };
}

void running_function_call_is_reported() {
    TemporaryDirectory temporary;
    write_runtime_and_transcript(
        temporary.path(),
        "chat-1",
        4242,
        "qw-sess-1",
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z"}
{"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","message":{"model":"qwen3-coder","parts":[{"functionCall":{"name":"run_shell"}}]}}
)",
        "0.9.0");

    const QwenSessionScanner scanner(scan_options(
        temporary.path(),
        [](std::uint32_t pid) { return pid == 4242; }));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "a live Qwen runtime should create one task");
    expect(tasks.front().id == "qwen-session-qw-sess-1", "session ID should be stable");
    expect(tasks.front().provider == AIProvider::qwen, "provider should be Qwen");
    expect(tasks.front().status == AIProgressStatus::running, "function calls should run");
    expect(tasks.front().detail == "qwen3-coder", "message model should be retained");
}

void ask_user_and_tool_errors_are_reflected() {
    TemporaryDirectory temporary;
    const auto fixture = write_runtime_and_transcript(
        temporary.path(),
        "chat-blocked",
        100,
        "qw-blocked",
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z"}
{"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","message":{"parts":[{"functionCall":{"name":"ask_user_question"}}]}}
)");

    QwenSessionScanner scanner(scan_options(
        temporary.path(),
        [](std::uint32_t) { return true; }));
    const auto blocked = scanner.active_tasks();
    expect(blocked.size() == 1 && blocked.front().status == AIProgressStatus::blocked,
        "ask_user_question should block the task");

    append_file(
        fixture.transcript_path,
        R"({"type":"tool_result","timestamp":"2026-07-19T01:00:02.000Z","toolCallResult":{"status":"error"}}
)");
    const auto errored = scanner.active_tasks();
    expect(errored.size() == 1 && errored.front().status == AIProgressStatus::error,
        "tool failures should surface as errors");

    append_file(
        fixture.transcript_path,
        R"({"type":"tool_result","timestamp":"2026-07-19T01:00:03.000Z","toolCallResult":{"status":"success"}}
)");
    const auto recovered = scanner.active_tasks();
    expect(recovered.size() == 1 && recovered.front().status == AIProgressStatus::running,
        "successful tool results should clear recoverable errors");
}

void completed_and_dead_runtimes_are_ignored() {
    TemporaryDirectory temporary;
    write_runtime_and_transcript(
        temporary.path(),
        "chat-done",
        300,
        "qw-done",
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z"}
{"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","message":{"parts":[{"text":"done"}]}}
)");
    write_runtime_and_transcript(
        temporary.path(),
        "chat-dead",
        9999,
        "qw-dead",
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z"}
{"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","message":{"parts":[{"functionCall":{"name":"run_shell"}}]}}
)");

    const QwenSessionScanner scanner(scan_options(
        temporary.path(),
        [](std::uint32_t pid) { return pid == 300; }));
    expect(scanner.active_tasks().empty(),
        "completed transcripts and dead runtimes must not stay active");
}

void version_fallback_and_corrupt_records_are_safe() {
    TemporaryDirectory temporary;
    write_runtime_and_transcript(
        temporary.path(),
        "chat-version",
        700,
        "qw-version",
        "{bad\n"
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z"})"
        "\n"
        R"({"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","message":{"parts":[{"functionCall":{"name":"run_shell"}}]}})"
        "\n{\"partial\"",
        "1.2.3");

    const QwenSessionScanner scanner(scan_options(
        temporary.path(),
        [](std::uint32_t) { return true; }));
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 1 && tasks.front().detail == "1.2.3",
        "corrupt records must not discard the version fallback");

    const QwenSessionScanner missing(scan_options(
        temporary.path() / "missing",
        [](std::uint32_t) { return true; }));
    expect(missing.active_tasks().empty(), "missing Qwen directories should be tolerated");
}

void dead_newer_runtime_does_not_hide_live_runtime() {
    TemporaryDirectory temporary;
    const auto live = write_runtime_and_transcript(
        temporary.path(),
        "live",
        800,
        "qw-live",
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z"}
{"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","message":{"parts":[{"functionCall":{"name":"run_shell"}}]}}
)");
    const auto dead = write_runtime_and_transcript(
        temporary.path(),
        "dead",
        801,
        "qw-dead",
        R"({"type":"user","timestamp":"2026-07-19T02:00:00.000Z"}
{"type":"assistant","timestamp":"2026-07-19T02:00:01.000Z","message":{"parts":[{"functionCall":{"name":"run_shell"}}]}}
)");
    const auto now = fs::file_time_type::clock::now();
    fs::last_write_time(live.runtime_path, now - std::chrono::seconds(2));
    fs::last_write_time(live.transcript_path, now - std::chrono::seconds(2));
    fs::last_write_time(dead.runtime_path, now - std::chrono::seconds(1));
    fs::last_write_time(dead.transcript_path, now - std::chrono::seconds(1));

    auto options = scan_options(
        temporary.path(),
        [](std::uint32_t pid) { return pid == 800; });
    options.max_runtime_files = 1;
    const QwenSessionScanner scanner(std::move(options));
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 1 && tasks.front().id == "qwen-session-qw-live",
        "newer dead runtimes must not consume the live runtime budget");
}

void bounded_tail_does_not_restore_old_turns() {
    TemporaryDirectory temporary;
    write_runtime_and_transcript(
        temporary.path(),
        "chat-old",
        900,
        "qw-old",
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z"})"
        "\n" + std::string(4'096, 'x') + "\n");

    auto options = scan_options(
        temporary.path(),
        [](std::uint32_t) { return true; });
    options.initial_tail_bytes = 128;
    const QwenSessionScanner scanner(std::move(options));
    expect(scanner.active_tasks().empty(),
        "records outside the complete bounded tail must not stay active");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"running function call", running_function_call_is_reported},
        {"blocked and errors", ask_user_and_tool_errors_are_reflected},
        {"completed and dead", completed_and_dead_runtimes_are_ignored},
        {"version and corrupt", version_fallback_and_corrupt_records_are_safe},
        {"live runtime budget", dead_newer_runtime_does_not_hide_live_runtime},
        {"bounded tail", bounded_tail_does_not_restore_old_turns},
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
