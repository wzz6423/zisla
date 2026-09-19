#pragma once

#include <zisla/core/AIModels.hpp>
#include <zisla/core/NowPlaying.hpp>
#include <zisla/core/Pet.hpp>

#include <windows.h>

#include <cstddef>
#include <memory>
#include <optional>
#include <string>

struct ITaskbarList3;

namespace winrt::Zisla {

// Owns the app's normal Windows taskbar button. It never draws over Explorer.
class TaskbarButtonWindow {
public:
    TaskbarButtonWindow(
        HWND activation_target,
        UINT activation_message,
        UINT exit_message);
    ~TaskbarButtonWindow();

    TaskbarButtonWindow(const TaskbarButtonWindow&) = delete;
    TaskbarButtonWindow& operator=(const TaskbarButtonWindow&) = delete;

    void setEnabled(bool enabled) noexcept;
    void setNowPlaying(std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot);
    void setDockNotice(
        std::optional<zisla::core::IslandNotice> notice,
        std::size_t count);
    void setPet(std::optional<zisla::core::PetLibraryEntry> entry);
    void refreshAfterExplorerRestart() noexcept;

    [[nodiscard]] bool available() const noexcept;
    [[nodiscard]] bool enabled() const noexcept;

private:
    static LRESULT CALLBACK windowProc(
        HWND hwnd,
        UINT message,
        WPARAM wparam,
        LPARAM lparam) noexcept;
    [[nodiscard]] static bool registerWindowClass() noexcept;

    void createWindow() noexcept;
    void updateSystemMenu() noexcept;
    void postActivation() const noexcept;
    void postExit() const noexcept;
    void clearPetOverlay() noexcept;
    [[nodiscard]] bool ensureTaskbarList() noexcept;
    void updateTaskbarState() noexcept;
    [[nodiscard]] std::wstring taskbarText() const;
    void minimize() noexcept;
    void scheduleMinimize() noexcept;
    void showMinimized() noexcept;

    HWND hwnd_{nullptr};
    HWND activation_target_{nullptr};
    UINT activation_message_{0};
    UINT exit_message_{0};
    ITaskbarList3* taskbar_list_{nullptr};
    HICON pet_overlay_icon_{nullptr};
    std::shared_ptr<const zisla::core::NowPlayingSnapshot> now_playing_;
    std::wstring notice_text_;
    std::wstring pet_sprite_path_;
    bool showing_minimized_{false};
    bool enabled_{false};
};

}
