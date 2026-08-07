#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <vector>

namespace zisla::core {

using MediaArtwork = std::shared_ptr<const std::vector<std::uint8_t>>;

enum class MediaPlaybackStatus {
    stopped,
    paused,
    playing,
};

struct MediaControlCapabilities {
    bool can_toggle_play_pause{false};
    bool can_previous{false};
    bool can_next{false};
    bool can_seek{false};

    friend bool operator==(
        const MediaControlCapabilities&,
        const MediaControlCapabilities&) = default;
};

struct NowPlayingSnapshot {
    std::string session_id;
    std::string title;
    std::string artist;
    std::string album;
    std::string source_application;
    MediaArtwork artwork;
    std::optional<double> duration_seconds;
    std::optional<double> elapsed_seconds;
    std::optional<std::int64_t> position_timestamp_unix_ms;
    MediaPlaybackStatus playback_status{MediaPlaybackStatus::stopped};
    MediaControlCapabilities controls;

    [[nodiscard]] bool valid() const noexcept;
    [[nodiscard]] std::optional<double> elapsedAt(
        std::int64_t now_unix_ms) const noexcept;

    friend bool operator==(const NowPlayingSnapshot&, const NowPlayingSnapshot&) = default;
};

struct MediaSessionCandidate {
    NowPlayingSnapshot snapshot;
    bool is_system_current{false};
    std::int64_t updated_at_unix_ms{0};
};

class NowPlaying {
public:
    [[nodiscard]] static double clampedSeekTime(
        double seconds,
        double duration_seconds) noexcept;
    [[nodiscard]] static NowPlayingSnapshot mergingMetadata(
        NowPlayingSnapshot update,
        const NowPlayingSnapshot& previous);
    [[nodiscard]] static std::optional<std::size_t> selectSession(
        std::span<const MediaSessionCandidate> candidates) noexcept;
};

}  // namespace zisla::core
