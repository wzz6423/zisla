#include "zisla/core/Update.hpp"

#include <yyjson.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <charconv>
#include <cmath>
#include <cstdint>
#include <limits>
#include <memory>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>

namespace zisla::core {
namespace {

using JsonDocument = std::unique_ptr<yyjson_doc, decltype(&yyjson_doc_free)>;

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

bool is_identifier_character(unsigned char character) noexcept {
    return (character >= '0' && character <= '9')
        || (character >= 'a' && character <= 'z')
        || (character >= 'A' && character <= 'Z')
        || character == '-';
}

bool is_numeric_identifier(std::string_view value) noexcept {
    return !value.empty()
        && std::all_of(value.begin(), value.end(), [](unsigned char character) {
            return character >= '0' && character <= '9';
        });
}

std::string_view without_leading_zeroes(std::string_view value) noexcept {
    const auto first = value.find_first_not_of('0');
    return first == std::string_view::npos ? std::string_view{"0"} : value.substr(first);
}

int compare_numeric_identifiers(std::string_view left, std::string_view right) noexcept {
    left = without_leading_zeroes(left);
    right = without_leading_zeroes(right);
    if (left.size() != right.size()) {
        return left.size() < right.size() ? -1 : 1;
    }
    if (left == right) {
        return 0;
    }
    return left < right ? -1 : 1;
}

bool is_safe_https_url(std::string_view value) noexcept {
    constexpr std::string_view prefix = "https://";
    if (!value.starts_with(prefix) || value.size() == prefix.size()) {
        return false;
    }
    const auto authority_start = prefix.size();
    const auto authority_end = value.find_first_of("/?#", authority_start);
    const auto authority = value.substr(
        authority_start,
        authority_end == std::string_view::npos
            ? value.size() - authority_start
            : authority_end - authority_start);
    if (authority.empty() || authority.find('@') != std::string_view::npos) {
        return false;
    }
    return std::all_of(value.begin(), value.end(), [](unsigned char character) {
        return character >= 0x20 && character != 0x7f;
    });
}

std::optional<std::string> string_member(yyjson_val* object, const char* name) {
    if (!yyjson_is_obj(object)) {
        return std::nullopt;
    }
    auto* value = yyjson_obj_get(object, name);
    if (!yyjson_is_str(value)) {
        return std::nullopt;
    }
    const auto* text = yyjson_get_str(value);
    return text ? std::optional<std::string>{std::string(text, yyjson_get_len(value))}
                : std::nullopt;
}

std::optional<bool> bool_member(yyjson_val* object, const char* name) {
    if (!yyjson_is_obj(object)) {
        return std::nullopt;
    }
    auto* value = yyjson_obj_get(object, name);
    if (!value) {
        return false;
    }
    if (!yyjson_is_bool(value)) {
        return std::nullopt;
    }
    return yyjson_get_bool(value);
}

std::uint64_t size_member(yyjson_val* object) noexcept {
    if (!yyjson_is_obj(object)) {
        return 0;
    }
    auto* value = yyjson_obj_get(object, "size");
    if (!value || !yyjson_is_num(value)) {
        return 0;
    }
    const auto number = yyjson_get_num(value);
    if (!std::isfinite(number) || number < 0
        || number > static_cast<double>(std::numeric_limits<std::uint64_t>::max())) {
        return 0;
    }
    return static_cast<std::uint64_t>(number);
}

bool is_available_release(
    const SemanticVersion& current,
    const std::optional<ReleaseInfo>& release,
    UpdateChannel channel) {
    if (!release || release->draft
        || (channel == UpdateChannel::release && release->prerelease)
        || (channel == UpdateChannel::preview && !release->prerelease)) {
        return false;
    }
    const auto version = SemanticVersion::parse(release->tag_name);
    return version && current < *version;
}

}  // namespace

std::string_view update_channel_token(UpdateChannel channel) noexcept {
    switch (channel) {
    case UpdateChannel::release:
        return "release";
    case UpdateChannel::preview:
        return "preview";
    }
    return "release";
}

std::optional<UpdateChannel> update_channel_from_token(std::string_view token) noexcept {
    if (token == "release") {
        return UpdateChannel::release;
    }
    if (token == "preview") {
        return UpdateChannel::preview;
    }
    return std::nullopt;
}

std::optional<SemanticVersion> SemanticVersion::parse(std::string_view value) {
    auto text = trim_ascii(value);
    if (text.empty()) {
        return std::nullopt;
    }
    if (text.front() == 'v' || text.front() == 'V') {
        text.erase(text.begin());
    }
    if (text.empty()) {
        return std::nullopt;
    }

    const auto build_separator = text.find('+');
    if (build_separator != std::string::npos) {
        text.erase(build_separator);
    }
    const auto prerelease_separator = text.find('-');
    const auto core = text.substr(0, prerelease_separator);
    if (core.empty()) {
        return std::nullopt;
    }

    SemanticVersion result;
    std::size_t component = 0;
    std::size_t begin = 0;
    while (begin <= core.size()) {
        const auto end = core.find('.', begin);
        const auto part = std::string_view(core).substr(
            begin,
            end == std::string::npos ? core.size() - begin : end - begin);
        if (part.empty() || component >= result.numbers_.size()) {
            return std::nullopt;
        }
        std::uint64_t number = 0;
        const auto [parsed_end, error] = std::from_chars(
            part.data(),
            part.data() + part.size(),
            number);
        if (error != std::errc{} || parsed_end != part.data() + part.size()
            || number > std::numeric_limits<std::uint32_t>::max()) {
            return std::nullopt;
        }
        result.numbers_[component++] = static_cast<std::uint32_t>(number);
        if (end == std::string::npos) {
            break;
        }
        begin = end + 1;
    }

    if (prerelease_separator != std::string::npos) {
        const auto prerelease = std::string_view(text).substr(prerelease_separator + 1);
        if (prerelease.empty()) {
            return std::nullopt;
        }
        begin = 0;
        while (begin <= prerelease.size()) {
            const auto end = prerelease.find('.', begin);
            const auto part = prerelease.substr(
                begin,
                end == std::string::npos ? prerelease.size() - begin : end - begin);
            if (part.empty()
                || !std::all_of(part.begin(), part.end(), [](unsigned char character) {
                    return is_identifier_character(character);
                })) {
                return std::nullopt;
            }
            result.prerelease_.emplace_back(part);
            if (end == std::string::npos) {
                break;
            }
            begin = end + 1;
        }
    }
    return result;
}

bool operator<(
    const SemanticVersion& left,
    const SemanticVersion& right) noexcept {
    if (left.numbers_ != right.numbers_) {
        return std::lexicographical_compare(
            left.numbers_.begin(),
            left.numbers_.end(),
            right.numbers_.begin(),
            right.numbers_.end());
    }
    if (left.prerelease_.empty() || right.prerelease_.empty()) {
        return !left.prerelease_.empty() && right.prerelease_.empty();
    }
    const auto count = std::min(left.prerelease_.size(), right.prerelease_.size());
    for (std::size_t index = 0; index < count; ++index) {
        const auto& left_part = left.prerelease_[index];
        const auto& right_part = right.prerelease_[index];
        if (left_part == right_part) {
            continue;
        }
        const bool left_numeric = is_numeric_identifier(left_part);
        const bool right_numeric = is_numeric_identifier(right_part);
        if (left_numeric != right_numeric) {
            return left_numeric;
        }
        if (left_numeric) {
            return compare_numeric_identifiers(left_part, right_part) < 0;
        }
        return left_part < right_part;
    }
    return left.prerelease_.size() < right.prerelease_.size();
}

std::string_view release_source_display_name(ReleaseSource source) noexcept {
    switch (source) {
    case ReleaseSource::gitee:
        return "Gitee";
    case ReleaseSource::github:
        return "GitHub";
    }
    return "GitHub";
}

std::string_view release_endpoint(
    ReleaseSource source,
    UpdateChannel channel) noexcept {
    switch (source) {
    case ReleaseSource::gitee:
        return channel == UpdateChannel::preview
            ? "https://gitee.com/api/v5/repos/wzz6423/zisla/releases/tags/preview"
            : "https://gitee.com/api/v5/repos/wzz6423/zisla/releases/latest";
    case ReleaseSource::github:
        return channel == UpdateChannel::preview
            ? "https://api.github.com/repos/wzz6423/zisla/releases/tags/preview"
            : "https://api.github.com/repos/wzz6423/zisla/releases/latest";
    }
    return "https://api.github.com/repos/wzz6423/zisla/releases/latest";
}

ReleaseResponseError::ReleaseResponseError(
    ReleaseResponseErrorCode code,
    std::string message)
    : std::runtime_error(std::move(message)), code_(code) {}

ReleaseResponseErrorCode ReleaseResponseError::code() const noexcept {
    return code_;
}

ReleaseInfo ReleaseResponseParser::parse(std::string_view response) {
    if (response.size() > maximum_response_bytes) {
        throw ReleaseResponseError(
            ReleaseResponseErrorCode::response_too_large,
            "更新服务响应超过大小限制");
    }
    JsonDocument document{
        yyjson_read(response.data(), response.size(), YYJSON_READ_NOFLAG),
        &yyjson_doc_free,
    };
    if (!document) {
        throw ReleaseResponseError(
            ReleaseResponseErrorCode::invalid_json,
            "更新服务返回了无效 JSON");
    }
    auto* root = yyjson_doc_get_root(document.get());
    if (!yyjson_is_obj(root)) {
        throw ReleaseResponseError(
            ReleaseResponseErrorCode::invalid_shape,
            "更新服务返回了无效 Release 对象");
    }

    const auto tag = string_member(root, "tag_name");
    const auto html_url = string_member(root, "html_url");
    if (!tag || tag->empty() || !html_url || !is_safe_https_url(*html_url)
        || !SemanticVersion::parse(*tag)) {
        throw ReleaseResponseError(
            ReleaseResponseErrorCode::invalid_value,
            "Release 版本或地址无效");
    }
    const auto draft = bool_member(root, "draft");
    const auto prerelease = bool_member(root, "prerelease");
    if (!draft || !prerelease) {
        throw ReleaseResponseError(
            ReleaseResponseErrorCode::invalid_shape,
            "Release 状态字段无效");
    }

    ReleaseInfo result{
        .tag_name = *tag,
        .html_url = *html_url,
        .draft = *draft,
        .prerelease = *prerelease,
    };

    auto* assets = yyjson_obj_get(root, "assets");
    if (!assets) {
        return result;
    }
    if (!yyjson_is_arr(assets)) {
        throw ReleaseResponseError(
            ReleaseResponseErrorCode::invalid_shape,
            "Release 资源列表无效");
    }
    std::size_t index = 0;
    std::size_t maximum = 0;
    yyjson_val* item = nullptr;
    yyjson_arr_foreach(assets, index, maximum, item) {
        const auto name = string_member(item, "name");
        const auto download_url = string_member(item, "browser_download_url");
        if (name && !name->empty() && download_url && is_safe_https_url(*download_url)) {
            result.assets.push_back({
                .name = *name,
                .download_url = *download_url,
                .size = size_member(item),
            });
        }
    }
    return result;
}

std::optional<AvailableUpdate> UpdateSelector::select(
    std::string_view current_version,
    const std::optional<ReleaseInfo>& gitee_release,
    const std::optional<ReleaseInfo>& github_release,
    UpdateChannel channel) {
    const auto current = SemanticVersion::parse(current_version);
    if (!current) {
        return std::nullopt;
    }
    if (is_available_release(*current, gitee_release, channel)) {
        return AvailableUpdate{
            .source = ReleaseSource::gitee,
            .release = *gitee_release,
        };
    }
    if (is_available_release(*current, github_release, channel)) {
        return AvailableUpdate{
            .source = ReleaseSource::github,
            .release = *github_release,
        };
    }
    return std::nullopt;
}

bool UpdateSourceQueryPolicy::should_query_github(
    std::string_view current_version,
    const std::optional<ReleaseInfo>& gitee_release,
    UpdateChannel channel) {
    const auto current = SemanticVersion::parse(current_version);
    return !current || !is_available_release(*current, gitee_release, channel);
}

}  // namespace zisla::core
