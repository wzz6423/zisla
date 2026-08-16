#include "zisla/core/CodexSessionScanner.hpp"

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
#include <vector>

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
            / ("zisla-codex-scanner-" + std::to_string(timestamp) + "-"
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

std::string event_line(
    std::string_view timestamp,
    std::string_view event_type,
    std::string_view turn_id) {
    return "{\"timestamp\":\"" + std::string(timestamp)
        + "\",\"type\":\"event_msg\",\"payload\":{\"type\":\""
        + std::string(event_type) + "\",\"turn_id\":\""
        + std::string(turn_id) + "\"}}";
}

void write_file(const fs::path& path, std::string_view contents) {
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) {
        throw std::runtime_error("unable to create test fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write test fixture");
    }
}

void scansNewestRolloutAndAppliesSessionTitle() {
    TemporaryDirectory temporary;
    const auto sessions = temporary.path() / "sessions";
    const auto index = temporary.path() / "session_index.jsonl";
    const auto old_rollout = sessions / "2026/07/18/rollout-old.jsonl";
    const auto new_rollout = sessions / "2026/07/19/rollout-new.jsonl";

    write_file(
        old_rollout,
        event_line("2026-07-18T01:00:00.000Z", "task_started", "turn-old")
            + "\n");
    write_file(
        new_rollout,
        R"({"type":"session_meta","payload":{"id":"session-new"}})" "\n"
        R"({"timestamp":"2026-07-19T01:00:00.000Z","type":"turn_context","payload":{"turn_id":"turn-new","model":"gpt-5.6-sol","effort":"high"}})" "\n"
            + event_line(
                "2026-07-19T01:00:01.000Z",
                "task_started",
                "turn-new")
            + "\n");
    write_file(
        sessions / "2026/07/19/not-a-rollout.jsonl",
        event_line("2026-07-19T01:00:02.000Z", "task_started", "turn-noise")
            + "\n");
    write_file(index, R"({"id":"session-new","thread_name":"  Windows shell  "})" "\n");

    const auto now = fs::file_time_type::clock::now();
    fs::last_write_time(old_rollout, now - std::chrono::hours(2));
    fs::last_write_time(new_rollout, now - std::chrono::hours(1));

    const CodexSessionScanner scanner({
        .sessions_directory = sessions,
        .session_index_path = index,
        .max_rollout_files = 1,
    });
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "only the newest rollout should be selected");
    expect(tasks[0].id == "codex-turn-turn-new", "selected rollout should be parsed");
    expect(tasks[0].provider == AIProvider::gpt, "model should select the GPT identity");
    expect(tasks[0].title == "Windows shell", "session index title should be applied");
    expect(tasks[0].detail == "gpt-5.6-sol", "model detail should be retained");
    expect(tasks[0].effort == "high", "reasoning effort should be retained");
}

void boundedTailStartsAtCompleteLineAndIgnoresPartialTail() {
    TemporaryDirectory temporary;
    const auto sessions = temporary.path() / "sessions";
    const auto rollout = sessions / "2026/07/19/rollout-tail.jsonl";
    const auto recent = event_line(
        "2026-07-19T02:00:00.000Z",
        "task_started",
        "turn-recent");
    const auto partial = event_line(
        "2026-07-19T02:01:00.000Z",
        "task_started",
        "turn-partial");
    const std::string contents = event_line(
        "2026-07-18T01:00:00.000Z",
        "task_started",
        "turn-outside-tail")
        + "\n" + std::string(512, 'x') + "\n" + recent + "\n" + partial;
    write_file(rollout, contents);

    const CodexSessionScanner scanner({
        .sessions_directory = sessions,
        .initial_tail_bytes = recent.size() + partial.size() + 32,
    });
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "only one complete lifecycle event is inside the tail");
    expect(tasks[0].id == "codex-turn-turn-recent",
        "partial leading and trailing lines should be ignored");
}

void lifecycleEventsPairAcrossRolloutFiles() {
    TemporaryDirectory temporary;
    const auto sessions = temporary.path() / "sessions";
    write_file(
        sessions / "2026/07/19/rollout-a.jsonl",
        event_line("2026-07-19T03:00:00.000Z", "task_started", "turn-closed")
            + "\n");
    write_file(
        sessions / "2026/07/19/rollout-b.jsonl",
        event_line("2026-07-19T03:01:00.000Z", "task_complete", "turn-closed")
            + "\n"
            + event_line("2026-07-19T03:02:00.000Z", "task_started", "turn-live")
            + "\n");

    const CodexSessionScanner scanner({.sessions_directory = sessions});
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "completion in a separate rollout should close the task");
    expect(tasks[0].id == "codex-turn-turn-live", "the remaining active turn should survive");
}

void missingSessionsDirectoryProducesNoTasks() {
    TemporaryDirectory temporary;
    const CodexSessionScanner scanner({
        .sessions_directory = temporary.path() / "missing",
    });

    expect(scanner.active_tasks().empty(), "a missing sessions directory should be tolerated");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"newest rollout and session title", scansNewestRolloutAndAppliesSessionTitle},
        {"bounded tail honors line boundaries", boundedTailStartsAtCompleteLineAndIgnoresPartialTail},
        {"lifecycle pairs across files", lifecycleEventsPairAcrossRolloutFiles},
        {"missing sessions directory", missingSessionsDirectoryProducesNoTasks},
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
