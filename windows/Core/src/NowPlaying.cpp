#include "zisla/core/NowPlaying.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <string_view>
#include <tuple>

namespace zisla::core {
namespace {

std::string normalized(std::string_view value) {
    std::string result;
    result.reserve(value.size());
    bool pending_space = false;
    for (const auto byte : value) {
        const auto character = static_cast<unsigned char>(byte);
        if (std::isspace(character)) {
            pending_space = !result.empty();
            continue;
        }
        if (pending_space) {
            result.push_back(' ');
            pending_space = false;
        }
        result.push_back(static_cast<char>(std::tolower(character)));
    }
    return result;
}

bool durationsIdentifySameTrack(
    const std::optional<double>& lhs,
    const std::optional<double>& rhs) noexcept {
    if (!lhs || !rhs || !std::isfinite(*lhs) || !std::isfinite(*rhs)
        || *lhs <= 0 || *rhs <= 0) {
        return true;
    }
    return std::abs(*lhs - *rhs) <= 2.0;
}

bool identifiesSameTrack(
    const NowPlayingSnapshot& lhs,
    const NowPlayingSnapshot& rhs) {
    return lhs.session_id == rhs.session_id
        && normalized(lhs.title) == normalized(rhs.title)
        && normalized(lhs.artist) == normalized(rhs.artist)
        && durationsIdentifySameTrack(lhs.duration_seconds, rhs.duration_seconds);
}

}  // namespace

bool NowPlayingSnapshot::valid() const noexcept {
    return !title.empty() || !artist.empty();
}

std::optional<double> NowPlayingSnapshot::elapsedAt(
    std::int64_t now_unix_ms) const noexcept {
    if (!elapsed_seconds || !std::isfinite(*elapsed_seconds)) {
        return std::nullopt;
    }

    auto elapsed = std::max(0.0, *elapsed_seconds);
    if (playback_status == MediaPlaybackStatus::playing
        && position_timestamp_unix_ms && now_unix_ms > *position_timestamp_unix_ms) {
        elapsed += static_cast<double>(now_unix_ms - *position_timestamp_unix_ms) / 1'000.0;
    }
    if (duration_seconds && std::isfinite(*duration_seconds) && *duration_seconds > 0) {
        elapsed = std::min(elapsed, *duration_seconds);
    }
    return elapsed;
}

double NowPlaying::clampedSeekTime(
    double seconds,
    double duration_seconds) noexcept {
    if (!std::isfinite(seconds) || !std::isfinite(duration_seconds)
        || duration_seconds <= 0) {
        return 0;
    }
    return std::clamp(seconds, 0.0, duration_seconds);
}

NowPlayingSnapshot NowPlaying::mergingMetadata(
    NowPlayingSnapshot update,
    const NowPlayingSnapshot& previous) {
    if (!identifiesSameTrack(update, previous)) {
        return update;
    }
    if (update.album.empty()) {
        update.album = previous.album;
    }
    if (!update.artwork) {
        update.artwork = previous.artwork;
    }
    if (update.source_application.empty()) {
        update.source_application = previous.source_application;
    }
    return update;
}

std::optional<std::size_t> NowPlaying::selectSession(
    std::span<const MediaSessionCandidate> candidates) noexcept {
    std::optional<std::size_t> selected;
    std::tuple<bool, bool, std::int64_t> selected_rank{};

    for (std::size_t index = 0; index < candidates.size(); ++index) {
        const auto& candidate = candidates[index];
        if (!candidate.snapshot.valid()) {
            continue;
        }
        const auto rank = std::tuple{
            candidate.is_system_current,
            candidate.snapshot.playback_status == MediaPlaybackStatus::playing,
            candidate.updated_at_unix_ms,
        };
        if (!selected || rank > selected_rank) {
            selected = index;
            selected_rank = rank;
        }
    }
    return selected;
}

}  // namespace zisla::core
