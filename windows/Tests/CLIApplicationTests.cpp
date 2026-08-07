#include "zisla/core/CLIApplication.hpp"

#include "zisla/core/AIStateRepository.hpp"

#include <chrono>
#include <exception>
#include <filesystem>
#include <functional>
#include <initializer_list>
#include <iostream>
#include <span>
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

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        const auto suffix = std::chrono::steady_clock::now()
            .time_since_epoch()
            .count();
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-cli-" + std::to_string(suffix));
    }

    ~TemporaryDirectory() {
        std::error_code error;
        std::filesystem::remove_all(path_, error);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_;
};

CLIResult run(
    const std::filesystem::path& directory,
    std::initializer_list<std::string_view> arguments,
    std::int64_t now_unix_ms = 42'000,
    std::string generated_id = "generated-id") {
    return run_cli(
        std::span<const std::string_view>(arguments.begin(), arguments.size()),
        directory,
        now_unix_ms,
        std::move(generated_id));
}

void taskLifecycleCommandsMutateAndListRepositoryState() {
    const TemporaryDirectory directory;
    const auto update = run(directory.path(), {
        "update", "--id", "job", "--provider", "codex",
        "--title", "Compile", "--progress", "40",
    });
    expect(update.exit_code == 0 && update.error.empty(),
        "update should succeed without stderr");

    const auto list = run(directory.path(), {"list"});
    expect(list.exit_code == 0
            && list.output.find("[running] job codex Compile 40%") != std::string::npos,
        "list should print persisted task fields");

    const auto finish = run(directory.path(), {
        "finish", "--id", "job", "--detail", "Done",
    }, 50'000);
    expect(finish.exit_code == 0, "finish should succeed for an existing task");
    const auto finished = AIStateRepository(directory.path()).load(false).tasks;
    expect(finished.size() == 1
            && finished.front().status == AIProgressStatus::succeeded
            && finished.front().progress == 1.0
            && finished.front().detail == "Done"
            && finished.front().updated_at_unix_ms == 50'000,
        "finish should persist its terminal task state");

    expect(run(directory.path(), {"remove", "--id", "job"}).exit_code == 0,
        "remove should succeed for an existing task");
    expect(AIStateRepository(directory.path()).load(false).tasks.empty(),
        "remove should delete the persisted task");

    (void)run(directory.path(), {
        "update", "--id", "one", "--provider", "claude", "--title", "One",
    });
    (void)run(directory.path(), {
        "update", "--id", "two", "--provider", "grok", "--title", "Two",
    });
    expect(run(directory.path(), {"clear"}).exit_code == 0,
        "clear should succeed");
    expect(AIStateRepository(directory.path()).load(false).tasks.empty(),
        "clear should remove every persisted task");
}

void usageNotifyAndMessageCommandsPersistStructuredState() {
    const TemporaryDirectory directory;
    const auto usage = run(directory.path(), {
        "usage", "--provider", "gpt", "--input-tokens", "12",
        "--output-tokens", "3", "--cost", "0.02", "--model", "gpt-5",
    });
    const auto notify = run(directory.path(), {
        "notify", "--title", "Ready", "--kind", "success", "--side", "left",
    }, 43'000, "notice-1");
    const auto message = run(directory.path(), {
        "message", "--app", "Messages", "--sender", "Alice",
        "--content", "Hello\nthere",
    }, 44'000, "pair-1");

    expect(usage.exit_code == 0 && notify.exit_code == 0 && message.exit_code == 0,
        "usage, notify, and message should succeed");
    const auto state = AIStateRepository(directory.path()).load();
    expect(state.usage_samples.size() == 1
            && state.usage_samples.front().total_tokens() == 15,
        "usage should persist one structured sample");
    expect(state.notices.size() == 3
            && state.notices[0].id == "notice-1"
            && state.notices[1].id == "message-pair-1-left"
            && state.notices[2].id == "message-pair-1-right"
            && state.notices[2].title == "Hello there",
        "notify and message should persist ordered notice rows");
}

void exitCodesSeparateHelpUsageAndRepositoryDataErrors() {
    const TemporaryDirectory directory;
    const auto help = run(directory.path(), {"help"});
    expect(help.exit_code == 0
            && help.output.find("zislactl") != std::string::npos
            && help.error.empty(),
        "help should succeed and print usage");

    const auto invalid = run(directory.path(), {"unknown"});
    expect(invalid.exit_code == 64 && invalid.output.empty() && !invalid.error.empty(),
        "parse failures should return EX_USAGE");

    const auto missing_remove = run(directory.path(), {"remove", "--id", "missing"});
    expect(missing_remove.exit_code == 65 && !missing_remove.error.empty(),
        "missing remove targets should return EX_DATAERR");
    const auto missing_finish = run(directory.path(), {"finish", "--id", "missing"});
    expect(missing_finish.exit_code == 65 && !missing_finish.error.empty(),
        "repository task errors should return EX_DATAERR");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"task lifecycle commands mutate state", taskLifecycleCommandsMutateAndListRepositoryState},
        {"usage and notices persist", usageNotifyAndMessageCommandsPersistStructuredState},
        {"exit codes separate error classes", exitCodesSeparateHelpUsageAndRepositoryDataErrors},
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
