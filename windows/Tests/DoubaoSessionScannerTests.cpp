#include "zisla/core/DoubaoSessionScanner.hpp"

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
            / ("zisla-doubao-scanner-" + std::to_string(timestamp) + "-"
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
        throw std::runtime_error("unable to create Doubao fixture");
    }
    stream.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    if (!stream) {
        throw std::runtime_error("unable to write Doubao fixture");
    }
}

void requires_a_running_application() {
    TemporaryDirectory temporary;
    write_file(temporary.path() / "active.json", "recent local data");

    const DoubaoSessionScanner scanner({
        .data_roots = {temporary.path()},
        .application_running = false,
    });
    expect(scanner.active_tasks().empty(),
        "local file activity must not report Doubao after the process exits");
}

void reports_only_recent_local_data_when_running() {
    TemporaryDirectory temporary;
    const auto old_file = temporary.path() / "old.json";
    const auto new_file = temporary.path() / "nested" / "new.json";
    write_file(old_file, "old");
    write_file(new_file, "new");
    fs::last_write_time(
        old_file,
        fs::file_time_type::clock::now() - std::chrono::minutes(30));

    const DoubaoSessionScanner scanner({
        .data_roots = {temporary.path(), temporary.path()},
        .max_files = 4,
        .recency_threshold_ms = 10 * 60 * 1'000,
        .application_running = true,
    });
    const auto tasks = scanner.active_tasks();
    expect(tasks.size() == 1, "recent local activity should create one aggregate task");
    expect(tasks.front().id == "doubao-active", "Doubao task ID should be stable");
    expect(tasks.front().provider == AIProvider::doubao,
        "Doubao task should use the Doubao provider");
    expect(tasks.front().title == "\xE8\xB1\x86\xE5\x8C\x85",
        "Doubao display title should preserve its product name");
    expect(tasks.front().status == AIProgressStatus::running,
        "recent activity should be running");
    expect(!tasks.front().detail.has_value(),
        "scanner must not expose local file names or contents");
}

void handles_stale_and_missing_roots() {
    TemporaryDirectory temporary;
    const auto stale_file = temporary.path() / "stale.json";
    write_file(stale_file, "stale");
    fs::last_write_time(
        stale_file,
        fs::file_time_type::clock::now() - std::chrono::hours(2));

    const DoubaoSessionScanner stale({
        .data_roots = {temporary.path()},
        .recency_threshold_ms = 60 * 1'000,
        .application_running = true,
    });
    expect(stale.active_tasks().empty(), "stale data should not report activity");

    const DoubaoSessionScanner missing({
        .data_roots = {temporary.path() / "missing"},
        .application_running = true,
    });
    expect(missing.active_tasks().empty(), "missing data roots should be tolerated");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"process gate", requires_a_running_application},
        {"recent activity", reports_only_recent_local_data_when_running},
        {"stale and missing", handles_stale_and_missing_roots},
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
