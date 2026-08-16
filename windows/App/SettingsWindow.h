#pragma once

#include "SettingsContent.xaml.h"
#include "MailService.h"
#include "UpdateService.h"

#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Xaml.h>

namespace winrt::Zisla {

class SettingsWindow {
public:
    SettingsWindow();
    ~SettingsWindow();

    void show();
    void hide() noexcept;
    void refreshBackdrop() noexcept;
    void setMail(std::shared_ptr<const MailServiceSnapshot> snapshot);
    void setUpdate(std::shared_ptr<const UpdateServiceSnapshot> snapshot);
    [[nodiscard]] HWND hwnd() const noexcept;

private:
    void createWindow();

    Microsoft::UI::Xaml::Window window_{nullptr};
    com_ptr<implementation::SettingsContent> content_;
    HWND hwnd_{nullptr};
    Microsoft::UI::Windowing::AppWindow app_window_{nullptr};
    winrt::event_token closing_token_{};
    winrt::event_token activated_token_{};
    bool closing_registered_{false};
    bool activated_registered_{false};
    bool destroying_{false};
};

}
