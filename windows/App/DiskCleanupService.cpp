#include "pch.h"
#include "DiskCleanupService.h"

#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl_core.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <limits>
#include <optional>
#include <string_view>
#include <utility>

namespace winrt::Zisla {
namespace {

using FileClock = std::filesystem::file_time_type::clock;

struct CleanupRoot {
    std::filesystem::path path;
    zisla::core::DiskCleanupKind kind;
    std::chrono::hours minimum_age;
};

std::optional<std::filesystem::path> known_folder(
    REFKNOWNFOLDERID identifier) {
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(
            identifier,
            KF_FLAG_DEFAULT,
            nullptr,
            &raw))) {
        return std::nullopt;
    }
    std::filesystem::path result{raw};
    CoTaskMemFree(raw);
    return result;
}

std::optional<std::filesystem::path> local_app_data() {
    return known_folder(FOLDERID_LocalAppData);
}

std::optional<std::filesystem::path> temporary_directory() {
    std::wstring buffer(MAX_PATH, L'\0');
    for (;;) {
        const auto length = GetTempPathW(
            static_cast<DWORD>(buffer.size()),
            buffer.data());
        if (length == 0) {
            return std::nullopt;
        }
        if (length < buffer.size() - 1) {
            buffer.resize(length);
            return std::filesystem::path{buffer};
        }
        buffer.resize(buffer.size() * 2, L'\0');
    }
}

std::vector<CleanupRoot> cleanup_roots() {
    std::vector<CleanupRoot> roots;
    if (const auto path = temporary_directory()) {
        roots.push_back({
            *path,
            zisla::core::DiskCleanupKind::temporary_file,
            std::chrono::hours{24 * 7},
        });
    }

    if (const auto path = local_app_data()) {
        roots.push_back({
            *path / L"CrashDumps",
            zisla::core::DiskCleanupKind::crash_report,
            std::chrono::hours{24 * 30},
        });
        roots.push_back({
            *path / L"Microsoft" / L"Windows" / L"WER" / L"ReportArchive",
            zisla::core::DiskCleanupKind::crash_report,
            std::chrono::hours{24 * 30},
        });
        const auto application_root = *path / L"zisla";
        roots.push_back({
            application_root / L"cache",
            zisla::core::DiskCleanupKind::application_cache,
            std::chrono::hours{24 * 7},
        });
        roots.push_back({
            application_root / L"logs",
            zisla::core::DiskCleanupKind::log,
            std::chrono::hours{24 * 14},
        });
    }
    return roots;
}

std::uint64_t add_saturated(std::uint64_t left, std::uint64_t right) noexcept {
    if (right > std::numeric_limits<std::uint64_t>::max() - left) {
        return std::numeric_limits<std::uint64_t>::max();
    }
    return left + right;
}

bool is_reparse_point(const std::filesystem::path& path) noexcept {
    const auto attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES
        && (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
}

std::uint64_t directory_size(const std::filesystem::path& path) noexcept {
    std::error_code error;
    const auto status = std::filesystem::symlink_status(path, error);
    if (error || std::filesystem::is_symlink(status) || is_reparse_point(path)) {
        return 0;
    }
    if (std::filesystem::is_regular_file(status)) {
        const auto size = std::filesystem::file_size(path, error);
        return error ? 0 : size;
    }
    if (!std::filesystem::is_directory(status)) {
        return 0;
    }

    std::uint64_t total = 0;
    std::size_t entries = 0;
    std::filesystem::recursive_directory_iterator iterator(
        path,
        std::filesystem::directory_options::skip_permission_denied,
        error);
    const std::filesystem::recursive_directory_iterator end;
    while (!error && iterator != end && entries++ < 100'000) {
        const auto current = iterator->path();
        const auto current_status = std::filesystem::symlink_status(current, error);
        if (error) {
            error.clear();
            iterator.increment(error);
            continue;
        }
        if (std::filesystem::is_symlink(current_status)
            || is_reparse_point(current)) {
            iterator.disable_recursion_pending();
        } else if (std::filesystem::is_regular_file(current_status)) {
            const auto size = std::filesystem::file_size(current, error);
            if (!error) {
                total = add_saturated(total, size);
            } else {
                error.clear();
            }
        }
        iterator.increment(error);
    }
    return total;
}

std::vector<zisla::core::DiskCleanupCandidate> scan_candidates() {
    std::vector<zisla::core::DiskCleanupCandidate> candidates;
    const auto now = FileClock::now();
    for (const auto& root : cleanup_roots()) {
        std::error_code error;
        const auto root_status = std::filesystem::symlink_status(root.path, error);
        if (error || !std::filesystem::is_directory(root_status)
            || std::filesystem::is_symlink(root_status)) {
            continue;
        }

        std::filesystem::directory_iterator iterator(
            root.path,
            std::filesystem::directory_options::skip_permission_denied,
            error);
        const std::filesystem::directory_iterator end;
        while (!error && iterator != end && candidates.size() < 512) {
            const auto path = iterator->path();
            const auto status = std::filesystem::symlink_status(path, error);
            if (error) {
                error.clear();
                iterator.increment(error);
                continue;
            }
            if (!std::filesystem::is_symlink(status)
                && !is_reparse_point(path)) {
                const auto modified = std::filesystem::last_write_time(path, error);
                if (!error && now - modified >= root.minimum_age) {
                    candidates.push_back({
                        .path = path,
                        .kind = root.kind,
                        .size_bytes = directory_size(path),
                    });
                }
                error.clear();
            }
            iterator.increment(error);
        }
    }

    return zisla::core::DiskCleanupPlanner::deduplicate(candidates);
}

std::string recycle_path(const std::filesystem::path& path) {
    com_ptr<IFileOperation> operation;
    auto result = CoCreateInstance(
        CLSID_FileOperation,
        nullptr,
        CLSCTX_INPROC_SERVER,
        __uuidof(IFileOperation),
        operation.put_void());
    if (FAILED(result)) {
        return "无法创建回收站操作（错误 "
            + std::to_string(static_cast<std::uint32_t>(result)) + ")";
    }

    result = operation->SetOperationFlags(
        FOF_ALLOWUNDO
        | FOF_NOCONFIRMATION
        | FOF_NOERRORUI
        | FOF_SILENT
        | FOFX_EARLYFAILURE
        | FOFX_RECYCLEONDELETE);
    if (FAILED(result)) {
        return "无法配置回收站操作（错误 "
            + std::to_string(static_cast<std::uint32_t>(result)) + ")";
    }

    com_ptr<IShellItem> item;
    result = SHCreateItemFromParsingName(
        path.c_str(),
        nullptr,
        __uuidof(IShellItem),
        item.put_void());
    if (FAILED(result)) {
        return "无法读取清理项目（错误 "
            + std::to_string(static_cast<std::uint32_t>(result)) + ")";
    }
    result = operation->DeleteItem(item.get(), nullptr);
    if (SUCCEEDED(result)) {
        result = operation->PerformOperations();
    }
    BOOL aborted = FALSE;
    if (SUCCEEDED(result)) {
        result = operation->GetAnyOperationsAborted(&aborted);
    }
    if (FAILED(result) || aborted) {
        return "无法将项目移入回收站（错误 "
            + std::to_string(static_cast<std::uint32_t>(result)) + ")";
    }
    return {};
}

std::vector<std::filesystem::path> root_paths(
    const std::vector<CleanupRoot>& roots) {
    std::vector<std::filesystem::path> result;
    result.reserve(roots.size());
    for (const auto& root : roots) {
        result.push_back(root.path);
    }
    return result;
}

}  // namespace

DiskCleanupService::DiskCleanupService()
    : snapshot_(std::make_shared<const DiskCleanupServiceSnapshot>()) {}

DiskCleanupService::~DiskCleanupService() {
    stop();
}

bool DiskCleanupService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || thread_.joinable() || !target || changed_message == 0) {
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

void DiskCleanupService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
        commands_.clear();
    }
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    target_ = nullptr;
    changed_message_ = 0;
}

void DiskCleanupService::scan() {
    enqueue(Command{.kind = CommandKind::scan});
}

void DiskCleanupService::clean(std::vector<std::filesystem::path> paths) {
    enqueue(Command{
        .kind = CommandKind::clean,
        .paths = std::move(paths),
    });
}

std::shared_ptr<const DiskCleanupServiceSnapshot>
DiskCleanupService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void DiskCleanupService::enqueue(Command command) {
    {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        commands_.push_back(std::move(command));
    }
    condition_.notify_one();
}

void DiskCleanupService::run() noexcept {
    const auto apartment = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(apartment)) {
        state_.error = "无法初始化磁盘清理线程";
        state_.status.clear();
        ++state_.revision;
        publish();
        std::lock_guard lock(mutex_);
        running_ = false;
        commands_.clear();
        return;
    }

    while (true) {
        Command command;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !running_ || !commands_.empty();
            });
            if (!running_) {
                break;
            }
            command = std::move(commands_.front());
            commands_.pop_front();
        }
        try {
            execute(std::move(command));
        } catch (const std::exception& error) {
            state_.scanning = false;
            state_.cleaning = false;
            state_.error = error.what();
            state_.status.clear();
            ++state_.revision;
            publish();
        } catch (...) {
            state_.scanning = false;
            state_.cleaning = false;
            state_.error = "磁盘清理发生未知错误";
            state_.status.clear();
            ++state_.revision;
            publish();
        }
    }

    if (apartment == S_OK || apartment == S_FALSE) {
        CoUninitialize();
    }
}

void DiskCleanupService::execute(Command command) {
    if (command.kind == CommandKind::scan) {
        state_.scanning = true;
        state_.cleaning = false;
        state_.error.clear();
        state_.status = "正在扫描可安全清理的项目";
        ++state_.revision;
        publish();

        state_.candidates = scan_candidates();
        state_.scanning = false;
        state_.status = state_.candidates.empty()
            ? "没有发现超过保留期限的项目"
            : "扫描完成，可选择移入回收站";
        ++state_.revision;
        publish();
        return;
    }

    state_.cleaning = true;
    state_.scanning = false;
    state_.error.clear();
    state_.status = "正在移入回收站";
    ++state_.revision;
    publish();

    const auto roots = root_paths(cleanup_roots());
    std::vector<zisla::core::DiskCleanupCandidate> remaining;
    remaining.reserve(state_.candidates.size());
    std::uint64_t freed = 0;
    std::size_t success_count = 0;
    std::string first_error;
    for (const auto& candidate : state_.candidates) {
        const bool selected = std::any_of(
            command.paths.begin(),
            command.paths.end(),
            [&candidate](const auto& path) {
                return path.lexically_normal() == candidate.path.lexically_normal();
            });
        if (!selected) {
            remaining.push_back(candidate);
            continue;
        }
        if (!zisla::core::DiskCleanupPlanner::isAllowedCandidate(candidate, roots)) {
            remaining.push_back(candidate);
            if (first_error.empty()) {
                first_error = "清理路径不在允许的用户目录内";
            }
            continue;
        }
        if (is_reparse_point(candidate.path)) {
            remaining.push_back(candidate);
            if (first_error.empty()) {
                first_error = "为安全起见，未处理符号链接或目录联接";
            }
            continue;
        }
        const auto error = recycle_path(candidate.path);
        if (!error.empty()) {
            remaining.push_back(candidate);
            if (first_error.empty()) {
                first_error = error;
            }
            continue;
        }
        ++success_count;
        freed = add_saturated(freed, candidate.size_bytes);
    }

    state_.candidates = std::move(remaining);
    state_.cleaning = false;
    state_.freed_bytes = add_saturated(state_.freed_bytes, freed);
    if (!first_error.empty()) {
        state_.error = std::move(first_error);
        state_.status = "部分项目未能移入回收站";
    } else {
        state_.status = "已移入回收站 " + std::to_string(success_count) + " 项";
    }
    ++state_.revision;
    publish();
}

void DiskCleanupService::publish() noexcept {
    try {
        snapshot_.store(
            std::make_shared<const DiskCleanupServiceSnapshot>(state_),
            std::memory_order_release);
        notify();
    } catch (...) {
    }
}

void DiskCleanupService::notify() const noexcept {
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

}
