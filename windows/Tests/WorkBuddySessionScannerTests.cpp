#include "zisla/core/WorkBuddySessionScanner.hpp"

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

constexpr std::int64_t test_now_unix_ms = 2'000'000'000'000;
constexpr std::int64_t broad_recency_threshold_ms = 500'000'000'000;

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
            / ("zisla-workbuddy-scanner-" + std::to_string(timestamp) + "-"
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

fs::path write_sessions(const fs::path& root, std::string_view contents) {
    const auto path = root / "sessions.json";
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) {
        throw std::runtime_error("unable to create WorkBuddy fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write WorkBuddy fixture");
    }
    return path;
}

WorkBuddySessionScanOptions scan_options(const fs::path& root) {
    return {
        .sessions_file = root / "sessions.json",
        .recency_threshold_ms = broad_recency_threshold_ms,
        .now_unix_ms = test_now_unix_ms,
    };
}

void recent_sessions_preserve_only_safe_metadata() {
    TemporaryDirectory temporary;
    write_sessions(
        temporary.path(),
        R"({"sessions":[{"conversationId":"conversation-1","startedAt":"2026-07-19T01:00:00.000Z","resumedAt":"2026-07-19T01:03:00.250Z","prompt":"private prompt","response":"private response"}]})");

    const WorkBuddySessionScanner scanner(scan_options(temporary.path()));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "recent WorkBuddy sessions should create one task");
    expect(tasks.front().id == "workbuddy-session-conversation-1", "session ID should be stable");
    expect(tasks.front().provider == AIProvider::harness, "WorkBuddy should use its stable provider");
    expect(tasks.front().title == "WorkBuddy", "WorkBuddy title should be stable");
    expect(tasks.front().detail == "Desktop", "task detail must not expose conversation content");
    expect(tasks.front().status == AIProgressStatus::running, "recent sessions should run");
    expect(tasks.front().started_at_unix_ms.has_value(), "started time should be retained");
}

void stale_invalid_and_corrupt_sessions_are_ignored() {
    TemporaryDirectory temporary;
    write_sessions(
        temporary.path(),
        R"({"sessions":[{"conversationId":"stale","startedAt":"2020-01-01T00:00:00Z","resumedAt":"2020-01-01T00:00:01Z"},{"conversationId":"bad-time","startedAt":"not-a-time","resumedAt":"2026-07-19T01:00:00Z"},{"conversationId":"missing","startedAt":"2026-07-19T01:00:00Z"}]})");

    auto options = scan_options(temporary.path());
    options.recency_threshold_ms = 60 * 1'000;
    const WorkBuddySessionScanner stale(std::move(options));
    expect(stale.active_tasks().empty(), "stale and malformed sessions should not be active");

    write_sessions(temporary.path(), "{broken");
    const WorkBuddySessionScanner corrupt(scan_options(temporary.path()));
    expect(corrupt.active_tasks().empty(), "corrupt indexes should be tolerated");
}

void latest_duplicate_and_configured_cap_win() {
    TemporaryDirectory temporary;
    write_sessions(
        temporary.path(),
        R"({"sessions":[{"conversationId":"duplicate","startedAt":"2026-07-19T01:00:00Z","resumedAt":"2026-07-19T01:01:00Z"},{"conversationId":"duplicate","startedAt":"2026-07-19T01:00:00Z","resumedAt":"2026-07-19T01:03:00Z"},{"conversationId":"second","startedAt":"2026-07-20T01:00:00Z","resumedAt":"2026-07-20T01:01:00Z"}]})");

    auto options = scan_options(temporary.path());
    options.max_sessions = 1;
    const WorkBuddySessionScanner scanner(std::move(options));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "configured session cap should be enforced");
    expect(tasks.front().id == "workbuddy-session-second", "newest session should survive cap");
}

void missing_and_oversized_indexes_are_safe() {
    TemporaryDirectory temporary;
    const WorkBuddySessionScanner missing(scan_options(temporary.path()));
    expect(missing.active_tasks().empty(), "missing WorkBuddy indexes should be tolerated");

    write_sessions(
        temporary.path(),
        R"({"sessions":[{"conversationId":"large","startedAt":"2026-07-19T01:00:00Z","resumedAt":"2026-07-19T01:01:00Z"}]})");
    auto options = scan_options(temporary.path());
    options.maximum_file_bytes = 16;
    const WorkBuddySessionScanner oversized(std::move(options));
    expect(oversized.active_tasks().empty(), "oversized indexes should not be read");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"safe metadata", recent_sessions_preserve_only_safe_metadata},
        {"stale and corrupt", stale_invalid_and_corrupt_sessions_are_ignored},
        {"dedupe and cap", latest_duplicate_and_configured_cap_win},
        {"missing and oversized", missing_and_oversized_indexes_are_safe},
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
