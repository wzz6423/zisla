#include "pch.h"
#include "WorkBuddyActivityMonitor.h"

#include <zisla/core/WorkBuddySessionScanner.hpp>

#include <shlobj.h>

#include <array>
#include <cstddef>
#include <iterator>
#include <memory>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr DWORD retry_interval_ms = 30'000;
constexpr DWORD stale_refresh_interval_ms = 60'000;
constexpr ULONGLONG minimum_refresh_interval_ms = 1'000;
constexpr DWORD notification_buffer_bytes = 64 * 1'024;

}

WorkBuddyActivityMonitor::WorkBuddyActivityMonitor(std::filesystem::path sessions_file)
    : sessions_file_(std::move(sessions_file)),
      watch_directory_(sessions_file_.parent_path()),
      snapshot_(std::make_shared<const ActivityList>()) {}

WorkBuddyActivityMonitor::~WorkBuddyActivityMonitor() {
    stop();
}

bool WorkBuddyActivityMonitor::start(HWND target, UINT changed_message) {
    if (thread_.joinable()) {
        return true;
    }
    if (!target || changed_message == 0 || sessions_file_.empty()
        || watch_directory_.empty()) {
        return false;
    }

    stop_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!stop_event_) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
    running_.store(true, std::memory_order_release);
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_.store(false, std::memory_order_release);
        CloseHandle(stop_event_);
        stop_event_ = nullptr;
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    return true;
}

void WorkBuddyActivityMonitor::stop() noexcept {
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
    running_.store(false, std::memory_order_release);
    target_ = nullptr;
    changed_message_ = 0;
}

bool WorkBuddyActivityMonitor::running() const noexcept {
    return running_.load(std::memory_order_acquire);
}

std::shared_ptr<const WorkBuddyActivityMonitor::ActivityList>
WorkBuddyActivityMonitor::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

std::optional<std::filesystem::path>
WorkBuddyActivityMonitor::defaultSessionsFile() noexcept {
    PWSTR profile = nullptr;
    if (FAILED(SHGetKnownFolderPath(
            FOLDERID_Profile,
            KF_FLAG_DEFAULT,
            nullptr,
            &profile))) {
        return std::nullopt;
    }

    try {
        auto result = std::filesystem::path{profile} / L".workbuddy" / L"app"
            / L"sessions.json";
        CoTaskMemFree(profile);
        return result;
    } catch (...) {
        CoTaskMemFree(profile);
        return std::nullopt;
    }
}

void WorkBuddyActivityMonitor::run() noexcept {
    scanAndPublish();
    auto last_refresh_tick = GetTickCount64();

    while (!waitForStop(0)) {
        const auto raw_directory = CreateFileW(
            watch_directory_.c_str(),
            FILE_LIST_DIRECTORY,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
            nullptr);
        if (raw_directory == INVALID_HANDLE_VALUE) {
            if (waitForStop(retry_interval_ms)) {
                break;
            }
            continue;
        }

        winrt::handle directory;
        directory.attach(raw_directory);
        scanAndPublish();
        last_refresh_tick = GetTickCount64();
        if (watchDirectory(directory.get(), last_refresh_tick)) {
            break;
        }
        if (waitForStop(1'000)) {
            break;
        }
    }

    running_.store(false, std::memory_order_release);
}

bool WorkBuddyActivityMonitor::watchDirectory(
    HANDLE directory,
    ULONGLONG& last_refresh_tick) noexcept {
    winrt::handle changed_event;
    changed_event.attach(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    if (!changed_event) {
        return waitForStop(0);
    }

    alignas(DWORD) std::array<std::byte, notification_buffer_bytes> buffer{};
    const HANDLE events[] = {stop_event_, changed_event.get()};

    while (!waitForStop(0)) {
        (void)ResetEvent(changed_event.get());
        OVERLAPPED overlapped{};
        overlapped.hEvent = changed_event.get();
        if (!ReadDirectoryChangesW(
                directory,
                buffer.data(),
                static_cast<DWORD>(buffer.size()),
                FALSE,
                FILE_NOTIFY_CHANGE_FILE_NAME
                    | FILE_NOTIFY_CHANGE_SIZE
                    | FILE_NOTIFY_CHANGE_LAST_WRITE
                    | FILE_NOTIFY_CHANGE_CREATION,
                nullptr,
                &overlapped,
                nullptr)) {
            return false;
        }

        const auto wait_result = WaitForMultipleObjects(
            static_cast<DWORD>(std::size(events)),
            events,
            FALSE,
            stale_refresh_interval_ms);
        if (wait_result == WAIT_OBJECT_0) {
            (void)CancelIoEx(directory, &overlapped);
            DWORD ignored = 0;
            (void)GetOverlappedResult(directory, &overlapped, &ignored, TRUE);
            return true;
        }
        if (wait_result == WAIT_TIMEOUT) {
            (void)CancelIoEx(directory, &overlapped);
            DWORD ignored = 0;
            (void)GetOverlappedResult(directory, &overlapped, &ignored, TRUE);
            scanAndPublish();
            last_refresh_tick = GetTickCount64();
            continue;
        }
        if (wait_result != WAIT_OBJECT_0 + 1) {
            (void)CancelIoEx(directory, &overlapped);
            DWORD ignored = 0;
            (void)GetOverlappedResult(directory, &overlapped, &ignored, TRUE);
            return waitForStop(0);
        }

        DWORD bytes_returned = 0;
        if (!GetOverlappedResult(
                directory,
                &overlapped,
                &bytes_returned,
                FALSE)) {
            scanAndPublish();
            return waitForStop(0);
        }
        (void)bytes_returned;

        const auto now = GetTickCount64();
        const auto elapsed = now - last_refresh_tick;
        if (elapsed < minimum_refresh_interval_ms) {
            const auto remaining = static_cast<DWORD>(
                minimum_refresh_interval_ms - elapsed);
            if (waitForStop(remaining)) {
                return true;
            }
        }
        scanAndPublish();
        last_refresh_tick = GetTickCount64();
    }
    return true;
}

void WorkBuddyActivityMonitor::scanAndPublish() noexcept {
    try {
        const zisla::core::WorkBuddySessionScanner scanner({
            .sessions_file = sessions_file_,
            .max_sessions = 8,
            .maximum_file_bytes = 1U * 1024U * 1024U,
            .recency_threshold_ms = 30 * 60 * 1'000,
        });
        auto next = std::make_shared<const ActivityList>(scanner.active_tasks());
        snapshot_.store(std::move(next), std::memory_order_release);
        (void)PostMessageW(target_, changed_message_, 0, 0);
    } catch (...) {
    }
}

bool WorkBuddyActivityMonitor::waitForStop(DWORD timeout_ms) const noexcept {
    if (!stop_event_) {
        return true;
    }
    return WaitForSingleObject(stop_event_, timeout_ms) != WAIT_TIMEOUT;
}

}
