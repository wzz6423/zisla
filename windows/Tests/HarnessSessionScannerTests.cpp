#include "zisla/core/HarnessSessionScanner.hpp"

#include <atomic>
#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <limits>
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
            / ("zisla-harness-scanner-" + std::to_string(timestamp) + "-"
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

fs::path write_file(
    const fs::path& root,
    std::string_view name,
    std::string_view contents = "{}") {
    const auto path = root / std::string(name);
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) {
        throw std::runtime_error("unable to create harnext fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write harnext fixture");
    }
    return path;
}

HarnessSessionScanOptions scan_options(const fs::path& root) {
    return {.data_directory = root};
}

void recent_supported_files_are_active_without_content_exposure() {
    TemporaryDirectory temporary;
    write_file(
        temporary.path(),
        "session.json",
        R"({"prompt":"private prompt","response":"private response"})");

    const HarnessSessionScanner scanner(scan_options(temporary.path()));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1, "recent supported harnext files should create one task");
    expect(tasks.front().id == "harness-file-session.json", "file name should identify task");
    expect(tasks.front().provider == AIProvider::harness, "provider should be harnext");
    expect(tasks.front().title == "harnext", "harnext title should be stable");
    expect(!tasks.front().detail.has_value(), "file contents must not become task detail");
    expect(tasks.front().status == AIProgressStatus::running, "recent files should run");
}

void stale_and_unsupported_files_are_ignored() {
    TemporaryDirectory temporary;
    const auto stale = write_file(temporary.path(), "stale.log");
    write_file(temporary.path(), "readme.txt");
    write_file(temporary.path(), "UPPER.JSONL");
    fs::last_write_time(stale, fs::file_time_type::clock::now() - std::chrono::hours(2));

    auto options = scan_options(temporary.path());
    options.recency_threshold_ms = 60 * 1'000;
    const HarnessSessionScanner scanner(std::move(options));
    const auto tasks = scanner.active_tasks();

    expect(tasks.size() == 1 && tasks.front().id == "harness-file-UPPER.JSONL",
        "only recent log, json, and jsonl files should be retained");
}

void configured_time_and_file_cap_are_honored() {
    TemporaryDirectory temporary;
    const auto older = write_file(temporary.path(), "older.json");
    const auto newer = write_file(temporary.path(), "newer.json");
    const auto current = fs::file_time_type::clock::now();
    fs::last_write_time(older, current - std::chrono::seconds(2));
    fs::last_write_time(newer, current - std::chrono::seconds(1));

    auto options = scan_options(temporary.path());
    options.max_files = 1;
    const HarnessSessionScanner capped(std::move(options));
    const auto capped_tasks = capped.active_tasks();
    expect(capped_tasks.size() == 1 && capped_tasks.front().id == "harness-file-newer.json",
        "newest file should survive the configured cap");

    auto expired_options = scan_options(temporary.path());
    expired_options.now_unix_ms = std::numeric_limits<std::int64_t>::max();
    expired_options.recency_threshold_ms = 0;
    const HarnessSessionScanner expired(std::move(expired_options));
    expect(expired.active_tasks().empty(), "configured current time should control recency");
}

void hidden_and_duplicate_file_names_are_safe() {
    TemporaryDirectory temporary;
    write_file(temporary.path(), ".hidden/secret.json");
    write_file(temporary.path(), "one/shared.log");
    write_file(temporary.path(), "two/shared.log");

    const HarnessSessionScanner scanner(scan_options(temporary.path()));
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 1 && tasks.front().id == "harness-file-shared.log",
        "hidden directories and duplicate IDs must not duplicate output");

    const HarnessSessionScanner missing(scan_options(temporary.path() / "missing"));
    expect(missing.active_tasks().empty(), "missing harnext directories should be tolerated");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"recent metadata", recent_supported_files_are_active_without_content_exposure},
        {"stale and extension", stale_and_unsupported_files_are_ignored},
        {"time and cap", configured_time_and_file_cap_are_honored},
        {"hidden and duplicate", hidden_and_duplicate_file_names_are_safe},
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
