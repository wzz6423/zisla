#include "pch.h"
#include "SettingsContent.xaml.h"
#include "AppHost.h"

#include <zisla/core/VoiceHotkey.hpp>

#include <winrt/Windows.System.h>

#if __has_include("SettingsContent.g.cpp")
#include "SettingsContent.g.cpp"
#endif

namespace winrt::Zisla::implementation {
namespace {

constexpr wchar_t startup_task_id[] = L"ZislaStartup";

hstring startup_task_status(
    Windows::ApplicationModel::StartupTaskState state) {
    using Windows::ApplicationModel::StartupTaskState;
    switch (state) {
    case StartupTaskState::Disabled:
        return L"开机或登录后自动在后台运行";
    case StartupTaskState::DisabledByUser:
        return L"已在 Windows 设置中禁用，需要由你重新允许";
    case StartupTaskState::Enabled:
        return L"已在登录时自动启动";
    case StartupTaskState::DisabledByPolicy:
        return L"启动项已被系统策略禁用";
    case StartupTaskState::EnabledByPolicy:
        return L"启动项已由系统策略启用";
    }
    return L"无法读取启动项状态";
}

}

SettingsContent::SettingsContent() {
    InitializeComponent();
    TopEdgeToggle().IsOn(AppHost::instance().isTopEdgeEnabled());
    TaskbarWidgetToggle().IsOn(AppHost::instance().isTaskbarWidgetEnabled());
    populatePetControls();
    SideNoticesToggle().IsOn(AppHost::instance().areSideNoticesEnabled());
    NotificationsMutedToggle().IsOn(AppHost::instance().areNotificationsMuted());
    ClipboardHistoryToggle().IsOn(AppHost::instance().isClipboardHistoryEnabled());
    ClipboardDetectionToggle().IsOn(AppHost::instance().isClipboardDetectionEnabled());
    WeatherToggle().IsOn(AppHost::instance().isWeatherEnabled());
    BrowserDownloadStatusToggle().IsOn(
        AppHost::instance().isBrowserDownloadStatusEnabled());
    VoiceInputToggle().IsOn(AppHost::instance().isVoiceInputEnabled());
    populateVoiceHotkeyControls();
    populateMailControls();
    populateUpdateControls();
    setMailSnapshot(AppHost::instance().mailSnapshot());
    setUpdateSnapshot(AppHost::instance().updateSnapshot());
    refreshStartupTask();
}

void SettingsContent::populateMailControls() {
    updating_mail_controls_ = true;
    const auto& settings = AppHost::instance().mailConnectionSettings();
    MailTenantBox().Text(to_hstring(settings.tenant));
    MailClientIdBox().Text(to_hstring(settings.client_id));
    MailAccountNameBox().Text(to_hstring(settings.account_name));
    updating_mail_controls_ = false;
}

void SettingsContent::populateUpdateControls() {
    updating_update_controls_ = true;
    const auto token = zisla::core::update_channel_token(
        AppHost::instance().updateChannel());
    for (std::uint32_t index = 0; index < UpdateChannelPicker().Items().Size(); ++index) {
        const auto item = UpdateChannelPicker().Items().GetAt(index)
            .try_as<Microsoft::UI::Xaml::Controls::ComboBoxItem>();
        if (item && unbox_value_or<hstring>(item.Tag(), L"") == token) {
            UpdateChannelPicker().SelectedIndex(static_cast<std::int32_t>(index));
            break;
        }
    }
    updating_update_controls_ = false;
}

std::optional<zisla::core::UpdateChannel>
SettingsContent::selectedUpdateChannel() const {
    const auto item = UpdateChannelPicker().SelectedItem()
        .try_as<Microsoft::UI::Xaml::Controls::ComboBoxItem>();
    if (!item) {
        return std::nullopt;
    }
    return zisla::core::update_channel_from_token(to_string(
        unbox_value_or<hstring>(item.Tag(), L"")));
}

void SettingsContent::setMailSnapshot(
    std::shared_ptr<const MailServiceSnapshot> snapshot) {
    mail_snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const MailServiceSnapshot>();
    const auto& value = *mail_snapshot_;
    using Microsoft::UI::Xaml::Visibility;

    hstring status = value.message.empty() ? hstring{L"尚未连接"} : to_hstring(value.message);
    switch (value.phase) {
    case MailServicePhase::not_configured:
        if (value.message.empty()) {
            status = L"请填写 Microsoft Graph 客户端 ID";
        }
        break;
    case MailServicePhase::idle:
        break;
    case MailServicePhase::loading:
        status = value.message.empty() ? hstring{L"正在处理邮件"} : to_hstring(value.message);
        break;
    case MailServicePhase::authorization_required:
        status = value.message.empty() ? hstring{L"请完成 Microsoft 登录"} : to_hstring(value.message);
        break;
    case MailServicePhase::ready: {
        std::wstring connected = L"已连接 · ";
        connected.append(std::to_wstring(value.messages.size()));
        connected.append(L" 封邮件");
        status = hstring{connected};
        break;
    }
    case MailServicePhase::failed:
        status = value.message.empty() ? hstring{L"邮件服务失败"} : to_hstring(value.message);
        break;
    }
    MailStatusText().Text(status);
    MailAuthorizeButton().IsEnabled(!MailClientIdBox().Text().empty());

    const auto device = value.device_code;
    const bool has_device_code = device.has_value();
    MailVerificationCodeText().Visibility(
        has_device_code ? Visibility::Visible : Visibility::Collapsed);
    MailVerificationUriText().Visibility(
        has_device_code ? Visibility::Visible : Visibility::Collapsed);
    MailOpenAuthorizationButton().Visibility(
        has_device_code ? Visibility::Visible : Visibility::Collapsed);
    if (device) {
        std::wstring user_code = L"用户代码：";
        const auto code = to_hstring(device->user_code);
        user_code.append(code.c_str(), code.size());
        MailVerificationCodeText().Text(hstring{user_code});
        mail_verification_uri_ = to_hstring(device->verification_uri);
        std::wstring verification_uri = L"登录地址：";
        verification_uri.append(
            mail_verification_uri_.c_str(),
            mail_verification_uri_.size());
        MailVerificationUriText().Text(hstring{verification_uri});
    } else {
        mail_verification_uri_ = {};
        MailVerificationCodeText().Text(L"");
        MailVerificationUriText().Text(L"");
    }
}

void SettingsContent::setUpdateSnapshot(
    std::shared_ptr<const UpdateServiceSnapshot> snapshot) {
    update_snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const UpdateServiceSnapshot>();
    using Microsoft::UI::Xaml::Visibility;
    const auto& value = *update_snapshot_;
    updating_update_controls_ = true;
    const auto token = zisla::core::update_channel_token(value.channel);
    for (std::uint32_t index = 0; index < UpdateChannelPicker().Items().Size(); ++index) {
        const auto item = UpdateChannelPicker().Items().GetAt(index)
            .try_as<Microsoft::UI::Xaml::Controls::ComboBoxItem>();
        if (item && unbox_value_or<hstring>(item.Tag(), L"") == token) {
            UpdateChannelPicker().SelectedIndex(static_cast<std::int32_t>(index));
            break;
        }
    }
    updating_update_controls_ = false;

    hstring status = value.message.empty() ? hstring{L"尚未检查更新"} : to_hstring(value.message);
    switch (value.phase) {
    case UpdateServicePhase::idle:
        break;
    case UpdateServicePhase::checking:
        status = L"正在检查更新";
        break;
    case UpdateServicePhase::up_to_date:
        status = value.message.empty() ? hstring{L"当前已是最新版本"} : to_hstring(value.message);
        break;
    case UpdateServicePhase::available:
        if (value.update) {
            std::wstring available = L"发现 ";
            const auto tag = to_hstring(value.update->release.tag_name);
            available.append(tag.c_str(), tag.size());
            available.append(L" · ");
            const auto source = to_hstring(zisla::core::release_source_display_name(
                value.update->source));
            available.append(source.c_str(), source.size());
            status = hstring{available};
        }
        break;
    case UpdateServicePhase::failed:
        status = value.message.empty() ? hstring{L"更新检查失败"} : to_hstring(value.message);
        break;
    }
    UpdateStatusText().Text(status);
    UpdateCheckButton().IsEnabled(value.phase != UpdateServicePhase::checking);
    UpdateOpenButton().Visibility(
        value.phase == UpdateServicePhase::available && value.update
            ? Visibility::Visible
            : Visibility::Collapsed);
}

void SettingsContent::populatePetControls() {
    updating_pet_controls_ = true;
    const auto& host = AppHost::instance();
    const auto pets = host.availablePets();
    const bool enabled = host.isPetEnabled();

    PetToggle().IsOn(enabled);
    PetToggle().IsEnabled(!pets.empty());
    PetPicker().Items().Clear();

    std::int32_t selected_index = -1;
    for (std::size_t index = 0; index < pets.size(); ++index) {
        const auto& pet = pets[index];
        Microsoft::UI::Xaml::Controls::ComboBoxItem item;
        item.Content(box_value(to_hstring(
            pet.display_name.empty() ? pet.id : pet.display_name)));
        item.Tag(box_value(to_hstring(pet.id)));
        PetPicker().Items().Append(item);
        if (pet.id == host.petId()) {
            selected_index = static_cast<std::int32_t>(index);
        }
    }

    PetPicker().SelectedIndex(selected_index);
    PetPicker().IsEnabled(enabled && !pets.empty());
    PetSidePicker().SelectedIndex(
        host.petSide() == zisla::core::PetSide::left ? 0 : 1);
    PetSidePicker().IsEnabled(enabled && !pets.empty());
    updating_pet_controls_ = false;
}

winrt::fire_and_forget SettingsContent::refreshStartupTask() {
    const auto lifetime = get_strong();
    (void)lifetime;
    const auto generation = ++startup_task_generation_;
    StartupTaskToggle().IsEnabled(false);
    try {
        const auto task = co_await Windows::ApplicationModel::StartupTask::GetAsync(
            startup_task_id);
        if (generation == startup_task_generation_) {
            applyStartupTaskState(task.State());
        }
    } catch (const hresult_error& error) {
        if (generation == startup_task_generation_) {
            auto message = error.message();
            if (message.empty()) {
                message = L"无法读取启动项，请确认应用已通过 MSIX 安装";
            }
            applyStartupTaskError(message);
        }
    } catch (...) {
        if (generation == startup_task_generation_) {
            applyStartupTaskError(L"无法读取启动项，请确认应用已通过 MSIX 安装");
        }
    }
}

void SettingsContent::Navigation_SelectionChanged(
    Microsoft::UI::Xaml::Controls::NavigationView const&,
    Microsoft::UI::Xaml::Controls::NavigationViewSelectionChangedEventArgs const& args) {
    const auto item = args.SelectedItem().try_as<
        Microsoft::UI::Xaml::Controls::NavigationViewItem>();
    const auto tag = item
        ? unbox_value_or<hstring>(item.Tag(), L"general")
        : hstring{L"general"};
    const bool shows_about = tag == L"about";
    GeneralPage().Visibility(shows_about
        ? Microsoft::UI::Xaml::Visibility::Collapsed
        : Microsoft::UI::Xaml::Visibility::Visible);
    AboutPage().Visibility(shows_about
        ? Microsoft::UI::Xaml::Visibility::Visible
        : Microsoft::UI::Xaml::Visibility::Collapsed);
}

void SettingsContent::TopEdgeToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setTopEdgeEnabled(TopEdgeToggle().IsOn());
}

void SettingsContent::TaskbarWidgetToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setTaskbarWidgetEnabled(TaskbarWidgetToggle().IsOn());
}

void SettingsContent::PetToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (updating_pet_controls_) {
        return;
    }
    const bool enabled = PetToggle().IsOn();
    PetPicker().IsEnabled(enabled && PetPicker().Items().Size() > 0);
    PetSidePicker().IsEnabled(enabled && PetPicker().Items().Size() > 0);
    AppHost::instance().setPetEnabled(enabled);
}

void SettingsContent::PetPicker_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (updating_pet_controls_) {
        return;
    }
    const auto item = PetPicker().SelectedItem().try_as<
        Microsoft::UI::Xaml::Controls::ComboBoxItem>();
    if (!item) {
        return;
    }
    const auto id = unbox_value_or<hstring>(item.Tag(), L"");
    if (!id.empty()) {
        AppHost::instance().setPetId(to_string(id));
    }
}

void SettingsContent::PetSidePicker_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (updating_pet_controls_) {
        return;
    }
    const auto item = PetSidePicker().SelectedItem().try_as<
        Microsoft::UI::Xaml::Controls::ComboBoxItem>();
    if (!item) {
        return;
    }
    const auto side = unbox_value_or<hstring>(item.Tag(), L"right");
    AppHost::instance().setPetSide(
        side == L"left"
            ? zisla::core::PetSide::left
            : zisla::core::PetSide::right);
}

winrt::fire_and_forget SettingsContent::StartupTaskToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (updating_startup_task_) {
        co_return;
    }

    const auto lifetime = get_strong();
    (void)lifetime;
    const auto generation = ++startup_task_generation_;
    const bool enable = StartupTaskToggle().IsOn();
    StartupTaskToggle().IsEnabled(false);
    StartupTaskStatusText().Text(enable
        ? L"正在开启登录时启动"
        : L"正在关闭登录时启动");

    Windows::ApplicationModel::StartupTask task{nullptr};
    try {
        task = co_await Windows::ApplicationModel::StartupTask::GetAsync(
            startup_task_id);
        auto state = task.State();
        if (enable) {
            state = co_await task.RequestEnableAsync();
        } else {
            task.Disable();
            state = task.State();
        }
        if (generation == startup_task_generation_) {
            applyStartupTaskState(state);
        }
    } catch (const hresult_error& error) {
        if (generation == startup_task_generation_) {
            try {
                if (task) {
                    applyStartupTaskState(task.State());
                } else {
                    applyStartupTaskError(L"启动项不可用");
                }
            } catch (...) {
                applyStartupTaskError(L"启动项不可用");
            }
            const auto detail = error.message();
            if (detail.empty()) {
                StartupTaskStatusText().Text(enable
                    ? L"无法开启登录时启动"
                    : L"无法关闭登录时启动");
            } else {
                StartupTaskStatusText().Text(detail);
            }
        }
    } catch (...) {
        if (generation == startup_task_generation_) {
            try {
                if (task) {
                    applyStartupTaskState(task.State());
                } else {
                    applyStartupTaskError(L"启动项不可用");
                }
            } catch (...) {
                applyStartupTaskError(L"启动项不可用");
            }
            StartupTaskStatusText().Text(enable
                ? L"无法开启登录时启动"
                : L"无法关闭登录时启动");
        }
    }
}

winrt::fire_and_forget SettingsContent::OpenStartupSettingsButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    try {
        (void)co_await Windows::System::Launcher::LaunchUriAsync(
            Windows::Foundation::Uri{L"ms-settings:startupapps"});
    } catch (...) {
        StartupTaskStatusText().Text(L"无法打开 Windows 启动应用设置");
    }
}

void SettingsContent::SideNoticesToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setSideNoticesEnabled(SideNoticesToggle().IsOn());
}

void SettingsContent::NotificationsMutedToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setNotificationsMuted(NotificationsMutedToggle().IsOn());
}

void SettingsContent::ClipboardHistoryToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setClipboardHistoryEnabled(ClipboardHistoryToggle().IsOn());
}

void SettingsContent::ClipboardDetectionToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setClipboardDetectionEnabled(ClipboardDetectionToggle().IsOn());
}

void SettingsContent::WeatherToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setWeatherEnabled(WeatherToggle().IsOn());
}

void SettingsContent::BrowserDownloadStatusToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setBrowserDownloadStatusEnabled(
        BrowserDownloadStatusToggle().IsOn());
}

void SettingsContent::VoiceInputToggle_Toggled(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setVoiceInputEnabled(VoiceInputToggle().IsOn());
    populateVoiceHotkeyControls();
}

void SettingsContent::applyStartupTaskState(
    Windows::ApplicationModel::StartupTaskState state) {
    using Microsoft::UI::Xaml::Visibility;
    using Windows::ApplicationModel::StartupTaskState;

    const bool enabled = state == StartupTaskState::Enabled
        || state == StartupTaskState::EnabledByPolicy;
    const bool can_toggle = state == StartupTaskState::Disabled
        || state == StartupTaskState::Enabled;
    updating_startup_task_ = true;
    StartupTaskToggle().IsOn(enabled);
    StartupTaskToggle().IsEnabled(can_toggle);
    OpenStartupSettingsButton().Visibility(
        state == StartupTaskState::DisabledByUser
            ? Visibility::Visible
            : Visibility::Collapsed);
    StartupTaskStatusText().Text(startup_task_status(state));
    updating_startup_task_ = false;
}

void SettingsContent::applyStartupTaskError(hstring const& message) {
    updating_startup_task_ = true;
    StartupTaskToggle().IsOn(false);
    StartupTaskToggle().IsEnabled(false);
    OpenStartupSettingsButton().Visibility(
        Microsoft::UI::Xaml::Visibility::Collapsed);
    StartupTaskStatusText().Text(message);
    updating_startup_task_ = false;
}

void SettingsContent::populateVoiceHotkeyControls() {
    updating_voice_hotkey_controls_ = true;
    const auto& host = AppHost::instance();
    const bool enabled = host.isVoiceInputEnabled();

    const auto action = host.voiceHotkeyAction();
    const auto action_token = zisla::core::voice_hotkey_action_token(action);
    for (std::uint32_t i = 0; i < VoiceHotkeyActionPicker().Items().Size(); ++i) {
        const auto item = VoiceHotkeyActionPicker().Items().GetAt(i)
            .try_as<Microsoft::UI::Xaml::Controls::ComboBoxItem>();
        if (item) {
            const auto tag = unbox_value_or<hstring>(item.Tag(), L"");
            if (to_string(tag) == action_token) {
                VoiceHotkeyActionPicker().SelectedIndex(static_cast<std::int32_t>(i));
                break;
            }
        }
    }

    const auto preset = host.voiceHotkeyPreset();
    const auto preset_token = zisla::core::voice_hotkey_preset_token(preset);
    for (std::uint32_t i = 0; i < VoiceHotkeyPresetPicker().Items().Size(); ++i) {
        const auto item = VoiceHotkeyPresetPicker().Items().GetAt(i)
            .try_as<Microsoft::UI::Xaml::Controls::ComboBoxItem>();
        if (item) {
            const auto tag = unbox_value_or<hstring>(item.Tag(), L"");
            if (to_string(tag) == preset_token) {
                VoiceHotkeyPresetPicker().SelectedIndex(static_cast<std::int32_t>(i));
                break;
            }
        }
    }

    VoiceHotkeyActionPicker().IsEnabled(enabled);
    VoiceHotkeyPresetPicker().IsEnabled(enabled);
    VoiceHotkeyStatusText().Text(to_hstring(host.voiceHotkeyStatus()));
    updating_voice_hotkey_controls_ = false;
}

void SettingsContent::VoiceHotkeyActionPicker_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (updating_voice_hotkey_controls_) {
        return;
    }
    const auto selected = VoiceHotkeyActionPicker().SelectedItem()
        .try_as<Microsoft::UI::Xaml::Controls::ComboBoxItem>();
    if (!selected) {
        return;
    }
    const auto tag = unbox_value_or<hstring>(selected.Tag(), L"");
    const auto action = zisla::core::voice_hotkey_action_from_token(to_string(tag));
    if (action) {
        AppHost::instance().setVoiceHotkeyAction(*action);
        populateVoiceHotkeyControls();
    }
}

void SettingsContent::VoiceHotkeyPresetPicker_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (updating_voice_hotkey_controls_) {
        return;
    }
    const auto selected = VoiceHotkeyPresetPicker().SelectedItem()
        .try_as<Microsoft::UI::Xaml::Controls::ComboBoxItem>();
    if (!selected) {
        return;
    }
    const auto tag = unbox_value_or<hstring>(selected.Tag(), L"");
    const auto preset = zisla::core::voice_hotkey_preset_from_token(to_string(tag));
    if (preset) {
        AppHost::instance().setVoiceHotkeyPreset(*preset);
        populateVoiceHotkeyControls();
    }
}

void SettingsContent::MailSaveButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    saveMailSettings();
}

void SettingsContent::saveMailSettings() {
    auto tenant = to_string(MailTenantBox().Text());
    if (tenant.empty()) {
        tenant = "common";
        MailTenantBox().Text(L"common");
    }
    AppHost::instance().configureMail({
        .tenant = std::move(tenant),
        .client_id = to_string(MailClientIdBox().Text()),
        .account_name = to_string(MailAccountNameBox().Text()),
    });
}

void SettingsContent::MailAuthorizeButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    saveMailSettings();
    if (MailClientIdBox().Text().empty()) {
        MailStatusText().Text(L"请先填写 Microsoft Graph 客户端 ID");
        return;
    }
    AppHost::instance().beginMailAuthorization();
}

winrt::fire_and_forget SettingsContent::MailOpenAuthorizationButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    if (mail_verification_uri_.empty()) {
        co_return;
    }
    try {
        const auto opened = co_await Windows::System::Launcher::LaunchUriAsync(
            Windows::Foundation::Uri{mail_verification_uri_});
        if (!opened) {
            MailStatusText().Text(L"无法打开 Microsoft 登录页面");
        }
    } catch (...) {
        MailStatusText().Text(L"无法打开 Microsoft 登录页面");
    }
}

void SettingsContent::UpdateChannelPicker_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (updating_update_controls_) {
        return;
    }
    if (const auto channel = selectedUpdateChannel()) {
        AppHost::instance().checkForUpdates(*channel);
    }
}

void SettingsContent::UpdateCheckButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().checkForUpdates(
        selectedUpdateChannel().value_or(AppHost::instance().updateChannel()));
}

void SettingsContent::UpdateOpenButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().openAvailableUpdate();
}

}
