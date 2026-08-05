#pragma once

#include <zisla/core/Download.hpp>

#include <winhttp.h>

#include <atomic>
#include <filesystem>
#include <functional>
#include <string>
#include <vector>

namespace winrt::Zisla {

class BilibiliDownloadClient {
public:
    using CancellationCheck = std::function<bool()>;
    using ProgressCallback = std::function<void(double, std::string)>;

    BilibiliDownloadClient(
        CancellationCheck cancellation_check,
        ProgressCallback progress_callback);
    ~BilibiliDownloadClient();

    BilibiliDownloadClient(const BilibiliDownloadClient&) = delete;
    BilibiliDownloadClient& operator=(const BilibiliDownloadClient&) = delete;

    [[nodiscard]] std::vector<zisla::core::DownloadedMediaComponent> download(
        std::string_view url,
        const std::filesystem::path& directory);
    void cancel() noexcept;

private:
    [[nodiscard]] bool cancellation_requested() const noexcept;

    CancellationCheck cancellation_check_;
    ProgressCallback progress_callback_;
    std::atomic<HINTERNET> active_request_{nullptr};
};

}
