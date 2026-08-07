#pragma once

#include <zisla/core/AIModels.hpp>
#include <zisla/core/FeatureSettings.hpp>
#include <zisla/core/NowPlaying.hpp>
#include <zisla/core/OverlayPlacementEngine.hpp>
#include <zisla/core/Pet.hpp>

#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>

namespace winrt::Zisla {

class TaskbarWidgetWindow {
public:
    TaskbarWidgetWindow(HWND activation_target, UINT activation_message);
    ~TaskbarWidgetWindow();

    [[nodiscard]] bool show(const zisla::core::PixelRect& bounds);
    void hide() noexcept;
    void setNowPlaying(std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot);
    void setDockNotice(
        std::optional<zisla::core::IslandNotice> notice,
        std::size_t count);
    void setPet(
        std::optional<zisla::core::PetLibraryEntry> entry,
        zisla::core::PetSide side);
    void setTaskbarEdge(zisla::core::TaskbarEdge edge);
    void refreshBackdrop() noexcept;

    [[nodiscard]] zisla::core::DipSize preferredSize() const noexcept;

    [[nodiscard]] HWND hwnd() const noexcept;
    [[nodiscard]] bool visible() const noexcept;

private:
    static LRESULT CALLBACK windowProc(
        HWND hwnd,
        UINT message,
        WPARAM wparam,
        LPARAM lparam) noexcept;
    [[nodiscard]] static bool registerWindowClass() noexcept;

    void createWindow();
    [[nodiscard]] bool attachToTaskbar() noexcept;
    void render() noexcept;
    void drawLogo(COLORREF foreground) noexcept;
    void drawNowPlaying(COLORREF foreground) noexcept;
    void drawDockNotice(COLORREF foreground) noexcept;
    void drawPet() noexcept;
    void applyTextMaskColor(COLORREF foreground) noexcept;
    [[nodiscard]] bool loadLogo() noexcept;
    [[nodiscard]] bool loadPet(
        const zisla::core::PetLibraryEntry& entry) noexcept;
    [[nodiscard]] bool ensureTargetSurface(
        std::int32_t width,
        std::int32_t height) noexcept;
    void destroyTargetSurface() noexcept;
    void destroyLogoSurface() noexcept;
    void destroyPetSurface() noexcept;
    void updatePetTimer() noexcept;
    void stopPetTimer() noexcept;
    [[nodiscard]] RECT contentBounds() const noexcept;
    [[nodiscard]] std::int32_t petSlotSize() const noexcept;

    HWND hwnd_{nullptr};
    HWND taskbar_parent_{nullptr};
    HDC logo_dc_{nullptr};
    HBITMAP logo_dib_{nullptr};
    HGDIOBJ old_logo_dib_{nullptr};
    void* logo_bits_{nullptr};
    std::int32_t logo_width_{0};
    std::int32_t logo_height_{0};

    HDC pet_dc_{nullptr};
    HBITMAP pet_dib_{nullptr};
    HGDIOBJ old_pet_dib_{nullptr};
    void* pet_bits_{nullptr};
    std::int32_t pet_image_width_{0};
    std::int32_t pet_image_height_{0};
    std::int32_t pet_frame_width_{0};
    std::int32_t pet_frame_count_{1};
    UINT pet_frame_interval_ms_{125};
    std::wstring pet_sprite_path_;

    HDC target_dc_{nullptr};
    HBITMAP target_dib_{nullptr};
    HGDIOBJ old_target_dib_{nullptr};
    void* target_bits_{nullptr};
    std::int32_t target_width_{0};
    std::int32_t target_height_{0};

    zisla::core::PixelRect bounds_{};
    zisla::core::TaskbarEdge edge_{zisla::core::TaskbarEdge::bottom};
    std::wstring now_playing_text_;
    std::wstring dock_notice_text_;
    std::size_t dock_notice_count_{0};
    bool dock_notice_active_{false};
    bool media_active_{false};
    bool pet_active_{false};
    bool visible_{false};
    zisla::core::PetSide pet_side_{zisla::core::PetSide::right};
    HWND activation_target_{nullptr};
    UINT activation_message_{0};
};

}
