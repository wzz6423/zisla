#include "zisla/core/GrokSessionScanner.hpp"

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
            / ("zisla-grok-scanner-" + std::to_string(timestamp) + "-"
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

fs::path write_events(
    const fs::path& root,
    std::string_view session_id,
    std::string_view contents) {
    const auto path = root / std::string(session_id) / "events.jsonl";
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) {
        throw std::runtime_error("unable to create Grok fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write Grok fixture");
    }
    return path;
}

void append_event(const fs::path& path, std::string_view contents) {
    std::ofstream stream(path, std::ios::binary | std::ios::app);
    if (!stream) {
        throw std::runtime_error("unable to append Grok fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to append Grok fixture");
    }
}

GrokSessionScanOptions scan_options(const fs::path& root) {
    return {.sessions_directory = root};
}

void started_turn_retains_structured_metadata() {
    TemporaryDirectory temporary;
    write_events(
        temporary.path(),
        "directory-id",
        R"({"type":"turn_started","ts":"2026-07-19T01:00:00.000Z","session_id":"event-session","model_id":"grok-4.5"}
)");

    const GrokSessionScanner scanner(scan_options(temporary.path()));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "a started Grok turn should create one task");
    expect(tasks.front().id == "grok-session-event-session", "event session ID should win");
    expect(tasks.front().provider == AIProvider::grok, "provider should be Grok");
    expect(tasks.front().title == "Grok", "Grok title should be stable");
    expect(tasks.front().detail == "grok-4.5", "model ID should be retained");
    expect(tasks.front().status == AIProgressStatus::running, "started turn should run");
}

void permissions_block_until_they_are_resolved() {
    TemporaryDirectory temporary;
    const auto event_path = write_events(
        temporary.path(),
        "permissions",
        R"({"type":"turn_started","ts":"2026-07-19T01:00:00.000Z"}
{"type":"permission_requested","ts":"2026-07-19T01:00:01.000Z","request_id":"request-1"}
)");

    GrokSessionScanner scanner(scan_options(temporary.path()));
    const auto blocked = scanner.active_tasks();
    expect(blocked.size() == 1 && blocked.front().status == AIProgressStatus::blocked,
        "pending permission with an ID should block the task");

    append_event(
        event_path,
        R"({"type":"permission_resolved","ts":"2026-07-19T01:00:02.000Z","request_id":"request-1"}
)");
    const auto running = scanner.active_tasks();
    expect(running.size() == 1 && running.front().status == AIProgressStatus::running,
        "resolved identified permission should resume the task");

    append_event(
        event_path,
        R"({"type":"permission_requested","ts":"2026-07-19T01:00:03.000Z"}
{"type":"permission_resolved","ts":"2026-07-19T01:00:04.000Z"}
)");
    const auto anonymous_running = scanner.active_tasks();
    expect(anonymous_running.size() == 1
            && anonymous_running.front().status == AIProgressStatus::running,
        "anonymous permissions should balance without keeping a task blocked");
}

void tool_error_and_turn_endings_are_reflected() {
    TemporaryDirectory temporary;
    const auto event_path = write_events(
        temporary.path(),
        "lifecycle",
        R"({"type":"turn_started","ts":"2026-07-19T01:00:00.000Z"}
{"type":"tool_completed","ts":"2026-07-19T01:00:01.000Z","outcome":"error"}
)");

    GrokSessionScanner scanner(scan_options(temporary.path()));
    const auto errored = scanner.active_tasks();
    expect(errored.size() == 1 && errored.front().status == AIProgressStatus::error,
        "failed tools should surface an error");

    append_event(
        event_path,
        R"({"type":"tool_completed","ts":"2026-07-19T01:00:02.000Z","outcome":"success"}
)");
    const auto recovered = scanner.active_tasks();
    expect(recovered.size() == 1 && recovered.front().status == AIProgressStatus::running,
        "successful tool completion should clear a recoverable error");

    append_event(
        event_path,
        R"({"type":"turn_ended","ts":"2026-07-19T01:00:03.000Z","data":{"outcome":"completed"}}
)");
    expect(scanner.active_tasks().empty(), "completed turns should disappear");

    append_event(
        event_path,
        R"({"type":"turn_started","ts":"2026-07-19T01:01:00.000Z"}
{"type":"turn_ended","ts":"2026-07-19T01:01:01.000Z","outcome":"error"}
)");
    const auto terminal_error = scanner.active_tasks();
    expect(terminal_error.size() == 1
            && terminal_error.front().status == AIProgressStatus::error,
        "error endings should remain visible until the next turn");
}

void corrupt_partial_and_bounded_data_are_safe() {
    TemporaryDirectory temporary;
    write_events(
        temporary.path(),
        "noisy",
        "{bad\n"
        R"({"type":"turn_started","timestamp":1910000000000})"
        "\n{\"partial\"");

    const auto old_contents = R"({"type":"turn_started","ts":"2026-07-19T01:00:00.000Z"})"
        "\n" + std::string(4'096, 'x') + "\n";
    write_events(temporary.path(), "old", old_contents);

    const GrokSessionScanner normal(scan_options(temporary.path()));
    const auto normal_tasks = normal.active_tasks();
    expect(normal_tasks.size() == 2, "valid records should survive corrupt records");

    auto options = scan_options(temporary.path());
    options.initial_tail_bytes = 128;
    const GrokSessionScanner bounded(std::move(options));
    const auto bounded_tasks = bounded.active_tasks();
    expect(bounded_tasks.size() == 1 && bounded_tasks.front().id == "grok-session-noisy",
        "activity before a bounded tail must not be restored");

    const GrokSessionScanner missing(scan_options(temporary.path() / "missing"));
    expect(missing.active_tasks().empty(), "missing session roots should be tolerated");
}

void hidden_directories_and_duplicate_session_ids_are_safe() {
    TemporaryDirectory temporary;
    write_events(
        temporary.path(),
        ".hidden",
        R"({"type":"turn_started","ts":"2026-07-19T01:00:00.000Z"}
)");
    write_events(
        temporary.path() / "first",
        "one",
        R"({"type":"turn_started","ts":"2026-07-19T01:00:01.000Z","session_id":"shared"}
)");
    write_events(
        temporary.path() / "second",
        "two",
        R"({"type":"turn_started","ts":"2026-07-19T01:00:02.000Z","session_id":"shared"}
)");

    const GrokSessionScanner scanner(scan_options(temporary.path()));
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 1 && tasks.front().id == "grok-session-shared",
        "hidden directories and duplicate task IDs must not duplicate output");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"metadata", started_turn_retains_structured_metadata},
        {"permissions", permissions_block_until_they_are_resolved},
        {"lifecycle", tool_error_and_turn_endings_are_reflected},
        {"corrupt and bounded", corrupt_partial_and_bounded_data_are_safe},
        {"hidden and duplicate", hidden_directories_and_duplicate_session_ids_are_safe},
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
