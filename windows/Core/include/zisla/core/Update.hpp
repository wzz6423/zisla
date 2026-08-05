#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

enum class UpdateChannel {
    release,
    preview,
};

[[nodiscard]] std::string_view update_channel_token(UpdateChannel channel) noexcept;
[[nodiscard]] std::optional<UpdateChannel> update_channel_from_token(
    std::string_view token) noexcept;

class SemanticVersion {
public:
    [[nodiscard]] static std::optional<SemanticVersion> parse(std::string_view value);

    friend bool operator<(
        const SemanticVersion& left,
        const SemanticVersion& right) noexcept;

    friend bool operator==(const SemanticVersion&, const SemanticVersion&) = default;

private:
    std::array<std::uint32_t, 3> numbers_{};
    std::vector<std::string> prerelease_;
};

enum class ReleaseSource {
    gitee,
    github,
};

[[nodiscard]] std::string_view release_source_display_name(ReleaseSource source) noexcept;
[[nodiscard]] std::string_view release_endpoint(
    ReleaseSource source,
    UpdateChannel channel) noexcept;

struct ReleaseAsset {
    std::string name;
    std::string download_url;
    std::uint64_t size{0};

    friend bool operator==(const ReleaseAsset&, const ReleaseAsset&) = default;
};

struct ReleaseInfo {
    std::string tag_name;
    std::string html_url;
    bool draft{false};
    bool prerelease{false};
    std::vector<ReleaseAsset> assets;

    friend bool operator==(const ReleaseInfo&, const ReleaseInfo&) = default;
};

enum class ReleaseResponseErrorCode {
    invalid_json,
    invalid_shape,
    invalid_value,
    response_too_large,
};

class ReleaseResponseError : public std::runtime_error {
public:
    ReleaseResponseError(ReleaseResponseErrorCode code, std::string message);

    [[nodiscard]] ReleaseResponseErrorCode code() const noexcept;

private:
    ReleaseResponseErrorCode code_;
};

class ReleaseResponseParser {
public:
    static constexpr std::size_t maximum_response_bytes = 1U * 1024U * 1024U;

    [[nodiscard]] static ReleaseInfo parse(std::string_view response);
};

struct AvailableUpdate {
    ReleaseSource source{ReleaseSource::github};
    ReleaseInfo release;

    friend bool operator==(const AvailableUpdate&, const AvailableUpdate&) = default;
};

class UpdateSelector {
public:
    /// Chooses the first newer, non-draft release in the platform's preferred source order.
    [[nodiscard]] static std::optional<AvailableUpdate> select(
        std::string_view current_version,
        const std::optional<ReleaseInfo>& gitee_release,
        const std::optional<ReleaseInfo>& github_release,
        UpdateChannel channel = UpdateChannel::release);
};

class UpdateSourceQueryPolicy {
public:
    [[nodiscard]] static bool should_query_github(
        std::string_view current_version,
        const std::optional<ReleaseInfo>& gitee_release,
        UpdateChannel channel = UpdateChannel::release);
};

}  // namespace zisla::core
