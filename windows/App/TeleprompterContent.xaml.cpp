#include "pch.h"
#include "TeleprompterContent.xaml.h"
#include "AppHost.h"

#include <winrt/Windows.ApplicationModel.DataTransfer.h>

#include <cmath>

#if __has_include("TeleprompterContent.g.cpp")
#include "TeleprompterContent.g.cpp"
#endif

namespace winrt::Zisla::implementation {

TeleprompterContent::TeleprompterContent() {
    InitializeComponent();
}

void TeleprompterContent::setSnapshot(
    const zisla::core::TeleprompterSnapshot& snapshot) {
    updating_ = true;
    if (script_ != snapshot.script) {
        script_ = snapshot.script;
        ScriptText().Text(script_.empty() ? hstring{} : to_hstring(script_));
    }
    const auto visibility = script_.empty()
        ? Microsoft::UI::Xaml::Visibility::Visible
        : Microsoft::UI::Xaml::Visibility::Collapsed;
    EmptyIcon().Visibility(visibility);
    ScriptScroll().Visibility(script_.empty()
        ? Microsoft::UI::Xaml::Visibility::Collapsed
        : Microsoft::UI::Xaml::Visibility::Visible);
    PlayPauseButton().IsEnabled(!script_.empty());
    PlayPauseIcon().Glyph(snapshot.auto_scrolling ? L"\uE769" : L"\uE768");
    const auto action = snapshot.auto_scrolling
        ? L"暂停自动滚动"
        : L"开始自动滚动";
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        PlayPauseButton(),
        action);
    Microsoft::UI::Xaml::Controls::ToolTipService::SetToolTip(
        PlayPauseButton(),
        box_value(action));
    SpeedSlider().Value(snapshot.scroll_speed);
    SpeedText().Text(hstring{
        std::to_wstring(static_cast<int>(std::lround(snapshot.scroll_speed)))
        + L" px/s"});
    const auto vertical_offset = box_value(snapshot.scroll_offset)
        .as<Windows::Foundation::IReference<double>>();
    (void)ScriptScroll().ChangeView(nullptr, vertical_offset, nullptr, true);
    updating_ = false;
}

double TeleprompterContent::scrollableHeight() noexcept {
    try {
        return ScriptScroll().ScrollableHeight();
    } catch (...) {
        return 0.0;
    }
}

void TeleprompterContent::PlayPauseButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().toggleTeleprompterScrolling();
}

void TeleprompterContent::ResetButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().resetTeleprompter();
}

void TeleprompterContent::SpeedSlider_ValueChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const& args) {
    if (!updating_) {
        AppHost::instance().setTeleprompterSpeed(args.NewValue());
    }
}

winrt::fire_and_forget TeleprompterContent::PasteButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    try {
        const auto content = Windows::ApplicationModel::DataTransfer::Clipboard::GetContent();
        if (!content.Contains(
                Windows::ApplicationModel::DataTransfer::StandardDataFormats::Text())) {
            co_return;
        }
        const auto text = co_await content.GetTextAsync();
        AppHost::instance().setTeleprompterScript(to_string(text));
    } catch (...) {
    }
}

void TeleprompterContent::CloseButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().closeTeleprompter();
}

}
