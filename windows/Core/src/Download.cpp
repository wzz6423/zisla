#include "zisla/core/Download.hpp"

#include "zisla/core/DiskCleanup.hpp"

#include <yyjson.h>

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cctype>
#include <cwctype>
#include <limits>
#include <memory>
#include <system_error>
#include <utility>

namespace zisla::core {
namespace {

constexpr std::size_t maximum_event_bytes = 64U * 1024U;
constexpr std::size_t maximum_bilibili_response_bytes = 4U * 1024U * 1024U;

std::string trim_ascii(std::string_view value) {
    std::size_t begin = 0;
    while (begin < value.size()
        && std::isspace(static_cast<unsigned char>(value[begin])) != 0) {
        ++begin;
    }
    std::size_t end = value.size();
    while (end > begin
        && std::isspace(static_cast<unsigned char>(value[end - 1])) != 0) {
        --end;
    }
    return std::string(value.substr(begin, end - begin));
}

std::string lower_ascii(std::string_view value) {
    std::string result(value);
    std::transform(result.begin(), result.end(), result.begin(), [](char character) {
        return static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
    });
    return result;
}

bool contains_ascii_case_insensitive(
    std::string_view text,
    std::string_view needle) {
    return lower_ascii(text).find(lower_ascii(needle)) != std::string::npos;
}

std::string path_as_utf8(const std::filesystem::path& path) {
    const auto encoded = path.u8string();
    return {reinterpret_cast<const char*>(encoded.data()), encoded.size()};
}

std::filesystem::path path_from_utf8(std::string_view value) {
    const std::u8string encoded(
        reinterpret_cast<const char8_t*>(value.data()),
        reinterpret_cast<const char8_t*>(value.data() + value.size()));
    return std::filesystem::path(encoded);
}

std::optional<std::string> json_string(yyjson_val* value) {
    if (!value || !yyjson_is_str(value)) {
        return std::nullopt;
    }
    return std::string(yyjson_get_str(value), yyjson_get_len(value));
}

std::optional<double> parse_percent(std::string_view value) noexcept {
    try {
        auto normalized = trim_ascii(value);
        if (normalized.ends_with('%')) {
            normalized.pop_back();
            normalized = trim_ascii(normalized);
        }
        if (normalized.empty()) {
            return std::nullopt;
        }
        double result = 0.0;
        const auto parsed = std::from_chars(
            normalized.data(),
            normalized.data() + normalized.size(),
            result,
            std::chars_format::general);
        if (parsed.ec != std::errc{}
            || parsed.ptr != normalized.data() + normalized.size()
            || !std::isfinite(result)) {
            return std::nullopt;
        }
        return std::clamp(result / 100.0, 0.0, 1.0);
    } catch (...) {
        return std::nullopt;
    }
}

bool codec_present(const std::optional<std::string>& codec) {
    return codec && !codec->empty() && lower_ascii(*codec) != "none";
}

std::optional<DownloadedMediaKind> component_kind(
    const std::optional<std::string>& video_codec,
    const std::optional<std::string>& audio_codec) {
    const bool has_video = codec_present(video_codec);
    const bool has_audio = codec_present(audio_codec);
    if (has_video && has_audio) {
        return DownloadedMediaKind::combined;
    }
    if (has_video) {
        return DownloadedMediaKind::video;
    }
    if (has_audio) {
        return DownloadedMediaKind::audio;
    }
    return std::nullopt;
}

std::optional<std::string_view> authority_host(
    std::string_view authority) noexcept {
    if (const auto user_info = authority.rfind('@');
        user_info != std::string_view::npos) {
        authority.remove_prefix(user_info + 1);
    }
    if (authority.empty()) {
        return std::nullopt;
    }
    if (authority.starts_with('[')) {
        const auto close = authority.find(']');
        if (close == std::string_view::npos || close == 1) {
            return std::nullopt;
        }
        const auto remainder = authority.substr(close + 1);
        if (!remainder.empty() && !remainder.starts_with(':')) {
            return std::nullopt;
        }
        return authority.substr(0, close + 1);
    }
    if (const auto port = authority.find(':'); port != std::string_view::npos) {
        authority = authority.substr(0, port);
    }
    return authority.empty()
        ? std::nullopt
        : std::optional<std::string_view>{authority};
}

std::optional<std::string> url_host(std::string_view url) noexcept {
    try {
        const auto normalized = DownloadRequestValidator::normalized_url(url);
        if (!normalized) {
            return std::nullopt;
        }
        const auto scheme_end = normalized->find("://");
        const auto authority_begin = scheme_end + 3;
        const auto authority_end = normalized->find_first_of("/?#", authority_begin);
        auto authority = std::string_view(*normalized).substr(
            authority_begin,
            authority_end == std::string::npos
                ? std::string::npos
                : authority_end - authority_begin);
        const auto host = authority_host(authority);
        return host
            ? std::optional<std::string>{lower_ascii(*host)}
            : std::nullopt;
    } catch (...) {
        return std::nullopt;
    }
}

bool host_matches(std::string_view host, std::string_view expected) noexcept {
    return host == expected
        || (host.size() > expected.size()
            && host.ends_with(expected)
            && host[host.size() - expected.size() - 1] == '.');
}

std::int64_t json_integer(yyjson_val* value, std::int64_t fallback = 0) noexcept {
    return value && yyjson_is_int(value) ? yyjson_get_sint(value) : fallback;
}

int json_bounded_int(yyjson_val* value) noexcept {
    const auto integer = json_integer(value);
    return integer >= std::numeric_limits<int>::min()
            && integer <= std::numeric_limits<int>::max()
        ? static_cast<int>(integer)
        : 0;
}

std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)> parse_bilibili_response(
    std::string_view response) {
    if (response.empty() || response.size() > maximum_bilibili_response_bytes) {
        throw BilibiliResponseError("B站接口响应大小异常");
    }
    std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)> document(
        yyjson_read(response.data(), response.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free);
    if (!document) {
        throw BilibiliResponseError("B站接口返回了无效 JSON");
    }
    return document;
}

yyjson_val* bilibili_response_data(
    const std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>& document) {
    auto* root = yyjson_doc_get_root(document.get());
    if (!root || !yyjson_is_obj(root)) {
        throw BilibiliResponseError("B站接口返回了无效 JSON");
    }
    auto* code = yyjson_obj_get(root, "code");
    if (!code || !yyjson_is_int(code)) {
        throw BilibiliResponseError("B站接口响应缺少状态码");
    }
    const auto code_value = yyjson_get_sint(code);
    if (code_value != 0) {
        const auto message = json_string(yyjson_obj_get(root, "message"));
        throw BilibiliResponseError(
            "B站接口返回异常："
            + message.value_or("code " + std::to_string(code_value)));
    }
    auto* data = yyjson_obj_get(root, "data");
    if (!data || !yyjson_is_obj(data)) {
        throw BilibiliResponseError("B站接口响应缺少数据");
    }
    return data;
}

void append_https_url(
    std::vector<std::string>& urls,
    const std::optional<std::string>& value) {
    if (!value) {
        return;
    }
    const auto normalized = DownloadRequestValidator::normalized_url(*value);
    if (!normalized || !std::string_view(*normalized).starts_with("https://")
        || std::find(urls.begin(), urls.end(), *normalized) != urls.end()) {
        return;
    }
    urls.push_back(*normalized);
}

std::optional<BilibiliMediaTrack> bilibili_track(yyjson_val* value) {
    if (!value || !yyjson_is_obj(value)) {
        return std::nullopt;
    }
    auto* id = yyjson_obj_get(value, "id");
    if (!id || !yyjson_is_int(id)) {
        return std::nullopt;
    }

    BilibiliMediaTrack result{
        .id = yyjson_get_sint(id),
        .bandwidth = std::max<std::int64_t>(
            0,
            json_integer(yyjson_obj_get(value, "bandwidth"))),
        .codecs = json_string(yyjson_obj_get(value, "codecs")).value_or(""),
        .mime_type = json_string(yyjson_obj_get(value, "mimeType")).value_or(""),
        .width = std::max(0, json_bounded_int(yyjson_obj_get(value, "width"))),
        .height = std::max(0, json_bounded_int(yyjson_obj_get(value, "height"))),
    };
    auto base_url = json_string(yyjson_obj_get(value, "baseUrl"));
    if (!base_url) {
        base_url = json_string(yyjson_obj_get(value, "base_url"));
    }
    append_https_url(result.urls, base_url);

    auto* backups = yyjson_obj_get(value, "backupUrl");
    if (!backups) {
        backups = yyjson_obj_get(value, "backup_url");
    }
    if (backups && yyjson_is_arr(backups)) {
        std::size_t index = 0;
        std::size_t maximum = 0;
        yyjson_val* item = nullptr;
        yyjson_arr_foreach(backups, index, maximum, item) {
            append_https_url(result.urls, json_string(item));
        }
    }
    return result.urls.empty()
        ? std::nullopt
        : std::optional<BilibiliMediaTrack>{std::move(result)};
}

std::vector<BilibiliMediaTrack> bilibili_tracks(yyjson_val* value) {
    std::vector<BilibiliMediaTrack> result;
    if (!value || !yyjson_is_arr(value)) {
        return result;
    }
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_val* item = nullptr;
    yyjson_arr_foreach(value, index, maximum, item) {
        if (auto track = bilibili_track(item)) {
            result.push_back(std::move(*track));
        }
    }
    return result;
}

bool is_avc_mp4(const BilibiliMediaTrack& track) {
    return lower_ascii(track.mime_type) == "video/mp4"
        && lower_ascii(track.codecs).starts_with("avc1");
}

bool is_mp4_video(const BilibiliMediaTrack& track) {
    return lower_ascii(track.mime_type) == "video/mp4";
}

bool lower_quality_video(
    const BilibiliMediaTrack& left,
    const BilibiliMediaTrack& right) noexcept {
    const auto left_pixels = static_cast<std::int64_t>(left.width) * left.height;
    const auto right_pixels = static_cast<std::int64_t>(right.width) * right.height;
    return left_pixels == right_pixels
        ? left.bandwidth < right.bandwidth
        : left_pixels < right_pixels;
}

}  // namespace

std::optional<std::string> DownloadRequestValidator::normalized_url(
    std::string_view value) noexcept {
    try {
        auto result = trim_ascii(value);
        if (result.empty()
            || std::any_of(result.begin(), result.end(), [](char character) {
                return std::isspace(static_cast<unsigned char>(character)) != 0
                    || static_cast<unsigned char>(character) < 0x20U;
            })) {
            return std::nullopt;
        }
        const auto scheme_end = result.find("://");
        if (scheme_end == std::string::npos) {
            return std::nullopt;
        }
        const auto scheme = lower_ascii(std::string_view(result).substr(0, scheme_end));
        if (scheme != "http" && scheme != "https") {
            return std::nullopt;
        }
        const auto authority_begin = scheme_end + 3;
        const auto authority_end = result.find_first_of("/?#", authority_begin);
        const auto authority = std::string_view(result).substr(
            authority_begin,
            authority_end == std::string::npos
                ? std::string::npos
                : authority_end - authority_begin);
        if (!authority_host(authority)) {
            return std::nullopt;
        }
        result.replace(0, scheme_end, scheme);
        return result;
    } catch (...) {
        return std::nullopt;
    }
}

DownloadRequestValidation DownloadRequestValidator::validate(
    const DownloadRequest& request) noexcept {
    if (!normalized_url(request.url)) {
        return DownloadRequestValidation::unsupported_url;
    }
    std::error_code error;
    if (request.output_directory.empty()
        || !request.output_directory.is_absolute()
        || !std::filesystem::is_directory(request.output_directory, error)
        || error) {
        return DownloadRequestValidation::invalid_output_directory;
    }
    return DownloadRequestValidation::valid;
}

DownloadExecutionStrategy YTDLPArgumentBuilder::strategy(
    const DownloadRequest& request,
    DownloadCapabilities capabilities) noexcept {
    return request.mode == DownloadMode::video && !capabilities.has_ffmpeg
        ? DownloadExecutionStrategy::native_packaging
        : DownloadExecutionStrategy::direct;
}

std::vector<std::string> YTDLPArgumentBuilder::arguments(
    const DownloadRequest& request,
    DownloadCapabilities capabilities,
    const std::filesystem::path& task_temporary_directory,
    std::optional<std::filesystem::path> ffmpeg_executable) {
    const auto execution_strategy = strategy(request, capabilities);
    const auto output_directory = execution_strategy
        == DownloadExecutionStrategy::native_packaging
        ? task_temporary_directory
        : request.output_directory;
    const auto output_template = execution_strategy
        == DownloadExecutionStrategy::native_packaging
        ? "%(title)s [%(id)s].%(format_id)s.%(ext)s"
        : "%(title)s [%(id)s].%(ext)s";

    std::vector<std::string> result{
        "--ignore-config",
        "--no-plugin-dirs",
        "--no-exec",
        "--no-playlist",
        "--no-overwrites",
        "--no-color",
        "--newline",
        "--no-simulate",
        "--progress",
        "--windows-filenames",
        "--paths",
        "home:" + path_as_utf8(output_directory),
        "--paths",
        "temp:" + path_as_utf8(task_temporary_directory),
        "-o",
        output_template,
    };

    if (capabilities.has_ffmpeg && ffmpeg_executable) {
        result.push_back("--ffmpeg-location");
        result.push_back(path_as_utf8(*ffmpeg_executable));
    }

    if (request.mode == DownloadMode::video) {
        if (capabilities.has_ffmpeg) {
            result.insert(result.end(), {
                "-f", "bv*+ba/b",
                "--merge-output-format", "mp4",
            });
        } else {
            result.insert(result.end(), {
                "-f",
                "(bv*[ext=mp4][vcodec^=avc1][acodec=none]/bv*[ext=mp4][acodec=none],ba[ext=m4a][vcodec=none])/b[ext=mp4]/b",
            });
        }
    } else if (capabilities.has_ffmpeg) {
        result.insert(result.end(), {
            "-f", "ba/b",
            "--extract-audio",
            "--audio-format", "m4a",
        });
    } else {
        result.insert(result.end(), {"-f", "ba[ext=m4a]/ba"});
    }

    const auto completed_template = execution_strategy
        == DownloadExecutionStrategy::direct
        ? "after_move:" + std::string(YTDLPOutputParser::sentinel)
            + R"({"event":"completed","filepath":%(filepath)j})"
        : "after_move:" + std::string(YTDLPOutputParser::sentinel)
            + R"({"event":"component","filepath":%(filepath)j,"format_id":%(format_id)j,"vcodec":%(vcodec)j,"acodec":%(acodec)j})";
    result.insert(result.end(), {
        "--progress-template",
        "download:" + std::string(YTDLPOutputParser::sentinel)
            + R"({"event":"progress","percent":%(progress._percent_str)j,"speed":%(progress._speed_str)j,"eta":%(progress._eta_str)j})",
        "--print",
        completed_template,
        "--",
        request.url,
    });
    return result;
}

std::optional<YTDLPEvent> YTDLPOutputParser::parse(
    std::string_view line) noexcept {
    try {
        const auto trimmed = trim_ascii(line);
        if (trimmed.size() <= sentinel.size()
            || trimmed.size() > maximum_event_bytes
            || !trimmed.starts_with(sentinel)) {
            return std::nullopt;
        }
        const auto payload = std::string_view(trimmed).substr(sentinel.size());
        const std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)> document(
            yyjson_read(payload.data(), payload.size(), YYJSON_READ_NOFLAG),
            &yyjson_doc_free);
        if (!document) {
            return std::nullopt;
        }
        auto* root = yyjson_doc_get_root(document.get());
        if (!root || !yyjson_is_obj(root)) {
            return std::nullopt;
        }
        const auto event = json_string(yyjson_obj_get(root, "event"));
        if (!event) {
            return std::nullopt;
        }
        if (*event == "progress") {
            const auto percent = json_string(yyjson_obj_get(root, "percent"));
            if (!percent) {
                return std::nullopt;
            }
            const auto fraction = parse_percent(*percent);
            if (!fraction) {
                return std::nullopt;
            }
            return YTDLPEvent{
                .kind = YTDLPEventKind::progress,
                .fraction = *fraction,
                .speed = json_string(yyjson_obj_get(root, "speed")).value_or(""),
                .eta = json_string(yyjson_obj_get(root, "eta")).value_or(""),
            };
        }

        const auto filepath = json_string(yyjson_obj_get(root, "filepath"));
        if (!filepath || filepath->empty()) {
            return std::nullopt;
        }
        const auto path = path_from_utf8(*filepath);
        if (*event == "completed") {
            return YTDLPEvent{
                .kind = YTDLPEventKind::completed_file,
                .path = path,
            };
        }
        if (*event != "component") {
            return std::nullopt;
        }
        const auto format_id = json_string(yyjson_obj_get(root, "format_id"));
        const auto kind = component_kind(
            json_string(yyjson_obj_get(root, "vcodec")),
            json_string(yyjson_obj_get(root, "acodec")));
        if (!format_id || format_id->empty() || !kind) {
            return std::nullopt;
        }
        auto component = DownloadedMediaComponent{
            .path = path,
            .format_id = *format_id,
            .kind = *kind,
        };
        return YTDLPEvent{
            .kind = YTDLPEventKind::completed_component,
            .path = path,
            .component = std::move(component),
        };
    } catch (...) {
        return std::nullopt;
    }
}

std::filesystem::path DownloadOutputPathBuilder::destination(
    const DownloadedMediaComponent& component,
    const std::filesystem::path& output_directory,
    std::optional<std::string_view> extension) {
    auto stem = component.path.stem().native();
    const auto suffix = std::filesystem::path(
        "." + component.format_id).native();
    if (stem.size() >= suffix.size()
        && std::equal(suffix.rbegin(), suffix.rend(), stem.rbegin())) {
        stem.erase(stem.size() - suffix.size());
    }
    auto result = output_directory / std::filesystem::path(stem);
    auto selected_extension = extension
        ? std::filesystem::path(std::string(*extension))
        : component.path.extension();
    if (!selected_extension.empty()) {
        if (selected_extension.native().front() != '.') {
            result += std::filesystem::path(".");
        }
        result += std::move(selected_extension);
    }
    return result.lexically_normal();
}

std::optional<std::filesystem::path>
DownloadOutputPathBuilder::available_destination(
    const std::filesystem::path& desired,
    std::size_t maximum_suffix) noexcept {
    try {
        if (desired.empty() || maximum_suffix == 0) {
            return std::nullopt;
        }
        std::error_code error;
        if (!std::filesystem::exists(desired, error)) {
            return error
                ? std::nullopt
                : std::optional<std::filesystem::path>{desired.lexically_normal()};
        }
        for (std::size_t index = 1; index <= maximum_suffix; ++index) {
            auto filename = desired.stem();
            filename += std::filesystem::path(
                " (" + std::to_string(index) + ")");
            filename += desired.extension();
            auto candidate = desired.parent_path() / filename;
            if (!std::filesystem::exists(candidate, error)) {
                return error
                    ? std::nullopt
                    : std::optional<std::filesystem::path>{
                        candidate.lexically_normal()};
            }
            if (error) {
                return std::nullopt;
            }
        }
    } catch (...) {
    }
    return std::nullopt;
}

std::optional<std::filesystem::path> DownloadOutputPathValidator::normalized_file(
    const std::filesystem::path& file,
    const std::filesystem::path& output_directory) noexcept {
    try {
        if (file.empty() || output_directory.empty()
            || !file.is_absolute() || !output_directory.is_absolute()) {
            return std::nullopt;
        }
        std::error_code error;
        const auto normalized_directory = std::filesystem::weakly_canonical(
            output_directory,
            error);
        if (error) {
            return std::nullopt;
        }
        const auto normalized_file = std::filesystem::weakly_canonical(file, error);
        if (error || !std::filesystem::is_regular_file(normalized_file, error)
            || error
            || !DiskCleanupPlanner::isDescendantOfAllowedRoot(
                normalized_file,
                std::span<const std::filesystem::path>(&normalized_directory, 1))) {
            return std::nullopt;
        }
        return normalized_file;
    } catch (...) {
        return std::nullopt;
    }
}

bool DownloadFailureDiagnostics::is_bilibili_url(std::string_view url) noexcept {
    const auto host = url_host(url);
    return host && (host_matches(*host, "bilibili.com")
        || host_matches(*host, "b23.tv"));
}

bool DownloadFailureDiagnostics::should_use_bilibili_fallback(
    std::string_view diagnostic,
    std::string_view url) noexcept {
    if (!is_bilibili_url(url)) {
        return false;
    }
    return contains_ascii_case_insensitive(diagnostic, "http error 412")
        || contains_ascii_case_insensitive(diagnostic, "http 412")
        || contains_ascii_case_insensitive(diagnostic, "412: precondition failed")
        || contains_ascii_case_insensitive(
            diagnostic,
            "requested format is not available");
}

std::string DownloadFailureDiagnostics::actionable_message(
    std::string_view diagnostic,
    std::string_view url) {
    if (is_bilibili_url(url)
        && (contains_ascii_case_insensitive(diagnostic, "http error 412")
            || contains_ascii_case_insensitive(diagnostic, "http 412")
            || contains_ascii_case_insensitive(
                diagnostic,
                "412: precondition failed"))) {
        return "B站返回 HTTP 412 风控拦截。请先在浏览器登录 B站并完成验证，稍后或更换网络重试。";
    }
    return diagnostic.empty() ? "下载失败" : std::string(diagnostic);
}

std::optional<std::string> BilibiliDownloadPlanner::extract_bvid(
    std::string_view url) noexcept {
    try {
        const auto normalized = DownloadRequestValidator::normalized_url(url);
        const auto host = normalized ? url_host(*normalized) : std::nullopt;
        if (!normalized || !host
            || (!host_matches(*host, "bilibili.com")
                && !host_matches(*host, "b23.tv"))) {
            return std::nullopt;
        }
        const auto scheme_end = normalized->find("://");
        const auto path_begin = normalized->find('/', scheme_end + 3);
        if (path_begin == std::string::npos) {
            return std::nullopt;
        }
        const auto path_end = normalized->find_first_of("?#", path_begin);
        auto path = std::string_view(*normalized).substr(
            path_begin,
            path_end == std::string::npos
                ? std::string::npos
                : path_end - path_begin);
        while (!path.empty()) {
            if (path.front() == '/') {
                path.remove_prefix(1);
            }
            const auto separator = path.find('/');
            const auto segment = path.substr(0, separator);
            if (segment.size() >= 12 && segment.starts_with("BV")
                && std::all_of(
                    segment.begin() + 2,
                    segment.end(),
                    [](char character) {
                        return static_cast<unsigned char>(character) < 0x80U
                            && std::isalnum(
                                static_cast<unsigned char>(character)) != 0;
                    })) {
                return std::string(segment);
            }
            if (separator == std::string_view::npos) {
                break;
            }
            path.remove_prefix(separator);
        }
    } catch (...) {
    }
    return std::nullopt;
}

BilibiliVideoView BilibiliDownloadPlanner::parse_view_response(
    std::string bvid,
    std::string_view response) {
    auto document = parse_bilibili_response(response);
    auto* data = bilibili_response_data(document);
    const auto title = json_string(yyjson_obj_get(data, "title"));
    auto* cid = yyjson_obj_get(data, "cid");
    if (bvid.empty() || !title || title->empty()
        || !cid || !yyjson_is_int(cid) || yyjson_get_sint(cid) <= 0) {
        throw BilibiliResponseError("B站视频信息不完整");
    }
    return {
        .bvid = std::move(bvid),
        .title = *title,
        .cid = yyjson_get_sint(cid),
    };
}

BilibiliMediaSelection BilibiliDownloadPlanner::parse_play_response(
    std::string_view response) {
    auto document = parse_bilibili_response(response);
    auto* data = bilibili_response_data(document);
    auto* dash = yyjson_obj_get(data, "dash");
    if (!dash || !yyjson_is_obj(dash)) {
        throw BilibiliResponseError(
            "B站接口未返回可封装的 DASH 轨道");
    }

    auto videos = bilibili_tracks(yyjson_obj_get(dash, "video"));
    auto audios = bilibili_tracks(yyjson_obj_get(dash, "audio"));
    const bool has_avc = std::any_of(videos.begin(), videos.end(), is_avc_mp4);
    const auto video = std::max_element(
        videos.begin(),
        videos.end(),
        [has_avc](const auto& left, const auto& right) {
            const bool left_allowed = has_avc ? is_avc_mp4(left) : is_mp4_video(left);
            const bool right_allowed = has_avc ? is_avc_mp4(right) : is_mp4_video(right);
            if (left_allowed != right_allowed) {
                return !left_allowed;
            }
            return lower_quality_video(left, right);
        });
    const auto audio = std::max_element(
        audios.begin(),
        audios.end(),
        [](const auto& left, const auto& right) {
            return left.bandwidth < right.bandwidth;
        });
    if (video == videos.end() || audio == audios.end()
        || !(has_avc ? is_avc_mp4(*video) : is_mp4_video(*video))) {
        throw BilibiliResponseError(
            "B站接口未返回可封装的 DASH 视频轨和音频轨");
    }
    return {
        .video = *video,
        .audio = *audio,
    };
}

bool DownloadSnapshot::active() const noexcept {
    return phase == DownloadPhase::preparing
        || phase == DownloadPhase::downloading
        || phase == DownloadPhase::cancelling;
}

bool DownloadState::begin(DownloadRequest request) {
    if (snapshot_.active()) {
        return false;
    }
    snapshot_.request = std::move(request);
    snapshot_.phase = DownloadPhase::preparing;
    snapshot_.fraction = 0.0;
    snapshot_.speed.clear();
    snapshot_.eta.clear();
    snapshot_.completed_file.reset();
    snapshot_.error.clear();
    ++snapshot_.revision;
    return true;
}

void DownloadState::update_progress(
    double fraction,
    std::string speed,
    std::string eta) {
    if (!snapshot_.active() || snapshot_.phase == DownloadPhase::cancelling) {
        return;
    }
    snapshot_.phase = DownloadPhase::downloading;
    snapshot_.fraction = std::isfinite(fraction)
        ? std::clamp(fraction, 0.0, 1.0)
        : 0.0;
    snapshot_.speed = std::move(speed);
    snapshot_.eta = std::move(eta);
    ++snapshot_.revision;
}

bool DownloadState::request_cancel() noexcept {
    if (!snapshot_.active() || snapshot_.phase == DownloadPhase::cancelling) {
        return false;
    }
    snapshot_.phase = DownloadPhase::cancelling;
    ++snapshot_.revision;
    return true;
}

void DownloadState::complete(std::filesystem::path file) {
    if (!snapshot_.active() || snapshot_.phase == DownloadPhase::cancelling) {
        return;
    }
    snapshot_.phase = DownloadPhase::completed;
    snapshot_.fraction = 1.0;
    snapshot_.speed.clear();
    snapshot_.eta.clear();
    snapshot_.completed_file = std::move(file);
    snapshot_.error.clear();
    ++snapshot_.revision;
}

void DownloadState::fail(std::string error) {
    if (!snapshot_.active() || snapshot_.phase == DownloadPhase::cancelling) {
        return;
    }
    snapshot_.phase = DownloadPhase::failed;
    snapshot_.speed.clear();
    snapshot_.eta.clear();
    snapshot_.completed_file.reset();
    snapshot_.error = std::move(error);
    ++snapshot_.revision;
}

void DownloadState::cancel() noexcept {
    if (!snapshot_.active()) {
        return;
    }
    snapshot_.phase = DownloadPhase::cancelled;
    snapshot_.speed.clear();
    snapshot_.eta.clear();
    snapshot_.completed_file.reset();
    snapshot_.error.clear();
    ++snapshot_.revision;
}

const DownloadSnapshot& DownloadState::snapshot() const noexcept {
    return snapshot_;
}

std::wstring WindowsCommandLine::quote_argument(std::wstring_view value) {
    const bool needs_quotes = value.empty()
        || std::any_of(value.begin(), value.end(), [](wchar_t character) {
            return character == L'"' || std::iswspace(character) != 0;
        });
    if (!needs_quotes) {
        return std::wstring(value);
    }

    std::wstring result{L"\""};
    std::size_t backslashes = 0;
    for (const auto character : value) {
        if (character == L'\\') {
            ++backslashes;
            continue;
        }
        if (character == L'"') {
            result.append(backslashes * 2 + 1, L'\\');
            result.push_back(L'"');
        } else {
            result.append(backslashes, L'\\');
            result.push_back(character);
        }
        backslashes = 0;
    }
    result.append(backslashes * 2, L'\\');
    result.push_back(L'"');
    return result;
}

std::wstring WindowsCommandLine::build(
    std::span<const std::wstring> arguments) {
    std::wstring result;
    for (const auto& argument : arguments) {
        if (!result.empty()) {
            result.push_back(L' ');
        }
        result.append(quote_argument(argument));
    }
    return result;
}

std::vector<std::string> DownloadProcessOutputBuffer::append(
    std::string_view chunk) {
    append_diagnostic(chunk);

    std::vector<std::string> lines;
    std::size_t cursor = 0;
    while (cursor < chunk.size()) {
        if (discarding_line_) {
            const auto newline = chunk.find('\n', cursor);
            if (newline == std::string_view::npos) {
                return lines;
            }
            discarding_line_ = false;
            cursor = newline + 1;
            continue;
        }

        const auto newline = chunk.find('\n', cursor);
        const auto end = newline == std::string_view::npos
            ? chunk.size()
            : newline;
        const auto segment = chunk.substr(cursor, end - cursor);
        if (pending_line_.size() + segment.size() > maximum_line_bytes) {
            pending_line_.clear();
            if (newline == std::string_view::npos) {
                discarding_line_ = true;
                return lines;
            }
        } else {
            pending_line_.append(segment);
            if (newline != std::string_view::npos) {
                if (pending_line_.ends_with('\r')) {
                    pending_line_.pop_back();
                }
                lines.push_back(std::move(pending_line_));
                pending_line_.clear();
            }
        }

        if (newline == std::string_view::npos) {
            break;
        }
        cursor = newline + 1;
    }
    return lines;
}

std::optional<std::string> DownloadProcessOutputBuffer::finish() {
    if (discarding_line_ || pending_line_.empty()) {
        pending_line_.clear();
        discarding_line_ = false;
        return std::nullopt;
    }
    if (pending_line_.ends_with('\r')) {
        pending_line_.pop_back();
    }
    auto line = std::move(pending_line_);
    pending_line_.clear();
    return line;
}

std::string DownloadProcessOutputBuffer::diagnostic() const {
    return trim_ascii(diagnostic_);
}

void DownloadProcessOutputBuffer::append_diagnostic(std::string_view chunk) {
    if (chunk.size() >= maximum_diagnostic_bytes) {
        diagnostic_.assign(chunk.end() - maximum_diagnostic_bytes, chunk.end());
    } else {
        const auto overflow = diagnostic_.size() + chunk.size()
            > maximum_diagnostic_bytes
            ? diagnostic_.size() + chunk.size() - maximum_diagnostic_bytes
            : 0;
        if (overflow != 0) {
            diagnostic_.erase(0, overflow);
        }
        diagnostic_.append(chunk);
    }
    while (!diagnostic_.empty()
        && (static_cast<unsigned char>(diagnostic_.front()) & 0xC0U) == 0x80U) {
        diagnostic_.erase(diagnostic_.begin());
    }
}

}  // namespace zisla::core
