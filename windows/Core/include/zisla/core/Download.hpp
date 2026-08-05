#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

enum class DownloadMode {
    video,
    audio,
};

struct DownloadRequest {
    std::string url;
    DownloadMode mode{DownloadMode::video};
    std::filesystem::path output_directory;

    friend bool operator==(const DownloadRequest&, const DownloadRequest&) = default;
};

enum class DownloadRequestValidation {
    valid,
    unsupported_url,
    invalid_output_directory,
};

class DownloadRequestValidator {
public:
    [[nodiscard]] static std::optional<std::string> normalized_url(
        std::string_view value) noexcept;
    [[nodiscard]] static DownloadRequestValidation validate(
        const DownloadRequest& request) noexcept;
};

struct DownloadCapabilities {
    bool has_ffmpeg{false};

    friend bool operator==(
        const DownloadCapabilities&,
        const DownloadCapabilities&) = default;
};

enum class DownloadExecutionStrategy {
    direct,
    native_packaging,
};

class YTDLPArgumentBuilder {
public:
    [[nodiscard]] static DownloadExecutionStrategy strategy(
        const DownloadRequest& request,
        DownloadCapabilities capabilities) noexcept;
    [[nodiscard]] static std::vector<std::string> arguments(
        const DownloadRequest& request,
        DownloadCapabilities capabilities,
        const std::filesystem::path& task_temporary_directory,
        std::optional<std::filesystem::path> ffmpeg_executable = std::nullopt);
};

enum class DownloadedMediaKind {
    video,
    audio,
    combined,
};

struct DownloadedMediaComponent {
    std::filesystem::path path;
    std::string format_id;
    DownloadedMediaKind kind{DownloadedMediaKind::combined};

    friend bool operator==(
        const DownloadedMediaComponent&,
        const DownloadedMediaComponent&) = default;
};

enum class YTDLPEventKind {
    progress,
    completed_file,
    completed_component,
};

struct YTDLPEvent {
    YTDLPEventKind kind{YTDLPEventKind::progress};
    double fraction{0.0};
    std::string speed;
    std::string eta;
    std::filesystem::path path;
    std::optional<DownloadedMediaComponent> component;

    friend bool operator==(const YTDLPEvent&, const YTDLPEvent&) = default;
};

class YTDLPOutputParser {
public:
    static constexpr std::string_view sentinel = "__ZISLA_YTDLP_JSON__";

    [[nodiscard]] static std::optional<YTDLPEvent> parse(
        std::string_view line) noexcept;
};

class DownloadOutputPathBuilder {
public:
    [[nodiscard]] static std::filesystem::path destination(
        const DownloadedMediaComponent& component,
        const std::filesystem::path& output_directory,
        std::optional<std::string_view> extension = std::nullopt);
    [[nodiscard]] static std::optional<std::filesystem::path>
        available_destination(
            const std::filesystem::path& desired,
            std::size_t maximum_suffix = 9'999) noexcept;
};

class DownloadOutputPathValidator {
public:
    [[nodiscard]] static std::optional<std::filesystem::path> normalized_file(
        const std::filesystem::path& file,
        const std::filesystem::path& output_directory) noexcept;
};

class DownloadFailureDiagnostics {
public:
    [[nodiscard]] static bool is_bilibili_url(std::string_view url) noexcept;
    [[nodiscard]] static bool should_use_bilibili_fallback(
        std::string_view diagnostic,
        std::string_view url) noexcept;
    [[nodiscard]] static std::string actionable_message(
        std::string_view diagnostic,
        std::string_view url);
};

class BilibiliResponseError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

struct BilibiliVideoView {
    std::string bvid;
    std::string title;
    std::int64_t cid{0};

    friend bool operator==(const BilibiliVideoView&, const BilibiliVideoView&) = default;
};

struct BilibiliMediaTrack {
    std::int64_t id{0};
    std::vector<std::string> urls;
    std::int64_t bandwidth{0};
    std::string codecs;
    std::string mime_type;
    int width{0};
    int height{0};

    friend bool operator==(const BilibiliMediaTrack&, const BilibiliMediaTrack&) = default;
};

struct BilibiliMediaSelection {
    BilibiliMediaTrack video;
    BilibiliMediaTrack audio;

    friend bool operator==(
        const BilibiliMediaSelection&,
        const BilibiliMediaSelection&) = default;
};

class BilibiliDownloadPlanner {
public:
    [[nodiscard]] static std::optional<std::string> extract_bvid(
        std::string_view url) noexcept;
    [[nodiscard]] static BilibiliVideoView parse_view_response(
        std::string bvid,
        std::string_view response);
    [[nodiscard]] static BilibiliMediaSelection parse_play_response(
        std::string_view response);
};

enum class DownloadPhase {
    idle,
    preparing,
    downloading,
    cancelling,
    completed,
    failed,
    cancelled,
};

struct DownloadSnapshot {
    DownloadRequest request;
    DownloadPhase phase{DownloadPhase::idle};
    double fraction{0.0};
    std::string speed;
    std::string eta;
    std::optional<std::filesystem::path> completed_file;
    std::string error;
    std::uint64_t revision{0};

    [[nodiscard]] bool active() const noexcept;
    friend bool operator==(const DownloadSnapshot&, const DownloadSnapshot&) = default;
};

class DownloadState {
public:
    [[nodiscard]] bool begin(DownloadRequest request);
    void update_progress(double fraction, std::string speed, std::string eta);
    [[nodiscard]] bool request_cancel() noexcept;
    void complete(std::filesystem::path file);
    void fail(std::string error);
    void cancel() noexcept;

    [[nodiscard]] const DownloadSnapshot& snapshot() const noexcept;

private:
    DownloadSnapshot snapshot_;
};

class WindowsCommandLine {
public:
    [[nodiscard]] static std::wstring quote_argument(std::wstring_view value);
    [[nodiscard]] static std::wstring build(
        std::span<const std::wstring> arguments);
};

class DownloadProcessOutputBuffer {
public:
    static constexpr std::size_t maximum_line_bytes = 64U * 1024U;
    static constexpr std::size_t maximum_diagnostic_bytes = 128U * 1024U;

    [[nodiscard]] std::vector<std::string> append(std::string_view chunk);
    [[nodiscard]] std::optional<std::string> finish();
    [[nodiscard]] std::string diagnostic() const;

private:
    void append_diagnostic(std::string_view chunk);

    std::string pending_line_;
    std::string diagnostic_;
    bool discarding_line_{false};
};

}  // namespace zisla::core
