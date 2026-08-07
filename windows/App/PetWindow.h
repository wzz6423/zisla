#pragma once

#include <zisla/core/Pet.hpp>
#include <zisla/core/OverlayPlacementEngine.hpp>

#include <windows.h>

#include <cstdint>
#include <memory>
#include <optional>

namespace winrt::Zisla {

class PetWindow {
public:
    PetWindow();
    ~PetWindow();

    PetWindow(const PetWindow&) = delete;
    PetWindow& operator=(const PetWindow&) = delete;

    [[nodiscard]] bool load(const zisla::core::PetLibraryEntry& entry) noexcept;

    void show(const zisla::core::PixelRect& bounds) noexcept;
    void hide() noexcept;

    void setActivity(std::optional<zisla::core::PetActivity> activity) noexcept;
    void refreshSystemPreferences() noexcept;

    [[nodiscard]] bool visible() const noexcept { return visible_; }
    [[nodiscard]] HWND hwnd() const noexcept { return hwnd_; }

private:
    static LRESULT CALLBACK windowProc(
        HWND hwnd,
        UINT message,
        WPARAM wParam,
        LPARAM lParam) noexcept;
    [[nodiscard]] static bool registerWindowClass() noexcept;

    void onCreate(HWND hwnd) noexcept;
    void onTimer() noexcept;
    void onNcHitTest(LPARAM lParam, LRESULT& result) noexcept;
    void onLeftButtonDown() noexcept;
    void render() noexcept;
    void updateTimerState() noexcept;
    void stopTimer() noexcept;

    [[nodiscard]] bool loadImage(const wchar_t* path) noexcept;
    [[nodiscard]] bool ensureTargetSurface(
        std::int32_t width,
        std::int32_t height) noexcept;
    void destroyTargetSurface() noexcept;
    [[nodiscard]] bool createLayeredWindow() noexcept;
    void cleanup() noexcept;

    [[nodiscard]] std::int64_t nowMs() const noexcept;
    [[nodiscard]] int currentFrameIndex() const noexcept;
    [[nodiscard]] double verticalOffset() const noexcept;

    HWND hwnd_{nullptr};
    HDC mem_dc_{nullptr};
    HBITMAP dib_{nullptr};
    HGDIOBJ old_dib_{nullptr};
    void* dib_bits_{nullptr};

    HDC target_dc_{nullptr};
    HBITMAP target_dib_{nullptr};
    HGDIOBJ old_target_dib_{nullptr};
    void* target_bits_{nullptr};
    std::int32_t target_width_{0};
    std::int32_t target_height_{0};

    std::int32_t image_width_{0};
    std::int32_t image_height_{0};
    std::int32_t frame_width_{0};
    int frame_count_{1};
    double fps_{6.0};

    zisla::core::PixelRect bounds_{};
    zisla::core::PetBehavior behavior_;

    bool visible_{false};
    bool animations_enabled_{true};
    bool timer_active_{false};
    std::int64_t animation_start_ms_{0};
};

}
