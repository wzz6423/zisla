#include "zisla/core/KimiSessionScanner.hpp"

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
            / ("zisla-kimi-scanner-" + std::to_string(timestamp) + "-"
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
        throw std::runtime_error("unable to create Kimi fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write Kimi fixture");
    }
}

void append_file(const fs::path& path, std::string_view contents) {
    std::ofstream stream(path, std::ios::binary | std::ios::app);
    if (!stream) {
        throw std::runtime_error("unable to append Kimi fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to append Kimi fixture");
    }
}

fs::path write_session(
    const fs::path& home,
    std::string_view session_id,
    std::string_view state,
    std::string_view wire) {
    const auto session_directory = home / "sessions" / "workspace" / session_id;
    write_file(session_directory / "state.json", state);
    const auto wire_path = session_directory / "agents" / "main" / "wire.jsonl";
    write_file(wire_path, wire);
    return wire_path;
}

void running_shared_session_is_reported() {
    TemporaryDirectory temporary;
    const auto wire_path = write_session(
        temporary.path(),
        "kimi-vscode-1",
        R"({"title":"Implement monitor","archived":false})",
        R"({"type":"turn.prompt","time":1910000000000}
{"type":"llm.request","model":"kimi-k2.5","time":1910000001000}
{"type":"context.append_loop_event","event":{"type":"step.begin"},"time":1910000002000}
)");
    (void)wire_path;

    const KimiSessionScanner scanner({.home_directory = temporary.path()});
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "a Kimi turn should create one task");
    expect(tasks.front().id == "kimi-session-kimi-vscode-1", "session ID should be stable");
    expect(tasks.front().provider == AIProvider::kimi, "provider should be Kimi");
    expect(tasks.front().title == "Implement monitor", "state title should be used");
    expect(tasks.front().detail == "kimi-k2.5", "model should be retained");
    expect(tasks.front().status == AIProgressStatus::running, "active turn should run");
}

void terminal_steps_and_cancellation_clear_tasks() {
    TemporaryDirectory temporary;
    const auto wire_path = write_session(
        temporary.path(),
        "kimi-terminal",
        R"({"archived":false})",
        R"({"type":"turn.prompt","time":1910000010000}
{"type":"context.append_loop_event","event":{"type":"step.end","finishReason":"end_turn"},"time":1910000011000}
)");

    KimiSessionScanner scanner({.home_directory = temporary.path()});
    expect(scanner.active_tasks().empty(), "a finished step should end the task");

    append_file(wire_path, R"({"type":"turn.prompt","time":1910000012000}
)");
    expect(scanner.active_tasks().size() == 1, "a later prompt should reactivate the task");

    append_file(wire_path, R"({"type":"turn.cancel","time":1910000013000}
)");
    expect(scanner.active_tasks().empty(), "cancellation should clear the task");
}

void paused_and_archived_sessions_are_reflected() {
    TemporaryDirectory temporary;
    const auto session_directory = temporary.path() / "sessions" / "workspace" / "kimi-blocked";
    write_session(
        temporary.path(),
        "kimi-blocked",
        R"({"archived":false})",
        R"({"type":"turn.prompt","time":1910000020000}
{"type":"context.append_loop_event","event":{"type":"step.end","finishReason":"paused"},"time":1910000021000}
)");

    KimiSessionScanner scanner({.home_directory = temporary.path()});
    const auto blocked = scanner.active_tasks();
    expect(blocked.size() == 1 && blocked.front().status == AIProgressStatus::blocked,
        "a paused Kimi turn should block the task");

    write_file(session_directory / "state.json", R"({"archived":true})");
    expect(scanner.active_tasks().empty(), "archived sessions must not be displayed");
}

void interruption_and_recovery_are_reflected() {
    TemporaryDirectory temporary;
    const auto wire_path = write_session(
        temporary.path(),
        "kimi-error",
        R"({"archived":false})",
        R"({"type":"turn.prompt","time":1910000030000}
{"type":"context.append_loop_event","event":{"type":"turn.interrupted"},"time":1910000031000}
)");

    KimiSessionScanner scanner({.home_directory = temporary.path()});
    const auto interrupted = scanner.active_tasks();
    expect(interrupted.size() == 1
            && interrupted.front().status == AIProgressStatus::error,
        "interrupted turns should surface as errors");

    append_file(wire_path, R"({"type":"turn.prompt","time":1910000032000}
)");
    const auto recovered = scanner.active_tasks();
    expect(recovered.size() == 1
            && recovered.front().status == AIProgressStatus::running,
        "a later prompt should clear a recoverable error");
}

void corrupt_partial_and_bounded_records_are_safe() {
    TemporaryDirectory temporary;
    const auto noisy_path = write_session(
        temporary.path(),
        "kimi-noisy",
        R"({"archived":false})",
        "{bad\n"
        R"({"type":"turn.prompt","time":1910000040000})"
        "\n{\"partial\"");
    (void)noisy_path;

    write_session(
        temporary.path(),
        "kimi-old",
        R"({"archived":false})",
        R"({"type":"turn.prompt","time":1910000050000})"
        "\n" + std::string(4'096, 'x') + "\n");

    const KimiSessionScanner scanner({.home_directory = temporary.path()});
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 2, "valid records should survive corrupt records");

    const KimiSessionScanner bounded({
        .home_directory = temporary.path(),
        .initial_tail_bytes = 128,
    });
    const auto bounded_tasks = bounded.active_tasks();
    expect(bounded_tasks.size() == 1
            && bounded_tasks.front().id == "kimi-session-kimi-noisy",
        "records outside a bounded tail must not stay active");

    const KimiSessionScanner missing({
        .home_directory = temporary.path() / "missing",
    });
    expect(missing.active_tasks().empty(), "missing Kimi directories should be tolerated");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"running shared session", running_shared_session_is_reported},
        {"terminal and cancellation", terminal_steps_and_cancellation_clear_tasks},
        {"paused and archived", paused_and_archived_sessions_are_reflected},
        {"interruption recovery", interruption_and_recovery_are_reflected},
        {"corrupt and bounded", corrupt_partial_and_bounded_records_are_safe},
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
