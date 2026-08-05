#include "pch.h"
#include "TaskbarWidgetContent.xaml.h"
#include "AppHost.h"

#if __has_include("TaskbarWidgetContent.g.cpp")
#include "TaskbarWidgetContent.g.cpp"
#endif

namespace winrt::Zisla::implementation {

TaskbarWidgetContent::TaskbarWidgetContent() {
    InitializeComponent();
}

void TaskbarWidgetContent::setOpaqueSurface(bool opaque) {
    try {
        const auto key = box_value(
            opaque ? L"OverlayOpaqueSurfaceBrush" : L"OverlaySurfaceBrush");
        const auto brush = Application::Current().Resources().Lookup(key)
            .try_as<Microsoft::UI::Xaml::Media::Brush>();
        if (brush) {
            SurfaceBorder().Background(brush);
        }
    } catch (...) {
    }
}

void TaskbarWidgetContent::OpenButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().openTaskbarWidget();
}

}
