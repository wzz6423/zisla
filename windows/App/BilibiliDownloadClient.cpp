#include "pch.h"
#include "BilibiliDownloadClient.h"

#include <winhttp.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <climits>
#include <cmath>
#include <cstdint>
#include <cwctype>
#include <iomanip>
#include <limits>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string_view>
#include <system_error>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr std::size_t maximum_api_response_bytes = 4U * 1024U * 1024U;
constexpr DWORD maximum_redirects = 5;
constexpr int resolve_timeout_ms = 5'000;
constexpr int connect_timeout_ms = 8'000;
constexpr int send_timeout_ms = 15'000;
constexpr int receive_timeout_ms = 30'000;

class InternetHandle {
public:
    InternetHandle() = default;
    explicit InternetHandle(HINTERNET value) noexcept : value_(value) {}

    ~InternetHandle() {
        reset();
    }

    InternetHandle(const InternetHandle&) = delete;
    InternetHandle& operator=(const InternetHandle&) = delete;

    InternetHandle(InternetHandle&& other) noexcept
        : value_(std::exchange(other.value_, nullptr)) {}

    InternetHandle& operator=(InternetHandle&& other) noexcept {
        if (this != &other) {
            reset(std::exchange(other.value_, nullptr));
        }
        return *this;
    }

    [[nodiscard]] HINTERNET get() const noexcept {
        return value_;
    }

    [[nodiscard]] explicit operator bool() const noexcept {
        return value_ != nullptr;
    }

    void reset(HINTERNET value = nullptr) noexcept {
        if (value_) {
            WinHttpCloseHandle(value_);
        }
        value_ = value;
    }

private:
    HINTERNET value_{nullptr};
};

class PublishedRequest {
public:
    PublishedRequest(std::atomic<HINTERNET>& active, HINTERNET request)
        : active_(active), request_(request) {
        HINTERNET expected = nullptr;
        if (!request_
            || !active_.compare_exchange_strong(
                expected,
                request_,
                std::memory_order_acq_rel)) {
            if (request_) {
                WinHttpCloseHandle(request_);
            }
            throw std::runtime_error("B站下载请求状态冲突");
        }
    }

    ~PublishedRequest() {
        if (!request_) {
            return;
        }
        HINTERNET expected = request_;
        if (active_.compare_exchange_strong(
                expected,
                nullptr,
                std::memory_order_acq_rel)) {
            WinHttpCloseHandle(request_);
        }
    }

    PublishedRequest(const PublishedRequest&) = delete;
    PublishedRequest& operator=(const PublishedRequest&) = delete;

    PublishedRequest(PublishedRequest&& other) noexcept
        : active_(other.active_),
          request_(std::exchange(other.request_, nullptr)) {}

    PublishedRequest& operator=(PublishedRequest&&) = delete;

    [[nodiscard]] HINTERNET get() const noexcept {
        return request_;
    }

private:
    std::atomic<HINTERNET>& active_;
    HINTERNET request_{nullptr};
};

class FileHandle {
public:
    FileHandle() = default;
    explicit FileHandle(HANDLE value) noexcept : value_(value) {}

    ~FileHandle() {
        reset();
    }

    FileHandle(const FileHandle&) = delete;
    FileHandle& operator=(const FileHandle&) = delete;

    [[nodiscard]] HANDLE get() const noexcept {
        return value_;
    }

    [[nodiscard]] explicit operator bool() const noexcept {
        return value_ && value_ != INVALID_HANDLE_VALUE;
    }

    void reset(HANDLE value = nullptr) noexcept {
        if (value_ && value_ != INVALID_HANDLE_VALUE) {
            CloseHandle(value_);
        }
        value_ = value;
    }

private:
    HANDLE value_{nullptr};
};

struct ParsedURL {
    std::wstring host;
    std::wstring path;
    INTERNET_PORT port{INTERNET_DEFAULT_HTTPS_PORT};
};

std::optional<std::wstring> wide_from_utf8(std::string_view value) noexcept {
    if (value.empty()) {
        return std::wstring{};
    }
    if (value.size() > static_cast<std::size_t>(INT_MAX)) {
        return std::nullopt;
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

std::optional<std::string> utf8_from_wide(std::wstring_view value) noexcept {
    if (value.empty()) {
        return std::string{};
    }
    if (value.size() > static_cast<std::size_t>(INT_MAX)) {
        return std::nullopt;
    }
    const auto length = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (length <= 0) {
        return std::nullopt;
    }
    std::string result(static_cast<std::size_t>(length), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            length,
            nullptr,
            nullptr) != length) {
        return std::nullopt;
    }
    return result;
}

ParsedURL parse_https_url(std::string_view url) {
    const auto wide = wide_from_utf8(url);
    if (!wide) {
        throw std::runtime_error("B站媒体地址包含无效 UTF-8 文本");
    }

    URL_COMPONENTS components{};
    components.dwStructSize = sizeof(components);
    components.dwSchemeLength = static_cast<DWORD>(-1);
    components.dwHostNameLength = static_cast<DWORD>(-1);
    components.dwUrlPathLength = static_cast<DWORD>(-1);
    components.dwExtraInfoLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(
            wide->c_str(),
            0,
            ICU_REJECT_USERPWD,
            &components)
        || components.nScheme != INTERNET_SCHEME_HTTPS
        || !components.lpszHostName
        || components.dwHostNameLength == 0) {
        throw std::runtime_error("B站媒体地址不是有效的 HTTPS 链接");
    }

    std::wstring path;
    if (components.lpszUrlPath && components.dwUrlPathLength > 0) {
        path.assign(components.lpszUrlPath, components.dwUrlPathLength);
    }
    if (path.empty()) {
        path = L"/";
    }
    if (components.lpszExtraInfo && components.dwExtraInfoLength > 0) {
        path.append(components.lpszExtraInfo, components.dwExtraInfoLength);
    }
    return {
        .host = std::wstring(
            components.lpszHostName,
            components.dwHostNameLength),
        .path = std::move(path),
        .port = components.nPort,
    };
}

std::runtime_error network_error(std::string_view operation, DWORD code) {
    return std::runtime_error(
        std::string(operation) + "（Windows 错误 " + std::to_string(code) + "）");
}

std::wstring request_headers(std::wstring_view referer, bool json) {
    std::wstring headers = json
        ? L"Accept: application/json\r\n"
        : L"Accept: */*\r\n";
    headers.append(L"Referer: ");
    headers.append(referer);
    headers.append(L"\r\nOrigin: https://www.bilibili.com\r\n");
    return headers;
}

DWORD status_code(HINTERNET request) {
    DWORD status = 0;
    DWORD size = sizeof(status);
    if (!WinHttpQueryHeaders(
            request,
            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            WINHTTP_HEADER_NAME_BY_INDEX,
            &status,
            &size,
            WINHTTP_NO_HEADER_INDEX)) {
        throw network_error("无法读取 B站 HTTP 状态", GetLastError());
    }
    return status;
}

std::optional<std::uint64_t> content_length(HINTERNET request) noexcept {
    DWORD size = 0;
    if (WinHttpQueryHeaders(
            request,
            WINHTTP_QUERY_CONTENT_LENGTH,
            WINHTTP_HEADER_NAME_BY_INDEX,
            nullptr,
            &size,
            WINHTTP_NO_HEADER_INDEX)
        || GetLastError() != ERROR_INSUFFICIENT_BUFFER
        || size < sizeof(wchar_t)) {
        return std::nullopt;
    }
    std::wstring value((size / sizeof(wchar_t)) + 1, L'\0');
    if (!WinHttpQueryHeaders(
            request,
            WINHTTP_QUERY_CONTENT_LENGTH,
            WINHTTP_HEADER_NAME_BY_INDEX,
            value.data(),
            &size,
            WINHTTP_NO_HEADER_INDEX)) {
        return std::nullopt;
    }
    std::uint64_t result = 0;
    bool has_digit = false;
    const auto character_count = size / sizeof(wchar_t);
    for (std::size_t index = 0; index < character_count; ++index) {
        const auto character = value[index];
        if (character == L'\0') {
            break;
        }
        if (character < L'0' || character > L'9') {
            return std::nullopt;
        }
        has_digit = true;
        const auto digit = static_cast<std::uint64_t>(character - L'0');
        if (result > (std::numeric_limits<std::uint64_t>::max() - digit) / 10U) {
            return std::nullopt;
        }
        result = result * 10U + digit;
    }
    return has_digit ? std::optional<std::uint64_t>{result} : std::nullopt;
}

std::string formatted_speed(
    std::uint64_t bytes,
    std::chrono::steady_clock::duration elapsed) {
    const auto seconds = std::chrono::duration<double>(elapsed).count();
    if (!(seconds > 0.0)) {
        return {};
    }
    const auto bytes_per_second = static_cast<double>(bytes) / seconds;
    constexpr double kibibyte = 1024.0;
    constexpr double mebibyte = 1024.0 * 1024.0;
    std::ostringstream stream;
    stream << std::fixed << std::setprecision(1);
    if (bytes_per_second >= mebibyte) {
        stream << bytes_per_second / mebibyte << " MiB/s";
    } else {
        stream << bytes_per_second / kibibyte << " KiB/s";
    }
    return stream.str();
}

bool windows_reserved_filename(std::wstring_view filename) noexcept {
    const auto separator = filename.find(L'.');
    auto stem = filename.substr(0, separator);
    std::wstring upper;
    upper.reserve(stem.size());
    for (const auto character : stem) {
        upper.push_back(static_cast<wchar_t>(std::towupper(character)));
    }
    if (upper == L"CON" || upper == L"PRN" || upper == L"AUX"
        || upper == L"NUL") {
        return true;
    }
    return upper.size() == 4
        && (upper.starts_with(L"COM") || upper.starts_with(L"LPT"))
        && upper.back() >= L'1' && upper.back() <= L'9';
}

std::wstring safe_filename(
    std::string_view title,
    std::string_view bvid) {
    auto wide_title = wide_from_utf8(title).value_or(L"Bilibili Video");
    constexpr std::wstring_view forbidden = L"<>:\"/\\|?*";
    for (auto& character : wide_title) {
        if (character < L' ' || forbidden.find(character) != std::wstring_view::npos) {
            character = L'_';
        }
    }
    while (!wide_title.empty()
        && (std::iswspace(wide_title.front()) || wide_title.front() == L'.')) {
        wide_title.erase(wide_title.begin());
    }
    while (!wide_title.empty()
        && (std::iswspace(wide_title.back()) || wide_title.back() == L'.')) {
        wide_title.pop_back();
    }
    if (wide_title.empty()) {
        wide_title = L"Bilibili Video";
    }
    if (wide_title.size() > 140) {
        std::size_t limit = 140;
        if (limit > 0 && limit < wide_title.size()
            && wide_title[limit] >= 0xdc00 && wide_title[limit] <= 0xdfff
            && wide_title[limit - 1] >= 0xd800 && wide_title[limit - 1] <= 0xdbff) {
            --limit;
        }
        wide_title.resize(limit);
    }
    if (windows_reserved_filename(wide_title)) {
        wide_title.push_back(L'_');
    }
    if (const auto wide_bvid = wide_from_utf8(bvid); wide_bvid && !wide_bvid->empty()) {
        wide_title.append(L" [");
        wide_title.append(*wide_bvid);
        wide_title.push_back(L']');
    }
    return wide_title;
}

void delete_file(const std::filesystem::path& path) noexcept {
    if (!path.empty()) {
        (void)DeleteFileW(path.c_str());
    }
}

}  // namespace

BilibiliDownloadClient::BilibiliDownloadClient(
    CancellationCheck cancellation_check,
    ProgressCallback progress_callback)
    : cancellation_check_(std::move(cancellation_check)),
      progress_callback_(std::move(progress_callback)) {}

BilibiliDownloadClient::~BilibiliDownloadClient() {
    cancel();
}

std::vector<zisla::core::DownloadedMediaComponent>
BilibiliDownloadClient::download(
    std::string_view url,
    const std::filesystem::path& directory) {
    if (cancellation_requested()) {
        throw std::runtime_error("B站备用下载已取消");
    }
    std::error_code directory_error;
    if (directory.empty() || !directory.is_absolute()
        || !std::filesystem::is_directory(directory, directory_error)
        || directory_error) {
        throw std::runtime_error("B站备用下载目录不可用");
    }

    InternetHandle session{WinHttpOpen(
        L"Zisla/0.1.2",
        WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0)};
    if (!session) {
        throw network_error("无法启动 B站网络会话", GetLastError());
    }
    if (!WinHttpSetTimeouts(
            session.get(),
            resolve_timeout_ms,
            connect_timeout_ms,
            send_timeout_ms,
            receive_timeout_ms)) {
        throw network_error("无法配置 B站网络超时", GetLastError());
    }

    const auto open_request = [this, &session](
                                  std::string_view request_url,
                                  std::wstring_view headers) {
        const auto parsed = parse_https_url(request_url);
        InternetHandle connection{WinHttpConnect(
            session.get(),
            parsed.host.c_str(),
            parsed.port,
            0)};
        if (!connection) {
            throw network_error("无法连接 B站服务", GetLastError());
        }
        const auto raw_request = WinHttpOpenRequest(
            connection.get(),
            L"GET",
            parsed.path.c_str(),
            nullptr,
            WINHTTP_NO_REFERER,
            WINHTTP_DEFAULT_ACCEPT_TYPES,
            WINHTTP_FLAG_SECURE);
        if (!raw_request) {
            throw network_error("无法创建 B站请求", GetLastError());
        }
        PublishedRequest request{active_request_, raw_request};
        DWORD redirect_policy = WINHTTP_OPTION_REDIRECT_POLICY_DISALLOW_HTTPS_TO_HTTP;
        DWORD redirect_limit = maximum_redirects;
        if (!WinHttpSetOption(
                request.get(),
                WINHTTP_OPTION_REDIRECT_POLICY,
                &redirect_policy,
                sizeof(redirect_policy))
            || !WinHttpSetOption(
                request.get(),
                WINHTTP_OPTION_MAX_HTTP_AUTOMATIC_REDIRECTS,
                &redirect_limit,
                sizeof(redirect_limit))) {
            throw network_error("无法限制 B站请求重定向", GetLastError());
        }
        if (cancellation_requested()) {
            throw std::runtime_error("B站备用下载已取消");
        }
        if (!WinHttpSendRequest(
                request.get(),
                headers.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : headers.data(),
                headers.empty() ? 0 : static_cast<DWORD>(headers.size()),
                WINHTTP_NO_REQUEST_DATA,
                0,
                0,
                0)
            || !WinHttpReceiveResponse(request.get(), nullptr)) {
            const auto error = GetLastError();
            if (cancellation_requested()) {
                throw std::runtime_error("B站备用下载已取消");
            }
            throw network_error("B站请求失败", error);
        }
        return std::pair<InternetHandle, PublishedRequest>{
            std::move(connection),
            std::move(request),
        };
    };

    const auto read_body = [this](HINTERNET request) {
        std::string body;
        std::array<char, 64U * 1024U> buffer{};
        for (;;) {
            if (cancellation_requested()) {
                throw std::runtime_error("B站备用下载已取消");
            }
            DWORD read = 0;
            if (!WinHttpReadData(
                    request,
                    buffer.data(),
                    static_cast<DWORD>(buffer.size()),
                    &read)) {
                const auto error = GetLastError();
                if (cancellation_requested()) {
                    throw std::runtime_error("B站备用下载已取消");
                }
                throw network_error("无法读取 B站接口响应", error);
            }
            if (read == 0) {
                break;
            }
            if (body.size() > maximum_api_response_bytes
                || read > maximum_api_response_bytes - body.size()) {
                throw std::runtime_error("B站接口响应超过 4 MiB 限制");
            }
            body.append(buffer.data(), read);
        }
        return body;
    };

    auto bvid = zisla::core::BilibiliDownloadPlanner::extract_bvid(url);
    if (!bvid) {
        const auto [connection, request] = open_request(url, L"Accept: text/html\r\n");
        (void)connection;
        const auto status = status_code(request.get());
        if (status < 200 || status >= 300) {
            throw std::runtime_error(
                "B站短链接返回 HTTP " + std::to_string(status));
        }
        DWORD bytes = 0;
        if (!WinHttpQueryOption(request.get(), WINHTTP_OPTION_URL, nullptr, &bytes)
            && GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
            throw network_error("无法解析 B站短链接", GetLastError());
        }
        std::vector<wchar_t> final_url((bytes / sizeof(wchar_t)) + 1, L'\0');
        if (!WinHttpQueryOption(
                request.get(),
                WINHTTP_OPTION_URL,
                final_url.data(),
                &bytes)) {
            throw network_error("无法读取 B站短链接目标", GetLastError());
        }
        const auto resolved = utf8_from_wide(final_url.data());
        bvid = resolved
            ? zisla::core::BilibiliDownloadPlanner::extract_bvid(*resolved)
            : std::nullopt;
    }
    if (!bvid) {
        throw std::runtime_error("无法从 B站链接识别 BV 号");
    }

    const auto referer_utf8 = "https://www.bilibili.com/video/" + *bvid + "/";
    const auto referer = wide_from_utf8(referer_utf8);
    if (!referer) {
        throw std::runtime_error("无法编码 B站 Referer");
    }
    const auto headers = request_headers(*referer, true);
    const auto view_url = "https://api.bilibili.com/x/web-interface/view?bvid=" + *bvid;
    const auto [view_connection, view_request] = open_request(view_url, headers);
    (void)view_connection;
    const auto view_status = status_code(view_request.get());
    if (view_status < 200 || view_status >= 300) {
        throw std::runtime_error(
            "B站视频接口返回 HTTP " + std::to_string(view_status));
    }
    const auto view = zisla::core::BilibiliDownloadPlanner::parse_view_response(
        *bvid,
        read_body(view_request.get()));
    if (progress_callback_) {
        progress_callback_(0.03, {});
    }

    const auto play_url = "https://api.bilibili.com/x/player/playurl?bvid="
        + view.bvid + "&cid=" + std::to_string(view.cid)
        + "&qn=127&fnval=4048&fourk=1";
    const auto [play_connection, play_request] = open_request(play_url, headers);
    (void)play_connection;
    const auto play_status = status_code(play_request.get());
    if (play_status < 200 || play_status >= 300) {
        throw std::runtime_error(
            "B站播放接口返回 HTTP " + std::to_string(play_status));
    }
    const auto selection = zisla::core::BilibiliDownloadPlanner::parse_play_response(
        read_body(play_request.get()));
    if (progress_callback_) {
        progress_callback_(0.06, {});
    }

    const auto stem = safe_filename(view.title, view.bvid);
    const auto media_headers = request_headers(*referer, false);
    const auto download_track = [this, &open_request, &media_headers](
                                    const zisla::core::BilibiliMediaTrack& track,
                                    const std::filesystem::path& destination,
                                    double progress_base,
                                    double progress_span) {
        std::string last_failure = "没有可用的 B站 HTTPS 媒体地址";
        for (const auto& candidate : track.urls) {
            if (cancellation_requested()) {
                throw std::runtime_error("B站备用下载已取消");
            }
            auto partial = destination;
            partial += L".part";
            delete_file(partial);
            try {
                const auto [connection, request] = open_request(candidate, media_headers);
                (void)connection;
                const auto status = status_code(request.get());
                if (status < 200 || status >= 300) {
                    last_failure = "B站 CDN 返回 HTTP " + std::to_string(status);
                    continue;
                }
                const auto expected_bytes = content_length(request.get());
                FileHandle output{CreateFileW(
                    partial.c_str(),
                    GENERIC_WRITE,
                    0,
                    nullptr,
                    CREATE_NEW,
                    FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_SEQUENTIAL_SCAN,
                    nullptr)};
                if (!output) {
                    throw network_error("无法创建 B站媒体临时文件", GetLastError());
                }

                std::array<std::byte, 128U * 1024U> buffer{};
                std::uint64_t total_read = 0;
                const auto started = std::chrono::steady_clock::now();
                auto last_published = started;
                for (;;) {
                    if (cancellation_requested()) {
                        throw std::runtime_error("B站备用下载已取消");
                    }
                    DWORD read = 0;
                    if (!WinHttpReadData(
                            request.get(),
                            buffer.data(),
                            static_cast<DWORD>(buffer.size()),
                            &read)) {
                        const auto error = GetLastError();
                        if (cancellation_requested()) {
                            throw std::runtime_error("B站备用下载已取消");
                        }
                        throw network_error("无法读取 B站媒体流", error);
                    }
                    if (read == 0) {
                        break;
                    }
                    DWORD written = 0;
                    const auto write_succeeded = WriteFile(
                            output.get(),
                            buffer.data(),
                            read,
                            &written,
                            nullptr);
                    if (!write_succeeded || written != read) {
                        throw network_error(
                            "无法写入 B站媒体文件",
                            write_succeeded ? ERROR_WRITE_FAULT : GetLastError());
                    }
                    total_read += read;
                    const auto now = std::chrono::steady_clock::now();
                    if (progress_callback_
                        && now - last_published >= std::chrono::milliseconds(250)) {
                        const auto local_fraction = expected_bytes && *expected_bytes > 0
                            ? std::clamp(
                                static_cast<double>(total_read)
                                    / static_cast<double>(*expected_bytes),
                                0.0,
                                1.0)
                            : 0.0;
                        progress_callback_(
                            progress_base + progress_span * local_fraction,
                            formatted_speed(total_read, now - started));
                        last_published = now;
                    }
                }
                if (total_read == 0) {
                    throw std::runtime_error("B站 CDN 返回了空媒体文件");
                }
                if (expected_bytes && total_read != *expected_bytes) {
                    throw std::runtime_error("B站 CDN 媒体流长度不完整");
                }
                if (!FlushFileBuffers(output.get())) {
                    throw network_error("无法刷新 B站媒体文件", GetLastError());
                }
                output.reset();
                if (!MoveFileExW(
                        partial.c_str(),
                        destination.c_str(),
                        MOVEFILE_WRITE_THROUGH)) {
                    throw network_error("无法完成 B站媒体文件", GetLastError());
                }
                if (progress_callback_) {
                    progress_callback_(
                        progress_base + progress_span,
                        formatted_speed(
                            total_read,
                            std::chrono::steady_clock::now() - started));
                }
                return;
            } catch (const std::exception& error) {
                delete_file(partial);
                delete_file(destination);
                if (cancellation_requested()) {
                    throw;
                }
                last_failure = error.what();
            }
        }
        throw std::runtime_error("B站媒体下载失败：" + last_failure);
    };

    auto video_path = directory / stem;
    video_path += L"." + std::to_wstring(selection.video.id) + L".mp4";
    auto audio_path = directory / stem;
    audio_path += L"." + std::to_wstring(selection.audio.id) + L".m4a";
    download_track(selection.video, video_path, 0.06, 0.70);
    download_track(selection.audio, audio_path, 0.76, 0.18);

    return {
        {
            .path = std::move(video_path),
            .format_id = std::to_string(selection.video.id),
            .kind = zisla::core::DownloadedMediaKind::video,
        },
        {
            .path = std::move(audio_path),
            .format_id = std::to_string(selection.audio.id),
            .kind = zisla::core::DownloadedMediaKind::audio,
        },
    };
}

void BilibiliDownloadClient::cancel() noexcept {
    if (const auto request = active_request_.exchange(
            nullptr,
            std::memory_order_acq_rel)) {
        WinHttpCloseHandle(request);
    }
}

bool BilibiliDownloadClient::cancellation_requested() const noexcept {
    try {
        return cancellation_check_ && cancellation_check_();
    } catch (...) {
        return true;
    }
}

}
