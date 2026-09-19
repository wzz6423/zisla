#include "pch.h"
#include "CleaningContent.xaml.h"
#include "AppHost.h"

#if __has_include("CleaningContent.g.cpp")
#include "CleaningContent.g.cpp"
#endif

namespace winrt::Zisla::implementation {

CleaningContent::CleaningContent() {
    InitializeComponent();
}

void CleaningContent::setMode(zisla::core::CleaningMode mode) {
    mode_ = mode;
    const bool keyboard = mode == zisla::core::CleaningMode::keyboard;
    ScreenLayout().Visibility(keyboard
        ? Microsoft::UI::Xaml::Visibility::Collapsed
        : Microsoft::UI::Xaml::Visibility::Visible);
    KeyboardLayout().Visibility(keyboard
        ? Microsoft::UI::Xaml::Visibility::Visible
        : Microsoft::UI::Xaml::Visibility::Collapsed);
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        Root(),
        keyboard ? L"键盘清洁中" : L"屏幕清洁中");
}

void CleaningContent::Root_Tapped(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Input::TappedRoutedEventArgs const&) {
    AppHost::instance().requestEndCleaning();
}

void CleaningContent::ExitButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().requestEndCleaning();
}

void CleaningContent::Root_KeyDown(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const& args) {
    if (mode_ == zisla::core::CleaningMode::keyboard) {
        args.Handled(true);
    }
}

void CleaningContent::Root_KeyUp(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const& args) {
    if (mode_ == zisla::core::CleaningMode::keyboard) {
        args.Handled(true);
    }
}

}
