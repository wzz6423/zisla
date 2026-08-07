#include "pch.h"
#include "DesktopToolsService.h"

#include <exdisp.h>
#include <servprov.h>
#include <shlguid.h>
#include <shobjidl.h>

#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace winrt::Zisla {
namespace {

std::runtime_error shell_error(std::string_view action, HRESULT result) {
    std::string message{action};
    try {
        const auto detail = to_string(hresult_error(result).message());
        if (!detail.empty()) {
            message.append("：");
            message.append(detail);
        }
    } catch (...) {
        message.append("（HRESULT ");
        message.append(std::to_string(static_cast<std::uint32_t>(result)));
        message.push_back(')');
    }
    return std::runtime_error(std::move(message));
}

zisla::core::RecycleBinMetrics query_recycle_bin() {
    SHQUERYRBINFO info{};
    info.cbSize = sizeof(info);
    const auto result = SHQueryRecycleBinW(nullptr, &info);
    if (FAILED(result)) {
        throw shell_error("无法读取回收站", result);
    }
    return {
        .item_count = info.i64NumItems > 0
            ? static_cast<std::uint64_t>(info.i64NumItems)
            : 0,
        .size_bytes = info.i64Size > 0
            ? static_cast<std::uint64_t>(info.i64Size)
            : 0,
        .available = true,
    };
}

zisla::core::RecycleBinMetrics query_recycle_bin_or(
    zisla::core::RecycleBinMetrics fallback) noexcept {
    try {
        return query_recycle_bin();
    } catch (...) {
        return fallback;
    }
}

void arrange_desktop_icons() {
    com_ptr<IShellWindows> shell_windows;
    check_hresult(CoCreateInstance(
        CLSID_ShellWindows,
        nullptr,
        CLSCTX_LOCAL_SERVER,
        __uuidof(IShellWindows),
        shell_windows.put_void()));

    VARIANT location{};
    VARIANT root{};
    long window_handle = 0;
    com_ptr<IDispatch> dispatch;
    check_hresult(shell_windows->FindWindowSW(
        &location,
        &root,
        SWC_DESKTOP,
        &window_handle,
        SWFO_NEEDDISPATCH,
        dispatch.put()));

    const auto service_provider = dispatch.as<::IServiceProvider>();
    com_ptr<IShellBrowser> browser;
    check_hresult(service_provider->QueryService(
        SID_STopLevelBrowser,
        __uuidof(IShellBrowser),
        browser.put_void()));

    com_ptr<IShellView> view;
    check_hresult(browser->QueryActiveShellView(view.put()));
    const auto folder_options = view.as<IFolderViewOptions>();
    check_hresult(folder_options->SetFolderViewOptions(
        FVO_CUSTOMPOSITION,
        FVO_CUSTOMPOSITION));
    const auto folder_view = view.as<IFolderView2>();
    check_hresult(folder_view->SetCurrentFolderFlags(
        FWF_AUTOARRANGE,
        FWF_AUTOARRANGE));
}

void empty_recycle_bin(HWND owner) {
    const auto result = SHEmptyRecycleBinW(
        owner,
        nullptr,
        SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
    if (FAILED(result)) {
        throw shell_error("无法清空回收站", result);
    }
}

void open_store_updates(HWND owner) {
    const auto result = reinterpret_cast<INT_PTR>(ShellExecuteW(
        owner,
        L"open",
        L"ms-windows-store://downloadsandupdates",
        nullptr,
        nullptr,
        SW_SHOWNORMAL));
    if (result <= 32) {
        throw std::runtime_error(
            "无法打开 Microsoft Store 更新页（错误 "
            + std::to_string(result) + ")");
    }
}

void release_system_memory() {
    using NtSetSystemInformationFunction = LONG (NTAPI*)(ULONG, PVOID, ULONG);
    constexpr ULONG system_memory_list_information = 80;
    constexpr ULONG memory_empty_working_sets = 2;
    constexpr ULONG memory_purge_standby_list = 4;

    const auto ntdll = GetModuleHandleW(L"ntdll.dll");
    const auto function = ntdll
        ? reinterpret_cast<NtSetSystemInformationFunction>(
            GetProcAddress(ntdll, "NtSetSystemInformation"))
        : nullptr;
    if (!function) {
        throw std::runtime_error("当前 Windows 版本不支持系统内存回收");
    }

    for (const ULONG command_value : {
             memory_empty_working_sets,
             memory_purge_standby_list,
         }) {
        ULONG command = command_value;
        const auto status = function(
            system_memory_list_information,
            &command,
            sizeof(command));
        if (status < 0) {
            throw std::runtime_error(
                "Windows 无法回收系统内存（状态 "
                + std::to_string(status) + ")");
        }
    }
}

}  // namespace

DesktopToolsService::DesktopToolsService()
    : snapshot_(std::make_shared<const zisla::core::DesktopToolsSnapshot>()) {}

DesktopToolsService::~DesktopToolsService() {
    stop();
}

bool DesktopToolsService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || thread_.joinable() || !target || changed_message == 0) {
        return false;
    }
    target_ = target;
    changed_message_ = changed_message;
    running_ = true;
    commands_.push_back(zisla::core::DesktopToolAction::refresh_recycle_bin);
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_ = false;
        commands_.clear();
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    condition_.notify_one();
    return true;
}

void DesktopToolsService::stop() noexcept {
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

void DesktopToolsService::refreshRecycleBin() {
    enqueue(zisla::core::DesktopToolAction::refresh_recycle_bin);
}

void DesktopToolsService::arrangeDesktop() {
    enqueue(zisla::core::DesktopToolAction::arrange_desktop);
}

void DesktopToolsService::emptyRecycleBin() {
    enqueue(zisla::core::DesktopToolAction::empty_recycle_bin);
}

void DesktopToolsService::openStoreUpdates() {
    enqueue(zisla::core::DesktopToolAction::open_store_updates);
}

void DesktopToolsService::releaseSystemMemory() {
    enqueue(zisla::core::DesktopToolAction::release_system_memory);
}

std::shared_ptr<const zisla::core::DesktopToolsSnapshot>
DesktopToolsService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void DesktopToolsService::enqueue(zisla::core::DesktopToolAction action) {
    {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        commands_.push_back(action);
    }
    condition_.notify_one();
}

void DesktopToolsService::run() noexcept {
    const auto apartment = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(apartment)) {
        state_.fail("无法初始化 Windows Shell 线程");
        publish();
        std::lock_guard lock(mutex_);
        running_ = false;
        commands_.clear();
        return;
    }

    while (true) {
        zisla::core::DesktopToolAction action;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !running_ || !commands_.empty();
            });
            if (!running_) {
                break;
            }
            action = commands_.front();
            commands_.pop_front();
        }

        if (!state_.begin(action)) {
            continue;
        }
        publish();
        try {
            execute(action);
        } catch (const std::exception& error) {
            state_.fail(error.what());
        } catch (...) {
            state_.fail("桌面工具发生未知错误");
        }
        publish();
    }

    CoUninitialize();
}

void DesktopToolsService::execute(zisla::core::DesktopToolAction action) {
    const auto previous = state_.snapshot().recycle_bin;
    switch (action) {
    case zisla::core::DesktopToolAction::refresh_recycle_bin:
        state_.complete(query_recycle_bin(), {});
        return;
    case zisla::core::DesktopToolAction::arrange_desktop:
        arrange_desktop_icons();
        state_.complete(
            query_recycle_bin_or(previous),
            "已启用桌面图标自动排列");
        return;
    case zisla::core::DesktopToolAction::empty_recycle_bin: {
        const auto before = query_recycle_bin();
        if (before.item_count == 0) {
            state_.complete(before, "回收站已经是空的");
            return;
        }
        empty_recycle_bin(target_);
        state_.complete(
            query_recycle_bin_or({.available = false}),
            "已清空回收站（" + std::to_string(before.item_count) + " 个项目）");
        return;
    }
    case zisla::core::DesktopToolAction::open_store_updates:
        open_store_updates(target_);
        state_.complete(
            query_recycle_bin_or(previous),
            "已打开 Microsoft Store 更新页");
        return;
    case zisla::core::DesktopToolAction::release_system_memory:
        release_system_memory();
        state_.complete(
            query_recycle_bin_or(previous),
            "已请求 Windows 回收系统工作集和待机内存");
        return;
    case zisla::core::DesktopToolAction::none:
        break;
    }
    throw std::runtime_error("无效的桌面工具操作");
}

void DesktopToolsService::publish() noexcept {
    try {
        snapshot_.store(
            std::make_shared<const zisla::core::DesktopToolsSnapshot>(
                state_.snapshot()),
            std::memory_order_release);
        notify();
    } catch (...) {
    }
}

void DesktopToolsService::notify() const noexcept {
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
