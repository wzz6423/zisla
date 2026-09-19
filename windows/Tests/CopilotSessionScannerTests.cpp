#include "zisla/core/CopilotSessionScanner.hpp"

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
            / ("zisla-copilot-scanner-" + std::to_string(timestamp) + "-"
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
        throw std::runtime_error("unable to create Copilot fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write Copilot fixture");
    }
}

CopilotSessionScanOptions scan_options(const fs::path& root) {
    return {
        .workspace_storage_roots = {root / "workspaceStorage"},
        .cli_session_state_directory = root / "session-state",
    };
}

void scans_active_vscode_session_without_retaining_content() {
    TemporaryDirectory temporary;
    const auto transcript = temporary.path()
        / "workspaceStorage" / "workspace-a" / "chatSessions" / "session.jsonl";
    write_file(
        transcript,
        R"({"timestamp":"2026-07-26T01:00:00.000Z","type":"session.start","data":{"sessionId":"session-vscode","startTime":"2026-07-26T01:00:00.000Z"}})" "\n"
        R"({"timestamp":"2026-07-26T01:00:01.000Z","type":"user.message","data":{"content":"private prompt"}})" "\n"
        R"({"timestamp":"2026-07-26T01:00:02.000Z","type":"assistant.turn_start","data":{"turnId":"turn-1"}})" "\n");

    const CopilotSessionScanner scanner(scan_options(temporary.path()));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "active VS Code transcript should create one task");
    expect(tasks.front().id == "copilot-vscode-session-session-vscode",
        "VS Code task ID should retain only session ID");
    expect(tasks.front().provider == AIProvider::copilot,
        "VS Code task should use the Copilot provider");
    expect(tasks.front().title == "GitHub Copilot (VS Code)",
        "VS Code task title should be stable");
    expect(!tasks.front().detail.has_value(),
        "prompt text must not become task detail");
    expect(tasks.front().status == AIProgressStatus::running,
        "active assistant turn should be running");
    expect(!tasks.front().session_uri.has_value(),
        "scanner must not invent a Copilot deep link");
}

void completed_and_failed_vscode_sessions_have_expected_states() {
    TemporaryDirectory temporary;
    const auto completed = temporary.path()
        / "workspaceStorage" / "workspace-complete" / "chatSessions" / "complete.jsonl";
    const auto failed = temporary.path()
        / "workspaceStorage" / "workspace-failed" / "chatSessions" / "failed.jsonl";
    write_file(
        completed,
        R"({"timestamp":"2026-07-26T01:00:00Z","type":"session.start","data":{"sessionId":"complete"}})" "\n"
        R"({"timestamp":"2026-07-26T01:00:01Z","type":"user.message","data":{}})" "\n"
        R"({"timestamp":"2026-07-26T01:00:02Z","type":"assistant.turn_end","data":{}})" "\n");
    write_file(
        failed,
        R"({"timestamp":"2026-07-26T02:00:00Z","type":"session.start","data":{"sessionId":"failed"}})" "\n"
        R"({"timestamp":"2026-07-26T02:00:01Z","type":"user.message","data":{}})" "\n"
        R"({"timestamp":"2026-07-26T02:00:02Z","type":"tool.execution_complete","data":{"success":false,"content":"private failure"}})" "\n");

    const CopilotSessionScanner scanner(scan_options(temporary.path()));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "completed transcript should not remain active");
    expect(tasks.front().id == "copilot-vscode-session-failed",
        "failed session should remain visible");
    expect(tasks.front().status == AIProgressStatus::error,
        "failed tool execution should surface an error state");
}

void scans_cli_workspace_metadata_and_respects_bounded_tails() {
    TemporaryDirectory temporary;
    const auto cli_workspace = temporary.path()
        / "session-state" / "session-cli" / "workspace.yaml";
    write_file(
        cli_workspace,
        "id: session-cli\n"
        R"(cwd: 'C:\work\project')" "\n"
        "created_at: 2026-07-26T01:00:00.000Z\n"
        "updated_at: 2026-07-26T01:00:03.000Z\n");

    const auto old_transcript = temporary.path()
        / "workspaceStorage" / "workspace-old" / "chatSessions" / "old.jsonl";
    write_file(
        old_transcript,
        R"({"timestamp":"2026-07-26T01:00:00Z","type":"session.start","data":{"sessionId":"old"}})" "\n"
        R"({"timestamp":"2026-07-26T01:00:01Z","type":"user.message","data":{}})" "\n"
            + std::string(512, 'x') + "\n");

    auto options = scan_options(temporary.path());
    options.initial_tail_bytes = 128;
    const CopilotSessionScanner scanner(std::move(options));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "state outside the bounded transcript tail must be ignored");
    expect(tasks.front().id == "copilot-cli-session-session-cli",
        "CLI task ID should be stable");
    expect(tasks.front().title == "GitHub Copilot CLI",
        "CLI task title should be stable");
    expect(tasks.front().detail == "C:\\work\\project",
        "CLI task should retain only the working directory metadata");
    expect(tasks.front().started_at_unix_ms == 1'785'027'600'000LL,
        "CLI created_at should be parsed as UTC milliseconds");

    const CopilotSessionScanner missing({
        .workspace_storage_roots = {temporary.path() / "missing"},
        .cli_session_state_directory = temporary.path() / "missing-cli",
    });
    expect(missing.active_tasks().empty(), "missing Copilot roots should be tolerated");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"active VS Code", scans_active_vscode_session_without_retaining_content},
        {"completed and failed", completed_and_failed_vscode_sessions_have_expected_states},
        {"CLI and bounded tail", scans_cli_workspace_metadata_and_respects_bounded_tails},
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
