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

using AlarmWeekdayMask = std::uint8_t;

[[nodiscard]] constexpr AlarmWeekdayMask alarm_weekday_bit(
    std::uint8_t weekday) noexcept {
    return weekday >= 1 && weekday <= 7
        ? static_cast<AlarmWeekdayMask>(1U << (weekday - 1U))
        : AlarmWeekdayMask{0};
}

struct AlarmItem {
    std::string id;
    int hour{8};
    int minute{0};
    std::string label;
    AlarmWeekdayMask weekday_mask{0};
    bool enabled{true};
    std::int64_t one_shot_fire_unix_ms{0};

    [[nodiscard]] bool repeating() const noexcept;

    friend bool operator==(const AlarmItem&, const AlarmItem&) = default;
};

struct AlarmLocalClock {
    std::uint8_t weekday{1};
    int hour{0};
    int minute{0};
    int second{0};
    std::int64_t now_unix_ms{0};
};

struct AlarmOccurrence {
    int day_offset{0};
    int hour{0};
    int minute{0};

    friend bool operator==(const AlarmOccurrence&, const AlarmOccurrence&) = default;
};

struct NextAlarm {
    AlarmItem alarm;
    std::int64_t fire_unix_ms{0};

    friend bool operator==(const NextAlarm&, const NextAlarm&) = default;
};

class AlarmBook {
public:
    static constexpr std::size_t maximum_alarms = 64;

    explicit AlarmBook(std::vector<AlarmItem> alarms = {});

    [[nodiscard]] const std::vector<AlarmItem>& alarms() const noexcept;
    [[nodiscard]] std::optional<AlarmItem> find(std::string_view id) const;
    [[nodiscard]] bool add(AlarmItem alarm);
    [[nodiscard]] bool update(AlarmItem alarm);
    [[nodiscard]] bool remove(std::string_view id);
    [[nodiscard]] bool reconcile(
        std::int64_t now_unix_ms,
        std::int64_t delivery_grace_ms = 0) noexcept;
    [[nodiscard]] std::optional<NextAlarm> next_alarm(
        AlarmLocalClock now) const noexcept;

    [[nodiscard]] static AlarmItem normalized(AlarmItem alarm);
    [[nodiscard]] static std::string format_time(const AlarmItem& alarm);
    [[nodiscard]] static std::string format_repeat(AlarmWeekdayMask mask);
    [[nodiscard]] static std::int64_t delivery_deadline(
        std::int64_t fire_unix_ms,
        std::int64_t delivery_grace_ms) noexcept;
    [[nodiscard]] static std::vector<AlarmOccurrence>
    upcoming_repeating_occurrences(
        const AlarmItem& alarm,
        AlarmLocalClock now,
        std::size_t count);

private:
    void sort() noexcept;

    std::vector<AlarmItem> alarms_;
};

class AlarmRepositoryError : public std::runtime_error {
public:
    explicit AlarmRepositoryError(std::string message);
};

class AlarmRepository {
public:
    explicit AlarmRepository(std::filesystem::path directory);

    [[nodiscard]] const std::filesystem::path& directory() const noexcept;
    [[nodiscard]] std::filesystem::path database_path() const;
    [[nodiscard]] std::vector<AlarmItem> load() const;
    void replace(std::span<const AlarmItem> alarms) const;

private:
    std::filesystem::path directory_;
};

}  // namespace zisla::core
