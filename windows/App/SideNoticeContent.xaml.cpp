#include "pch.h"
#include "SideNoticeContent.xaml.h"
#include "AppHost.h"

#include <algorithm>
#include <winrt/Windows.UI.Text.h>

#if __has_include("SideNoticeContent.g.cpp")
#include "SideNoticeContent.g.cpp"
#endif

namespace winrt::Zisla::implementation {
namespace {

hstring from_utf8(std::string_view value) {
    return value.empty() ? hstring{} : to_hstring(std::string(value));
}

hstring notice_glyph(zisla::core::NoticeKind kind) noexcept {
    switch (kind) {
    case zisla::core::NoticeKind::info: return L"\uE946";
    case zisla::core::NoticeKind::success: return L"\uE73E";
    case zisla::core::NoticeKind::warning: return L"\uE7BA";
    case zisla::core::NoticeKind::error: return L"\uEA39";
    }
    return L"\uE946";
}

hstring accessible_name(
    const zisla::core::IslandNotice& notice,
    std::size_t compact_count) {
    std::wstring value = from_utf8(notice.title).c_str();
    if (notice.detail && !notice.detail->empty()) {
        value.append(L"，");
        value.append(from_utf8(*notice.detail).c_str());
    }
    if (compact_count > 1) {
        value.append(L"，");
        value.append(std::to_wstring(compact_count));
        value.append(L" 项活动");
    }
    return hstring{value};
}

}

SideNoticeContent::SideNoticeContent() {
    InitializeComponent();
}

void SideNoticeContent::setOpaqueSurface(bool opaque) {
    try {
        const auto key = box_value(
            opaque ? L"OverlayOpaqueSurfaceBrush" : L"OverlaySurfaceBrush");
        const auto brush = Microsoft::UI::Xaml::Application::Current().Resources().Lookup(key)
            .try_as<Microsoft::UI::Xaml::Media::Brush>();
        if (brush) {
            Surface().Background(brush);
        }
    } catch (...) {
    }
}

void SideNoticeContent::setState(
    zisla::core::NoticeSide side,
    const zisla::core::SideNoticeViewState& state) {
    NoticeRows().Children().Clear();
    if (state.compact_notice) {
        NoticeRows().Children().Append(makeRow(
            *state.compact_notice,
            state.compact_count));
    }
    for (const auto& notice : state.ordinary_notices) {
        NoticeRows().Children().Append(makeRow(notice, 0));
    }
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        Surface(),
        side == zisla::core::NoticeSide::left
            ? L"左侧活动通知"
            : L"右侧活动通知");
}

Microsoft::UI::Xaml::Controls::Grid SideNoticeContent::makeRow(
    const zisla::core::IslandNotice& notice,
    std::size_t compact_count) {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    Grid row;
    row.Height(54);
    row.Padding(Thickness{10, 5, 6, 5});

    ColumnDefinition icon_column;
    icon_column.Width(GridLength{28, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(icon_column);
    ColumnDefinition text_column;
    text_column.Width(GridLength{1, GridUnitType::Star});
    row.ColumnDefinitions().Append(text_column);
    ColumnDefinition action_column;
    action_column.Width(GridLength{32, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(action_column);

    FontIcon icon;
    icon.Glyph(notice_glyph(notice.kind));
    icon.FontSize(15);
    icon.HorizontalAlignment(HorizontalAlignment::Left);
    icon.VerticalAlignment(VerticalAlignment::Center);
    row.Children().Append(icon);

    StackPanel text;
    text.Spacing(1);
    text.VerticalAlignment(VerticalAlignment::Center);
    Grid::SetColumn(text, 1);

    TextBlock title;
    title.Text(from_utf8(notice.title));
    title.FontSize(13);
    title.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    title.MaxLines(1);
    title.TextTrimming(TextTrimming::CharacterEllipsis);
    text.Children().Append(title);

    std::wstring detail;
    if (notice.detail && !notice.detail->empty()) {
        detail = from_utf8(*notice.detail).c_str();
    }
    if (compact_count > 1) {
        if (!detail.empty()) {
            detail.append(L" · ");
        }
        detail.append(std::to_wstring(compact_count));
        detail.append(L" 项活动");
    }
    if (!detail.empty()) {
        TextBlock secondary;
        secondary.Text(hstring{detail});
        secondary.FontSize(11);
        secondary.MaxLines(1);
        secondary.Opacity(0.68);
        secondary.TextTrimming(TextTrimming::CharacterEllipsis);
        text.Children().Append(secondary);
    }
    if (notice.progress) {
        ProgressBar progress;
        progress.Height(2);
        progress.Margin(Thickness{0, 2, 4, 0});
        progress.Minimum(0);
        progress.Maximum(1);
        progress.Value(std::clamp(*notice.progress, 0.0, 1.0));
        text.Children().Append(progress);
    }
    row.Children().Append(text);

    Button dismiss;
    dismiss.Width(28);
    dismiss.Height(28);
    dismiss.Padding(Thickness{});
    dismiss.HorizontalAlignment(HorizontalAlignment::Right);
    dismiss.VerticalAlignment(VerticalAlignment::Center);
    Grid::SetColumn(dismiss, 2);
    FontIcon close_icon;
    close_icon.FontSize(11);
    close_icon.Glyph(L"\uE8BB");
    dismiss.Content(close_icon);
    Automation::AutomationProperties::SetName(dismiss, L"关闭通知");
    ToolTipService::SetToolTip(dismiss, box_value(L"关闭"));
    const auto id = notice.id;
    dismiss.Click([id](
        Windows::Foundation::IInspectable const&,
        RoutedEventArgs const&) {
        AppHost::instance().dismissSideNotice(id);
    });
    row.Children().Append(dismiss);

    row.PointerEntered([id](
        Windows::Foundation::IInspectable const&,
        Input::PointerRoutedEventArgs const&) {
        AppHost::instance().setSideNoticeHovered(id, true);
    });
    row.PointerExited([id](
        Windows::Foundation::IInspectable const&,
        Input::PointerRoutedEventArgs const&) {
        AppHost::instance().setSideNoticeHovered(id, false);
    });
    Automation::AutomationProperties::SetName(
        row,
        accessible_name(notice, compact_count));
    return row;
}

}
