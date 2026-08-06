#include "pch.h"
#include "TrayIcon.h"
#include "resource.h"

#include <zisla/core/ApplicationIconTheme.hpp>

namespace winrt::Zisla {
namespace {

constexpr GUID tray_icon_guid{
    0x26d3546c,
    0x82d4,
    0x4e59,
    {0x9b, 0x4c, 0x3e, 0xc8, 0xc8, 0x87, 0x1e, 0x41},
};

bool systemUsesLightTheme() noexcept {
    DWORD value = 1;
    DWORD value_size = sizeof(value);
    const auto result = RegGetValueW(
        HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"SystemUsesLightTheme",
        RRF_RT_DWORD,
        nullptr,
        &value,
        &value_size);
    return result != ERROR_SUCCESS || value != 0;
}

int iconResourceForTheme(zisla::core::ApplicationIconTheme theme) noexcept {
    return theme == zisla::core::ApplicationIconTheme::night
        ? IDI_ZISLA_TRAY_NIGHT
        : IDI_ZISLA_TRAY_DAY;
}

HICON loadCurrentThemeIcon() noexcept {
    const auto icon_id = iconResourceForTheme(
        zisla::core::application_icon_theme(systemUsesLightTheme()));
    return static_cast<HICON>(LoadImageW(
        GetModuleHandleW(nullptr),
        MAKEINTRESOURCEW(icon_id),
        IMAGE_ICON,
        GetSystemMetrics(SM_CXSMICON),
        GetSystemMetrics(SM_CYSMICON),
        LR_DEFAULTCOLOR));
}

}

TrayIcon::~TrayIcon() {
    remove();
}

bool TrayIcon::add(HWND owner, UINT callback_message) noexcept {
    remove();
    if (!owner) {
        return false;
    }

    icon_ = loadCurrentThemeIcon();
    owns_icon_ = icon_ != nullptr;
    if (!icon_) {
        icon_ = LoadIconW(nullptr, IDI_APPLICATION);
    }

    data_ = {};
    data_.cbSize = sizeof(data_);
    data_.hWnd = owner;
    data_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_GUID | NIF_SHOWTIP;
    data_.uCallbackMessage = callback_message;
    data_.hIcon = icon_;
    data_.guidItem = tray_icon_guid;
    wcscpy_s(data_.szTip, L"Zisla");
    configured_ = true;
    return addToShell();
}

bool TrayIcon::addToShell() noexcept {
    if (!configured_ || !Shell_NotifyIconW(NIM_ADD, &data_)) {
        return false;
    }

    data_.uVersion = NOTIFYICON_VERSION_4;
    return Shell_NotifyIconW(NIM_SETVERSION, &data_) != FALSE;
}

bool TrayIcon::restore() noexcept {
    return addToShell();
}

void TrayIcon::remove() noexcept {
    if (configured_) {
        Shell_NotifyIconW(NIM_DELETE, &data_);
    }
    if (owns_icon_ && icon_) {
        DestroyIcon(icon_);
    }
    data_ = {};
    icon_ = nullptr;
    owns_icon_ = false;
    configured_ = false;
}

std::optional<zisla::core::PixelRect> TrayIcon::bounds() const noexcept {
    if (!configured_) {
        return std::nullopt;
    }

    NOTIFYICONIDENTIFIER identifier{};
    identifier.cbSize = sizeof(identifier);
    identifier.hWnd = data_.hWnd;
    identifier.guidItem = tray_icon_guid;

    RECT rect{};
    if (FAILED(Shell_NotifyIconGetRect(&identifier, &rect))) {
        return std::nullopt;
    }

    return zisla::core::PixelRect{
        rect.left,
        rect.top,
        rect.right - rect.left,
        rect.bottom - rect.top,
    };
}

void TrayIcon::refreshTheme() noexcept {
    if (!configured_) {
        return;
    }

    HICON new_icon = loadCurrentThemeIcon();

    if (!new_icon) {
        return;
    }

    const auto old_icon = icon_;
    const bool owned_old_icon = owns_icon_;
    data_.hIcon = new_icon;
    if (!Shell_NotifyIconW(NIM_MODIFY, &data_)) {
        data_.hIcon = old_icon;
        DestroyIcon(new_icon);
        return;
    }

    icon_ = new_icon;
    owns_icon_ = true;
    if (owned_old_icon && old_icon) {
        DestroyIcon(old_icon);
    }
}

}
