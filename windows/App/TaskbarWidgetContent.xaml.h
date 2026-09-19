#pragma once

#include "TaskbarWidgetContent.g.h"

#include <zisla/core/NowPlaying.hpp>
#include <zisla/core/OverlayPlacementEngine.hpp>

#include <memory>

namespace winrt::Zisla::implementation {

struct TaskbarWidgetContent : TaskbarWidgetContentT<TaskbarWidgetContent> {
    TaskbarWidgetContent();

    void setNowPlaying(std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot);
    void setTaskbarEdge(zisla::core::TaskbarEdge edge);
    [[nodiscard]] zisla::core::DipSize preferredSize() const noexcept;

    void OpenButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);

private:
    void updateLayout();

    bool media_active_{false};
    zisla::core::TaskbarEdge edge_{zisla::core::TaskbarEdge::bottom};
};

}

namespace winrt::Zisla::factory_implementation {

struct TaskbarWidgetContent : TaskbarWidgetContentT<
    TaskbarWidgetContent,
    implementation::TaskbarWidgetContent> {};

}
