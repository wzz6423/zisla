#pragma once

#include "TaskbarWidgetContent.g.h"

namespace winrt::Zisla::implementation {

struct TaskbarWidgetContent : TaskbarWidgetContentT<TaskbarWidgetContent> {
    TaskbarWidgetContent();

    void setOpaqueSurface(bool opaque);

    void OpenButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
};

}

namespace winrt::Zisla::factory_implementation {

struct TaskbarWidgetContent : TaskbarWidgetContentT<
    TaskbarWidgetContent,
    implementation::TaskbarWidgetContent> {};

}
