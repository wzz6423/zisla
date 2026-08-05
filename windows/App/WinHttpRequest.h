#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace winrt::Zisla {

struct WinHttpResponse {
    std::uint32_t status{0};
    std::string body;
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
};

}
