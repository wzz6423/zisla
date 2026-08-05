#include "zisla/core/BrowserDownloads.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <numeric>

namespace zisla::core {
namespace {

constexpr std::int64_t chromium_epoch_delta_us = 11'644'473'600'000'000LL;
constexpr std::int64_t max_reasonable_chromium_us = 20'000'000'000'000'000LL;

constexpr std::string_view crdownload_extension = ".crdownload";
constexpr std::string_view tmp_extension = ".tmp";

bool ends_with_case_insensitive(
    std::string_view text,
    std::string_view suffix) noexcept {
    if (text.size() < suffix.size()) {
        return false;
    }
    const auto text_suffix = text.substr(text.size() - suffix.size());
    return std::equal(
        text_suffix.begin(),
        text_suffix.end(),
        suffix.begin(),
        suffix.end(),
        [](char a, char b) {
            const auto lower_a = (a >= 'A' && a <= 'Z') ? (a + ('a' - 'A')) : a;
            const auto lower_b = (b >= 'A' && b <= 'Z') ? (b + ('a' - 'A')) : b;
            return lower_a == lower_b;
        });
}

}  // namespace

std::int64_t ChromiumTimeConverter::to_unix_ms(
    std::int64_t chromium_timestamp_us) noexcept {
    if (!is_valid_chromium_timestamp(chromium_timestamp_us)) {
        return 0;
    }
    const auto unix_us = chromium_timestamp_us - chromium_epoch_delta_us;
    if (unix_us < 0) {
        return 0;
    }
    constexpr auto max_unix_ms = std::numeric_limits<std::int64_t>::max() / 1000;
    if (unix_us > max_unix_ms * 1000) {
        return max_unix_ms;
    }
    return unix_us / 1000;
}

bool ChromiumTimeConverter::is_valid_chromium_timestamp(
    std::int64_t chromium_timestamp_us) noexcept {
    return chromium_timestamp_us > 0
        && chromium_timestamp_us <= max_reasonable_chromium_us;
}

BrowserDownloadState BrowserDownloadStateMapper::map_chromium_state(
    int state_code) noexcept {
    switch (state_code) {
        case 0:
            return BrowserDownloadState::in_progress;
        case 1:
            return BrowserDownloadState::complete;
        case 2:
            return BrowserDownloadState::cancelled;
        case 3:
            return BrowserDownloadState::interrupted;
        default:
            return BrowserDownloadState::unknown;
    }
}

std::optional<double> BrowserDownloadProgressCalculator::calculate_progress(
    std::int64_t received_bytes,
    std::int64_t total_bytes) noexcept {
    if (received_bytes < 0 || total_bytes < 0) {
        return std::nullopt;
    }
    if (total_bytes == 0) {
        return std::nullopt;
    }
    if (received_bytes == 0) {
        return 0.0;
    }
    if (received_bytes >= total_bytes) {
        return 1.0;
    }
    const auto progress = static_cast<double>(received_bytes)
        / static_cast<double>(total_bytes);
    if (!std::isfinite(progress)) {
        return std::nullopt;
    }
    return std::clamp(progress, 0.0, 1.0);
}

std::string BrowserDownloadPathCleaner::remove_temporary_extension(
    std::string_view path) noexcept {
    if (ends_with_case_insensitive(path, crdownload_extension)) {
        return std::string(path.substr(0, path.size() - crdownload_extension.size()));
    }
    if (ends_with_case_insensitive(path, tmp_extension)) {
        return std::string(path.substr(0, path.size() - tmp_extension.size()));
    }
    return std::string(path);
}

BrowserDownloadSummary BrowserDownloadSummarizer::summarize(
    const std::vector<BrowserDownloadItem>& downloads) noexcept {
    BrowserDownloadSummary result;

    for (const auto& item : downloads) {
        if (item.state == BrowserDownloadState::in_progress) {
            result.active_downloads.push_back(item);
        }
    }

    std::sort(
        result.active_downloads.begin(),
        result.active_downloads.end(),
        [](const BrowserDownloadItem& left, const BrowserDownloadItem& right) {
            if (left.start_time_unix_ms != right.start_time_unix_ms) {
                return left.start_time_unix_ms > right.start_time_unix_ms;
            }
            return left.id > right.id;
        });

    result.total_active_count = result.active_downloads.size();

    if (result.active_downloads.empty()) {
        result.combined_progress = std::nullopt;
        return result;
    }

    std::vector<double> known_progresses;
    known_progresses.reserve(result.active_downloads.size());

    for (const auto& item : result.active_downloads) {
        if (item.progress) {
            known_progresses.push_back(*item.progress);
        }
    }

    if (known_progresses.empty()) {
        result.combined_progress = std::nullopt;
    } else {
        const auto sum = std::accumulate(
            known_progresses.begin(),
            known_progresses.end(),
            0.0);
        result.combined_progress = sum / static_cast<double>(known_progresses.size());
    }

    return result;
}

std::optional<std::int64_t> ChromiumDownloadRowReader::read_int64(
    sqlite3_stmt* statement,
    int column_index) noexcept {
    if (!statement || column_index < 0) {
        return std::nullopt;
    }
    const auto column_type = sqlite3_column_type(statement, column_index);
    if (column_type == SQLITE_NULL) {
        return std::nullopt;
    }
    if (column_type != SQLITE_INTEGER) {
        return std::nullopt;
    }
    return sqlite3_column_int64(statement, column_index);
}

std::optional<std::string> ChromiumDownloadRowReader::read_string(
    sqlite3_stmt* statement,
    int column_index) noexcept {
    if (!statement || column_index < 0) {
        return std::nullopt;
    }
    const auto column_type = sqlite3_column_type(statement, column_index);
    if (column_type == SQLITE_NULL) {
        return std::nullopt;
    }
    if (column_type != SQLITE_TEXT) {
        return std::nullopt;
    }
    const auto* text = reinterpret_cast<const char*>(
        sqlite3_column_text(statement, column_index));
    if (!text) {
        return std::nullopt;
    }
    const auto length = sqlite3_column_bytes(statement, column_index);
    return std::string(text, static_cast<std::size_t>(length));
}

std::optional<int> ChromiumDownloadRowReader::read_int(
    sqlite3_stmt* statement,
    int column_index) noexcept {
    const auto int64_value = read_int64(statement, column_index);
    if (!int64_value) {
        return std::nullopt;
    }
    if (*int64_value < std::numeric_limits<int>::min()
        || *int64_value > std::numeric_limits<int>::max()) {
        return std::nullopt;
    }
    return static_cast<int>(*int64_value);
}

}  // namespace zisla::core
