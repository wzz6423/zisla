#include "pch.h"
#include "WinHttpRequest.h"

#include <winhttp.h>

#include <algorithm>
#include <limits>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr int resolve_timeout_ms = 5'000;
constexpr int connect_timeout_ms = 5'000;
constexpr int send_timeout_ms = 30'000;
constexpr int receive_timeout_ms = 30'000;

class InternetHandle {
public:
    explicit InternetHandle(HINTERNET value = nullptr) noexcept : value_(value) {}

    ~InternetHandle() {
        if (value_) {
            WinHttpCloseHandle(value_);
        }
    }

    InternetHandle(const InternetHandle&) = delete;
    InternetHandle& operator=(const InternetHandle&) = delete;

    InternetHandle(InternetHandle&& other) noexcept
        : value_(std::exchange(other.value_, nullptr)) {}

    InternetHandle& operator=(InternetHandle&& other) noexcept {
        if (this != &other) {
            if (value_) {
                WinHttpCloseHandle(value_);
            }
            value_ = std::exchange(other.value_, nullptr);
        }
        return *this;
    }

    [[nodiscard]] HINTERNET get() const noexcept {
        return value_;
    }

private:
    HINTERNET value_{nullptr};
};

void throw_http_error(std::string_view operation) {
    throw std::runtime_error(std::string(operation) + " (WinHTTP error "
        + std::to_string(GetLastError()) + ")");
}

std::optional<std::wstring> wide_from_utf8(std::string_view value) {
    if (value.empty()
        || value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return value.empty() ? std::optional<std::wstring>{std::wstring{}}
                             : std::nullopt;
    }
    const auto length = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (length <= 0) {
        return std::nullopt;
    }
    std::wstring result(static_cast<std::size_t>(length), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            length) != length) {
        return std::nullopt;
    }
    return result;
}

struct ParsedUrl {
    std::wstring host;
    std::wstring target;
    INTERNET_PORT port{INTERNET_DEFAULT_HTTPS_PORT};
};

ParsedUrl parse_url(std::string_view value) {
    const auto wide = wide_from_utf8(value);
    if (!wide || wide->empty()
        || wide->size() > static_cast<std::size_t>(std::numeric_limits<DWORD>::max())
        || value.find('#') != std::string_view::npos) {
        throw std::runtime_error("HTTPS URL 无效");
    }

    URL_COMPONENTS components{};
    components.dwStructSize = sizeof(components);
    components.dwHostNameLength = static_cast<DWORD>(-1);
    components.dwUrlPathLength = static_cast<DWORD>(-1);
    components.dwExtraInfoLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(
            wide->c_str(),
            static_cast<DWORD>(wide->size()),
            ICU_REJECT_USERPWD,
            &components)
        || components.nScheme != INTERNET_SCHEME_HTTPS
        || !components.lpszHostName || components.dwHostNameLength == 0) {
        throw std::runtime_error("仅支持 HTTPS URL");
    }

    ParsedUrl result{
        .host = std::wstring(components.lpszHostName, components.dwHostNameLength),
        .target = L"/",
        .port = components.nPort,
    };
    if (components.lpszUrlPath && components.dwUrlPathLength > 0) {
        result.target.assign(components.lpszUrlPath, components.dwUrlPathLength);
    }
    if (components.lpszExtraInfo && components.dwExtraInfoLength > 0) {
        result.target.append(components.lpszExtraInfo, components.dwExtraInfoLength);
    }
    return result;
}

std::uint32_t response_status(HINTERNET request) {
    DWORD status = 0;
    DWORD length = sizeof(status);
    if (!WinHttpQueryHeaders(
            request,
            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            WINHTTP_HEADER_NAME_BY_INDEX,
            &status,
            &length,
            WINHTTP_NO_HEADER_INDEX)) {
        throw_http_error("无法读取 HTTP 状态");
    }
    return status;
}

std::string response_body(HINTERNET request, std::size_t limit) {
    std::string body;
    while (true) {
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request, &available)) {
            throw_http_error("无法读取 HTTP 响应");
        }
        if (available == 0) {
            break;
        }
        if (body.size() > limit || available > limit - body.size()) {
            throw std::runtime_error("HTTP 响应超过大小限制");
        }
        const auto offset = body.size();
        body.resize(offset + available);
        DWORD read = 0;
        if (!WinHttpReadData(request, body.data() + offset, available, &read)) {
            throw_http_error("无法读取 HTTP 响应数据");
        }
        if (read > available) {
            throw std::runtime_error("HTTP 响应长度无效");
        }
        body.resize(offset + read);
        if (read == 0) {
            break;
        }
    }
    return body;
}

bool has_control(std::string_view value) noexcept {
    return std::any_of(value.begin(), value.end(), [](unsigned char character) {
        return character < 0x20U || character == 0x7fU;
    });
}

}  // namespace

WinHttpResponse WinHttpRequest::send(
    std::string_view method,
    std::string_view url,
    std::wstring_view headers,
    std::string_view body,
    std::size_t maximum_response_bytes) {
    if (method.empty() || has_control(method)
        || method.size() > static_cast<std::size_t>(std::numeric_limits<DWORD>::max())
        || body.size() > static_cast<std::size_t>(std::numeric_limits<DWORD>::max())
        || headers.size() > static_cast<std::size_t>(std::numeric_limits<DWORD>::max())) {
        throw std::runtime_error("HTTP 请求参数无效");
    }
    const auto parsed = parse_url(url);
    const auto wide_method = wide_from_utf8(method);
    if (!wide_method || wide_method->empty()) {
        throw std::runtime_error("HTTP 请求方法无效");
    }

    InternetHandle session{WinHttpOpen(
        L"Zisla/0.1.2",
        WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0)};
    if (!session.get()) {
        throw_http_error("无法启动 HTTPS 会话");
    }
    if (!WinHttpSetTimeouts(
            session.get(),
            resolve_timeout_ms,
            connect_timeout_ms,
            send_timeout_ms,
            receive_timeout_ms)) {
        throw_http_error("无法配置 HTTPS 超时");
    }

    InternetHandle connection{WinHttpConnect(
        session.get(),
        parsed.host.c_str(),
        parsed.port,
        0)};
    if (!connection.get()) {
        throw_http_error("无法连接 HTTPS 主机");
    }
    InternetHandle request{WinHttpOpenRequest(
        connection.get(),
        wide_method->c_str(),
        parsed.target.c_str(),
        nullptr,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        WINHTTP_FLAG_SECURE)};
    if (!request.get()) {
        throw_http_error("无法创建 HTTPS 请求");
    }
    DWORD redirect_policy = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    if (!WinHttpSetOption(
            request.get(),
            WINHTTP_OPTION_REDIRECT_POLICY,
            &redirect_policy,
            sizeof(redirect_policy))) {
        throw_http_error("无法禁用 HTTP 重定向");
    }

    const auto* header_data = headers.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : headers.data();
    const auto header_length = headers.empty() ? 0U : static_cast<DWORD>(headers.size());
    auto* request_data = body.empty()
        ? WINHTTP_NO_REQUEST_DATA
        : const_cast<char*>(body.data());
    const auto body_length = static_cast<DWORD>(body.size());
    if (!WinHttpSendRequest(
            request.get(),
            header_data,
            header_length,
            request_data,
            body_length,
            body_length,
            0)
        || !WinHttpReceiveResponse(request.get(), nullptr)) {
        throw_http_error("HTTPS 请求失败");
    }
    return {
        .status = response_status(request.get()),
        .body = response_body(request.get(), maximum_response_bytes),
    };
}

}
