#pragma once

#include "SettingsContent.g.h"
#include "MailService.h"
#include "UpdateService.h"

#include <winrt/Windows.ApplicationModel.h>

#include <cstdint>

namespace winrt::Zisla::implementation {

struct SettingsContent : SettingsContentT<SettingsContent> {
    SettingsContent();

    winrt::fire_and_forget refreshStartupTask();
    void setMailSnapshot(std::shared_ptr<const MailServiceSnapshot> snapshot);
    void setUpdateSnapshot(std::shared_ptr<const UpdateServiceSnapshot> snapshot);

    void Navigation_SelectionChanged(
        Microsoft::UI::Xaml::Controls::NavigationView const&,
        Microsoft::UI::Xaml::Controls::NavigationViewSelectionChangedEventArgs const& args);
    void TopEdgeToggle_Toggled(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void TaskbarWidgetToggle_Toggled(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void TaskbarWidgetPositionPicker_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    winrt::fire_and_forget StartupTaskToggle_Toggled(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget OpenStartupSettingsButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void SideNoticesToggle_Toggled(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void NotificationsMutedToggle_Toggled(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ClipboardHistoryToggle_Toggled(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ClipboardDetectionToggle_Toggled(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void WeatherToggle_Toggled(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void BrowserDownloadStatusToggle_Toggled(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void VoiceInputToggle_Toggled(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void VoiceHotkeyActionPicker_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void VoiceHotkeyPresetPicker_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void MailSaveButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void MailAuthorizeButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget MailOpenAuthorizationButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void UpdateChannelPicker_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void UpdateCheckButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void UpdateOpenButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);

private:
    void populateVoiceHotkeyControls();
    void populateMailControls();
    void populateUpdateControls();
    void saveMailSettings();
    [[nodiscard]] std::optional<zisla::core::UpdateChannel>
        selectedUpdateChannel();
    void applyStartupTaskState(Windows::ApplicationModel::StartupTaskState state);
    void applyStartupTaskError(hstring const& message);

    std::uint64_t startup_task_generation_{0};
    bool updating_startup_task_{false};
    bool updating_taskbar_widget_controls_{false};
    bool updating_voice_hotkey_controls_{false};
    bool updating_mail_controls_{false};
    bool updating_update_controls_{false};
    std::shared_ptr<const MailServiceSnapshot> mail_snapshot_;
    std::shared_ptr<const UpdateServiceSnapshot> update_snapshot_;
    hstring mail_verification_uri_;
};

}

namespace winrt::Zisla::factory_implementation {

struct SettingsContent : SettingsContentT<SettingsContent, implementation::SettingsContent> {};

}
