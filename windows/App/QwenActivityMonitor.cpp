#include "pch.h"
#include "QwenActivityMonitor.h"

#include <zisla/core/QwenSessionScanner.hpp>

#include <shlobj.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <memory>
#include <string>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr DWORD retry_interval_ms = 30'000;
constexpr ULONGLONG minimum_refresh_interval_ms = 1'000;
constexpr DWORD notification_buffer_bytes = 64 * 1'024;

std::optional<std::filesystem::path> environment_path(const wchar_t* name) noexcept {
    const auto required = GetEnvironmentVariableW(name, nullptr, 0);
    if (required == 0) {
        return std::nullopt;
    }

    try {
        std::wstring value(required, L'\0');
        const auto length = GetEnvironmentVariableW(
            name,
            value.data(),
            static_cast<DWORD>(value.size()));
        if (length == 0 || length >= value.size()) {
            return std::nullopt;
        }
        value.resize(length);
        const auto first = value.find_first_not_of(L" \t\r\n\f\v");
        if (first == std::wstring::npos) {
            return std::nullopt;
        }
        const auto last = value.find_last_not_of(L" \t\r\n\f\v");
        return std::filesystem::path{value.substr(first, last - first + 1)};
    } catch (...) {
        return std::nullopt;
    }
}

bool process_is_alive(std::uint32_t pid) noexcept {
    if (pid == 0) {
        return false;
    }
    const auto raw_process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!raw_process) {
        return GetLastError() == ERROR_ACCESS_DENIED;
    }

    winrt::handle process;
    process.attach(raw_process);
    DWORD exit_code = 0;
    return GetExitCodeProcess(process.get(), &exit_code) && exit_code == STILL_ACTIVE;
}

}

QwenActivityMonitor::QwenActivityMonitor(std::filesystem::path projects_directory)
    : projects_directory_(std::move(projects_directory)),
      snapshot_(std::make_shared<const ActivityList>()) {}

QwenActivityMonitor::~QwenActivityMonitor() {
    stop();
}

bool QwenActivityMonitor::start(HWND target, UINT changed_message) {
    if (thread_.joinable()) {
        return true;
    }
    if (!target || changed_message == 0 || projects_directory_.empty()) {
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

void QwenActivityMonitor::stop() noexcept {
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

bool QwenActivityMonitor::running() const noexcept {
    return running_.load(std::memory_order_acquire);
}

std::shared_ptr<const QwenActivityMonitor::ActivityList>
QwenActivityMonitor::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

std::optional<std::filesystem::path>
QwenActivityMonitor::defaultProjectsDirectory() noexcept {
    for (const auto* name : {L"QWEN_RUNTIME_DIR", L"QWEN_HOME"}) {
        if (const auto root = environment_path(name)) {
            return *root / L"projects";
        }
    }

    PWSTR profile = nullptr;
    if (FAILED(SHGetKnownFolderPath(
            FOLDERID_Profile,
            KF_FLAG_DEFAULT,
            nullptr,
            &profile))) {
        return std::nullopt;
    }

    try {
        auto result = std::filesystem::path{profile} / L".qwen" / L"projects";
        CoTaskMemFree(profile);
        return result;
    } catch (...) {
        CoTaskMemFree(profile);
        return std::nullopt;
    }
}

void QwenActivityMonitor::run() noexcept {
    scanAndPublish();
    auto last_refresh_tick = GetTickCount64();

    while (!waitForStop(0)) {
        const auto raw_directory = CreateFileW(
            projects_directory_.c_str(),
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

bool QwenActivityMonitor::watchDirectory(
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
                TRUE,
                FILE_NOTIFY_CHANGE_FILE_NAME
                    | FILE_NOTIFY_CHANGE_DIR_NAME
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
            INFINITE);
        if (wait_result == WAIT_OBJECT_0) {
            (void)CancelIoEx(directory, &overlapped);
            DWORD ignored = 0;
            (void)GetOverlappedResult(directory, &overlapped, &ignored, TRUE);
            return true;
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

void QwenActivityMonitor::scanAndPublish() noexcept {
    try {
        const zisla::core::QwenSessionScanner scanner({
            .projects_directory = projects_directory_,
            .max_runtime_files = 12,
            .initial_tail_bytes = 1'024 * 1'024,
            .maximum_runtime_bytes = 1'024 * 1'024,
            .is_process_alive = &process_is_alive,
        });
        auto next = std::make_shared<const ActivityList>(scanner.active_tasks());
        snapshot_.store(std::move(next), std::memory_order_release);
        (void)PostMessageW(target_, changed_message_, 0, 0);
    } catch (...) {
    }
}

bool QwenActivityMonitor::waitForStop(DWORD timeout_ms) const noexcept {
    if (!stop_event_) {
        return true;
    }
    return WaitForSingleObject(stop_event_, timeout_ms) != WAIT_TIMEOUT;
}

}
