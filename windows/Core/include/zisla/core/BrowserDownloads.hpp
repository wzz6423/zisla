#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

struct sqlite3_stmt;

namespace zisla::core {

enum class BrowserDownloadSource {
    chrome,
    edge,
    brave,
    vivaldi,
    opera,
    arc,
    unknown,
};

enum class BrowserDownloadState {
    in_progress,
    complete,
    cancelled,
    interrupted,
    unknown,
};

struct BrowserDownloadItem {
    std::int64_t id{0};
    BrowserDownloadSource source{BrowserDownloadSource::unknown};
    std::string target_path;
    std::string current_path;
    BrowserDownloadState state{BrowserDownloadState::unknown};
    std::int64_t received_bytes{0};
    std::int64_t total_bytes{0};
    std::optional<double> progress;
    std::int64_t start_time_unix_ms{0};
    std::int64_t end_time_unix_ms{0};

    friend bool operator==(
        const BrowserDownloadItem&,
        const BrowserDownloadItem&) = default;
};

struct BrowserDownloadSummary {
    std::vector<BrowserDownloadItem> active_downloads;
    std::optional<double> combined_progress;
    std::size_t total_active_count{0};

    friend bool operator==(
        const BrowserDownloadSummary&,
        const BrowserDownloadSummary&) = default;
};

class ChromiumTimeConverter {
public:
    [[nodiscard]] static std::int64_t to_unix_ms(
        std::int64_t chromium_timestamp_us) noexcept;
    [[nodiscard]] static bool is_valid_chromium_timestamp(
        std::int64_t chromium_timestamp_us) noexcept;
};

class BrowserDownloadStateMapper {
public:
    [[nodiscard]] static BrowserDownloadState map_chromium_state(
        int state_code) noexcept;
};

class BrowserDownloadProgressCalculator {
public:
    [[nodiscard]] static std::optional<double> calculate_progress(
        std::int64_t received_bytes,
        std::int64_t total_bytes) noexcept;
};

class BrowserDownloadPathCleaner {
public:
    [[nodiscard]] static std::string remove_temporary_extension(
        std::string_view path) noexcept;
};

class BrowserDownloadSummarizer {
public:
    [[nodiscard]] static BrowserDownloadSummary summarize(
        const std::vector<BrowserDownloadItem>& downloads) noexcept;
};

class BrowserDownloadPollingPolicy {
public:
    [[nodiscard]] static std::chrono::milliseconds next_interval(
        bool has_visible_activity,
        std::size_t consecutive_idle_scans) noexcept;
};

class ChromiumDownloadRowReader {
public:
    [[nodiscard]] static std::optional<std::int64_t> read_int64(
        sqlite3_stmt* statement,
        int column_index) noexcept;
    [[nodiscard]] static std::optional<std::string> read_string(
        sqlite3_stmt* statement,
        int column_index) noexcept;
    [[nodiscard]] static std::optional<int> read_int(
        sqlite3_stmt* statement,
        int column_index) noexcept;
};

}  // namespace zisla::core
