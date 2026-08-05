#include "zisla/core/ClaudeSessionScanner.hpp"

#include <atomic>
#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
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
            / ("zisla-claude-scanner-" + std::to_string(timestamp) + "-"
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
        throw std::runtime_error("unable to create transcript fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write transcript fixture");
    }
}

std::string active_transcript(std::string_view session_id, std::string_view model) {
    return R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z","sessionId":")"
        + std::string(session_id)
        + R"(","message":{"content":[{"type":"text"}]}})" "\n"
        + R"({"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","sessionId":")"
        + std::string(session_id)
        + R"(","message":{"model":")" + std::string(model)
        + R"(","stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Bash"}]}})"
        + "\n";
}

void scanner_selects_recent_files_and_discards_hidden_directories() {
    TemporaryDirectory temporary;
    const auto projects = temporary.path() / "projects";
    const auto old_path = projects / "old-project" / "old.jsonl";
    const auto new_path = projects / "new-project" / "new.jsonl";
    write_file(old_path, active_transcript("old-session", "claude-haiku"));
    write_file(new_path, active_transcript("new-session", "claude-opus"));
    write_file(
        projects / ".hidden" / "ignored.jsonl",
        active_transcript("hidden-session", "claude-secret"));

    const auto now = fs::file_time_type::clock::now();
    fs::last_write_time(old_path, now - std::chrono::hours(2));
    fs::last_write_time(new_path, now - std::chrono::hours(1));

    const ClaudeSessionScanner scanner({
        .projects_directory = projects,
        .max_transcript_files = 1,
    });
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "only the newest visible transcript should be selected");
    expect(tasks.front().id == "claude-session-new-session",
        "the newest transcript should be parsed");
    expect(tasks.front().detail == "claude-opus", "model should survive scanner ownership");
}

void bounded_tail_does_not_reactivate_old_records() {
    TemporaryDirectory temporary;
    const auto projects = temporary.path() / "projects";
    const auto transcript = projects / "project" / "bounded.jsonl";
    std::string contents = active_transcript("outside-tail", "claude-sonnet");
    contents += std::string(4'096, 'x');
    contents += "\n";
    write_file(transcript, contents);

    const ClaudeSessionScanner scanner({
        .projects_directory = projects,
        .initial_tail_bytes = 128,
    });
    expect(scanner.active_tasks().empty(),
        "records before the complete bounded tail must not remain active");
}

void missing_directory_and_filename_fallback_are_safe() {
    TemporaryDirectory temporary;
    const ClaudeSessionScanner missing({
        .projects_directory = temporary.path() / "missing",
    });
    expect(missing.active_tasks().empty(), "missing projects directory should be tolerated");

    const auto transcript = temporary.path() / "projects" / "project" / "fallback-id.jsonl";
    write_file(
        transcript,
        R"({"type":"user","timestamp":"2026-07-19T01:00:00.000Z","message":{"content":[{"type":"text"}]}})" "\n"
        R"({"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","message":{"stop_reason":"tool_use","content":[{"type":"tool_use","id":"tool-1","name":"Read"}]}})" "\n");
    const ClaudeSessionScanner scanner({
        .projects_directory = temporary.path() / "projects",
    });
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 1 && tasks.front().id == "claude-session-fallback-id",
        "filename stem should recover a session identity when the log omits one");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"recent visible transcript selection", scanner_selects_recent_files_and_discards_hidden_directories},
        {"bounded tail", bounded_tail_does_not_reactivate_old_records},
        {"missing directory and fallback", missing_directory_and_filename_fallback_are_safe},
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
