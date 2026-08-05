#pragma once

#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <mutex>
#include <string>
#include <string_view>

namespace winrt::Zisla {

struct WinHttpResponse {
    std::uint32_t status{0};
    std::string body;
};

class WinHttpCancellation {
public:
    WinHttpCancellation() = default;
    ~WinHttpCancellation();

    WinHttpCancellation(const WinHttpCancellation&) = delete;
    WinHttpCancellation& operator=(const WinHttpCancellation&) = delete;

    void reset() noexcept;
    void cancel() noexcept;
    [[nodiscard]] bool cancelled() const noexcept;

private:
    friend class WinHttpRequest;
    class Registration;

    [[nodiscard]] bool register_request(HINTERNET request) noexcept;
    void release_request(HINTERNET request) noexcept;

    mutable std::mutex mutex_;
    HINTERNET request_{nullptr};
    bool cancelled_{false};
};

/// Shared HTTPS transport for services that do not need streaming or redirects.
class WinHttpRequest {
public:
    static constexpr std::size_t default_maximum_response_bytes = 1U * 1024U * 1024U;

    [[nodiscard]] static WinHttpResponse send(
        std::string_view method,
        std::string_view url,
        std::wstring_view headers,
        std::string_view body,
        std::size_t maximum_response_bytes = default_maximum_response_bytes);

    [[nodiscard]] static WinHttpResponse send(
        std::string_view method,
        std::string_view url,
        std::wstring_view headers,
        std::string_view body,
        WinHttpCancellation& cancellation,
        std::size_t maximum_response_bytes = default_maximum_response_bytes);
};

}
