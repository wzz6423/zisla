#pragma once

#include <zisla/core/BrowserDownloads.hpp>

#include <windows.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace winrt::Zisla {

struct BrowserDownloadCompletion {
    std::string identity;
    zisla::core::BrowserDownloadItem item;
};

struct BrowserDownloadServiceSnapshot {
    zisla::core::BrowserDownloadSummary summary;
    std::vector<BrowserDownloadCompletion> recently_completed;
    std::string error;
    std::uint64_t revision{0};
};

class BrowserDownloadService {
public:
    BrowserDownloadService();
    ~BrowserDownloadService();

    BrowserDownloadService(const BrowserDownloadService&) = delete;
    BrowserDownloadService& operator=(const BrowserDownloadService&) = delete;

    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    [[nodiscard]] std::shared_ptr<const BrowserDownloadServiceSnapshot>
        snapshot() const noexcept;

private:
    struct ScanRow {
        std::string identity;
        zisla::core::BrowserDownloadItem item;
    };

    struct DownloadTracker {
        zisla::core::BrowserDownloadItem item;
        std::chrono::steady_clock::time_point completed_at{};
        bool seen{false};
    };

    using TrackerMap = std::unordered_map<std::string, DownloadTracker>;

    void run() noexcept;
    [[nodiscard]] bool scanAllBrowsers(std::vector<ScanRow>& rows);
    [[nodiscard]] bool scanBrowserRoot(
        zisla::core::BrowserDownloadSource source,
        const std::filesystem::path& browser_root,
        std::vector<ScanRow>& rows);
    [[nodiscard]] bool scanHistoryDatabase(
        zisla::core::BrowserDownloadSource source,
        const std::filesystem::path& history_path,
        std::vector<ScanRow>& rows);
    void updateTracking(const std::vector<ScanRow>& rows);
    void publish(std::string_view error = {}) noexcept;
    void notifyChanged() const noexcept;

    std::atomic<std::shared_ptr<const BrowserDownloadServiceSnapshot>>
        snapshot_;
    TrackerMap trackers_;
    std::unordered_set<std::string> observed_identities_;
    std::thread thread_;
    std::atomic_bool running_{false};
    bool first_scan_{true};
    HANDLE stop_event_{nullptr};
    mutable std::mutex mutex_;
    HWND target_{nullptr};
    UINT changed_message_{0};
    std::uint64_t revision_{0};
};

}
