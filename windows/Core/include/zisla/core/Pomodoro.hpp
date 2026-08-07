#pragma once

#include <cstdint>
#include <optional>
#include <string>

namespace zisla::core {

enum class PomodoroMode {
    focus,
    rest,
};

enum class PomodoroPhase {
    idle,
    running,
    paused,
};

struct PomodoroSnapshot {
    PomodoroMode mode{PomodoroMode::focus};
    PomodoroPhase phase{PomodoroPhase::idle};
    std::int64_t remaining_seconds{25 * 60};
    std::int64_t focus_duration_seconds{25 * 60};
    std::int64_t rest_duration_seconds{5 * 60};

    [[nodiscard]] bool active() const noexcept;

    friend bool operator==(const PomodoroSnapshot&, const PomodoroSnapshot&) = default;
};

class PomodoroEngine {
public:
    static constexpr std::int64_t default_focus_duration_seconds = 25 * 60;
    static constexpr std::int64_t default_rest_duration_seconds = 5 * 60;

    explicit PomodoroEngine(
        std::int64_t focus_duration_seconds = default_focus_duration_seconds,
        std::int64_t rest_duration_seconds = default_rest_duration_seconds) noexcept;

    [[nodiscard]] PomodoroMode mode() const noexcept;
    [[nodiscard]] PomodoroPhase phase() const noexcept;
    [[nodiscard]] std::int64_t duration_seconds(PomodoroMode mode) const noexcept;
    [[nodiscard]] std::int64_t remaining_milliseconds(
        std::int64_t now_unix_ms) const noexcept;
    [[nodiscard]] PomodoroSnapshot snapshot(std::int64_t now_unix_ms) const noexcept;

    void set_duration_seconds(PomodoroMode mode, std::int64_t seconds) noexcept;
    void start(std::int64_t now_unix_ms) noexcept;
    void pause(std::int64_t now_unix_ms) noexcept;
    void reset() noexcept;
    [[nodiscard]] bool complete_if_needed(std::int64_t now_unix_ms) noexcept;
    void start_with_remaining_seconds(
        std::int64_t seconds,
        std::int64_t now_unix_ms) noexcept;

    [[nodiscard]] static std::string format_clock(
        std::int64_t remaining_seconds,
        bool always_include_hours = false);

private:
    [[nodiscard]] static std::int64_t normalized_duration_seconds(
        std::int64_t seconds) noexcept;
    [[nodiscard]] static std::int64_t duration_milliseconds(
        std::int64_t seconds) noexcept;
    [[nodiscard]] static std::int64_t deadline_after(
        std::int64_t now_unix_ms,
        std::int64_t duration_ms) noexcept;
    [[nodiscard]] static PomodoroMode next_mode(PomodoroMode mode) noexcept;

    PomodoroMode mode_{PomodoroMode::focus};
    PomodoroPhase phase_{PomodoroPhase::idle};
    std::optional<std::int64_t> deadline_unix_ms_;
    std::int64_t focus_duration_seconds_{default_focus_duration_seconds};
    std::int64_t rest_duration_seconds_{default_rest_duration_seconds};
    std::int64_t remaining_when_paused_ms_{default_focus_duration_seconds * 1'000};
};

}  // namespace zisla::core
