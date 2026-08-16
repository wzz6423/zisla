#include "pch.h"
#include "TaskbarWidgetWindow.h"

#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <limits>

namespace winrt::Zisla {
namespace {

constexpr wchar_t window_class_name[] = L"ZislaTaskbarWidgetWindow";
constexpr UINT_PTR pet_timer_id = 1;
constexpr std::int32_t pet_gap_pixels = 3;

bool safeMultiply(std::int32_t left, std::int32_t right, std::int32_t& result) noexcept {
    if (left < 0 || right < 0
        || (left != 0 && right > std::numeric_limits<std::int32_t>::max() / left)) {
        return false;
    }
    result = left * right;
    return true;
}

std::filesystem::path taskbarLogoPath() {
    std::array<wchar_t, 32'768> module_path{};
    const auto length = GetModuleFileNameW(
        nullptr,
        module_path.data(),
        static_cast<DWORD>(module_path.size()));
    if (length == 0 || length >= module_path.size()) {
        return {};
    }
    return std::filesystem::path{std::wstring_view{module_path.data(), length}}
        .parent_path()
        / L"Assets"
        / L"TaskbarLogo.png";
}

COLORREF foregroundColor() noexcept {
    DWORD system_uses_light_theme = 0;
    DWORD size = sizeof(system_uses_light_theme);
    const auto result = RegGetValueW(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"SystemUsesLightTheme",
        RRF_RT_REG_DWORD,
        nullptr,
        &system_uses_light_theme,
        &size);
    return result == ERROR_SUCCESS && system_uses_light_theme != 0
        ? RGB(24, 24, 24)
        : RGB(245, 245, 245);
}

}  // namespace

bool TaskbarWidgetWindow::registerWindowClass() noexcept {
    static bool registered = false;
    if (registered) {
        return true;
    }

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = windowProc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.hCursor = LoadCursorW(nullptr, IDC_HAND);
    window_class.lpszClassName = window_class_name;
    if (!RegisterClassExW(&window_class)
        && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        return false;
    }
    registered = true;
    return true;
}

TaskbarWidgetWindow::TaskbarWidgetWindow(
    HWND activation_target,
    UINT activation_message)
    : activation_target_(activation_target),
      activation_message_(activation_message) {
    createWindow();
    (void)loadLogo();
}

TaskbarWidgetWindow::~TaskbarWidgetWindow() {
    visible_ = false;
    stopPetTimer();
    if (hwnd_) {
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }
    destroyTargetSurface();
    destroyLogoSurface();
    destroyPetSurface();
}

void TaskbarWidgetWindow::createWindow() {
    if (!registerWindowClass()) {
        return;
    }
    hwnd_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_LAYERED,
        window_class_name,
        L"Zisla taskbar widget",
        WS_POPUP,
        0,
        0,
        1,
        1,
        nullptr,
        nullptr,
        GetModuleHandleW(nullptr),
        this);
}

bool TaskbarWidgetWindow::show(const zisla::core::PixelRect& bounds) {
    if (!hwnd_) {
        createWindow();
    }
    if (!hwnd_ || bounds.width <= 0 || bounds.height <= 0
        || !ensureTargetSurface(bounds.width, bounds.height)) {
        hide();
        return false;
    }
    if (!attachToTaskbar()) {
        hide();
        return false;
    }

    POINT position{bounds.x, bounds.y};
    if (!ScreenToClient(taskbar_parent_, &position)) {
        hide();
        return false;
    }

    bounds_ = bounds;
    if (!SetWindowPos(
            hwnd_,
            HWND_TOP,
            position.x,
            position.y,
            bounds.width,
            bounds.height,
            SWP_SHOWWINDOW | SWP_NOACTIVATE)) {
        hide();
        return false;
    }
    visible_ = true;
    render();
    updatePetTimer();
    return visible_;
}

void TaskbarWidgetWindow::hide() noexcept {
    visible_ = false;
    stopPetTimer();
    if (hwnd_) {
        ShowWindow(hwnd_, SW_HIDE);
    }
}

void TaskbarWidgetWindow::setPet(
    std::optional<zisla::core::PetLibraryEntry> entry,
    zisla::core::PetSide side) {
    pet_side_ = side;
    const auto sprite_path = entry ? entry->sprite_file.wstring() : std::wstring{};
    if (sprite_path.empty()) {
        pet_active_ = false;
        destroyPetSurface();
    } else if (sprite_path != pet_sprite_path_ || !pet_bits_) {
        pet_active_ = false;
        destroyPetSurface();
        pet_active_ = loadPet(*entry);
    } else {
        pet_active_ = true;
    }
    if (visible_) {
        render();
    }
    updatePetTimer();
}

void TaskbarWidgetWindow::setNowPlaying(
    std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot) {
    media_active_ = snapshot && snapshot->valid()
        && snapshot->playback_status == zisla::core::MediaPlaybackStatus::playing;
    now_playing_text_.clear();
    if (media_active_) {
        now_playing_text_ = to_hstring(snapshot->title).c_str();
        const auto artist = to_hstring(snapshot->artist);
        if (!artist.empty()) {
            if (!now_playing_text_.empty()) {
                now_playing_text_.append(L"  -  ");
            }
            now_playing_text_.append(artist.c_str(), artist.size());
        }
        if (now_playing_text_.empty()) {
            now_playing_text_ = L"正在播放";
        }
    }
    if (visible_) {
        render();
        updatePetTimer();
    }
}

void TaskbarWidgetWindow::setDockNotice(
    std::optional<zisla::core::IslandNotice> notice,
    std::size_t count) {
    dock_notice_active_ = notice.has_value();
    dock_notice_count_ = dock_notice_active_ ? std::max<std::size_t>(1, count) : 0;
    dock_notice_text_.clear();
    if (notice) {
        if (dock_notice_count_ > 1) {
            dock_notice_text_ = std::to_wstring(dock_notice_count_);
            dock_notice_text_.append(L" 个任务  ");
        } else {
            dock_notice_text_ = L"任务  ";
        }
        const auto title = to_hstring(notice->title);
        dock_notice_text_.append(title.c_str(), title.size());
        if (notice->detail && !notice->detail->empty()) {
            const auto detail = to_hstring(*notice->detail);
            if (!detail.empty()) {
                dock_notice_text_.append(L"  -  ");
                dock_notice_text_.append(detail.c_str(), detail.size());
            }
        }
    }
    if (visible_) {
        render();
    }
}

void TaskbarWidgetWindow::setTaskbarEdge(zisla::core::TaskbarEdge edge) {
    if (edge_ == edge) {
        return;
    }
    edge_ = edge;
    if (visible_) {
        render();
    }
}

void TaskbarWidgetWindow::refreshBackdrop() noexcept {
}

zisla::core::DipSize TaskbarWidgetWindow::preferredSize() const noexcept {
    const bool horizontal = edge_ == zisla::core::TaskbarEdge::top
        || edge_ == zisla::core::TaskbarEdge::bottom;
    auto size = zisla::core::DipSize{36, 36};
    if (dock_notice_active_) {
        size = horizontal ? zisla::core::DipSize{240, 36} : zisla::core::DipSize{36, 240};
    } else if (media_active_) {
        size = horizontal ? zisla::core::DipSize{176, 36} : zisla::core::DipSize{36, 176};
    }
    if (pet_active_) {
        if (horizontal) {
            size.width += 31;
        } else {
            size.height += 31;
        }
    }
    return size;
}

HWND TaskbarWidgetWindow::hwnd() const noexcept {
    return hwnd_;
}

bool TaskbarWidgetWindow::visible() const noexcept {
    return visible_;
}

bool TaskbarWidgetWindow::attachToTaskbar() noexcept {
    // Cross-process child windows in Explorer can destabilize the taskbar.
    // Keep this legacy renderer inert until a supported shell integration is
    // implemented; AppHost uses TaskbarButtonWindow instead.
    return false;
}

LRESULT CALLBACK TaskbarWidgetWindow::windowProc(
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
    const auto self = reinterpret_cast<TaskbarWidgetWindow*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (!self) {
        return DefWindowProcW(hwnd, message, wparam, lparam);
    }

    switch (message) {
    case WM_NCHITTEST:
        return HTCLIENT;
    case WM_MOUSEACTIVATE:
        // Keep the taskbar focus unchanged without letting Windows consume the click.
        return MA_NOACTIVATE;
    case WM_LBUTTONUP:
    case WM_RBUTTONUP:
        if (self->activation_target_ && self->activation_message_ != 0) {
            (void)PostMessageW(
                self->activation_target_,
                self->activation_message_,
                0,
                0);
        }
        return 0;
    case WM_TIMER:
        if (wparam == pet_timer_id) {
            self->render();
            return 0;
        }
        break;
    case WM_DESTROY:
        self->stopPetTimer();
        if (self->hwnd_ == hwnd) {
            self->hwnd_ = nullptr;
            self->taskbar_parent_ = nullptr;
            self->visible_ = false;
        }
        return 0;
    default:
        break;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

void TaskbarWidgetWindow::render() noexcept {
    if (!hwnd_ || !target_bits_ || bounds_.width <= 0 || bounds_.height <= 0) {
        return;
    }

    std::int32_t pixel_count = 0;
    std::int32_t byte_count = 0;
    if (!safeMultiply(target_width_, target_height_, pixel_count)
        || !safeMultiply(pixel_count, 4, byte_count)) {
        return;
    }
    std::memset(target_bits_, 0, static_cast<std::size_t>(byte_count));

    const auto foreground = foregroundColor();
    if (dock_notice_active_) {
        drawDockNotice(foreground);
    } else if (media_active_) {
        drawNowPlaying(foreground);
    } else {
        drawLogo(foreground);
    }
    drawPet();

    HDC screen_dc = GetDC(nullptr);
    if (!screen_dc) {
        return;
    }
    POINT source{0, 0};
    SIZE size{target_width_, target_height_};
    BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    if (!UpdateLayeredWindow(
            hwnd_,
            screen_dc,
            nullptr,
            &size,
            target_dc_,
            &source,
            0,
            &blend,
            ULW_ALPHA)) {
        hide();
    }
    ReleaseDC(nullptr, screen_dc);
}

void TaskbarWidgetWindow::drawLogo(COLORREF foreground) noexcept {
    if (!logo_bits_ || logo_width_ <= 0 || logo_height_ <= 0) {
        return;
    }
    const auto content = contentBounds();
    const auto content_width = static_cast<std::int32_t>(content.right - content.left);
    const auto content_height = static_cast<std::int32_t>(content.bottom - content.top);
    const auto canvas_size = std::min(content_width, content_height);
    if (canvas_size <= 0) {
        return;
    }
    const auto draw_size = std::clamp(canvas_size * 32 / 36, 1, canvas_size);
    const auto draw_x = content.left + (content_width - draw_size) / 2;
    const auto draw_y = content.top + (content_height - draw_size) / 2;
    const auto* source = static_cast<const std::uint8_t*>(logo_bits_);
    auto* target = static_cast<std::uint8_t*>(target_bits_);

    for (std::int32_t y = 0; y < draw_size; ++y) {
        const auto source_y = y * logo_height_ / draw_size;
        for (std::int32_t x = 0; x < draw_size; ++x) {
            const auto source_x = x * logo_width_ / draw_size;
            const auto source_index = (source_y * logo_width_ + source_x) * 4;
            const auto target_index = ((draw_y + y) * target_width_ + draw_x + x) * 4;
            const auto alpha = source[source_index + 3];
            target[target_index] = static_cast<std::uint8_t>(
                GetBValue(foreground) * alpha / 255U);
            target[target_index + 1] = static_cast<std::uint8_t>(
                GetGValue(foreground) * alpha / 255U);
            target[target_index + 2] = static_cast<std::uint8_t>(
                GetRValue(foreground) * alpha / 255U);
            target[target_index + 3] = alpha;
        }
    }
}

void TaskbarWidgetWindow::drawNowPlaying(COLORREF foreground) noexcept {
    if (!target_dc_) {
        return;
    }
    const bool horizontal = edge_ == zisla::core::TaskbarEdge::top
        || edge_ == zisla::core::TaskbarEdge::bottom;
    const auto content = contentBounds();
    const auto content_width = static_cast<std::int32_t>(content.right - content.left);
    const auto content_height = static_cast<std::int32_t>(content.bottom - content.top);
    const auto icon_size = std::clamp(
        (horizontal ? content_height : content_width) * 12 / 36,
        8,
        16);
    const auto icon_x = horizontal ? content.left + 5 : content.left + (content_width - icon_size) / 2;
    const auto icon_y = horizontal ? content.top + (content_height - icon_size) / 2 : content.top + 5;
    POINT triangle[] = {
        {icon_x, icon_y},
        {icon_x, icon_y + icon_size},
        {icon_x + icon_size, icon_y + icon_size / 2},
    };
    const auto brush = CreateSolidBrush(RGB(255, 255, 255));
    if (brush) {
        const auto old_brush = SelectObject(target_dc_, brush);
        const auto old_pen = SelectObject(target_dc_, GetStockObject(NULL_PEN));
        (void)Polygon(target_dc_, triangle, static_cast<int>(std::size(triangle)));
        if (old_pen) {
            (void)SelectObject(target_dc_, old_pen);
        }
        if (old_brush) {
            (void)SelectObject(target_dc_, old_brush);
        }
        (void)DeleteObject(brush);
    }

    const auto font_height = -std::clamp(
        (horizontal ? content_height : content_width) * 12 / 36,
        10,
        14);
    const auto font = CreateFontW(
        font_height,
        0,
        0,
        0,
        FW_NORMAL,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI");
    if (font) {
        const auto old_font = SelectObject(target_dc_, font);
        const auto old_color = SetTextColor(target_dc_, RGB(255, 255, 255));
        const auto old_mode = SetBkMode(target_dc_, TRANSPARENT);
        RECT text_bounds = horizontal
            ? RECT{icon_x + icon_size + 5, content.top, content.right - 2, content.bottom}
            : RECT{content.left + 2, icon_y + icon_size + 4, content.right - 2, content.bottom - 2};
        const auto format = horizontal
            ? DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX
            : DT_CENTER | DT_WORDBREAK | DT_END_ELLIPSIS | DT_NOPREFIX;
        (void)DrawTextW(
            target_dc_,
            now_playing_text_.c_str(),
            static_cast<int>(now_playing_text_.size()),
            &text_bounds,
            format);
        (void)SetBkMode(target_dc_, old_mode);
        (void)SetTextColor(target_dc_, old_color);
        if (old_font) {
            (void)SelectObject(target_dc_, old_font);
        }
        (void)DeleteObject(font);
    }
    applyTextMaskColor(foreground);
}

void TaskbarWidgetWindow::drawDockNotice(COLORREF foreground) noexcept {
    if (!target_dc_) {
        return;
    }

    const bool horizontal = edge_ == zisla::core::TaskbarEdge::top
        || edge_ == zisla::core::TaskbarEdge::bottom;
    const auto content = contentBounds();
    const auto content_width = static_cast<std::int32_t>(content.right - content.left);
    const auto content_height = static_cast<std::int32_t>(content.bottom - content.top);
    const auto icon_size = std::clamp(
        (horizontal ? content_height : content_width) * 14 / 36,
        10,
        18);
    const auto icon_x = horizontal ? content.left + 5 : content.left + (content_width - icon_size) / 2;
    const auto icon_y = horizontal ? content.top + (content_height - icon_size) / 2 : content.top + 5;
    POINT bolt[] = {
        {icon_x + icon_size * 5 / 8, icon_y},
        {icon_x + icon_size / 3, icon_y + icon_size * 7 / 12},
        {icon_x + icon_size / 2, icon_y + icon_size * 7 / 12},
        {icon_x + icon_size * 3 / 8, icon_y + icon_size},
        {icon_x + icon_size * 5 / 6, icon_y + icon_size * 5 / 12},
        {icon_x + icon_size * 2 / 3, icon_y + icon_size * 5 / 12},
    };
    const auto brush = CreateSolidBrush(RGB(255, 255, 255));
    if (brush) {
        const auto old_brush = SelectObject(target_dc_, brush);
        const auto old_pen = SelectObject(target_dc_, GetStockObject(NULL_PEN));
        (void)Polygon(target_dc_, bolt, static_cast<int>(std::size(bolt)));
        if (old_pen) {
            (void)SelectObject(target_dc_, old_pen);
        }
        if (old_brush) {
            (void)SelectObject(target_dc_, old_brush);
        }
        (void)DeleteObject(brush);
    }

    const auto font_height = -std::clamp(
        (horizontal ? content_height : content_width) * 12 / 36,
        10,
        14);
    const auto font = CreateFontW(
        font_height,
        0,
        0,
        0,
        FW_NORMAL,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE,
        L"Segoe UI");
    if (font) {
        const auto old_font = SelectObject(target_dc_, font);
        const auto old_color = SetTextColor(target_dc_, RGB(255, 255, 255));
        const auto old_mode = SetBkMode(target_dc_, TRANSPARENT);
        RECT text_bounds = horizontal
            ? RECT{icon_x + icon_size + 5, content.top, content.right - 2, content.bottom}
            : RECT{content.left + 2, icon_y + icon_size + 4, content.right - 2, content.bottom - 2};
        const auto format = horizontal
            ? DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX
            : DT_CENTER | DT_WORDBREAK | DT_END_ELLIPSIS | DT_NOPREFIX;
        (void)DrawTextW(
            target_dc_,
            dock_notice_text_.c_str(),
            static_cast<int>(dock_notice_text_.size()),
            &text_bounds,
            format);
        (void)SetBkMode(target_dc_, old_mode);
        (void)SetTextColor(target_dc_, old_color);
        if (old_font) {
            (void)SelectObject(target_dc_, old_font);
        }
        (void)DeleteObject(font);
    }
    applyTextMaskColor(foreground);
}

void TaskbarWidgetWindow::drawPet() noexcept {
    if (!pet_active_ || !pet_bits_ || pet_image_width_ <= 0
        || pet_image_height_ <= 0 || pet_frame_width_ <= 0 || !target_bits_) {
        return;
    }

    const bool horizontal = edge_ == zisla::core::TaskbarEdge::top
        || edge_ == zisla::core::TaskbarEdge::bottom;
    const auto slot_size = petSlotSize() - pet_gap_pixels;
    if (slot_size <= 0) {
        return;
    }
    const auto draw_x = horizontal
        ? (pet_side_ == zisla::core::PetSide::left ? 1 : target_width_ - slot_size - 1)
        : (target_width_ - slot_size) / 2;
    const auto draw_y = horizontal
        ? (target_height_ - slot_size) / 2
        : (pet_side_ == zisla::core::PetSide::left ? 1 : target_height_ - slot_size - 1);
    const auto scale = std::min(
        static_cast<double>(slot_size) / pet_frame_width_,
        static_cast<double>(slot_size) / pet_image_height_);
    if (!std::isfinite(scale) || scale <= 0.0) {
        return;
    }
    const auto draw_width = std::clamp(
        static_cast<std::int32_t>(std::lround(pet_frame_width_ * scale)),
        1,
        slot_size);
    const auto draw_height = std::clamp(
        static_cast<std::int32_t>(std::lround(pet_image_height_ * scale)),
        1,
        slot_size);
    const auto x = draw_x + (slot_size - draw_width) / 2;
    const auto y = draw_y + (slot_size - draw_height) / 2;
    const auto frame = 0;
    const auto source_x_offset = frame * pet_frame_width_;
    const auto* source = static_cast<const std::uint8_t*>(pet_bits_);
    auto* target = static_cast<std::uint8_t*>(target_bits_);
    for (std::int32_t local_y = 0; local_y < draw_height; ++local_y) {
        const auto source_y = local_y * pet_image_height_ / draw_height;
        const auto target_y = y + local_y;
        for (std::int32_t local_x = 0; local_x < draw_width; ++local_x) {
            const auto source_x = source_x_offset
                + local_x * pet_frame_width_ / draw_width;
            const auto source_index = (source_y * pet_image_width_ + source_x) * 4;
            const auto target_index = (target_y * target_width_ + x + local_x) * 4;
            std::memcpy(target + target_index, source + source_index, 4);
        }
    }
}

void TaskbarWidgetWindow::applyTextMaskColor(COLORREF foreground) noexcept {
    if (!target_bits_) {
        return;
    }
    auto* pixels = static_cast<std::uint8_t*>(target_bits_);
    const auto count = static_cast<std::size_t>(target_width_) * target_height_;
    for (std::size_t index = 0; index < count; ++index) {
        auto* pixel = pixels + index * 4;
        const auto alpha = std::max({pixel[0], pixel[1], pixel[2]});
        pixel[0] = static_cast<std::uint8_t>(GetBValue(foreground) * alpha / 255U);
        pixel[1] = static_cast<std::uint8_t>(GetGValue(foreground) * alpha / 255U);
        pixel[2] = static_cast<std::uint8_t>(GetRValue(foreground) * alpha / 255U);
        pixel[3] = alpha;
    }
}

bool TaskbarWidgetWindow::loadLogo() noexcept {
    const auto path = taskbarLogoPath();
    if (path.empty()) {
        return false;
    }

    using ::Microsoft::WRL::ComPtr;
    ComPtr<IWICImagingFactory> factory;
    if (FAILED(CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&factory)))) {
        return false;
    }
    ComPtr<IWICBitmapDecoder> decoder;
    if (FAILED(factory->CreateDecoderFromFilename(
            path.c_str(),
            nullptr,
            GENERIC_READ,
            WICDecodeMetadataCacheOnDemand,
            &decoder))) {
        return false;
    }
    ComPtr<IWICBitmapFrameDecode> frame;
    if (FAILED(decoder->GetFrame(0, &frame))) {
        return false;
    }
    UINT width = 0;
    UINT height = 0;
    if (FAILED(frame->GetSize(&width, &height))
        || width == 0 || height == 0 || width > 4096 || height > 4096) {
        return false;
    }
    ComPtr<IWICFormatConverter> converter;
    if (FAILED(factory->CreateFormatConverter(&converter))
        || FAILED(converter->Initialize(
            frame.Get(),
            GUID_WICPixelFormat32bppPBGRA,
            WICBitmapDitherTypeNone,
            nullptr,
            0.0,
            WICBitmapPaletteTypeCustom))) {
        return false;
    }

    HDC screen_dc = GetDC(nullptr);
    if (!screen_dc) {
        return false;
    }
    logo_dc_ = CreateCompatibleDC(screen_dc);
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = static_cast<LONG>(width);
    info.bmiHeader.biHeight = -static_cast<LONG>(height);
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    logo_dib_ = logo_dc_ ? CreateDIBSection(
        logo_dc_, &info, DIB_RGB_COLORS, &logo_bits_, nullptr, 0) : nullptr;
    ReleaseDC(nullptr, screen_dc);
    if (!logo_dc_ || !logo_dib_ || !logo_bits_) {
        destroyLogoSurface();
        return false;
    }
    old_logo_dib_ = SelectObject(logo_dc_, logo_dib_);
    if (!old_logo_dib_ || old_logo_dib_ == HGDI_ERROR) {
        old_logo_dib_ = nullptr;
        destroyLogoSurface();
        return false;
    }
    logo_width_ = static_cast<std::int32_t>(width);
    logo_height_ = static_cast<std::int32_t>(height);
    std::int32_t stride = 0;
    std::int32_t buffer_size = 0;
    if (!safeMultiply(logo_width_, 4, stride)
        || !safeMultiply(stride, logo_height_, buffer_size)
        || FAILED(converter->CopyPixels(
            nullptr,
            static_cast<UINT>(stride),
            static_cast<UINT>(buffer_size),
            static_cast<BYTE*>(logo_bits_)))) {
        destroyLogoSurface();
        return false;
    }
    return true;
}

bool TaskbarWidgetWindow::loadPet(
    const zisla::core::PetLibraryEntry& entry) noexcept {
    const auto path = entry.sprite_file;
    if (path.empty()) {
        return false;
    }

    using ::Microsoft::WRL::ComPtr;
    ComPtr<IWICImagingFactory> factory;
    if (FAILED(CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&factory)))) {
        return false;
    }
    ComPtr<IWICBitmapDecoder> decoder;
    if (FAILED(factory->CreateDecoderFromFilename(
            path.c_str(),
            nullptr,
            GENERIC_READ,
            WICDecodeMetadataCacheOnDemand,
            &decoder))) {
        return false;
    }
    ComPtr<IWICBitmapFrameDecode> frame;
    if (FAILED(decoder->GetFrame(0, &frame))) {
        return false;
    }
    UINT width = 0;
    UINT height = 0;
    if (FAILED(frame->GetSize(&width, &height))
        || width == 0 || height == 0 || width > 8192 || height > 8192) {
        return false;
    }
    const auto frame_count = std::clamp(entry.manifest.frames, 1, 64);
    const auto frame_width = frame_count > 1
        ? entry.manifest.frame_width.value_or(0)
        : static_cast<int>(width);
    if (frame_width <= 0 || frame_width > static_cast<int>(width)
        || frame_count > static_cast<int>(width) / frame_width) {
        return false;
    }
    ComPtr<IWICFormatConverter> converter;
    if (FAILED(factory->CreateFormatConverter(&converter))
        || FAILED(converter->Initialize(
            frame.Get(),
            GUID_WICPixelFormat32bppPBGRA,
            WICBitmapDitherTypeNone,
            nullptr,
            0.0,
            WICBitmapPaletteTypeCustom))) {
        return false;
    }

    HDC screen_dc = GetDC(nullptr);
    if (!screen_dc) {
        return false;
    }
    pet_dc_ = CreateCompatibleDC(screen_dc);
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = static_cast<LONG>(width);
    info.bmiHeader.biHeight = -static_cast<LONG>(height);
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    pet_dib_ = pet_dc_ ? CreateDIBSection(
        pet_dc_, &info, DIB_RGB_COLORS, &pet_bits_, nullptr, 0) : nullptr;
    ReleaseDC(nullptr, screen_dc);
    if (!pet_dc_ || !pet_dib_ || !pet_bits_) {
        destroyPetSurface();
        return false;
    }
    old_pet_dib_ = SelectObject(pet_dc_, pet_dib_);
    if (!old_pet_dib_ || old_pet_dib_ == HGDI_ERROR) {
        old_pet_dib_ = nullptr;
        destroyPetSurface();
        return false;
    }
    pet_image_width_ = static_cast<std::int32_t>(width);
    pet_image_height_ = static_cast<std::int32_t>(height);
    pet_frame_width_ = frame_width;
    pet_frame_count_ = frame_count;
    pet_frame_interval_ms_ = static_cast<UINT>(std::clamp(
        static_cast<int>(std::lround(1000.0 / std::clamp(entry.manifest.fps, 1.0, 8.0))),
        125,
        1000));
    std::int32_t stride = 0;
    std::int32_t buffer_size = 0;
    if (!safeMultiply(pet_image_width_, 4, stride)
        || !safeMultiply(stride, pet_image_height_, buffer_size)
        || FAILED(converter->CopyPixels(
            nullptr,
            static_cast<UINT>(stride),
            static_cast<UINT>(buffer_size),
            static_cast<BYTE*>(pet_bits_)))) {
        destroyPetSurface();
        return false;
    }
    pet_sprite_path_ = path.wstring();
    return true;
}

bool TaskbarWidgetWindow::ensureTargetSurface(
    std::int32_t width,
    std::int32_t height) noexcept {
    if (width <= 0 || height <= 0) {
        return false;
    }
    if (target_dc_ && target_dib_ && target_bits_
        && target_width_ == width && target_height_ == height) {
        return true;
    }
    destroyTargetSurface();
    HDC screen_dc = GetDC(nullptr);
    if (!screen_dc) {
        return false;
    }
    target_dc_ = CreateCompatibleDC(screen_dc);
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    target_dib_ = target_dc_ ? CreateDIBSection(
        screen_dc, &info, DIB_RGB_COLORS, &target_bits_, nullptr, 0) : nullptr;
    ReleaseDC(nullptr, screen_dc);
    if (!target_dc_ || !target_dib_ || !target_bits_) {
        destroyTargetSurface();
        return false;
    }
    old_target_dib_ = SelectObject(target_dc_, target_dib_);
    if (!old_target_dib_ || old_target_dib_ == HGDI_ERROR) {
        old_target_dib_ = nullptr;
        destroyTargetSurface();
        return false;
    }
    target_width_ = width;
    target_height_ = height;
    return true;
}

void TaskbarWidgetWindow::destroyTargetSurface() noexcept {
    if (target_dc_ && old_target_dib_) {
        (void)SelectObject(target_dc_, old_target_dib_);
    }
    old_target_dib_ = nullptr;
    if (target_dib_) {
        (void)DeleteObject(target_dib_);
        target_dib_ = nullptr;
    }
    if (target_dc_) {
        (void)DeleteDC(target_dc_);
        target_dc_ = nullptr;
    }
    target_bits_ = nullptr;
    target_width_ = 0;
    target_height_ = 0;
}

void TaskbarWidgetWindow::destroyLogoSurface() noexcept {
    if (logo_dc_ && old_logo_dib_) {
        (void)SelectObject(logo_dc_, old_logo_dib_);
    }
    old_logo_dib_ = nullptr;
    if (logo_dib_) {
        (void)DeleteObject(logo_dib_);
        logo_dib_ = nullptr;
    }
    if (logo_dc_) {
        (void)DeleteDC(logo_dc_);
        logo_dc_ = nullptr;
    }
    logo_bits_ = nullptr;
    logo_width_ = 0;
    logo_height_ = 0;
}

void TaskbarWidgetWindow::destroyPetSurface() noexcept {
    stopPetTimer();
    if (pet_dc_ && old_pet_dib_) {
        (void)SelectObject(pet_dc_, old_pet_dib_);
    }
    old_pet_dib_ = nullptr;
    if (pet_dib_) {
        (void)DeleteObject(pet_dib_);
        pet_dib_ = nullptr;
    }
    if (pet_dc_) {
        (void)DeleteDC(pet_dc_);
        pet_dc_ = nullptr;
    }
    pet_bits_ = nullptr;
    pet_image_width_ = 0;
    pet_image_height_ = 0;
    pet_frame_width_ = 0;
    pet_frame_count_ = 1;
    pet_frame_interval_ms_ = 125;
    pet_sprite_path_.clear();
}

void TaskbarWidgetWindow::updatePetTimer() noexcept {
    // Explorer-hosted layered child windows can deadlock during a timer-driven
    // alpha update. Keep the compact pet on its first frame so the taskbar
    // integration remains responsive.
    stopPetTimer();
}

void TaskbarWidgetWindow::stopPetTimer() noexcept {
    if (hwnd_) {
        (void)KillTimer(hwnd_, pet_timer_id);
    }
}

RECT TaskbarWidgetWindow::contentBounds() const noexcept {
    RECT result{0, 0, target_width_, target_height_};
    if (!pet_active_) {
        return result;
    }
    const auto slot = petSlotSize();
    const bool horizontal = edge_ == zisla::core::TaskbarEdge::top
        || edge_ == zisla::core::TaskbarEdge::bottom;
    if (horizontal) {
        if (pet_side_ == zisla::core::PetSide::left) {
            result.left = std::min<LONG>(result.right, static_cast<LONG>(slot));
        } else {
            result.right = std::max<LONG>(result.left, result.right - static_cast<LONG>(slot));
        }
    } else if (pet_side_ == zisla::core::PetSide::left) {
        result.top = std::min<LONG>(result.bottom, static_cast<LONG>(slot));
    } else {
        result.bottom = std::max<LONG>(result.top, result.bottom - static_cast<LONG>(slot));
    }
    return result;
}

std::int32_t TaskbarWidgetWindow::petSlotSize() const noexcept {
    const bool horizontal = edge_ == zisla::core::TaskbarEdge::top
        || edge_ == zisla::core::TaskbarEdge::bottom;
    const auto cross_size = horizontal ? target_height_ : target_width_;
    return std::clamp(cross_size * 28 / 36, 18, 28) + pet_gap_pixels;
}

}  // namespace winrt::Zisla
