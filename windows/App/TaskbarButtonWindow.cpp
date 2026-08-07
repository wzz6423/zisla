#include "pch.h"
#include "TaskbarButtonWindow.h"
#include "resource.h"

#include <shobjidl_core.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cmath>

namespace winrt::Zisla {
namespace {

constexpr wchar_t window_class_name[] = L"ZislaTaskbarButtonWindow";
constexpr UINT system_menu_open = 0x1F00;
constexpr UINT system_menu_settings = 0x1F10;
constexpr UINT system_menu_exit = 0x1F20;
constexpr UINT minimize_message = WM_APP + 0x3A1;
constexpr std::size_t taskbar_text_limit = 260;
constexpr int taskbar_host_offscreen_coordinate = -32'000;

std::wstring truncateTaskbarText(std::wstring text) {
    if (text.size() <= taskbar_text_limit) {
        return text;
    }
    text.resize(taskbar_text_limit - 3);
    text.append(L"...");
    return text;
}

std::int64_t unixMillisecondsNow() noexcept {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

HICON loadPetOverlayIcon(const zisla::core::PetLibraryEntry& entry) noexcept {
    if (entry.sprite_file.empty()) {
        return nullptr;
    }

    using ::Microsoft::WRL::ComPtr;
    ComPtr<IWICImagingFactory> factory;
    if (FAILED(CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&factory)))) {
        return nullptr;
    }
    ComPtr<IWICBitmapDecoder> decoder;
    if (FAILED(factory->CreateDecoderFromFilename(
            entry.sprite_file.c_str(),
            nullptr,
            GENERIC_READ,
            WICDecodeMetadataCacheOnDemand,
            &decoder))) {
        return nullptr;
    }
    ComPtr<IWICBitmapFrameDecode> frame;
    if (FAILED(decoder->GetFrame(0, &frame))) {
        return nullptr;
    }

    UINT image_width = 0;
    UINT image_height = 0;
    if (FAILED(frame->GetSize(&image_width, &image_height))
        || image_width == 0 || image_height == 0) {
        return nullptr;
    }
    const auto frames = std::clamp(entry.manifest.frames, 1, 64);
    const auto frame_width = frames > 1
        ? entry.manifest.frame_width.value_or(0)
        : static_cast<int>(image_width);
    if (frame_width <= 0 || frame_width > static_cast<int>(image_width)
        || frames > static_cast<int>(image_width) / frame_width) {
        return nullptr;
    }

    ComPtr<IWICBitmapClipper> clipper;
    WICRect source{0, 0, frame_width, static_cast<INT>(image_height)};
    if (FAILED(factory->CreateBitmapClipper(&clipper))
        || FAILED(clipper->Initialize(frame.Get(), &source))) {
        return nullptr;
    }

    const UINT icon_width = static_cast<UINT>(std::max(16, GetSystemMetrics(SM_CXSMICON)));
    const UINT icon_height = static_cast<UINT>(std::max(16, GetSystemMetrics(SM_CYSMICON)));
    ComPtr<IWICBitmapScaler> scaler;
    ComPtr<IWICFormatConverter> converter;
    if (FAILED(factory->CreateBitmapScaler(&scaler))
        || FAILED(scaler->Initialize(
            clipper.Get(),
            icon_width,
            icon_height,
            WICBitmapInterpolationModeFant))
        || FAILED(factory->CreateFormatConverter(&converter))
        || FAILED(converter->Initialize(
            scaler.Get(),
            GUID_WICPixelFormat32bppBGRA,
            WICBitmapDitherTypeNone,
            nullptr,
            0.0,
            WICBitmapPaletteTypeCustom))) {
        return nullptr;
    }

    HDC screen_dc = GetDC(nullptr);
    if (!screen_dc) {
        return nullptr;
    }
    BITMAPINFO bitmap_info{};
    bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bitmap_info.bmiHeader.biWidth = static_cast<LONG>(icon_width);
    bitmap_info.bmiHeader.biHeight = -static_cast<LONG>(icon_height);
    bitmap_info.bmiHeader.biPlanes = 1;
    bitmap_info.bmiHeader.biBitCount = 32;
    bitmap_info.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    const auto color = CreateDIBSection(
        screen_dc,
        &bitmap_info,
        DIB_RGB_COLORS,
        &bits,
        nullptr,
        0);
    ReleaseDC(nullptr, screen_dc);
    if (!color || !bits) {
        if (color) {
            DeleteObject(color);
        }
        return nullptr;
    }

    const auto stride = icon_width * 4;
    const auto buffer_size = stride * icon_height;
    if (FAILED(converter->CopyPixels(
            nullptr,
            stride,
            buffer_size,
            static_cast<BYTE*>(bits)))) {
        DeleteObject(color);
        return nullptr;
    }

    const auto mask = CreateBitmap(
        static_cast<int>(icon_width),
        static_cast<int>(icon_height),
        1,
        1,
        nullptr);
    if (!mask) {
        DeleteObject(color);
        return nullptr;
    }
    ICONINFO icon_info{};
    icon_info.fIcon = TRUE;
    icon_info.hbmColor = color;
    icon_info.hbmMask = mask;
    const auto icon = CreateIconIndirect(&icon_info);
    DeleteObject(mask);
    DeleteObject(color);
    return icon;
}

}  // namespace

bool TaskbarButtonWindow::registerWindowClass() noexcept {
    static bool registered = false;
    if (registered) {
        return true;
    }

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = windowProc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.hIcon = LoadIconW(
        window_class.hInstance,
        MAKEINTRESOURCEW(IDI_ZISLA_APP));
    window_class.hIconSm = window_class.hIcon;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.lpszClassName = window_class_name;
    if (!RegisterClassExW(&window_class)
        && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        return false;
    }
    registered = true;
    return true;
}

TaskbarButtonWindow::TaskbarButtonWindow(
    HWND activation_target,
    UINT activation_message,
    UINT exit_message)
    : activation_target_(activation_target),
      activation_message_(activation_message),
      exit_message_(exit_message) {
    createWindow();
}

TaskbarButtonWindow::~TaskbarButtonWindow() {
    setEnabled(false);
    if (hwnd_) {
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }
    if (taskbar_list_) {
        taskbar_list_->Release();
        taskbar_list_ = nullptr;
    }
    clearPetOverlay();
}

void TaskbarButtonWindow::createWindow() noexcept {
    if (!registerWindowClass()) {
        return;
    }

    hwnd_ = CreateWindowExW(
        WS_EX_APPWINDOW | WS_EX_NOACTIVATE,
        window_class_name,
        L"Zisla",
        WS_OVERLAPPED | WS_SYSMENU | WS_MINIMIZEBOX,
        taskbar_host_offscreen_coordinate,
        taskbar_host_offscreen_coordinate,
        1,
        1,
        nullptr,
        nullptr,
        GetModuleHandleW(nullptr),
        this);
    if (!hwnd_) {
        return;
    }

    // Explorer can restore the taskbar host when its button is activated. Keep
    // it a captionless top-level window so that recovery can never expose a
    // small desktop window with title-bar controls.
    const auto style = GetWindowLongPtrW(hwnd_, GWL_STYLE);
    SetWindowLongPtrW(
        hwnd_,
        GWL_STYLE,
        style & ~static_cast<LONG_PTR>(WS_CAPTION | WS_THICKFRAME));
    SetWindowPos(
        hwnd_,
        nullptr,
        0,
        0,
        0,
        0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);

    const auto icon = static_cast<HICON>(LoadImageW(
        GetModuleHandleW(nullptr),
        MAKEINTRESOURCEW(IDI_ZISLA_APP),
        IMAGE_ICON,
        GetSystemMetrics(SM_CXSMICON),
        GetSystemMetrics(SM_CYSMICON),
        LR_DEFAULTCOLOR));
    if (icon) {
        SendMessageW(hwnd_, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(icon));
        SendMessageW(hwnd_, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(icon));
    }
    updateSystemMenu();
}

void TaskbarButtonWindow::updateSystemMenu() noexcept {
    if (!hwnd_) {
        return;
    }
    const auto menu = GetSystemMenu(hwnd_, FALSE);
    if (!menu) {
        return;
    }
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, system_menu_open, L"打开 Zisla");
    AppendMenuW(menu, MF_STRING, system_menu_settings, L"设置");
    AppendMenuW(menu, MF_STRING, system_menu_exit, L"退出");
}

void TaskbarButtonWindow::setEnabled(bool enabled) noexcept {
    if (enabled_ == enabled) {
        if (enabled) {
            updateTaskbarState();
        }
        return;
    }

    enabled_ = enabled;
    if (!hwnd_) {
        return;
    }

    if (!enabled_) {
        if (taskbar_list_) {
            (void)taskbar_list_->SetOverlayIcon(hwnd_, nullptr, nullptr);
            (void)taskbar_list_->SetProgressState(hwnd_, TBPF_NOPROGRESS);
        }
        ShowWindow(hwnd_, SW_HIDE);
        return;
    }

    showMinimized();
    updateTaskbarState();
}

void TaskbarButtonWindow::setNowPlaying(
    std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot) {
    now_playing_ = snapshot && snapshot->valid() ? std::move(snapshot) : nullptr;
    updateTaskbarState();
}

void TaskbarButtonWindow::setDockNotice(
    std::optional<zisla::core::IslandNotice> notice,
    std::size_t count) {
    notice_text_.clear();
    if (notice) {
        if (count > 1) {
            notice_text_ = std::to_wstring(count);
            notice_text_.append(L" 个任务 - ");
        }
        const auto title = to_hstring(notice->title);
        notice_text_.append(title.c_str(), title.size());
        if (notice->detail && !notice->detail->empty()) {
            const auto detail = to_hstring(*notice->detail);
            if (!detail.empty()) {
                notice_text_.append(L" - ");
                notice_text_.append(detail.c_str(), detail.size());
            }
        }
    }
    updateTaskbarState();
}

void TaskbarButtonWindow::setPet(
    std::optional<zisla::core::PetLibraryEntry> entry) {
    const auto sprite_path = entry ? entry->sprite_file.wstring() : std::wstring{};
    if (sprite_path == pet_sprite_path_) {
        return;
    }

    clearPetOverlay();
    pet_sprite_path_ = sprite_path;
    if (entry) {
        pet_overlay_icon_ = loadPetOverlayIcon(*entry);
    }
    updateTaskbarState();
}

void TaskbarButtonWindow::refreshAfterExplorerRestart() noexcept {
    if (taskbar_list_) {
        taskbar_list_->Release();
        taskbar_list_ = nullptr;
    }
    if (enabled_ && hwnd_) {
        showMinimized();
        updateTaskbarState();
    }
}

bool TaskbarButtonWindow::available() const noexcept {
    return hwnd_ != nullptr;
}

bool TaskbarButtonWindow::enabled() const noexcept {
    return enabled_ && hwnd_ != nullptr;
}

void TaskbarButtonWindow::postActivation() const noexcept {
    if (activation_target_ && activation_message_ != 0) {
        (void)PostMessageW(activation_target_, activation_message_, 0, 0);
    }
}

void TaskbarButtonWindow::postExit() const noexcept {
    if (activation_target_ && exit_message_ != 0) {
        (void)PostMessageW(activation_target_, exit_message_, 0, 0);
    }
}

void TaskbarButtonWindow::clearPetOverlay() noexcept {
    if (pet_overlay_icon_) {
        DestroyIcon(pet_overlay_icon_);
        pet_overlay_icon_ = nullptr;
    }
    pet_sprite_path_.clear();
}

bool TaskbarButtonWindow::ensureTaskbarList() noexcept {
    if (taskbar_list_) {
        return true;
    }

    ITaskbarList3* taskbar = nullptr;
    const auto created = CoCreateInstance(
        CLSID_TaskbarList,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&taskbar));
    if (FAILED(created) || !taskbar) {
        return false;
    }
    if (FAILED(taskbar->HrInit())) {
        taskbar->Release();
        return false;
    }
    taskbar_list_ = taskbar;
    return true;
}

std::wstring TaskbarButtonWindow::taskbarText() const {
    if (now_playing_) {
        auto text = std::wstring{L"正在播放: "};
        const auto title = to_hstring(now_playing_->title);
        text.append(title.c_str(), title.size());
        const auto artist = to_hstring(now_playing_->artist);
        if (!artist.empty()) {
            text.append(L" - ");
            text.append(artist.c_str(), artist.size());
        }
        return truncateTaskbarText(std::move(text));
    }
    if (!notice_text_.empty()) {
        auto text = std::wstring{L"Zisla - "};
        text.append(notice_text_);
        return truncateTaskbarText(std::move(text));
    }
    return L"Zisla";
}

void TaskbarButtonWindow::updateTaskbarState() noexcept {
    if (!enabled_ || !hwnd_ || !ensureTaskbarList()) {
        return;
    }

    const auto text = taskbarText();
    SetWindowTextW(hwnd_, text.c_str());
    (void)taskbar_list_->SetThumbnailTooltip(hwnd_, text.c_str());

    (void)taskbar_list_->SetOverlayIcon(
        hwnd_,
        pet_overlay_icon_,
        pet_overlay_icon_ ? L"Zisla 宠物" : nullptr);

    const bool has_media = now_playing_ != nullptr;
    if (!has_media) {
        (void)taskbar_list_->SetProgressState(hwnd_, TBPF_NOPROGRESS);
        return;
    }

    const bool playing = now_playing_->playback_status
        == zisla::core::MediaPlaybackStatus::playing;
    const auto duration = now_playing_->duration_seconds;
    const auto elapsed = now_playing_->elapsedAt(unixMillisecondsNow());
    if (duration && elapsed && *duration > 0.0) {
        const auto ratio = std::clamp(*elapsed / *duration, 0.0, 1.0);
        constexpr ULONGLONG total = 10'000;
        const auto current = static_cast<ULONGLONG>(std::llround(ratio * total));
        (void)taskbar_list_->SetProgressValue(hwnd_, current, total);
        (void)taskbar_list_->SetProgressState(
            hwnd_,
            playing ? TBPF_NORMAL : TBPF_PAUSED);
        return;
    }
    (void)taskbar_list_->SetProgressState(
        hwnd_,
        playing ? TBPF_INDETERMINATE : TBPF_PAUSED);
}

void TaskbarButtonWindow::minimize() noexcept {
    if (hwnd_ && enabled_ && !IsIconic(hwnd_)) {
        ShowWindow(hwnd_, SW_MINIMIZE);
    }
}

void TaskbarButtonWindow::scheduleMinimize() noexcept {
    if (hwnd_ && enabled_) {
        (void)PostMessageW(hwnd_, minimize_message, 0, 0);
    }
}

void TaskbarButtonWindow::showMinimized() noexcept {
    if (!hwnd_) {
        return;
    }
    showing_minimized_ = true;
    ShowWindow(hwnd_, SW_SHOWMINNOACTIVE);
    showing_minimized_ = false;
}

LRESULT CALLBACK TaskbarButtonWindow::windowProc(
    HWND hwnd,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) noexcept {
    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
        SetWindowLongPtrW(
            hwnd,
            GWLP_USERDATA,
            reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    const auto self = reinterpret_cast<TaskbarButtonWindow*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (!self) {
        return DefWindowProcW(hwnd, message, wparam, lparam);
    }

    switch (message) {
    case WM_WINDOWPOSCHANGING: {
        // Block Explorer from restoring the host onto the desktop before the
        // activation is forwarded to the real Zisla window.
        auto* position = reinterpret_cast<WINDOWPOS*>(lparam);
        if (position && self->enabled_ && !self->showing_minimized_
            && (position->flags & SWP_SHOWWINDOW) != 0) {
            position->flags &= ~SWP_SHOWWINDOW;
            position->flags |= SWP_NOACTIVATE;
            self->scheduleMinimize();
        }
        break;
    }
    case WM_SHOWWINDOW:
        if (wparam != FALSE && self->enabled_ && !self->showing_minimized_) {
            self->scheduleMinimize();
        }
        break;
    case WM_SIZE:
        if (wparam != SIZE_MINIMIZED && self->enabled_ && !self->showing_minimized_) {
            self->scheduleMinimize();
        }
        break;
    case WM_SYSCOMMAND: {
        const auto command = static_cast<UINT>(wparam) & 0xFFF0;
        if (command == system_menu_open || command == system_menu_settings) {
            self->postActivation();
            self->scheduleMinimize();
            return 0;
        }
        if (command == SC_RESTORE || command == SC_MAXIMIZE) {
            self->scheduleMinimize();
            return 0;
        }
        if (command == system_menu_exit || command == SC_CLOSE) {
            self->postExit();
            return 0;
        }
        break;
    }
    case WM_CLOSE:
        self->postExit();
        return 0;
    case WM_ACTIVATE:
        if (LOWORD(wparam) != WA_INACTIVE) {
            self->scheduleMinimize();
        }
        return 0;
    case minimize_message:
        self->minimize();
        return 0;
    case WM_DESTROY:
        if (self->hwnd_ == hwnd) {
            self->hwnd_ = nullptr;
        }
        return 0;
    default:
        break;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

}
