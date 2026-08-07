#pragma once

#include <filesystem>
#include <functional>

namespace winrt::Zisla {

class MediaFoundationMuxer {
public:
    using CancellationCheck = std::function<bool()>;

    explicit MediaFoundationMuxer(CancellationCheck cancellation_check);

    void mux(
        const std::filesystem::path& video,
        const std::filesystem::path& audio,
        const std::filesystem::path& output) const;

private:
    [[nodiscard]] bool cancellation_requested() const noexcept;

    CancellationCheck cancellation_check_;
};

}
