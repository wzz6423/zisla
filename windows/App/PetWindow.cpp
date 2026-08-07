#include "pch.h"
#include "PetWindow.h"

#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <numbers>

namespace winrt::Zisla {
namespace {

constexpr UINT_PTR timer_id = 1;
constexpr UINT timer_interval_ms = 33;
constexpr wchar_t window_class_name[] = L"ZislaPetWindow";

bool safeMultiply(std::int32_t a, std::int32_t b, std::int32_t& result) noexcept {
    if (a == 0 || b == 0) {
        result = 0;
        return true;
    }
    if (a > 0 && b > 0) {
        if (a > std::numeric_limits<std::int32_t>::max() / b) {
            return false;
        }
    } else if (a < 0 && b < 0) {
        if (a < std::numeric_limits<std::int32_t>::max() / b) {
            return false;
        }
    } else {
        if (a < 0) {
            if (a < std::numeric_limits<std::int32_t>::min() / b) {
                return false;
            }
        } else {
            if (b < std::numeric_limits<std::int32_t>::min() / a) {
                return false;
            }
        }
    }
    result = a * b;
    return true;
}

}  // namespace

bool PetWindow::registerWindowClass() noexcept {
    static bool registered = false;
    if (registered) {
        return true;
    }

    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = windowProc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.lpszClassName = window_class_name;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);

    if (!RegisterClassExW(&window_class)
        && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        return false;
    }
    registered = true;
    return true;
}

PetWindow::PetWindow() = default;

PetWindow::~PetWindow() {
    cleanup();
}

bool PetWindow::load(const zisla::core::PetLibraryEntry& entry) noexcept {
    cleanup();

    frame_count_ = std::max(1, entry.manifest.frames);
    fps_ = std::clamp(entry.manifest.fps, 1.0, 12.0);

    const auto sprite_path = entry.sprite_file.wstring();
    if (!loadImage(sprite_path.c_str())) {
        cleanup();
        return false;
    }

    if (frame_count_ > 1) {
        if (!entry.manifest.frame_width || *entry.manifest.frame_width <= 0) {
            cleanup();
            return false;
        }
        frame_width_ = *entry.manifest.frame_width;
        std::int32_t total_width = 0;
        if (!safeMultiply(frame_width_, frame_count_, total_width)
            || total_width > image_width_) {
            cleanup();
            return false;
        }
    } else {
        frame_width_ = image_width_;
    }

    if (!createLayeredWindow()) {
        cleanup();
        return false;
    }

    return true;
}

void PetWindow::show(const zisla::core::PixelRect& bounds) noexcept {
    if (!hwnd_ || bounds.width <= 0 || bounds.height <= 0) {
        return;
    }

    if (!ensureTargetSurface(bounds.width, bounds.height)) {
        hide();
        return;
    }

    bounds_ = bounds;
    animation_start_ms_ = nowMs();

    if (!SetWindowPos(
        hwnd_,
        HWND_TOPMOST,
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
        SWP_SHOWWINDOW | SWP_NOACTIVATE)) {
        hide();
        return;
    }

    visible_ = true;
    render();
    updateTimerState();
}

void PetWindow::hide() noexcept {
    if (!hwnd_) {
        return;
    }

    visible_ = false;
    stopTimer();
    ShowWindow(hwnd_, SW_HIDE);
}

void PetWindow::setActivity(std::optional<zisla::core::PetActivity> activity) noexcept {
    behavior_.set_activity(activity);
    updateTimerState();
    if (visible_) {
        render();
    }
}

void PetWindow::refreshSystemPreferences() noexcept {
    BOOL enabled = TRUE;
    SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &enabled, 0);
    const bool was_enabled = animations_enabled_;
    animations_enabled_ = enabled != FALSE;
    updateTimerState();
    if (visible_ && was_enabled && !animations_enabled_) {
        render();
    }
}

LRESULT CALLBACK PetWindow::windowProc(
    HWND hwnd,
    UINT message,
    WPARAM wParam,
    LPARAM lParam) noexcept {
    PetWindow* self = nullptr;

    if (message == WM_CREATE) {
        auto* cs = reinterpret_cast<CREATESTRUCTW*>(lParam);
        self = static_cast<PetWindow*>(cs->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        if (self) {
            self->onCreate(hwnd);
        }
        return 0;
    }

    self = reinterpret_cast<PetWindow*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (!self) {
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }

    switch (message) {
    case WM_TIMER:
        if (wParam == timer_id) {
            self->onTimer();
            return 0;
        }
        break;

    case WM_NCHITTEST: {
        LRESULT result = HTCLIENT;
        self->onNcHitTest(lParam, result);
        return result;
    }

    case WM_LBUTTONDOWN:
        self->onLeftButtonDown();
        return 0;

    case WM_DESTROY:
        self->stopTimer();
        return 0;
    }

    return DefWindowProcW(hwnd, message, wParam, lParam);
}

void PetWindow::onCreate(HWND hwnd) noexcept {
    hwnd_ = hwnd;
}

void PetWindow::onTimer() noexcept {
    const auto now = nowMs();
    behavior_.advance(now);
    render();
}

void PetWindow::onNcHitTest(LPARAM lParam, LRESULT& result) noexcept {
    if (!target_bits_ || target_width_ <= 0 || target_height_ <= 0) {
        result = HTTRANSPARENT;
        return;
    }

    const auto x = static_cast<std::int16_t>(LOWORD(lParam));
    const auto y = static_cast<std::int16_t>(HIWORD(lParam));

    POINT pt{x, y};
    if (!ScreenToClient(hwnd_, &pt)) {
        result = HTTRANSPARENT;
        return;
    }

    if (pt.x < 0 || pt.y < 0
        || pt.x >= target_width_ || pt.y >= target_height_) {
        result = HTTRANSPARENT;
        return;
    }

    std::int32_t pixel_offset = 0;
    if (!safeMultiply(pt.y, target_width_, pixel_offset)) {
        result = HTTRANSPARENT;
        return;
    }
    pixel_offset += pt.x;

    std::int32_t byte_offset = 0;
    if (!safeMultiply(pixel_offset, 4, byte_offset)) {
        result = HTTRANSPARENT;
        return;
    }

    const auto* pixels = static_cast<const std::uint8_t*>(target_bits_);
    const auto alpha = pixels[byte_offset + 3];

    result = alpha > 16 ? HTCLIENT : HTTRANSPARENT;
}

void PetWindow::onLeftButtonDown() noexcept {
    behavior_.handle_tap(nowMs());
    render();
    updateTimerState();
}

void PetWindow::render() noexcept {
    if (!hwnd_ || !dib_bits_ || frame_width_ <= 0 || image_height_ <= 0) {
        return;
    }

    if (bounds_.width <= 0 || bounds_.height <= 0) {
        return;
    }

    const auto frame_index = currentFrameIndex();
    std::int32_t src_x_offset = 0;
    if (!safeMultiply(frame_index, frame_width_, src_x_offset)
        || src_x_offset < 0
        || src_x_offset + frame_width_ > image_width_) {
        return;
    }

    if (!ensureTargetSurface(bounds_.width, bounds_.height)) {
        hide();
        return;
    }

    std::int32_t target_size = 0;
    if (!safeMultiply(target_width_, target_height_, target_size)) {
        return;
    }
    std::int32_t target_byte_size = 0;
    if (!safeMultiply(target_size, 4, target_byte_size)) {
        return;
    }
    std::memset(target_bits_, 0, static_cast<std::size_t>(target_byte_size));

    const auto scale = std::min(
        static_cast<double>(target_width_) / frame_width_,
        static_cast<double>(target_height_) / image_height_);
    if (!std::isfinite(scale) || scale <= 0.0) {
        return;
    }
    const auto draw_width = std::clamp(
        static_cast<std::int32_t>(std::lround(frame_width_ * scale)),
        1,
        target_width_);
    const auto draw_height = std::clamp(
        static_cast<std::int32_t>(std::lround(image_height_ * scale)),
        1,
        target_height_);
    const auto draw_x = (target_width_ - draw_width) / 2;
    const auto offset_pixels = static_cast<std::int32_t>(
        std::lround(verticalOffset() * draw_height));
    const auto draw_y = (target_height_ - draw_height) / 2 - offset_pixels;

    const auto* src = static_cast<const std::uint8_t*>(dib_bits_);
    auto* dst = static_cast<std::uint8_t*>(target_bits_);

    for (std::int32_t local_y = 0; local_y < draw_height; ++local_y) {
        const auto dst_y = draw_y + local_y;
        if (dst_y < 0 || dst_y >= target_height_) {
            continue;
        }
        const auto src_y = (local_y * image_height_) / draw_height;
        for (std::int32_t local_x = 0; local_x < draw_width; ++local_x) {
            const auto dst_x = draw_x + local_x;
            const auto src_x = src_x_offset
                + (local_x * frame_width_) / draw_width;

            std::int32_t src_pixel = 0;
            std::int32_t dst_pixel = 0;
            if (!safeMultiply(src_y, image_width_, src_pixel)
                || !safeMultiply(dst_y, target_width_, dst_pixel)) {
                continue;
            }
            src_pixel += src_x;
            dst_pixel += dst_x;

            std::int32_t src_byte = 0;
            std::int32_t dst_byte = 0;
            if (!safeMultiply(src_pixel, 4, src_byte)
                || !safeMultiply(dst_pixel, 4, dst_byte)) {
                continue;
            }
            std::memcpy(dst + dst_byte, src + src_byte, 4);
        }
    }

    HDC screen_dc = GetDC(nullptr);
    if (!screen_dc) {
        return;
    }

    POINT pt_src{0, 0};
    SIZE size_wnd{target_width_, target_height_};
    BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};

    if (!UpdateLayeredWindow(
        hwnd_,
        screen_dc,
        nullptr,
        &size_wnd,
        target_dc_,
        &pt_src,
        0,
        &blend,
        ULW_ALPHA)) {
        ReleaseDC(nullptr, screen_dc);
        hide();
        return;
    }

    ReleaseDC(nullptr, screen_dc);
}

void PetWindow::updateTimerState() noexcept {
    const bool should_animate = hwnd_ && visible_ && animations_enabled_;

    if (should_animate && !timer_active_) {
        if (SetTimer(hwnd_, timer_id, timer_interval_ms, nullptr)) {
            timer_active_ = true;
        }
    } else if (!should_animate && timer_active_) {
        stopTimer();
    }
}

void PetWindow::stopTimer() noexcept {
    if (timer_active_ && hwnd_) {
        KillTimer(hwnd_, timer_id);
        timer_active_ = false;
    }
}

bool PetWindow::loadImage(const wchar_t* path) noexcept {
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
            path,
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

    UINT width = 0, height = 0;
    if (FAILED(frame->GetSize(&width, &height))) {
        return false;
    }

    if (width == 0 || height == 0 || width > 8192 || height > 8192) {
        return false;
    }

    image_width_ = static_cast<std::int32_t>(width);
    image_height_ = static_cast<std::int32_t>(height);

    ComPtr<IWICFormatConverter> converter;
    if (FAILED(factory->CreateFormatConverter(&converter))) {
        return false;
    }

    if (FAILED(converter->Initialize(
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

    mem_dc_ = CreateCompatibleDC(screen_dc);
    if (!mem_dc_) {
        ReleaseDC(nullptr, screen_dc);
        return false;
    }

    BITMAPINFO bmi{};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = image_width_;
    bmi.bmiHeader.biHeight = -image_height_;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    dib_ = CreateDIBSection(
        mem_dc_,
        &bmi,
        DIB_RGB_COLORS,
        &dib_bits_,
        nullptr,
        0);

    ReleaseDC(nullptr, screen_dc);

    if (!dib_ || !dib_bits_) {
        return false;
    }

    old_dib_ = SelectObject(mem_dc_, dib_);
    if (!old_dib_ || old_dib_ == HGDI_ERROR) {
        old_dib_ = nullptr;
        return false;
    }

    std::int32_t stride = 0;
    if (!safeMultiply(image_width_, 4, stride)) {
        return false;
    }

    std::int32_t buffer_size = 0;
    if (!safeMultiply(stride, image_height_, buffer_size)) {
        return false;
    }

    if (FAILED(converter->CopyPixels(
            nullptr,
            static_cast<UINT>(stride),
            static_cast<UINT>(buffer_size),
            static_cast<BYTE*>(dib_bits_)))) {
        return false;
    }

    return true;
}

bool PetWindow::ensureTargetSurface(
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
    if (!target_dc_) {
        ReleaseDC(nullptr, screen_dc);
        return false;
    }

    BITMAPINFO bitmap_info{};
    bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bitmap_info.bmiHeader.biWidth = width;
    bitmap_info.bmiHeader.biHeight = -height;
    bitmap_info.bmiHeader.biPlanes = 1;
    bitmap_info.bmiHeader.biBitCount = 32;
    bitmap_info.bmiHeader.biCompression = BI_RGB;
    target_dib_ = CreateDIBSection(
        screen_dc,
        &bitmap_info,
        DIB_RGB_COLORS,
        &target_bits_,
        nullptr,
        0);
    ReleaseDC(nullptr, screen_dc);

    if (!target_dib_ || !target_bits_) {
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

void PetWindow::destroyTargetSurface() noexcept {
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

bool PetWindow::createLayeredWindow() noexcept {
    if (!PetWindow::registerWindowClass()) {
        return false;
    }

    hwnd_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_LAYERED,
        window_class_name,
        L"",
        WS_POPUP,
        0,
        0,
        1,
        1,
        nullptr,
        nullptr,
        GetModuleHandleW(nullptr),
        this);

    return hwnd_ != nullptr;
}

void PetWindow::cleanup() noexcept {
    stopTimer();

    if (hwnd_) {
        DestroyWindow(hwnd_);
        hwnd_ = nullptr;
    }

    destroyTargetSurface();
    if (mem_dc_ && old_dib_) {
        (void)SelectObject(mem_dc_, old_dib_);
    }
    old_dib_ = nullptr;
    if (dib_) {
        (void)DeleteObject(dib_);
        dib_ = nullptr;
    }
    if (mem_dc_) {
        (void)DeleteDC(mem_dc_);
        mem_dc_ = nullptr;
    }

    dib_bits_ = nullptr;
    image_width_ = 0;
    image_height_ = 0;
    frame_width_ = 0;
    frame_count_ = 1;
    fps_ = 6.0;
    bounds_ = {};
    visible_ = false;
    timer_active_ = false;
    animation_start_ms_ = 0;
}

std::int64_t PetWindow::nowMs() const noexcept {
    const auto now = std::chrono::steady_clock::now();
    const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch());
    return ms.count();
}

int PetWindow::currentFrameIndex() const noexcept {
    if (frame_count_ <= 1) {
        return 0;
    }

    const auto elapsed_ms = nowMs() - animation_start_ms_;
    if (elapsed_ms < 0) {
        return 0;
    }

    const auto frame_duration_ms = 1000.0 / fps_;
    const auto frame_index = static_cast<int>(elapsed_ms / frame_duration_ms) % frame_count_;
    return std::clamp(frame_index, 0, frame_count_ - 1);
}

double PetWindow::verticalOffset() const noexcept {
    if (frame_count_ > 1) {
        return 0.0;
    }

    if (!animations_enabled_) {
        return 0.0;
    }

    const auto profile = zisla::core::animation_profile_for(behavior_.activity());
    if (profile.period_ms <= 0 || profile.amplitude_ratio <= 0.0) {
        return 0.0;
    }

    const auto elapsed_ms = nowMs() - animation_start_ms_;
    if (elapsed_ms < 0) {
        return 0.0;
    }

    const auto phase = (2.0 * std::numbers::pi * elapsed_ms) / profile.period_ms;
    const auto breathe = std::sin(phase);
    return profile.amplitude_ratio * breathe;
}

}
