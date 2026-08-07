#include "zisla/core/TraeSessionScanner.hpp"

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
            / ("zisla-trae-scanner-" + std::to_string(timestamp) + "-"
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

fs::path write_log(
    const fs::path& root,
    std::string_view session_directory,
    std::string_view file_name,
    std::string_view contents) {
    const auto path = root / std::string(session_directory) / "Modular"
        / std::string(file_name);
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) {
        throw std::runtime_error("unable to create TRAE fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write TRAE fixture");
    }
    return path;
}

TraeSessionScanOptions scan_options(const fs::path& root) {
    return {.logs_roots = {root}};
}

void chat_activity_retains_safe_task_metadata() {
    TemporaryDirectory temporary;
    write_log(
        temporary.path(),
        "20260723T174155",
        "ai-agent_worker_stdout.log",
        "2026-07-23T20:08:01.801423+08:00  INFO agent::do_chat: request task_id=task-1 session_id=session-1 prompt=private\n");

    const TraeSessionScanner scanner(scan_options(temporary.path()));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "TRAE chat log should create one task");
    expect(tasks.front().id == "trae-task-task-1", "TRAE task ID should be stable");
    expect(tasks.front().provider == AIProvider::trae, "TRAE provider should be retained");
    expect(tasks.front().title == "TRAE", "TRAE title should be stable");
    expect(!tasks.front().detail.has_value(), "log text must not become task detail");
    expect(tasks.front().status == AIProgressStatus::running, "chat activity should run");
    expect(tasks.front().session_uri
            == "solo-cn://solo-deeplink.ai/teleport_session?sid=session-1",
        "session ID should use the official deep-link shape");
}

void error_lines_and_duplicates_are_merged() {
    TemporaryDirectory temporary;
    write_log(
        temporary.path(),
        "20260723T174155",
        "ai-agent_first_stdout.log",
        "2026-07-23T20:08:01Z  INFO agent::do_chat: task_id=shared session_id=one\n");
    write_log(
        temporary.path(),
        "20260724T174155",
        "ai-agent_second_stdout.log",
        "2026-07-24T20:08:01Z  ERROR agent::worker: failed task_id=shared session_id=two\n");

    const TraeSessionScanner scanner(scan_options(temporary.path()));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "same TRAE task should merge across log files");
    expect(tasks.front().status == AIProgressStatus::error, "TRAE error lines should surface errors");
    expect(tasks.front().session_uri
            == "solo-cn://solo-deeplink.ai/teleport_session?sid=two",
        "latest event session ID should win");
}

void bounded_tails_invalid_logs_and_caps_are_safe() {
    TemporaryDirectory temporary;
    write_log(
        temporary.path(),
        "20260723T174155",
        "ai-agent_old_stdout.log",
        "2026-07-23T20:08:01Z  INFO agent::do_chat: task_id=old\n"
            + std::string(512, 'x') + "\n");
    write_log(
        temporary.path(),
        "20260724T174155",
        "ai-agent_new_stdout.log",
        "invalid\n2026-07-24T20:08:01Z  INFO agent::do_chat: task_id=new\n");
    write_log(
        temporary.path(),
        "20260725T174155",
        "ignored.log",
        "2026-07-25T20:08:01Z  INFO agent::do_chat: task_id=ignored\n");

    auto bounded_options = scan_options(temporary.path());
    bounded_options.tail_bytes = 128;
    const TraeSessionScanner bounded(std::move(bounded_options));
    const auto tasks = bounded.active_tasks();
    expect(tasks.size() == 1 && tasks.front().id == "trae-task-new",
        "bounded tail should not restore activity before its read window");

    const TraeSessionScanner missing(scan_options(temporary.path() / "missing"));
    expect(missing.active_tasks().empty(), "missing TRAE roots should be tolerated");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"safe metadata", chat_activity_retains_safe_task_metadata},
        {"errors and duplicates", error_lines_and_duplicates_are_merged},
        {"bounded and invalid", bounded_tails_invalid_logs_and_caps_are_safe},
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
