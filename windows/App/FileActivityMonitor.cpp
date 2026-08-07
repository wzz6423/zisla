#include "pch.h"
#include "FileActivityMonitor.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <iterator>
#include <memory>
#include <system_error>
#include <utility>
#include <vector>

namespace winrt::Zisla {
namespace {

constexpr DWORD retry_interval_ms = 30'000;
constexpr DWORD stale_refresh_interval_ms = 60'000;
constexpr ULONGLONG minimum_refresh_interval_ms = 1'000;
constexpr DWORD notification_buffer_bytes = 16 * 1'024;
constexpr std::size_t maximum_watched_directories =
    static_cast<std::size_t>(MAXIMUM_WAIT_OBJECTS - 1);

struct DirectoryWatch {
    winrt::handle directory;
    winrt::handle changed_event;
    OVERLAPPED overlapped{};
    alignas(DWORD) std::array<std::byte, notification_buffer_bytes> buffer{};
};

std::vector<std::filesystem::path> existing_watch_directories(
    const std::vector<std::filesystem::path>& roots) {
    std::vector<std::filesystem::path> directories;
    directories.reserve(roots.size());
    for (const auto& root : roots) {
        if (root.empty()) {
            continue;
        }
        std::error_code error;
        const auto status = std::filesystem::symlink_status(root, error);
        if (error || std::filesystem::is_symlink(status)) {
            continue;
        }
        auto directory = std::filesystem::is_regular_file(status)
            ? root.parent_path()
            : root;
        std::error_code directory_error;
        const auto directory_status = std::filesystem::symlink_status(
            directory,
            directory_error);
        if (directory_error || !std::filesystem::is_directory(directory_status)
            || std::filesystem::is_symlink(directory_status)) {
            continue;
        }
        directory = directory.lexically_normal();
        if (std::find(directories.begin(), directories.end(), directory)
            == directories.end()) {
            directories.push_back(std::move(directory));
        }
    }
    return directories;
}

std::unique_ptr<DirectoryWatch> create_directory_watch(
    const std::filesystem::path& path) {
    auto watch = std::make_unique<DirectoryWatch>();
    const auto raw_directory = CreateFileW(
        path.c_str(),
        FILE_LIST_DIRECTORY,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr,
        OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
        nullptr);
    if (raw_directory == INVALID_HANDLE_VALUE) {
        return nullptr;
    }

    watch->directory.attach(raw_directory);
    watch->changed_event.attach(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    if (!watch->changed_event) {
        return nullptr;
    }
    watch->overlapped.hEvent = watch->changed_event.get();
    if (!ReadDirectoryChangesW(
            watch->directory.get(),
            watch->buffer.data(),
            static_cast<DWORD>(watch->buffer.size()),
            TRUE,
            FILE_NOTIFY_CHANGE_FILE_NAME
                | FILE_NOTIFY_CHANGE_DIR_NAME
                | FILE_NOTIFY_CHANGE_SIZE
                | FILE_NOTIFY_CHANGE_LAST_WRITE
                | FILE_NOTIFY_CHANGE_CREATION,
            nullptr,
            &watch->overlapped,
            nullptr)) {
        return nullptr;
    }
    return watch;
}

void cancel_directory_watches(
    const std::vector<std::unique_ptr<DirectoryWatch>>& watches) noexcept {
    for (const auto& watch : watches) {
        if (watch->directory) {
            (void)CancelIoEx(watch->directory.get(), &watch->overlapped);
        }
    }
    for (const auto& watch : watches) {
        if (watch->directory) {
            DWORD ignored = 0;
            (void)GetOverlappedResult(
                watch->directory.get(),
                &watch->overlapped,
                &ignored,
                TRUE);
        }
    }
}

}

FileActivityMonitor::FileActivityMonitor(
    std::vector<std::filesystem::path> watch_roots,
    Scanner scanner)
    : watch_roots_(std::move(watch_roots)),
      scanner_(std::move(scanner)),
      snapshot_(std::make_shared<const ActivityList>()) {}

FileActivityMonitor::~FileActivityMonitor() {
    stop();
}

bool FileActivityMonitor::start(HWND target, UINT changed_message) {
    if (thread_.joinable()) {
        return true;
    }
    if (!target || changed_message == 0 || watch_roots_.empty() || !scanner_) {
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

void FileActivityMonitor::stop() noexcept {
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

bool FileActivityMonitor::running() const noexcept {
    return running_.load(std::memory_order_acquire);
}

std::shared_ptr<const FileActivityMonitor::ActivityList>
FileActivityMonitor::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void FileActivityMonitor::run() noexcept {
    try {
        scanAndPublish();
        auto last_refresh_tick = GetTickCount64();

        while (!waitForStop(0)) {
            if (watchDirectories(last_refresh_tick)) {
                break;
            }
        }
    } catch (...) {
    }

    running_.store(false, std::memory_order_release);
}

bool FileActivityMonitor::watchDirectories(
    ULONGLONG& last_refresh_tick) {
    const auto directories = existing_watch_directories(watch_roots_);
    if (directories.empty()) {
        return waitForStop(retry_interval_ms);
    }

    std::vector<std::unique_ptr<DirectoryWatch>> watches;
    watches.reserve(std::min<std::size_t>(
        directories.size(),
        maximum_watched_directories));
    for (const auto& directory : directories) {
        if (watches.size() == maximum_watched_directories) {
            break;
        }
        if (auto watch = create_directory_watch(directory)) {
            watches.push_back(std::move(watch));
        }
    }
    if (watches.empty()) {
        return waitForStop(retry_interval_ms);
    }

    std::vector<HANDLE> events;
    events.reserve(watches.size() + 1);
    events.push_back(stop_event_);
    for (const auto& watch : watches) {
        events.push_back(watch->changed_event.get());
    }

    const auto wait_result = WaitForMultipleObjects(
        static_cast<DWORD>(events.size()),
        events.data(),
        FALSE,
        stale_refresh_interval_ms);
    cancel_directory_watches(watches);
    if (wait_result == WAIT_OBJECT_0) {
        return true;
    }

    if (wait_result != WAIT_TIMEOUT
        && (wait_result < WAIT_OBJECT_0 + 1
            || wait_result >= WAIT_OBJECT_0
                + static_cast<DWORD>(events.size()))) {
        return waitForStop(1'000);
    }

    const auto now = GetTickCount64();
    const auto elapsed = now - last_refresh_tick;
    if (wait_result != WAIT_TIMEOUT && elapsed < minimum_refresh_interval_ms) {
        const auto remaining = static_cast<DWORD>(
            minimum_refresh_interval_ms - elapsed);
        if (waitForStop(remaining)) {
            return true;
        }
    }
    scanAndPublish();
    last_refresh_tick = GetTickCount64();
    return false;
}

void FileActivityMonitor::scanAndPublish() noexcept {
    try {
        auto next = std::make_shared<const ActivityList>(scanner_());
        snapshot_.store(std::move(next), std::memory_order_release);
        (void)PostMessageW(target_, changed_message_, 0, 0);
    } catch (...) {
    }
}

bool FileActivityMonitor::waitForStop(DWORD timeout_ms) const noexcept {
    if (!stop_event_) {
        return true;
    }
    return WaitForSingleObject(stop_event_, timeout_ms) != WAIT_TIMEOUT;
}

}
