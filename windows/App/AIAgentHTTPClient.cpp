#include "pch.h"
#include "AIAgentHTTPClient.h"

#include <zisla/core/AIAgentChatProtocols.hpp>
#include <zisla/core/AIAgentServiceResponses.hpp>

#include <winhttp.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cwchar>
#include <limits>
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

void throw_windows_error(std::string_view operation);

class InternetHandle {
public:
    explicit InternetHandle(HINTERNET value = nullptr) noexcept : value_(value) {}

    ~InternetHandle() {
        reset();
    }

    InternetHandle(const InternetHandle&) = delete;
    InternetHandle& operator=(const InternetHandle&) = delete;

    InternetHandle(InternetHandle&& other) noexcept : value_(std::exchange(other.value_, nullptr)) {}

    InternetHandle& operator=(InternetHandle&& other) noexcept {
        if (this != &other) {
            reset(std::exchange(other.value_, nullptr));
        }
        return *this;
    }

    [[nodiscard]] HINTERNET get() const noexcept {
        return value_;
    }

private:
    void reset(HINTERNET value = nullptr) noexcept {
        if (value_) {
            WinHttpCloseHandle(value_);
        }
        value_ = value;
    }

    HINTERNET value_{nullptr};
};

template <typename Character>
class SensitiveString {
public:
    explicit SensitiveString(std::basic_string<Character>& value) noexcept : value_(value) {}

    ~SensitiveString() {
        if (!value_.empty()) {
            SecureZeroMemory(value_.data(), value_.size() * sizeof(Character));
        }
    }

    SensitiveString(const SensitiveString&) = delete;
    SensitiveString& operator=(const SensitiveString&) = delete;

private:
    std::basic_string<Character>& value_;
};

struct ParsedEndpoint {
    std::wstring host;
    std::wstring path;
    INTERNET_PORT port{0};
    bool is_secure{false};
};

std::optional<std::wstring> wide_from_utf8(std::string_view value) {
    if (value.empty()) {
        return std::wstring{};
    }
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return std::nullopt;
    }
    const auto size = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0);
    if (size <= 0) {
        return std::nullopt;
    }
    std::wstring result(static_cast<std::size_t>(size), L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            size) != size) {
        return std::nullopt;
    }
    return result;
}

bool ascii_case_equal(std::wstring_view left, std::wstring_view right) noexcept {
    if (left.size() != right.size()) {
        return false;
    }
    for (std::size_t index = 0; index < left.size(); ++index) {
        auto first = left[index];
        auto second = right[index];
        if (first >= L'A' && first <= L'Z') {
            first = static_cast<wchar_t>(first - L'A' + L'a');
        }
        if (second >= L'A' && second <= L'Z') {
            second = static_cast<wchar_t>(second - L'A' + L'a');
        }
        if (first != second) {
            return false;
        }
    }
    return true;
}

bool is_loopback_host(std::wstring_view host) noexcept {
    return ascii_case_equal(host, L"localhost")
        || ascii_case_equal(host, L"127.0.0.1")
        || ascii_case_equal(host, L"::1");
}

bool contains_version_segment(std::wstring_view path) noexcept {
    std::size_t start = 0;
    while (start < path.size()) {
        while (start < path.size() && path[start] == L'/') {
            ++start;
        }
        const auto end = path.find(L'/', start);
        const auto segment = path.substr(
            start,
            end == std::wstring_view::npos ? path.size() - start : end - start);
        if (segment.size() > 1 && (segment.front() == L'v' || segment.front() == L'V')) {
            return true;
        }
        if (end == std::wstring_view::npos) {
            break;
        }
        start = end + 1;
    }
    return false;
}

bool ends_with_path(std::wstring_view path, std::wstring_view suffix) noexcept {
    if (path.size() < suffix.size()) {
        return false;
    }
    return ascii_case_equal(path.substr(path.size() - suffix.size()), suffix);
}

void append_path(std::wstring& path, std::wstring_view suffix) {
    while (path.size() > 1 && path.back() == L'/') {
        path.pop_back();
    }
    if (path.empty()) {
        path = L"/";
    }
    if (path.back() != L'/') {
        path.push_back(L'/');
    }
    path.append(suffix);
}

ParsedEndpoint parse_endpoint(std::string_view base_url) {
    const auto wide = wide_from_utf8(base_url);
    if (!wide || wide->empty()
        || wide->size() > static_cast<std::size_t>(std::numeric_limits<DWORD>::max())) {
        throw std::runtime_error("AI Agent base URL is invalid");
    }

    URL_COMPONENTS components{};
    components.dwStructSize = sizeof(components);
    components.dwSchemeLength = static_cast<DWORD>(-1);
    components.dwHostNameLength = static_cast<DWORD>(-1);
    components.dwUrlPathLength = static_cast<DWORD>(-1);
    components.dwExtraInfoLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(
            wide->c_str(),
            static_cast<DWORD>(wide->size()),
            ICU_REJECT_USERPWD,
            &components)
        || !components.lpszHostName || components.dwHostNameLength == 0
        || (components.nScheme != INTERNET_SCHEME_HTTPS
            && components.nScheme != INTERNET_SCHEME_HTTP)
        || (components.lpszExtraInfo && components.dwExtraInfoLength > 0)) {
        throw std::runtime_error("AI Agent base URL is invalid");
    }

    const auto is_secure = components.nScheme == INTERNET_SCHEME_HTTPS;
    const std::wstring host(components.lpszHostName, components.dwHostNameLength);
    if (!is_secure && !is_loopback_host(host)) {
        throw std::runtime_error(
            "AI Agent only permits HTTPS endpoints or local loopback HTTP");
    }

    std::wstring path;
    if (components.lpszUrlPath && components.dwUrlPathLength > 0) {
        path.assign(components.lpszUrlPath, components.dwUrlPathLength);
    }
    if (path.empty()) {
        path = L"/";
    }
    return {
        .host = host,
        .path = std::move(path),
        .port = components.nPort,
        .is_secure = is_secure,
    };
}

std::string trim_ascii(std::string_view value) {
    const auto is_space = [](unsigned char character) noexcept {
        return character == ' ' || character == '\t' || character == '\n'
            || character == '\r' || character == '\f' || character == '\v';
    };
    while (!value.empty() && is_space(static_cast<unsigned char>(value.front()))) {
        value.remove_prefix(1);
    }
    while (!value.empty() && is_space(static_cast<unsigned char>(value.back()))) {
        value.remove_suffix(1);
    }
    return std::string(value);
}

std::wstring gemini_operation_path(std::string_view model) {
    const auto normalized = trim_ascii(model);
    if (normalized.empty()
        || !std::all_of(normalized.begin(), normalized.end(), [](unsigned char character) {
            return (character >= 'A' && character <= 'Z')
                || (character >= 'a' && character <= 'z')
                || (character >= '0' && character <= '9')
                || character == '.' || character == '_' || character == '-';
        })) {
        throw std::runtime_error("Gemini model is invalid");
    }
    const auto wide_model = wide_from_utf8(normalized);
    if (!wide_model) {
        throw std::runtime_error("Gemini model is invalid");
    }
    return L"models/" + *wide_model + L":generateContent";
}

ParsedEndpoint parse_completion_endpoint(
    std::string_view base_url,
    zisla::core::AgentChannelProtocol protocol,
    std::string_view model) {
    auto endpoint = parse_endpoint(base_url);
    switch (protocol) {
    case zisla::core::AgentChannelProtocol::openai_compatible:
        if (!contains_version_segment(endpoint.path)) {
            append_path(endpoint.path, L"v1");
        }
        if (!ends_with_path(endpoint.path, L"/chat/completions")) {
            append_path(endpoint.path, L"chat/completions");
        }
        break;
    case zisla::core::AgentChannelProtocol::anthropic_messages:
        if (!contains_version_segment(endpoint.path)) {
            append_path(endpoint.path, L"v1");
        }
        if (!ends_with_path(endpoint.path, L"/messages")) {
            append_path(endpoint.path, L"messages");
        }
        break;
    case zisla::core::AgentChannelProtocol::gemini_generate_content:
        if (!contains_version_segment(endpoint.path)) {
            append_path(endpoint.path, L"v1beta");
        }
        const auto operation = gemini_operation_path(model);
        if (!ends_with_path(endpoint.path, operation)) {
            append_path(endpoint.path, operation);
        }
        break;
    }
    return endpoint;
}

ParsedEndpoint parse_model_catalog_endpoint(
    std::string_view base_url,
    zisla::core::AgentChannelProtocol protocol) {
    auto endpoint = parse_endpoint(base_url);
    switch (protocol) {
    case zisla::core::AgentChannelProtocol::openai_compatible:
    case zisla::core::AgentChannelProtocol::anthropic_messages:
        if (!contains_version_segment(endpoint.path)) {
            append_path(endpoint.path, L"v1");
        }
        if (!ends_with_path(endpoint.path, L"/models")) {
            append_path(endpoint.path, L"models");
        }
        break;
    case zisla::core::AgentChannelProtocol::gemini_generate_content:
        if (!contains_version_segment(endpoint.path)) {
            append_path(endpoint.path, L"v1beta");
        }
        if (!ends_with_path(endpoint.path, L"/models")) {
            append_path(endpoint.path, L"models");
        }
        break;
    }
    return endpoint;
}

bool is_version_component(std::wstring_view value) noexcept {
    return value.size() > 1 && (value.front() == L'v' || value.front() == L'V');
}

void remove_trailing_version_component(std::wstring& path) {
    while (path.size() > 1 && path.back() == L'/') {
        path.pop_back();
    }
    const auto separator = path.find_last_of(L'/');
    const auto component = separator == std::wstring::npos
        ? std::wstring_view(path)
        : std::wstring_view(path).substr(separator + 1);
    if (!is_version_component(component)) {
        return;
    }
    path.erase(separator == std::wstring::npos ? 0 : separator);
    if (path.empty()) {
        path = L"/";
    }
}

std::wstring format_anthropic_timestamp(FILETIME file_time) {
    SYSTEMTIME system_time{};
    if (!FileTimeToSystemTime(&file_time, &system_time)) {
        throw_windows_error("Unable to format Anthropic usage timestamp");
    }
    wchar_t value[48]{};
    if (swprintf_s(
            value,
            L"%04u-%02u-%02uT%02u%%3A%02u%%3A%02uZ",
            system_time.wYear,
            system_time.wMonth,
            system_time.wDay,
            system_time.wHour,
            system_time.wMinute,
            system_time.wSecond) < 0) {
        throw std::runtime_error("Unable to format Anthropic usage timestamp");
    }
    return value;
}

void append_anthropic_usage_query(std::wstring& path) {
    FILETIME now{};
    GetSystemTimeAsFileTime(&now);
    ULARGE_INTEGER start{};
    start.LowPart = now.dwLowDateTime;
    start.HighPart = now.dwHighDateTime;
    constexpr ULONGLONG ticks_per_day = 24ULL * 60ULL * 60ULL * 10'000'000ULL;
    if (start.QuadPart < ticks_per_day) {
        throw std::runtime_error("Unable to calculate Anthropic usage period");
    }
    start.QuadPart -= ticks_per_day;
    FILETIME beginning{};
    beginning.dwLowDateTime = start.LowPart;
    beginning.dwHighDateTime = start.HighPart;
    path.append(L"?starting_at=");
    path.append(format_anthropic_timestamp(beginning));
    path.append(L"&ending_at=");
    path.append(format_anthropic_timestamp(now));
}

zisla::core::AgentChannelProtocol balance_protocol(
    zisla::core::AgentBalanceProbeKind kind) {
    switch (kind) {
    case zisla::core::AgentBalanceProbeKind::openai_credits:
    case zisla::core::AgentBalanceProbeKind::new_api_quota:
        return zisla::core::AgentChannelProtocol::openai_compatible;
    case zisla::core::AgentBalanceProbeKind::anthropic_usage:
        return zisla::core::AgentChannelProtocol::anthropic_messages;
    case zisla::core::AgentBalanceProbeKind::custom_script:
        break;
    }
    throw std::runtime_error("AI Agent custom balance scripts are not supported");
}

ParsedEndpoint parse_balance_endpoint(
    std::string_view base_url,
    zisla::core::AgentBalanceProbeKind kind) {
    auto endpoint = parse_endpoint(base_url);
    switch (kind) {
    case zisla::core::AgentBalanceProbeKind::openai_credits:
        remove_trailing_version_component(endpoint.path);
        append_path(endpoint.path, L"dashboard/billing/credit_grants");
        break;
    case zisla::core::AgentBalanceProbeKind::anthropic_usage:
        if (!contains_version_segment(endpoint.path)) {
            append_path(endpoint.path, L"v1");
        }
        append_path(endpoint.path, L"organizations/usage_report");
        append_anthropic_usage_query(endpoint.path);
        break;
    case zisla::core::AgentBalanceProbeKind::new_api_quota:
        remove_trailing_version_component(endpoint.path);
        append_path(endpoint.path, L"api/user/self");
        break;
    case zisla::core::AgentBalanceProbeKind::custom_script:
        throw std::runtime_error("AI Agent custom balance scripts are not supported");
    }
    return endpoint;
}

void require_safe_api_key(std::string_view api_key) {
    if (api_key.empty()) {
        throw std::runtime_error("AI Agent API key is missing");
    }
    for (const auto value : api_key) {
        const auto byte = static_cast<unsigned char>(value);
        if (byte < 0x21U || byte > 0x7EU) {
            throw std::runtime_error("AI Agent API key contains unsupported characters");
        }
    }
}

std::string request_body(
    zisla::core::AgentChannelProtocol protocol,
    const zisla::core::OpenAIChatCompletionRequest& request) {
    switch (protocol) {
    case zisla::core::AgentChannelProtocol::openai_compatible:
        return zisla::core::OpenAIChatCompletionsProtocol::make_request_body(request);
    case zisla::core::AgentChannelProtocol::anthropic_messages:
        return zisla::core::AnthropicMessagesProtocol::make_request_body(request);
    case zisla::core::AgentChannelProtocol::gemini_generate_content:
        return zisla::core::GeminiGenerateContentProtocol::make_request_body(request);
    }
    throw std::runtime_error("AI Agent protocol is invalid");
}

std::optional<std::string> completion_content(
    zisla::core::AgentChannelProtocol protocol,
    std::string_view response_body) {
    switch (protocol) {
    case zisla::core::AgentChannelProtocol::openai_compatible:
        return zisla::core::OpenAIChatCompletionsProtocol::parse_response(response_body);
    case zisla::core::AgentChannelProtocol::anthropic_messages:
        return zisla::core::AnthropicMessagesProtocol::parse_response(response_body);
    case zisla::core::AgentChannelProtocol::gemini_generate_content:
        return zisla::core::GeminiGenerateContentProtocol::parse_response(response_body);
    }
    return std::nullopt;
}

std::wstring request_headers(
    zisla::core::AgentChannelProtocol protocol,
    std::string_view api_key) {
    auto key = wide_from_utf8(api_key);
    if (!key) {
        throw std::runtime_error("AI Agent API key is invalid");
    }
    [[maybe_unused]] SensitiveString api_key_clearer(*key);

    std::wstring headers{L"Accept: application/json\r\nContent-Type: application/json\r\n"};
    switch (protocol) {
    case zisla::core::AgentChannelProtocol::openai_compatible:
        headers.append(L"Authorization: Bearer ");
        headers.append(*key);
        headers.append(L"\r\n");
        break;
    case zisla::core::AgentChannelProtocol::anthropic_messages:
        headers.append(L"x-api-key: ");
        headers.append(*key);
        headers.append(L"\r\nanthropic-version: 2023-06-01\r\n");
        break;
    case zisla::core::AgentChannelProtocol::gemini_generate_content:
        headers.append(L"x-goog-api-key: ");
        headers.append(*key);
        headers.append(L"\r\n");
        break;
    }
    return headers;
}

void throw_windows_error(std::string_view operation) {
    throw std::runtime_error(
        std::string(operation) + " (Windows error " + std::to_string(GetLastError()) + ')');
}

DWORD response_status(HINTERNET request) {
    DWORD value = 0;
    DWORD size = sizeof(value);
    if (!WinHttpQueryHeaders(
            request,
            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            WINHTTP_HEADER_NAME_BY_INDEX,
            &value,
            &size,
            WINHTTP_NO_HEADER_INDEX)) {
        throw_windows_error("Unable to read AI Agent HTTP status");
    }
    return value;
}

std::string read_body(HINTERNET request, std::size_t maximum_bytes) {
    std::string body;
    while (true) {
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request, &available)) {
            throw_windows_error("Unable to read AI Agent response");
        }
        if (available == 0) {
            return body;
        }
        if (available > maximum_bytes - body.size()) {
            throw std::runtime_error("AI Agent response exceeds the supported size");
        }
        const auto offset = body.size();
        body.resize(offset + available);
        DWORD read = 0;
        if (!WinHttpReadData(request, body.data() + offset, available, &read)) {
            throw_windows_error("Unable to read AI Agent response");
        }
        if (read > available) {
            throw std::runtime_error("AI Agent response is invalid");
        }
        body.resize(offset + read);
    }
}

struct HTTPResponse {
    DWORD status{0};
    std::string body;
};

HTTPResponse send_request(
    const ParsedEndpoint& endpoint,
    const wchar_t* method,
    std::wstring& headers,
    std::string& body) {
    InternetHandle session{WinHttpOpen(
        L"Zisla/0.1.2",
        WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0)};
    if (!session.get()) {
        throw_windows_error("Unable to start AI Agent HTTP session");
    }
    if (!WinHttpSetTimeouts(
            session.get(),
            resolve_timeout_ms,
            connect_timeout_ms,
            send_timeout_ms,
            receive_timeout_ms)) {
        throw_windows_error("Unable to configure AI Agent HTTP timeouts");
    }

    InternetHandle connection{WinHttpConnect(
        session.get(),
        endpoint.host.c_str(),
        endpoint.port,
        0)};
    if (!connection.get()) {
        throw_windows_error("Unable to connect to the AI Agent endpoint");
    }
    InternetHandle request{WinHttpOpenRequest(
        connection.get(),
        method,
        endpoint.path.c_str(),
        nullptr,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        endpoint.is_secure ? WINHTTP_FLAG_SECURE : 0)};
    if (!request.get()) {
        throw_windows_error("Unable to create AI Agent HTTP request");
    }
    DWORD redirect_policy = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
    if (!WinHttpSetOption(
            request.get(),
            WINHTTP_OPTION_REDIRECT_POLICY,
            &redirect_policy,
            sizeof(redirect_policy))) {
        throw_windows_error("Unable to configure AI Agent redirects");
    }

    const auto size = static_cast<DWORD>(body.size());
    auto* request_body = body.empty()
        ? WINHTTP_NO_REQUEST_DATA
        : static_cast<void*>(body.data());
    if (!WinHttpSendRequest(
            request.get(),
            headers.data(),
            static_cast<DWORD>(headers.size()),
            request_body,
            size,
            size,
            0)
        || !WinHttpReceiveResponse(request.get(), nullptr)) {
        throw_windows_error("AI Agent HTTP request failed");
    }
    return {
        .status = response_status(request.get()),
        .body = read_body(request.get(), AIAgentHTTPClient::maximum_response_bytes),
    };
}

}  // namespace

void AIAgentHTTPClient::validateOpenAICompatibleBaseUrl(std::string_view base_url) {
    validateBaseUrl(
        zisla::core::AgentChannelProtocol::openai_compatible,
        base_url,
        {});
}

void AIAgentHTTPClient::validateBaseUrl(
    zisla::core::AgentChannelProtocol protocol,
    std::string_view base_url,
    std::string_view model) {
    (void)parse_completion_endpoint(base_url, protocol, model);
}

std::string AIAgentHTTPClient::complete(
    const zisla::core::AgentRoute& route,
    std::string_view api_key,
    const zisla::core::OpenAIChatCompletionRequest& request) const {
    const auto endpoint = parse_completion_endpoint(
        route.base_url, route.protocol_kind, request.model);
    require_safe_api_key(api_key);
    auto body = request_body(route.protocol_kind, request);
    if (body.size() > maximum_request_bytes
        || body.size() > static_cast<std::size_t>(std::numeric_limits<DWORD>::max())) {
        throw std::runtime_error("AI Agent request exceeds the supported size");
    }
    auto headers = request_headers(route.protocol_kind, api_key);
    [[maybe_unused]] SensitiveString headers_clearer(headers);
    auto response = send_request(endpoint, L"POST", headers, body);
    [[maybe_unused]] SensitiveString response_body_clearer(response.body);
    if (response.status < 200 || response.status >= 300) {
        throw std::runtime_error("AI Agent endpoint returned HTTP " + std::to_string(response.status));
    }
    const auto content = completion_content(route.protocol_kind, response.body);
    if (!content || content->empty()) {
        throw std::runtime_error("AI Agent endpoint returned no assistant text");
    }
    return *content;
}

zisla::core::AgentChannelProbe AIAgentHTTPClient::probe(
    const zisla::core::AgentRoute& route,
    std::string_view api_key,
    std::int64_t checked_at_unix_ms) const {
    zisla::core::AgentChannelProbe result{
        .id = route.channel_id + "|" + route.endpoint_group_id + "|" + route.base_url,
        .channel_id = route.channel_id,
        .endpoint_group_id = route.endpoint_group_id,
        .base_url = route.base_url,
        .checked_at_unix_ms = checked_at_unix_ms,
    };
    const auto started = std::chrono::steady_clock::now();
    try {
        const auto endpoint = parse_model_catalog_endpoint(route.base_url, route.protocol_kind);
        require_safe_api_key(api_key);
        auto headers = request_headers(route.protocol_kind, api_key);
        [[maybe_unused]] SensitiveString headers_clearer(headers);
        std::string body;
        auto response = send_request(endpoint, L"GET", headers, body);
        [[maybe_unused]] SensitiveString response_body_clearer(response.body);
        result.health = zisla::core::agent_channel_health_for_http_status(response.status);
        const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - started).count();
        result.latency_milliseconds = static_cast<std::int32_t>(std::min<std::int64_t>(
            elapsed,
            std::numeric_limits<std::int32_t>::max()));
        if (result.health != zisla::core::AgentChannelHealth::healthy) {
            result.detail = "HTTP " + std::to_string(response.status);
        }
    } catch (...) {
        result.health = zisla::core::AgentChannelHealth::unavailable;
        result.detail = "Unable to reach AI Agent endpoint";
    }
    return result;
}

zisla::core::AgentChannelModelCatalog AIAgentHTTPClient::fetchModelCatalog(
    const zisla::core::AgentRoute& route,
    std::string_view api_key,
    std::int64_t checked_at_unix_ms) const {
    zisla::core::AgentChannelModelCatalog result{
        .channel_id = route.channel_id,
        .endpoint_group_id = route.endpoint_group_id,
        .base_url = route.base_url,
        .checked_at_unix_ms = checked_at_unix_ms,
    };
    try {
        const auto endpoint = parse_model_catalog_endpoint(route.base_url, route.protocol_kind);
        require_safe_api_key(api_key);
        auto headers = request_headers(route.protocol_kind, api_key);
        [[maybe_unused]] SensitiveString headers_clearer(headers);
        std::string body;
        auto response = send_request(endpoint, L"GET", headers, body);
        [[maybe_unused]] SensitiveString response_body_clearer(response.body);
        if (response.status < 200 || response.status >= 300) {
            result.detail = "HTTP " + std::to_string(response.status);
            return result;
        }
        const auto models = zisla::core::AIAgentModelCatalogResponseParser::parse(response.body);
        if (!models) {
            result.detail = "Model catalog response is invalid";
            return result;
        }
        result.models = *models;
    } catch (...) {
        result.detail = "Unable to fetch AI Agent model catalog";
    }
    return result;
}

zisla::core::AgentBalanceSnapshot AIAgentHTTPClient::checkBalance(
    const zisla::core::AgentBalanceProbe& probe,
    const zisla::core::AgentRoute& route,
    std::string_view api_key,
    std::int64_t checked_at_unix_ms) const {
    const auto protocol = balance_protocol(probe.kind);
    const auto endpoint = parse_balance_endpoint(route.base_url, probe.kind);
    require_safe_api_key(api_key);
    auto headers = request_headers(protocol, api_key);
    [[maybe_unused]] SensitiveString headers_clearer(headers);
    std::string body;
    auto response = send_request(endpoint, L"GET", headers, body);
    [[maybe_unused]] SensitiveString response_body_clearer(response.body);
    if (response.status < 200 || response.status >= 300) {
        throw std::runtime_error("AI Agent balance endpoint returned HTTP "
            + std::to_string(response.status));
    }
    const auto snapshot = zisla::core::AIAgentBalanceResponseParser::parse(
        probe.kind, response.body, checked_at_unix_ms);
    if (!snapshot) {
        throw std::runtime_error("AI Agent balance response is invalid");
    }
    return *snapshot;
}

}
