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

void TaskbarWidgetContent::setNowPlaying(
    std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot) {
    media_active_ = snapshot && snapshot->valid()
        && snapshot->playback_status == zisla::core::MediaPlaybackStatus::playing;
    if (media_active_) {
        std::wstring text = to_hstring(snapshot->title).c_str();
        const auto artist = to_hstring(snapshot->artist);
        if (!artist.empty()) {
            if (!text.empty()) {
                text.append(L" · ");
            }
            text.append(artist.c_str(), artist.size());
        }
        if (text.empty()) {
            text = L"正在播放";
        }
        NowPlayingText().Text(hstring{text});
        Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
            OpenButton(),
            hstring{std::wstring{L"打开 Zisla，正在播放："}.append(text)});
    } else {
        NowPlayingText().Text(L"");
        Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
            OpenButton(),
            L"打开 Zisla");
    }
    updateLayout();
}

void TaskbarWidgetContent::setTaskbarEdge(zisla::core::TaskbarEdge edge) {
    if (edge_ == edge) {
        return;
    }
    edge_ = edge;
    updateLayout();
}

zisla::core::DipSize TaskbarWidgetContent::preferredSize() const noexcept {
    if (!media_active_) {
        return {36, 36};
    }
    const bool horizontal = edge_ == zisla::core::TaskbarEdge::top
        || edge_ == zisla::core::TaskbarEdge::bottom;
    return horizontal ? zisla::core::DipSize{176, 36} : zisla::core::DipSize{36, 176};
}

void TaskbarWidgetContent::updateLayout() {
    const auto size = preferredSize();
    const bool horizontal = edge_ == zisla::core::TaskbarEdge::top
        || edge_ == zisla::core::TaskbarEdge::bottom;
    Width(size.width);
    Height(size.height);
    OpenButton().Width(size.width);
    OpenButton().Height(size.height);
    LogoMark().Visibility(media_active_
        ? Microsoft::UI::Xaml::Visibility::Collapsed
        : Microsoft::UI::Xaml::Visibility::Visible);
    NowPlayingLayout().Visibility(media_active_
        ? Microsoft::UI::Xaml::Visibility::Visible
        : Microsoft::UI::Xaml::Visibility::Collapsed);
    NowPlayingLayout().Orientation(horizontal
        ? Microsoft::UI::Xaml::Controls::Orientation::Horizontal
        : Microsoft::UI::Xaml::Controls::Orientation::Vertical);
    NowPlayingText().Width(horizontal ? 150.0 : 36.0);
    NowPlayingText().MaxHeight(horizontal
        ? 36.0
        : 146.0);
    NowPlayingText().TextWrapping(horizontal
        ? Microsoft::UI::Xaml::TextWrapping::NoWrap
        : Microsoft::UI::Xaml::TextWrapping::Wrap);
    NowPlayingText().TextAlignment(horizontal
        ? Microsoft::UI::Xaml::TextAlignment::Left
        : Microsoft::UI::Xaml::TextAlignment::Center);
}

void TaskbarWidgetContent::OpenButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().openTaskbarWidget();
}

}
