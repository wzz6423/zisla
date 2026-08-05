#include "pch.h"
#include "AIAgentSkillsContent.xaml.h"

#include "AppHost.h"

#include <algorithm>
#include <string_view>
#include <utility>

#if __has_include("AIAgentSkillsContent.g.cpp")
#include "AIAgentSkillsContent.g.cpp"
#endif

namespace winrt::Zisla::implementation {
namespace {

using Microsoft::UI::Xaml::Controls::Grid;
using Microsoft::UI::Xaml::Controls::RadioButton;
using Microsoft::UI::Xaml::Controls::TextBlock;
using Microsoft::UI::Xaml::Controls::ToggleSwitch;
using Microsoft::UI::Xaml::Application;
using Microsoft::UI::Xaml::GridLengthHelper;
using Microsoft::UI::Xaml::Visibility;

hstring from_utf8(std::string_view value) {
    return value.empty() ? hstring{} : to_hstring(std::string(value));
}

hstring path_label(const std::filesystem::path& path) {
    return path.empty() ? hstring{L"不可用"} : hstring{path.c_str()};
}

std::string path_as_utf8(const std::filesystem::path& path) {
    const auto encoded = path.generic_u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size()};
}

std::optional<AIAgentSkillDestination> destination_from_tag(hstring const& tag) {
    if (tag == L"codex") {
        return AIAgentSkillDestination::codex;
    }
    if (tag == L"claude") {
        return AIAgentSkillDestination::claude;
    }
    if (tag == L"agents") {
        return AIAgentSkillDestination::agents;
    }
    return std::nullopt;
}

ToggleSwitch destination_toggle(
    AIAgentSkillsContent& content,
    AIAgentSkillDestination destination) {
    switch (destination) {
    case AIAgentSkillDestination::codex:
        return content.CodexDestinationToggle();
    case AIAgentSkillDestination::claude:
        return content.ClaudeDestinationToggle();
    case AIAgentSkillDestination::agents:
        return content.AgentsDestinationToggle();
    }
    return nullptr;
}

TextBlock destination_path_text(
    AIAgentSkillsContent& content,
    AIAgentSkillDestination destination) {
    switch (destination) {
    case AIAgentSkillDestination::codex:
        return content.CodexDestinationPathText();
    case AIAgentSkillDestination::claude:
        return content.ClaudeDestinationPathText();
    case AIAgentSkillDestination::agents:
        return content.AgentsDestinationPathText();
    }
    return nullptr;
}

}  // namespace

AIAgentSkillsContent::AIAgentSkillsContent() {
    InitializeComponent();
    updateView();
}

void AIAgentSkillsContent::setSnapshot(
    std::shared_ptr<const AIAgentSkillsServiceSnapshot> snapshot) {
    snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const AIAgentSkillsServiceSnapshot>();
    updateView();
}

void AIAgentSkillsContent::updateView() {
    updating_ = true;
    const bool is_copy_mode = snapshot_->mode
        == zisla::core::AgentSkillSynchronizationMode::file_copy;
    FileCopyModeButton().IsChecked(box_value(is_copy_mode));
    SymbolicLinkModeButton().IsChecked(box_value(!is_copy_mode));
    ManagedLibraryPathText().Text(path_label(snapshot_->managed_directory));
    for (const auto& destination : snapshot_->destinations) {
        updateDestination(destination);
    }

    const bool busy = snapshot_->loading || snapshot_->synchronizing;
    RefreshButton().IsEnabled(!busy);
    SynchronizeButton().IsEnabled(!busy);
    if (snapshot_->loading) {
        SkillsStatusText().Text(L"正在扫描 Skills");
    } else if (snapshot_->synchronizing) {
        SkillsStatusText().Text(L"正在同步 Skills");
    } else {
        SkillsStatusText().Text(hstring{
            L"已发现 " + std::to_wstring(snapshot_->skills.size()) + L" 个 Skill"});
    }
    SkillsErrorText().Text(from_utf8(snapshot_->error));
    SkillsErrorText().Visibility(snapshot_->error.empty()
        ? Visibility::Collapsed
        : Visibility::Visible);
    updateSkillRows();
    updating_ = false;
}

void AIAgentSkillsContent::updateDestination(
    const AIAgentSkillDestinationState& destination) {
    const auto toggle = destination_toggle(*this, destination.destination);
    const auto path = destination_path_text(*this, destination.destination);
    if (toggle) {
        toggle.IsOn(destination.enabled);
    }
    if (path) {
        path.Text(path_label(destination.path));
    }
}

void AIAgentSkillsContent::updateSkillRows() {
    SkillRows().Children().Clear();
    SkillsEmptyText().Visibility(snapshot_->skills.empty()
        ? Visibility::Visible
        : Visibility::Collapsed);
    for (const auto& skill : snapshot_->skills) {
        Grid row;
        row.Padding(Microsoft::UI::Xaml::Thickness{0, 2, 0, 2});
        row.ColumnDefinitions().Append(Microsoft::UI::Xaml::Controls::ColumnDefinition{});
        row.ColumnDefinitions().GetAt(0).Width(GridLengthHelper::Auto());
        row.ColumnDefinitions().Append(Microsoft::UI::Xaml::Controls::ColumnDefinition{});

        ToggleSwitch toggle;
        toggle.Width(42);
        toggle.VerticalAlignment(Microsoft::UI::Xaml::VerticalAlignment::Center);
        toggle.OnContent(box_value(L""));
        toggle.OffContent(box_value(L""));
        toggle.IsOn(skill.is_enabled);
        toggle.Tag(box_value(path_label(skill.path)));
        toggle.Toggled({this, &AIAgentSkillsContent::SkillToggle_Toggled});
        Microsoft::UI::Xaml::Controls::ToolTipService::SetToolTip(
            toggle,
            box_value(skill.is_enabled ? L"停用 Skill" : L"启用 Skill"));
        row.Children().Append(toggle);

        Microsoft::UI::Xaml::Controls::StackPanel detail;
        detail.Spacing(1);
        Grid::SetColumn(detail, 1);
        TextBlock name;
        name.Foreground(Application::Current().Resources().Lookup(
            box_value(L"OverlayPrimaryTextBrush")).try_as<
                Microsoft::UI::Xaml::Media::Brush>());
        name.FontSize(11);
        name.Text(from_utf8(skill.name));
        name.TextTrimming(Microsoft::UI::Xaml::TextTrimming::CharacterEllipsis);
        detail.Children().Append(name);
        TextBlock location;
        location.Foreground(Application::Current().Resources().Lookup(
            box_value(L"OverlaySecondaryTextBrush")).try_as<
                Microsoft::UI::Xaml::Media::Brush>());
        location.FontFamily(Microsoft::UI::Xaml::Media::FontFamily{L"Consolas"});
        location.FontSize(9);
        location.Text(from_utf8(skill.source + "  " + path_as_utf8(skill.path)));
        location.TextTrimming(Microsoft::UI::Xaml::TextTrimming::CharacterEllipsis);
        detail.Children().Append(location);
        row.Children().Append(detail);
        SkillRows().Children().Append(row);
    }
}

void AIAgentSkillsContent::OpenLibraryButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().openAIAgentSkillsLibrary();
}

void AIAgentSkillsContent::RefreshButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().reloadAIAgentSkills();
}

void AIAgentSkillsContent::SynchronizeButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().synchronizeAIAgentSkills();
}

void AIAgentSkillsContent::SyncModeButton_Click(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (updating_) {
        return;
    }
    const auto button = sender.try_as<RadioButton>();
    if (!button || !unbox_value_or<bool>(button.IsChecked(), false)) {
        return;
    }
    const auto tag = unbox_value_or<hstring>(button.Tag(), L"file-copy");
    AppHost::instance().setAIAgentSkillsSynchronizationMode(
        tag == L"symbolic-link"
            ? zisla::core::AgentSkillSynchronizationMode::symbolic_link
            : zisla::core::AgentSkillSynchronizationMode::file_copy);
}

void AIAgentSkillsContent::DestinationToggle_Toggled(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (updating_) {
        return;
    }
    const auto toggle = sender.try_as<ToggleSwitch>();
    if (!toggle) {
        return;
    }
    const auto destination = destination_from_tag(
        unbox_value_or<hstring>(toggle.Tag(), L""));
    if (destination) {
        AppHost::instance().setAIAgentSkillsDestinationEnabled(
            *destination,
            toggle.IsOn());
    }
}

void AIAgentSkillsContent::SkillToggle_Toggled(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (updating_) {
        return;
    }
    const auto toggle = sender.try_as<ToggleSwitch>();
    if (!toggle) {
        return;
    }
    const auto path = unbox_value_or<hstring>(toggle.Tag(), L"");
    if (!path.empty()) {
        AppHost::instance().setAIAgentSkillEnabled(
            std::filesystem::path{path.c_str()},
            toggle.IsOn());
    }
}

}
