#include "pch.h"
#include "MediaSessionMonitor.h"

#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iterator>
#include <limits>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace winrt::Zisla {
namespace {

using Session = Windows::Media::Control::GlobalSystemMediaTransportControlsSession;
using SessionManager =
    Windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager;

constexpr DWORD playback_refresh_interval_ms = 1'000;
constexpr std::uint64_t maximum_artwork_bytes = 5 * 1'024 * 1'024;
constexpr std::int64_t ticks_per_second = 10'000'000;

std::int64_t nowUnixMilliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

std::int64_t unixMilliseconds(Windows::Foundation::DateTime value) noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        winrt::clock::to_sys(value).time_since_epoch()).count();
}

std::optional<double> positiveSeconds(Windows::Foundation::TimeSpan value) noexcept {
    const auto seconds = std::chrono::duration<double>(value).count();
    if (!std::isfinite(seconds) || seconds < 0) {
        return std::nullopt;
    }
    return seconds;
}

zisla::core::MediaPlaybackStatus playbackStatus(
    Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus status)
    noexcept {
    using WindowsStatus =
        Windows::Media::Control::GlobalSystemMediaTransportControlsSessionPlaybackStatus;
    switch (status) {
    case WindowsStatus::Playing:
        return zisla::core::MediaPlaybackStatus::playing;
    case WindowsStatus::Paused:
        return zisla::core::MediaPlaybackStatus::paused;
    default:
        return zisla::core::MediaPlaybackStatus::stopped;
    }
}

zisla::core::MediaArtwork readArtwork(
    const Windows::Storage::Streams::IRandomAccessStreamReference& reference) {
    if (!reference) {
        return nullptr;
    }

    const auto stream = reference.OpenReadAsync().get();
    const auto size = stream.Size();
    if (size == 0 || size > maximum_artwork_bytes
        || size > std::numeric_limits<std::uint32_t>::max()) {
        return nullptr;
    }

    const auto byte_count = static_cast<std::uint32_t>(size);
    const auto input = stream.GetInputStreamAt(0);
    const Windows::Storage::Streams::Buffer buffer{byte_count};
    const auto loaded = input.ReadAsync(
        buffer,
        byte_count,
        Windows::Storage::Streams::InputStreamOptions::None).get();
    const auto reader = Windows::Storage::Streams::DataReader::FromBuffer(loaded);
    std::vector<std::uint8_t> bytes(reader.UnconsumedBufferLength());
    reader.ReadBytes(bytes);
    return std::make_shared<const std::vector<std::uint8_t>>(std::move(bytes));
}

}  // namespace

struct MediaSessionMonitor::WorkerState {
    struct Registration {
        Session session{nullptr};
        std::string id;
        event_token media_properties_changed{};
        event_token playback_info_changed{};
        event_token timeline_properties_changed{};
    };

    explicit WorkerState(MediaSessionMonitor& owner) : owner(owner) {}

    ~WorkerState() {
        revokeSessionEvents();
        if (manager) {
            try {
                manager.SessionsChanged(sessions_changed);
            } catch (...) {
            }
            try {
                manager.CurrentSessionChanged(current_session_changed);
            } catch (...) {
            }
        }
    }

    void initialize() {
        manager = SessionManager::RequestAsync().get();
        sessions_changed = manager.SessionsChanged([monitor = &owner](auto&&, auto&&) {
            monitor->sessions_dirty_.store(true, std::memory_order_release);
            monitor->metadata_dirty_.store(true, std::memory_order_release);
            monitor->wake();
        });
        current_session_changed = manager.CurrentSessionChanged(
            [monitor = &owner](auto&&, auto&&) { monitor->wake(); });
        owner.sessions_dirty_.store(false, std::memory_order_release);
        rebuildSessions();
        refresh();
    }

    void rebuildSessions() {
        revokeSessionEvents();
        registrations.clear();

        const auto sessions = manager.GetSessions();
        registrations.reserve(sessions.Size());
        std::unordered_map<std::string, std::size_t> duplicate_counts;
        std::unordered_set<std::string> active_session_ids;
        active_session_ids.reserve(sessions.Size());
        for (const auto& session : sessions) {
            auto id = to_string(session.SourceAppUserModelId());
            if (id.empty()) {
                id = "media-session";
            }
            const auto duplicate = duplicate_counts[id]++;
            if (duplicate != 0) {
                id.append("#");
                id.append(std::to_string(duplicate + 1));
            }

            registrations.push_back({.session = session, .id = std::move(id)});
            auto& registration = registrations.back();
            active_session_ids.insert(registration.id);
            registration.media_properties_changed = session.MediaPropertiesChanged(
                [monitor = &owner](auto&&, auto&&) {
                    monitor->metadata_dirty_.store(true, std::memory_order_release);
                    monitor->wake();
                });
            registration.playback_info_changed = session.PlaybackInfoChanged(
                [monitor = &owner](auto&&, auto&&) { monitor->wake(); });
            registration.timeline_properties_changed = session.TimelinePropertiesChanged(
                [monitor = &owner](auto&&, auto&&) { monitor->wake(); });
        }
        std::erase_if(cache, [&active_session_ids](const auto& entry) {
            return !active_session_ids.contains(entry.first);
        });
        owner.metadata_dirty_.store(true, std::memory_order_release);
    }

    void revokeSessionEvents() noexcept {
        for (auto& registration : registrations) {
            if (registration.media_properties_changed.value != 0) {
                try {
                    registration.session.MediaPropertiesChanged(
                        registration.media_properties_changed);
                } catch (...) {
                }
            }
            if (registration.playback_info_changed.value != 0) {
                try {
                    registration.session.PlaybackInfoChanged(
                        registration.playback_info_changed);
                } catch (...) {
                }
            }
            if (registration.timeline_properties_changed.value != 0) {
                try {
                    registration.session.TimelinePropertiesChanged(
                        registration.timeline_properties_changed);
                } catch (...) {
                }
            }
        }
    }

    void refresh() {
        if (owner.sessions_dirty_.exchange(false, std::memory_order_acq_rel)) {
            rebuildSessions();
        }
        const bool reload_metadata =
            owner.metadata_dirty_.exchange(false, std::memory_order_acq_rel);
        const auto current = manager.GetCurrentSession();

        std::vector<zisla::core::MediaSessionCandidate> candidates;
        candidates.reserve(registrations.size());
        for (const auto& registration : registrations) {
            auto snapshot = cachedSnapshot(registration);
            if (reload_metadata || !snapshot.valid()) {
                snapshot = readMetadata(registration, std::move(snapshot));
            }
            updatePlayback(registration.session, snapshot);
            const auto updated = updateTimeline(registration.session, snapshot);
            cache[registration.id] = snapshot;
            candidates.push_back({
                .snapshot = std::move(snapshot),
                .is_system_current = current
                    && get_abi(current) == get_abi(registration.session),
                .updated_at_unix_ms = updated,
            });
        }

        const auto selected_index = zisla::core::NowPlaying::selectSession(candidates);
        if (!selected_index) {
            selected_session = nullptr;
            selected_start_ticks = 0;
            owner.publish(nullptr);
            return;
        }

        selected_session = registrations[*selected_index].session;
        selected_start_ticks = 0;
        try {
            selected_start_ticks = selected_session.GetTimelineProperties().StartTime().count();
        } catch (...) {
        }
        owner.publish(std::make_shared<const zisla::core::NowPlayingSnapshot>(
            std::move(candidates[*selected_index].snapshot)));
    }

    zisla::core::NowPlayingSnapshot cachedSnapshot(const Registration& registration) const {
        if (const auto found = cache.find(registration.id); found != cache.end()) {
            return found->second;
        }
        return {
            .session_id = registration.id,
            .source_application = registration.id,
        };
    }

    zisla::core::NowPlayingSnapshot readMetadata(
        const Registration& registration,
        zisla::core::NowPlayingSnapshot snapshot) const {
        try {
            const auto properties = registration.session.TryGetMediaPropertiesAsync().get();
            zisla::core::NowPlayingSnapshot update{
                .session_id = registration.id,
                .title = to_string(properties.Title()),
                .artist = to_string(properties.Artist()),
                .album = to_string(properties.AlbumTitle()),
                .source_application = registration.id,
            };
            if (update.artist.empty()) {
                update.artist = update.album;
            }
            update.artwork = readArtwork(properties.Thumbnail());
            (void)updateTimeline(registration.session, update);
            return zisla::core::NowPlaying::mergingMetadata(
                std::move(update),
                snapshot);
        } catch (...) {
            return snapshot;
        }
    }

    static void updatePlayback(
        const Session& session,
        zisla::core::NowPlayingSnapshot& snapshot) {
        try {
            const auto info = session.GetPlaybackInfo();
            snapshot.playback_status = playbackStatus(info.PlaybackStatus());
            const auto controls = info.Controls();
            snapshot.controls = {
                .can_toggle_play_pause = controls.IsPlayPauseToggleEnabled()
                    || controls.IsPlayEnabled() || controls.IsPauseEnabled(),
                .can_previous = controls.IsPreviousEnabled(),
                .can_next = controls.IsNextEnabled(),
                .can_seek = controls.IsPlaybackPositionEnabled(),
            };
        } catch (...) {
            snapshot.playback_status = zisla::core::MediaPlaybackStatus::stopped;
            snapshot.controls = {};
        }
    }

    static std::int64_t updateTimeline(
        const Session& session,
        zisla::core::NowPlayingSnapshot& snapshot) {
        try {
            const auto timeline = session.GetTimelineProperties();
            const auto start = timeline.StartTime();
            const auto end = timeline.EndTime();
            const auto position = timeline.Position();
            snapshot.duration_seconds = positiveSeconds(end - start);
            snapshot.elapsed_seconds = positiveSeconds(position - start);
            snapshot.position_timestamp_unix_ms = unixMilliseconds(
                timeline.LastUpdatedTime());
            return *snapshot.position_timestamp_unix_ms;
        } catch (...) {
            snapshot.duration_seconds.reset();
            snapshot.elapsed_seconds.reset();
            snapshot.position_timestamp_unix_ms.reset();
            return nowUnixMilliseconds();
        }
    }

    void processCommands() {
        for (const auto& command : owner.takeCommands()) {
            const auto published = owner.snapshot();
            if (!selected_session || !published
                || published->session_id != command.session_id) {
                continue;
            }

            try {
                const auto controls = selected_session.GetPlaybackInfo().Controls();
                switch (command.kind) {
                case MediaSessionCommandKind::toggle_play_pause:
                    if (controls.IsPlayPauseToggleEnabled()) {
                        (void)selected_session.TryTogglePlayPauseAsync().get();
                    } else if (published->playback_status
                            == zisla::core::MediaPlaybackStatus::playing
                        && controls.IsPauseEnabled()) {
                        (void)selected_session.TryPauseAsync().get();
                    } else if (controls.IsPlayEnabled()) {
                        (void)selected_session.TryPlayAsync().get();
                    }
                    break;
                case MediaSessionCommandKind::previous:
                    if (controls.IsPreviousEnabled()) {
                        (void)selected_session.TrySkipPreviousAsync().get();
                    }
                    break;
                case MediaSessionCommandKind::next:
                    if (controls.IsNextEnabled()) {
                        (void)selected_session.TrySkipNextAsync().get();
                    }
                    break;
                case MediaSessionCommandKind::seek:
                    if (controls.IsPlaybackPositionEnabled()
                        && published->duration_seconds) {
                        const auto seconds = zisla::core::NowPlaying::clampedSeekTime(
                            command.position_seconds,
                            *published->duration_seconds);
                        const auto ticks = selected_start_ticks + static_cast<std::int64_t>(
                            seconds * static_cast<double>(ticks_per_second));
                        (void)selected_session.TryChangePlaybackPositionAsync(ticks).get();
                    }
                    break;
                }
            } catch (...) {
            }
        }
    }

    [[nodiscard]] DWORD refreshTimeout() const noexcept {
        const auto published = owner.snapshot();
        return published && published->playback_status
                == zisla::core::MediaPlaybackStatus::playing
            ? playback_refresh_interval_ms
            : INFINITE;
    }

    MediaSessionMonitor& owner;
    SessionManager manager{nullptr};
    event_token sessions_changed{};
    event_token current_session_changed{};
    std::vector<Registration> registrations;
    std::unordered_map<std::string, zisla::core::NowPlayingSnapshot> cache;
    Session selected_session{nullptr};
    std::int64_t selected_start_ticks{0};
};

MediaSessionMonitor::MediaSessionMonitor() = default;

MediaSessionMonitor::~MediaSessionMonitor() {
    stop();
}

bool MediaSessionMonitor::start(HWND target, UINT changed_message) {
    if (thread_.joinable()) {
        return true;
    }
    if (!target || changed_message == 0) {
        return false;
    }

    stop_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    wake_event_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!stop_event_ || !wake_event_) {
        if (stop_event_) {
            CloseHandle(stop_event_);
            stop_event_ = nullptr;
        }
        if (wake_event_) {
            CloseHandle(wake_event_);
            wake_event_ = nullptr;
        }
        return false;
    }

    target_ = target;
    changed_message_ = changed_message;
    sessions_dirty_.store(true, std::memory_order_release);
    metadata_dirty_.store(true, std::memory_order_release);
    running_.store(true, std::memory_order_release);
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_.store(false, std::memory_order_release);
        CloseHandle(stop_event_);
        CloseHandle(wake_event_);
        stop_event_ = nullptr;
        wake_event_ = nullptr;
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    return true;
}

void MediaSessionMonitor::stop() noexcept {
    if (stop_event_) {
        (void)SetEvent(stop_event_);
    }
    if (thread_.joinable()) {
        thread_.join();
    }
    if (stop_event_) {
        CloseHandle(stop_event_);
        stop_event_ = nullptr;
    }
    if (wake_event_) {
        CloseHandle(wake_event_);
        wake_event_ = nullptr;
    }
    {
        const std::scoped_lock lock(command_mutex_);
        commands_.clear();
    }
    snapshot_.store({}, std::memory_order_release);
    running_.store(false, std::memory_order_release);
    target_ = nullptr;
    changed_message_ = 0;
}

bool MediaSessionMonitor::running() const noexcept {
    return running_.load(std::memory_order_acquire);
}

std::shared_ptr<const zisla::core::NowPlayingSnapshot>
MediaSessionMonitor::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

bool MediaSessionMonitor::request(MediaSessionCommand command) noexcept {
    if (!running() || command.session_id.empty()) {
        return false;
    }
    try {
        const std::scoped_lock lock(command_mutex_);
        if (command.kind == MediaSessionCommandKind::seek) {
            std::erase_if(commands_, [&](const auto& pending) {
                return pending.kind == MediaSessionCommandKind::seek
                    && pending.session_id == command.session_id;
            });
        }
        commands_.push_back(std::move(command));
        wake();
        return true;
    } catch (...) {
        return false;
    }
}

void MediaSessionMonitor::run() noexcept {
    bool apartment_initialized = false;
    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        apartment_initialized = true;
        {
            WorkerState state(*this);
            state.initialize();
            const HANDLE events[] = {stop_event_, wake_event_};
            while (true) {
                const auto wait_result = WaitForMultipleObjects(
                    static_cast<DWORD>(std::size(events)),
                    events,
                    FALSE,
                    state.refreshTimeout());
                if (wait_result == WAIT_OBJECT_0) {
                    break;
                }
                if (wait_result != WAIT_OBJECT_0 + 1 && wait_result != WAIT_TIMEOUT) {
                    break;
                }
                if (wait_result == WAIT_TIMEOUT) {
                    notifyChanged();
                    continue;
                }
                state.refresh();
                state.processCommands();
            }
        }
    } catch (...) {
        publish(nullptr);
    }
    if (apartment_initialized) {
        winrt::uninit_apartment();
    }
    running_.store(false, std::memory_order_release);
}

void MediaSessionMonitor::wake() noexcept {
    if (wake_event_) {
        (void)SetEvent(wake_event_);
    }
}

void MediaSessionMonitor::notifyChanged() const noexcept {
    if (target_ && changed_message_ != 0) {
        (void)PostMessageW(target_, changed_message_, 0, 0);
    }
}

std::deque<MediaSessionCommand> MediaSessionMonitor::takeCommands() noexcept {
    const std::scoped_lock lock(command_mutex_);
    std::deque<MediaSessionCommand> commands;
    commands.swap(commands_);
    return commands;
}

void MediaSessionMonitor::publish(
    std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot) noexcept {
    snapshot_.store(std::move(snapshot), std::memory_order_release);
    notifyChanged();
}

}
