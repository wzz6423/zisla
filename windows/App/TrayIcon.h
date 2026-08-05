#pragma once

#include <zisla/core/OverlayPlacementEngine.hpp>

#include <windows.h>
#include <shellapi.h>

#include <optional>

namespace winrt::Zisla {

class TrayIcon {
public:
    TrayIcon() = default;
    ~TrayIcon();

    TrayIcon(const TrayIcon&) = delete;
    TrayIcon& operator=(const TrayIcon&) = delete;

    [[nodiscard]] bool add(HWND owner, UINT callback_message) noexcept;
    [[nodiscard]] bool restore() noexcept;
    void remove() noexcept;
    [[nodiscard]] std::optional<zisla::core::PixelRect> bounds() const noexcept;

private:
    [[nodiscard]] bool addToShell() noexcept;

    NOTIFYICONDATAW data_{};
    HICON icon_{nullptr};
    bool owns_icon_{false};
    bool configured_{false};
};

}
