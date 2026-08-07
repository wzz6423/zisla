#include "pch.h"
#include "AppPersistenceService.h"

#include <algorithm>
#include <exception>
#include <fstream>
#include <system_error>
#include <utility>

namespace winrt::Zisla {

AppPersistenceService::AppPersistenceService(
    std::filesystem::path state_directory)
    : alarm_repository_(state_directory),
      teleprompter_path_(std::move(state_directory) / L"teleprompter.txt"),
      snapshot_(std::make_shared<const AppPersistenceServiceSnapshot>()) {}

AppPersistenceService::~AppPersistenceService() {
    stop();
}

std::vector<zisla::core::AlarmItem> AppPersistenceService::loadAlarms() {
    auto alarms = alarm_repository_.load();
    alarm_writes_enabled_ = true;
    return alarms;
}

bool AppPersistenceService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || !target || changed_message == 0) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
    running_ = true;
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_ = false;
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    return true;
}

void AppPersistenceService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
    }
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    commands_.clear();
    target_ = nullptr;
    changed_message_ = 0;
}

std::uint64_t AppPersistenceService::persistAlarms(
    std::vector<zisla::core::AlarmItem> alarms) noexcept {
    try {
        std::lock_guard lock(mutex_);
        if (!running_ || !alarm_writes_enabled_) {
            return 0;
        }
        const auto revision = ++next_alarm_revision_;
        std::erase_if(commands_, [](const Command& command) {
            return command.kind == CommandKind::alarms;
        });
        commands_.push_back({
            .kind = CommandKind::alarms,
            .revision = revision,
            .alarms = std::move(alarms),
        });
        condition_.notify_one();
        return revision;
    } catch (...) {
        return 0;
    }
}

void AppPersistenceService::persistTeleprompter(std::string script) noexcept {
    if (script.size() > maximum_teleprompter_script_bytes) {
        return;
    }
    try {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        std::erase_if(commands_, [](const Command& command) {
            return command.kind == CommandKind::teleprompter;
        });
        commands_.push_back({
            .kind = CommandKind::teleprompter,
            .script = std::move(script),
        });
        condition_.notify_one();
    } catch (...) {
    }
}

std::shared_ptr<const AppPersistenceServiceSnapshot>
AppPersistenceService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void AppPersistenceService::run() noexcept {
    while (true) {
        Command command;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !commands_.empty() || !running_;
            });
            if (commands_.empty() && !running_) {
                break;
            }
            command = std::move(commands_.front());
            commands_.pop_front();
        }

        execute(std::move(command));
    }
}

void AppPersistenceService::execute(Command command) noexcept {
    if (command.kind == CommandKind::teleprompter) {
        saveTeleprompter(command.script);
        return;
    }

    try {
        alarm_repository_.replace(command.alarms);
        publishAlarmResult(command.revision, {});
    } catch (const std::exception& error) {
        publishAlarmResult(command.revision, error.what());
    } catch (...) {
        publishAlarmResult(command.revision, "未知存储错误");
    }
}

void AppPersistenceService::publishAlarmResult(
    std::uint64_t revision,
    std::string error) noexcept {
    try {
        snapshot_.store(
            std::make_shared<const AppPersistenceServiceSnapshot>(
                AppPersistenceServiceSnapshot{
                    .alarm_revision = revision,
                    .alarm_error = std::move(error),
                }),
            std::memory_order_release);
        notify();
    } catch (...) {
    }
}

void AppPersistenceService::saveTeleprompter(
    std::string_view script) const noexcept {
    auto temporary = teleprompter_path_;
    temporary += L".tmp";
    try {
        std::ofstream stream(temporary, std::ios::binary | std::ios::trunc);
        stream.write(script.data(), static_cast<std::streamsize>(script.size()));
        stream.close();
        if (!stream || !MoveFileExW(
                temporary.c_str(),
                teleprompter_path_.c_str(),
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
            std::error_code error;
            (void)std::filesystem::remove(temporary, error);
        }
    } catch (...) {
        std::error_code error;
        (void)std::filesystem::remove(temporary, error);
    }
}

void AppPersistenceService::notify() noexcept {
    HWND target = nullptr;
    UINT message = 0;
    {
        std::lock_guard lock(mutex_);
        target = target_;
        message = changed_message_;
    }
    if (target && message != 0) {
        (void)PostMessageW(target, message, 0, 0);
    }
}

}  // namespace winrt::Zisla
