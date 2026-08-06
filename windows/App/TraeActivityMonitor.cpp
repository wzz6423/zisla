#include "pch.h"
#include "TraeActivityMonitor.h"

#include <zisla/core/TraeSessionScanner.hpp>

#include <shlobj.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <iterator>
#include <memory>
#include <optional>
#include <system_error>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr DWORD retry_interval_ms = 30'000;
constexpr DWORD stale_refresh_interval_ms = 60'000;
constexpr ULONGLONG minimum_refresh_interval_ms = 1'000;
constexpr DWORD notification_buffer_bytes = 16 * 1'024;

std::optional<std::filesystem::path> known_folder(REFKNOWNFOLDERID folder) noexcept {
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(folder, KF_FLAG_DEFAULT, nullptr, &raw))) {
        return std::nullopt;
    }
    try {
        auto result = std::filesystem::path{raw};
        CoTaskMemFree(raw);
        return result;
    } catch (...) {
        CoTaskMemFree(raw);
        return std::nullopt;
    }
}

std::optional<std::filesystem::path> existing_directory(
    const std::vector<std::filesystem::path>& roots) noexcept {
    for (const auto& root : roots) {
        std::error_code error;
        const auto status = std::filesystem::symlink_status(root, error);
        if (!error && std::filesystem::is_directory(status)
            && !std::filesystem::is_symlink(status)) {
            return root;
        }
    }
    return std::nullopt;
}

}

TraeActivityMonitor::TraeActivityMonitor(std::vector<std::filesystem::path> logs_roots)
    : logs_roots_(std::move(logs_roots)),
      snapshot_(std::make_shared<const ActivityList>()) {}

TraeActivityMonitor::~TraeActivityMonitor() {
    stop();
}

bool TraeActivityMonitor::start(HWND target, UINT changed_message) {
    if (thread_.joinable()) {
        return true;
    }
    if (!target || changed_message == 0 || logs_roots_.empty()) {
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

void TraeActivityMonitor::stop() noexcept {
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

bool TraeActivityMonitor::running() const noexcept {
    return running_.load(std::memory_order_acquire);
}

std::shared_ptr<const TraeActivityMonitor::ActivityList>
TraeActivityMonitor::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

std::vector<std::filesystem::path> TraeActivityMonitor::defaultLogsRoots() noexcept {
    try {
        std::vector<std::filesystem::path> roots;
        constexpr const wchar_t* application_names[]{
            L"TRAE SOLO CN",
            L"TRAE",
            L"Trae",
        };
        const auto append = [&roots](const std::filesystem::path& root) {
            if (std::find(roots.begin(), roots.end(), root) == roots.end()) {
                roots.push_back(root);
            }
        };
        for (const auto folder : {FOLDERID_RoamingAppData, FOLDERID_LocalAppData}) {
            const auto base = known_folder(folder);
            if (!base) {
                continue;
            }
            for (const auto* application_name : application_names) {
                append(*base / application_name / L"logs");
            }
        }
        return roots;
    } catch (...) {
        return {};
    }
}

void TraeActivityMonitor::run() noexcept {
    scanAndPublish();
    auto last_refresh_tick = GetTickCount64();

    while (!waitForStop(0)) {
        const auto watch_directory = existing_directory(logs_roots_);
        if (!watch_directory) {
            if (waitForStop(retry_interval_ms)) {
                break;
            }
            continue;
        }
        const auto raw_directory = CreateFileW(
            watch_directory->c_str(),
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

bool TraeActivityMonitor::watchDirectory(
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

void TraeActivityMonitor::scanAndPublish() noexcept {
    try {
        const zisla::core::TraeSessionScanner scanner({
            .logs_roots = logs_roots_,
            .max_log_files = 4,
            .tail_bytes = 512U * 1024U,
        });
        auto next = std::make_shared<const ActivityList>(scanner.active_tasks());
        snapshot_.store(std::move(next), std::memory_order_release);
        (void)PostMessageW(target_, changed_message_, 0, 0);
    } catch (...) {
    }
}

bool TraeActivityMonitor::waitForStop(DWORD timeout_ms) const noexcept {
    if (!stop_event_) {
        return true;
    }
    return WaitForSingleObject(stop_event_, timeout_ms) != WAIT_TIMEOUT;
}

}
