#include "zisla/core/BrowserDownloads.hpp"

#include <sqlite3.h>

#include <algorithm>
#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void convertsChromiumTimestamps() {
    constexpr std::int64_t chromium_2020_jan_1 = 13'222'310'400'000'000LL;
    const auto unix_ms = ChromiumTimeConverter::to_unix_ms(chromium_2020_jan_1);
    constexpr std::int64_t expected_unix_ms = 1'577'836'800'000LL;
    expect(unix_ms == expected_unix_ms,
        "Chromium timestamp for 2020-01-01 should convert to Unix milliseconds");

    expect(ChromiumTimeConverter::to_unix_ms(0) == 0,
        "zero Chromium timestamp should return zero");
    expect(ChromiumTimeConverter::to_unix_ms(-100) == 0,
        "negative Chromium timestamp should return zero");

    constexpr std::int64_t overflow_value = 25'000'000'000'000'000LL;
    expect(ChromiumTimeConverter::to_unix_ms(overflow_value) == 0,
        "invalid overflow Chromium timestamp should return zero");

    expect(ChromiumTimeConverter::is_valid_chromium_timestamp(chromium_2020_jan_1),
        "reasonable Chromium timestamp should be valid");
    expect(!ChromiumTimeConverter::is_valid_chromium_timestamp(0),
        "zero should not be a valid Chromium timestamp");
    expect(!ChromiumTimeConverter::is_valid_chromium_timestamp(-1),
        "negative values should not be valid Chromium timestamps");
}

void mapsChromiumDownloadStates() {
    expect(BrowserDownloadStateMapper::map_chromium_state(0)
            == BrowserDownloadState::in_progress,
        "Chromium state 0 should map to in_progress");
    expect(BrowserDownloadStateMapper::map_chromium_state(1)
            == BrowserDownloadState::complete,
        "Chromium state 1 should map to complete");
    expect(BrowserDownloadStateMapper::map_chromium_state(2)
            == BrowserDownloadState::cancelled,
        "Chromium state 2 should map to cancelled");
    expect(BrowserDownloadStateMapper::map_chromium_state(3)
            == BrowserDownloadState::interrupted,
        "Chromium state 3 should map to interrupted");
    expect(BrowserDownloadStateMapper::map_chromium_state(999)
            == BrowserDownloadState::unknown,
        "unknown Chromium state codes should map to unknown");
}

void calculatesDownloadProgress() {
    const auto half = BrowserDownloadProgressCalculator::calculate_progress(
        500'000,
        1'000'000);
    expect(half && *half == 0.5,
        "50% download should calculate 0.5 progress");

    const auto complete = BrowserDownloadProgressCalculator::calculate_progress(
        1'000'000,
        1'000'000);
    expect(complete && *complete == 1.0,
        "completed download should calculate 1.0 progress");

    const auto zero = BrowserDownloadProgressCalculator::calculate_progress(0, 1'000'000);
    expect(zero && *zero == 0.0,
        "zero received bytes should calculate 0.0 progress");

    const auto unknown_size = BrowserDownloadProgressCalculator::calculate_progress(
        500'000,
        0);
    expect(!unknown_size,
        "unknown total size should return no progress");

    const auto negative = BrowserDownloadProgressCalculator::calculate_progress(-100, 1'000);
    expect(!negative,
        "negative bytes should return no progress");

    const auto overflow = BrowserDownloadProgressCalculator::calculate_progress(
        1'500'000,
        1'000'000);
    expect(overflow && *overflow == 1.0,
        "received bytes exceeding total should be clamped to 1.0");
}

void cleansTemporaryDownloadExtensions() {
    expect(BrowserDownloadPathCleaner::remove_temporary_extension(
               "C:\\Users\\Downloads\\file.pdf.crdownload")
            == "C:\\Users\\Downloads\\file.pdf",
        ".crdownload extension should be removed");

    expect(BrowserDownloadPathCleaner::remove_temporary_extension(
               "/home/user/downloads/archive.zip.tmp")
            == "/home/user/downloads/archive.zip",
        ".tmp extension should be removed");

    expect(BrowserDownloadPathCleaner::remove_temporary_extension(
               "file.CRDOWNLOAD")
            == "file",
        "extension removal should be case-insensitive");

    expect(BrowserDownloadPathCleaner::remove_temporary_extension(
               "document.pdf")
            == "document.pdf",
        "paths without temporary extensions should remain unchanged");

    expect(BrowserDownloadPathCleaner::remove_temporary_extension(
               "file.crdownload.backup")
            == "file.crdownload.backup",
        "only trailing temporary extensions should be removed");
}

void summarizesActiveDownloads() {
    std::vector<BrowserDownloadItem> downloads{
        {
            .id = 1,
            .source = BrowserDownloadSource::chrome,
            .state = BrowserDownloadState::in_progress,
            .received_bytes = 500'000,
            .total_bytes = 1'000'000,
            .progress = 0.5,
        },
        {
            .id = 2,
            .source = BrowserDownloadSource::edge,
            .state = BrowserDownloadState::complete,
            .received_bytes = 2'000'000,
            .total_bytes = 2'000'000,
            .progress = 1.0,
        },
        {
            .id = 3,
            .source = BrowserDownloadSource::brave,
            .state = BrowserDownloadState::in_progress,
            .received_bytes = 300'000,
            .total_bytes = 1'000'000,
            .progress = 0.3,
        },
    };

    const auto summary = BrowserDownloadSummarizer::summarize(downloads);
    expect(summary.total_active_count == 2,
        "summary should count only active downloads");
    expect(summary.active_downloads.size() == 2,
        "summary should include only active download items");
    expect(summary.combined_progress && *summary.combined_progress == 0.4,
        "combined progress should average known progresses");

    std::vector<BrowserDownloadItem> unknown_progress{
        {
            .id = 1,
            .state = BrowserDownloadState::in_progress,
            .received_bytes = 500'000,
            .total_bytes = 0,
            .progress = std::nullopt,
        },
    };
    const auto unknown_summary = BrowserDownloadSummarizer::summarize(unknown_progress);
    expect(unknown_summary.total_active_count == 1,
        "active downloads without known progress should still be counted");
    expect(!unknown_summary.combined_progress,
        "summary without any known progress should return nullopt");

    const std::vector<BrowserDownloadItem> completed{
        {
            .id = 1,
            .state = BrowserDownloadState::complete,
            .progress = 1.0,
        },
    };
    const auto completed_summary = BrowserDownloadSummarizer::summarize(completed);
    expect(completed_summary.total_active_count == 0,
        "completed downloads should not be counted as active");
    expect(!completed_summary.combined_progress,
        "summary with no active downloads should have no combined progress");
}

void readsChromiumSQLiteRows() {
    expect(!ChromiumDownloadRowReader::read_int64(nullptr, 0),
        "reading from null statement should return nullopt");
    expect(!ChromiumDownloadRowReader::read_string(nullptr, 0),
        "reading string from null statement should return nullopt");
    expect(!ChromiumDownloadRowReader::read_int(nullptr, 0),
        "reading int from null statement should return nullopt");

    expect(!ChromiumDownloadRowReader::read_int64(nullptr, -1),
        "negative column index should return nullopt");

    sqlite3* raw_database = nullptr;
    expect(sqlite3_open(":memory:", &raw_database) == SQLITE_OK,
        "in-memory SQLite database should open");
    const auto close_database = [](sqlite3* database) {
        if (database) {
            (void)sqlite3_close(database);
        }
    };
    std::unique_ptr<sqlite3, decltype(close_database)> database(
        raw_database,
        close_database);

    sqlite3_stmt* raw_statement = nullptr;
    expect(sqlite3_prepare_v2(
               database.get(),
               "SELECT 42, 'download.zip', NULL, 2147483648",
               -1,
               &raw_statement,
               nullptr)
            == SQLITE_OK,
        "SQLite test statement should prepare");
    std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> statement(
        raw_statement,
        &sqlite3_finalize);
    expect(sqlite3_step(statement.get()) == SQLITE_ROW,
        "SQLite test statement should produce a row");
    expect(ChromiumDownloadRowReader::read_int64(statement.get(), 0) == 42,
        "SQLite integer should be read as int64");
    expect(ChromiumDownloadRowReader::read_string(statement.get(), 1)
            == "download.zip",
        "SQLite text should be read as a string");
    expect(!ChromiumDownloadRowReader::read_string(statement.get(), 2),
        "SQLite NULL text should return nullopt");
    expect(!ChromiumDownloadRowReader::read_int(statement.get(), 3),
        "out-of-range SQLite integer should not narrow to int");
}

void handlesMultipleActiveDownloadsWithMixedProgress() {
    std::vector<BrowserDownloadItem> downloads{
        {
            .id = 1,
            .state = BrowserDownloadState::in_progress,
            .progress = 0.25,
        },
        {
            .id = 2,
            .state = BrowserDownloadState::in_progress,
            .progress = 0.75,
        },
        {
            .id = 3,
            .state = BrowserDownloadState::in_progress,
            .progress = std::nullopt,
        },
        {
            .id = 4,
            .state = BrowserDownloadState::cancelled,
            .progress = 0.1,
        },
    };

    const auto summary = BrowserDownloadSummarizer::summarize(downloads);
    expect(summary.total_active_count == 3,
        "three in_progress downloads should be counted");
    expect(summary.combined_progress && *summary.combined_progress == 0.5,
        "combined progress should average only known progresses (0.25 + 0.75) / 2");
}

void sortsActiveDownloadsByPriority() {
    std::vector<BrowserDownloadItem> downloads{
        {
            .id = 1,
            .state = BrowserDownloadState::complete,
            .start_time_unix_ms = 1'000'000,
        },
        {
            .id = 2,
            .state = BrowserDownloadState::in_progress,
            .start_time_unix_ms = 3'000'000,
        },
        {
            .id = 3,
            .state = BrowserDownloadState::in_progress,
            .start_time_unix_ms = 2'000'000,
        },
    };

    const auto summary = BrowserDownloadSummarizer::summarize(downloads);
    expect(summary.active_downloads.size() == 2,
        "only active downloads should be in summary");
    expect(summary.active_downloads[0].id == 2
            && summary.active_downloads[1].id == 3,
        "active downloads should be ordered newest first");
}

void handlesEdgeCaseTimestamps() {
    constexpr std::int64_t min_chromium = 1;
    expect(ChromiumTimeConverter::is_valid_chromium_timestamp(min_chromium),
        "minimum positive timestamp should be valid");

    constexpr std::int64_t far_future = 20'000'000'000'000'000LL;
    expect(!ChromiumTimeConverter::is_valid_chromium_timestamp(far_future + 1),
        "unreasonably far future timestamps should be invalid");
}

void handlesInterruptedDownloads() {
    const std::vector<BrowserDownloadItem> downloads{
        {
            .id = 1,
            .state = BrowserDownloadState::interrupted,
            .received_bytes = 500'000,
            .total_bytes = 1'000'000,
            .progress = 0.5,
        },
    };

    const auto summary = BrowserDownloadSummarizer::summarize(downloads);
    expect(summary.total_active_count == 0,
        "interrupted downloads should not count as active");
    expect(!summary.combined_progress,
        "interrupted downloads should not contribute to combined progress");
}

void backsOffBrowserPollingWhileIdle() {
    expect(BrowserDownloadPollingPolicy::next_interval(true, 99)
            == std::chrono::seconds(2),
        "visible download activity should keep the polling interval responsive");
    expect(BrowserDownloadPollingPolicy::next_interval(false, 0)
            == std::chrono::seconds(5),
        "the first idle scan should reduce polling frequency");
    expect(BrowserDownloadPollingPolicy::next_interval(false, 1)
            == std::chrono::seconds(5),
        "the first counted idle scan should use the short backoff");
    expect(BrowserDownloadPollingPolicy::next_interval(false, 2)
            == std::chrono::seconds(10),
        "repeated idle scans should continue backing off");
    expect(BrowserDownloadPollingPolicy::next_interval(false, 3)
            == std::chrono::seconds(15),
        "sustained idle polling should be capped at fifteen seconds");
    expect(BrowserDownloadPollingPolicy::next_interval(false, 10'000)
            == std::chrono::seconds(15),
        "the idle polling interval should remain bounded");
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"Chromium timestamp conversion", convertsChromiumTimestamps},
        {"Chromium state mapping", mapsChromiumDownloadStates},
        {"download progress calculation", calculatesDownloadProgress},
        {"temporary extension cleaning", cleansTemporaryDownloadExtensions},
        {"active download summarization", summarizesActiveDownloads},
        {"SQLite row reading", readsChromiumSQLiteRows},
        {"multiple active with mixed progress", handlesMultipleActiveDownloadsWithMixedProgress},
        {"active download priority", sortsActiveDownloadsByPriority},
        {"edge case timestamps", handlesEdgeCaseTimestamps},
        {"interrupted downloads", handlesInterruptedDownloads},
        {"idle browser polling backoff", backsOffBrowserPollingWhileIdle},
    };

    int failures = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            std::cout << "PASS: " << name << '\n';
        } catch (const std::exception& error) {
            ++failures;
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }
    return failures == 0 ? 0 : 1;
}
