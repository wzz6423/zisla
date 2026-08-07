#include "zisla/core/NowPlaying.hpp"

#include <cmath>
#include <cstdint>
#include <exception>
#include <functional>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

using namespace zisla::core;

MediaArtwork artwork(std::initializer_list<std::uint8_t> bytes) {
    return std::make_shared<const std::vector<std::uint8_t>>(bytes);
}

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

NowPlayingSnapshot track(
    std::string title,
    MediaPlaybackStatus status = MediaPlaybackStatus::playing,
    std::string session_id = "player") {
    return {
        .session_id = std::move(session_id),
        .title = std::move(title),
        .artist = "Artist",
        .album = "Album",
        .duration_seconds = 180.0,
        .elapsed_seconds = 30.0,
        .position_timestamp_unix_ms = 1'000'000,
        .playback_status = status,
    };
}

void playbackClockAdvancesAndClampsToDuration() {
    const auto snapshot = track("Track");

    expect(snapshot.elapsedAt(1'012'000) == std::optional{42.0},
        "playing media should advance from its position timestamp");
    expect(snapshot.elapsedAt(1'500'000) == std::optional{180.0},
        "advanced media position should stop at the duration");
    expect(snapshot.elapsedAt(900'000) == std::optional{30.0},
        "a clock adjustment must not move playback backwards");
}

void pausedPlaybackClockDoesNotAdvance() {
    const auto snapshot = track("Track", MediaPlaybackStatus::paused);

    expect(snapshot.elapsedAt(1'012'000) == std::optional{30.0},
        "paused media should retain the reported position");
}

void missingPositionRemainsUnknown() {
    auto snapshot = track("Track");
    snapshot.elapsed_seconds.reset();

    expect(!snapshot.elapsedAt(1'012'000),
        "media without a timeline position must remain unknown");
}

void seekTimeIsClampedToTrackBounds() {
    expect(NowPlaying::clampedSeekTime(-4.0, 180.0) == 0.0,
        "negative seek positions should clamp to zero");
    expect(NowPlaying::clampedSeekTime(42.0, 180.0) == 42.0,
        "in-range seek positions should remain unchanged");
    expect(NowPlaying::clampedSeekTime(240.0, 180.0) == 180.0,
        "seek positions should clamp to the duration");
    expect(NowPlaying::clampedSeekTime(42.0, -1.0) == 0.0,
        "invalid durations should produce a zero seek position");
}

void sameTrackRefreshRetainsMissingMetadata() {
    auto previous = track("Track");
    previous.artwork = artwork({0x01, 0x02, 0x03});
    previous.source_application = "Music Player";

    auto refresh = previous;
    refresh.album.clear();
    refresh.artwork.reset();
    refresh.source_application.clear();
    refresh.elapsed_seconds = 31.0;

    const auto merged = NowPlaying::mergingMetadata(refresh, previous);

    expect(merged.album == "Album",
        "same-track refresh should retain the album");
    expect(merged.artwork == previous.artwork,
        "same-track refresh should retain existing artwork");
    expect(merged.source_application == "Music Player",
        "same-track refresh should retain the source name");
    expect(merged.elapsed_seconds == std::optional{31.0},
        "same-track refresh should keep fresh timeline data");
}

void newTrackDoesNotReusePreviousMetadata() {
    auto previous = track("First");
    previous.artwork = artwork({0x01});

    auto refresh = track("Second");
    refresh.artwork.reset();

    const auto merged = NowPlaying::mergingMetadata(refresh, previous);

    expect(!merged.artwork,
        "new tracks must not inherit artwork from the previous track");
}

void differentSessionsDoNotMergeMatchingTracks() {
    auto previous = track("Track", MediaPlaybackStatus::playing, "player-a");
    previous.artwork = artwork({0x01});

    auto refresh = track("Track", MediaPlaybackStatus::playing, "player-b");
    refresh.artwork.reset();

    const auto merged = NowPlaying::mergingMetadata(refresh, previous);

    expect(!merged.artwork,
        "matching titles from different sessions must remain isolated");
}

void durationDriftWithinTwoSecondsStillIdentifiesTheTrack() {
    auto previous = track("Track");
    previous.duration_seconds = 180.0;
    previous.artwork = artwork({0x01});

    auto refresh = previous;
    refresh.duration_seconds = 181.9;
    refresh.artwork.reset();

    expect(NowPlaying::mergingMetadata(refresh, previous).artwork == previous.artwork,
        "minor duration corrections should not discard same-track metadata");

    refresh.duration_seconds = 183.0;
    expect(!NowPlaying::mergingMetadata(refresh, previous).artwork,
        "materially different durations should identify a new track");
}

void systemCurrentSessionHasSelectionPriority() {
    const std::vector candidates{
        MediaSessionCandidate{
            .snapshot = track("Playing"),
            .updated_at_unix_ms = 300,
        },
        MediaSessionCandidate{
            .snapshot = track("Current", MediaPlaybackStatus::paused),
            .is_system_current = true,
            .updated_at_unix_ms = 100,
        },
    };

    expect(NowPlaying::selectSession(candidates) == std::optional<std::size_t>{1},
        "the Windows system-current session should be selected first");
}

void playingSessionWinsWithoutSystemCurrentSession() {
    const std::vector candidates{
        MediaSessionCandidate{
            .snapshot = track("Paused", MediaPlaybackStatus::paused),
            .updated_at_unix_ms = 500,
        },
        MediaSessionCandidate{
            .snapshot = track("Playing"),
            .updated_at_unix_ms = 100,
        },
    };

    expect(NowPlaying::selectSession(candidates) == std::optional<std::size_t>{1},
        "an active playing session should beat a newer paused session");
}

void newestValidSessionIsTheFinalFallback() {
    auto invalid = track("");
    invalid.artist.clear();

    const std::vector candidates{
        MediaSessionCandidate{
            .snapshot = track("Older", MediaPlaybackStatus::paused),
            .updated_at_unix_ms = 100,
        },
        MediaSessionCandidate{
            .snapshot = invalid,
            .is_system_current = true,
            .updated_at_unix_ms = 900,
        },
        MediaSessionCandidate{
            .snapshot = track("Newer", MediaPlaybackStatus::stopped),
            .updated_at_unix_ms = 500,
        },
    };

    expect(NowPlaying::selectSession(candidates) == std::optional<std::size_t>{2},
        "selection should ignore empty sessions and fall back to the newest metadata");
}

void controlCapabilitiesRemainExplicit() {
    auto snapshot = track("Track");
    snapshot.controls.can_next = true;

    expect(snapshot.controls.can_next,
        "reported controls should remain available");
    expect(!snapshot.controls.can_previous && !snapshot.controls.can_seek,
        "unreported controls must not be invented");
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"playback clock advances and clamps", playbackClockAdvancesAndClampsToDuration},
        {"paused clock stays fixed", pausedPlaybackClockDoesNotAdvance},
        {"missing position stays unknown", missingPositionRemainsUnknown},
        {"seek time clamps to track", seekTimeIsClampedToTrackBounds},
        {"same track retains metadata", sameTrackRefreshRetainsMissingMetadata},
        {"new track drops old metadata", newTrackDoesNotReusePreviousMetadata},
        {"sessions keep metadata isolated", differentSessionsDoNotMergeMatchingTracks},
        {"duration tolerance identifies track", durationDriftWithinTwoSecondsStillIdentifiesTheTrack},
        {"system current wins selection", systemCurrentSessionHasSelectionPriority},
        {"playing session wins selection", playingSessionWinsWithoutSystemCurrentSession},
        {"newest valid session is fallback", newestValidSessionIsTheFinalFallback},
        {"control capabilities stay explicit", controlCapabilitiesRemainExplicit},
    };

    std::size_t failed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            std::cout << "PASS: " << name << '\n';
        } catch (const std::exception& error) {
            ++failed;
            std::cerr << "FAIL: " << name << " - " << error.what() << '\n';
        }
    }

    if (failed != 0) {
        std::cerr << failed << " test(s) failed\n";
        return 1;
    }
    return 0;
}
