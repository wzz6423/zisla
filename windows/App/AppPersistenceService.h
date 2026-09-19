#pragma once

#include <zisla/core/Alarm.hpp>

#include <windows.h>

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace winrt::Zisla {

struct AppPersistenceServiceSnapshot {
    std::uint64_t alarm_revision{0};
    std::string alarm_error;
};

class AppPersistenceService {
public:
    static constexpr std::size_t maximum_teleprompter_script_bytes =
        4U * 1024U * 1024U;

    explicit AppPersistenceService(std::filesystem::path state_directory);
    ~AppPersistenceService();

    AppPersistenceService(const AppPersistenceService&) = delete;
    AppPersistenceService& operator=(const AppPersistenceService&) = delete;

    [[nodiscard]] std::vector<zisla::core::AlarmItem> loadAlarms();
    [[nodiscard]] bool start(HWND target, UINT changed_message);
    void stop() noexcept;

    [[nodiscard]] std::uint64_t persistAlarms(
        std::vector<zisla::core::AlarmItem> alarms) noexcept;
    void persistTeleprompter(std::string script) noexcept;

    [[nodiscard]] std::shared_ptr<const AppPersistenceServiceSnapshot>
        snapshot() const noexcept;

private:
    enum class CommandKind {
        alarms,
        teleprompter,
    };

    struct Command {
        CommandKind kind{CommandKind::alarms};
        std::uint64_t revision{0};
        std::vector<zisla::core::AlarmItem> alarms;
        std::string script;
    };

    void run() noexcept;
    void execute(Command command) noexcept;
    void publishAlarmResult(std::uint64_t revision, std::string error) noexcept;
    void saveTeleprompter(std::string_view script) const noexcept;
    void notify() noexcept;

    zisla::core::AlarmRepository alarm_repository_;
    std::filesystem::path teleprompter_path_;
    std::atomic<std::shared_ptr<const AppPersistenceServiceSnapshot>> snapshot_;
    std::mutex mutex_;
    std::condition_variable condition_;
    std::deque<Command> commands_;
    std::thread thread_;
    std::uint64_t next_alarm_revision_{0};
    bool running_{false};
    bool alarm_writes_enabled_{false};
    HWND target_{nullptr};
    UINT changed_message_{0};
};

}  // namespace winrt::Zisla
