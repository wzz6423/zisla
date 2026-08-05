#include "pch.h"
#include "AIAgentWorkspaceContent.xaml.h"

#include "AppHost.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string_view>
#include <utility>
#include <vector>

#if __has_include("AIAgentWorkspaceContent.g.cpp")
#include "AIAgentWorkspaceContent.g.cpp"
#endif

namespace winrt::Zisla::implementation {
namespace {

using Microsoft::UI::Xaml::Application;
using Microsoft::UI::Xaml::Controls::ComboBoxItem;
using Microsoft::UI::Xaml::Controls::ListViewItem;
using Microsoft::UI::Xaml::Controls::StackPanel;
using Microsoft::UI::Xaml::Controls::TextBlock;
using Microsoft::UI::Xaml::Visibility;

hstring from_utf8(std::string_view value) {
    return value.empty() ? hstring{} : to_hstring(std::string(value));
}

Microsoft::UI::Xaml::Media::Brush overlay_brush(hstring const& name) {
    return Application::Current().Resources().Lookup(box_value(name)).try_as<
        Microsoft::UI::Xaml::Media::Brush>();
}

std::string role_label(zisla::core::AgentWorkspaceMessageRole role) {
    switch (role) {
    case zisla::core::AgentWorkspaceMessageRole::system:
        return "系统";
    case zisla::core::AgentWorkspaceMessageRole::user:
        return "我";
    case zisla::core::AgentWorkspaceMessageRole::assistant:
        return "Agent";
    }
    return "消息";
}

std::string mode_label(zisla::core::AgentWorkspaceChatMode mode) {
    return mode == zisla::core::AgentWorkspaceChatMode::plan ? "计划" : "对话";
}

std::string execution_target_label(
    std::optional<zisla::core::AgentCLIKind> cli_kind) {
    if (!cli_kind) {
        return "API";
    }
    switch (*cli_kind) {
    case zisla::core::AgentCLIKind::claude: return "Claude CLI";
    case zisla::core::AgentCLIKind::codex: return "Codex CLI";
    case zisla::core::AgentCLIKind::gemini: return "Gemini CLI";
    case zisla::core::AgentCLIKind::grok: return "Grok CLI";
    case zisla::core::AgentCLIKind::opencode: return "OpenCode CLI";
    }
    return "CLI";
}

std::string protocol_label(zisla::core::AgentChannelProtocol protocol) {
    switch (protocol) {
    case zisla::core::AgentChannelProtocol::openai_compatible:
        return "OpenAI-compatible";
    case zisla::core::AgentChannelProtocol::anthropic_messages:
        return "Anthropic Messages";
    case zisla::core::AgentChannelProtocol::gemini_generate_content:
        return "Gemini generateContent";
    }
    return "API";
}

std::string balance_status_label(
    const std::optional<zisla::core::AgentBalanceProbe>& probe,
    const std::optional<zisla::core::AgentBalanceSnapshot>& balance) {
    if (!probe) {
        return {};
    }
    if (!balance) {
        return " · 余额待刷新";
    }
    if (balance->available) {
        return " · 余额已更新";
    }
    return balance->used ? " · 用量已更新" : " · 已刷新";
}

const zisla::core::AgentWorkspaceThread* selected_thread(
    const zisla::core::AIAgentWorkspaceState& state,
    const std::optional<std::string>& id) {
    if (!id) {
        return nullptr;
    }
    const auto found = std::find_if(
        state.threads.begin(),
        state.threads.end(),
        [id](const auto& thread) { return thread.id == *id; });
    return found == state.threads.end() ? nullptr : &*found;
}

std::string display_text(std::string_view value) {
    constexpr std::size_t maximum_display_bytes = 16 * 1024;
    if (value.size() <= maximum_display_bytes) {
        return std::string(value);
    }
    auto end = maximum_display_bytes;
    while (end > 0
        && (static_cast<unsigned char>(value[end]) & 0xC0U) == 0x80U) {
        --end;
    }
    return std::string(value.substr(0, end)) + "\n...";
}

std::string join_base_urls(const std::vector<std::string>& values) {
    std::string result;
    for (const auto& value : values) {
        if (!result.empty()) {
            result.push_back('\n');
        }
        result.append(value);
    }
    return result;
}

}  // namespace

AIAgentWorkspaceContent::AIAgentWorkspaceContent() {
    InitializeComponent();
    updateView();
}

void AIAgentWorkspaceContent::setSnapshot(
    std::shared_ptr<const AIAgentWorkspaceServiceSnapshot> snapshot) {
    snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const AIAgentWorkspaceServiceSnapshot>();
    if (snapshot_->preferred_thread_id) {
        selected_thread_id_ = snapshot_->preferred_thread_id;
    }
    updateView();
}

void AIAgentWorkspaceContent::updateView() {
    updating_ = true;
    const auto& threads = snapshot_->state.threads;
    const auto selected = selected_thread_id_
        && std::any_of(threads.begin(), threads.end(), [this](const auto& thread) {
            return thread.id == *selected_thread_id_;
        });
    if (!selected) {
        selected_thread_id_ = threads.empty()
            ? std::nullopt
            : std::optional<std::string>{threads.front().id};
    }

    ThreadList().Items().Clear();
    ThreadList().SelectedItem(nullptr);
    for (const auto& thread : threads) {
        ListViewItem item;
        item.Tag(box_value(from_utf8(thread.id)));
        StackPanel detail;
        detail.Spacing(1);
        TextBlock title;
        title.Foreground(overlay_brush(L"OverlayPrimaryTextBrush"));
        title.FontSize(11);
        title.Text(from_utf8(thread.title));
        title.TextTrimming(Microsoft::UI::Xaml::TextTrimming::CharacterEllipsis);
        detail.Children().Append(title);
        TextBlock metadata;
        metadata.Foreground(overlay_brush(L"OverlaySecondaryTextBrush"));
        metadata.FontSize(9);
        metadata.Text(from_utf8(
            mode_label(thread.mode) + " · " + execution_target_label(thread.cli_kind)));
        metadata.TextTrimming(Microsoft::UI::Xaml::TextTrimming::CharacterEllipsis);
        detail.Children().Append(metadata);
        item.Content(detail);
        ThreadList().Items().Append(item);
        if (selected_thread_id_ && thread.id == *selected_thread_id_) {
            ThreadList().SelectedItem(item);
        }
    }

    const auto* thread = selected_thread(snapshot_->state, selected_thread_id_);
    if (!creating_connection_ && !pending_new_connection_ && thread
        && !thread->cli_kind && thread->channel_id) {
        const auto found = std::find_if(
            snapshot_->connections.begin(),
            snapshot_->connections.end(),
            [thread](const auto& connection) {
                return connection.channel_id == *thread->channel_id;
            });
        if (found != snapshot_->connections.end()) {
            selectConnection(thread->channel_id);
        }
    }
    updateConnectionView();
    selectExecutionTarget(thread ? thread->cli_kind : std::nullopt);
    updateComposerAvailability();
    ThreadEmptyText().Visibility(threads.empty() ? Visibility::Visible : Visibility::Collapsed);
    WorkspaceErrorText().Text(from_utf8(snapshot_->error));
    WorkspaceErrorText().Visibility(snapshot_->error.empty()
        ? Visibility::Collapsed
        : Visibility::Visible);
    if (snapshot_->loading) {
        WorkspaceStatusText().Text(L"正在处理 AI Agent 请求");
    } else {
        WorkspaceStatusText().Text(hstring{
            L"本地保存 · " + std::to_wstring(threads.size()) + L" 个会话"});
    }
    updateMessages();
    updating_ = false;
}

void AIAgentWorkspaceContent::updateConnectionView() {
    if (pending_new_connection_ && !snapshot_->loading) {
        const auto created = std::find_if(
            snapshot_->connections.begin(),
            snapshot_->connections.end(),
            [this](const auto& connection) {
                return std::find(
                           pending_connection_ids_.begin(),
                           pending_connection_ids_.end(),
                           connection.channel_id)
                    == pending_connection_ids_.end();
            });
        if (created != snapshot_->connections.end()) {
            selectConnection(created->channel_id);
        } else if (!snapshot_->error.empty()) {
            pending_new_connection_ = false;
            pending_connection_ids_.clear();
        }
    }

    if (!creating_connection_ && !selectedConnection()) {
        if (snapshot_->preferred_connection_channel_id) {
            const auto preferred = std::find_if(
                snapshot_->connections.begin(),
                snapshot_->connections.end(),
                [this](const auto& connection) {
                    return connection.channel_id
                        == *snapshot_->preferred_connection_channel_id;
                });
            if (preferred != snapshot_->connections.end()) {
                selectConnection(preferred->channel_id);
            }
        }
        if (!selectedConnection() && !snapshot_->connections.empty()) {
            selectConnection(snapshot_->connections.front().channel_id);
        }
    }

    updateConnectionSelector();
    const auto* connection = selectedConnection();
    if (!connection_form_initialized_
        || populated_connection_channel_id_ != selected_connection_channel_id_) {
        populateConnectionForm(connection);
        populated_connection_channel_id_ = selected_connection_channel_id_;
        connection_form_initialized_ = true;
        ConnectionExpander().IsExpanded(!connection || !connection->is_configured);
    } else {
        updateModelCatalog(connection);
    }
    if (snapshot_->loading) {
        ConnectionStatusText().Text(L"正在处理请求");
    } else if (!connection && pending_new_connection_) {
        ConnectionStatusText().Text(L"正在保存新渠道");
    } else if (!connection && creating_connection_) {
        ConnectionStatusText().Text(L"新建渠道，保存后可用于会话");
    } else if (!connection) {
        ConnectionStatusText().Text(L"未配置可用渠道");
    } else if (!connection->is_configured) {
        ConnectionStatusText().Text(L"当前渠道没有可用 API Key");
    } else if (connection->has_stored_api_key) {
        ConnectionStatusText().Text(from_utf8(
            connection->name + " · " + protocol_label(connection->protocol)
            + " · " + connection->model + " · 优先级 "
            + std::to_string(connection->endpoint_priority) + " · 密钥已保存"
            + balance_status_label(connection->balance_probe, connection->balance)));
    } else {
        ConnectionStatusText().Text(from_utf8(
            connection->name + " · " + protocol_label(connection->protocol)
            + " · " + connection->model + " · 需要 API Key"));
    }
}

void AIAgentWorkspaceContent::updateConnectionSelector() {
    auto items = ConnectionSelectorBox().Items();
    items.Clear();
    std::int32_t selected_index = -1;
    for (std::size_t index = 0; index < snapshot_->connections.size(); ++index) {
        const auto& connection = snapshot_->connections[index];
        ComboBoxItem item;
        item.Tag(box_value(from_utf8(connection.channel_id)));
        item.Content(box_value(from_utf8(
            connection.name.empty() ? connection.channel_id : connection.name)));
        items.Append(item);
        if (selected_connection_channel_id_
            && connection.channel_id == *selected_connection_channel_id_) {
            selected_index = static_cast<std::int32_t>(index);
        }
    }
    ConnectionSelectorBox().SelectedIndex(selected_index);
}

void AIAgentWorkspaceContent::populateConnectionForm(
    const AIAgentAPIConnectionSummary* connection) {
    if (!connection) {
        resetConnectionForm();
        return;
    }
    ConnectionNameBox().Text(from_utf8(connection->name));
    selectConnectionProtocol(connection->protocol);
    ConnectionBaseUrlBox().Text(from_utf8(join_base_urls(connection->base_urls)));
    ConnectionModelBox().Text(from_utf8(connection->model));
    EndpointPriorityBox().Value(static_cast<double>(connection->endpoint_priority));
    ConnectionApiKeyBox().Password(L"");
    selectBalanceProbe(connection->balance_probe);
    updateModelCatalog(connection);
}

void AIAgentWorkspaceContent::updateModelCatalog(
    const AIAgentAPIConnectionSummary* connection) {
    auto items = ModelCatalogBox().Items();
    items.Clear();
    if (!connection) {
        ModelCatalogBox().SelectedIndex(-1);
        return;
    }

    auto models = connection->model_catalog;
    if (!connection->model.empty()
        && std::find(models.begin(), models.end(), connection->model) == models.end()) {
        models.insert(models.begin(), connection->model);
    }
    const auto selected_model = to_string(ConnectionModelBox().Text());
    std::int32_t selected_index = -1;
    for (std::size_t index = 0; index < models.size(); ++index) {
        ComboBoxItem item;
        item.Tag(box_value(from_utf8(models[index])));
        item.Content(box_value(from_utf8(models[index])));
        items.Append(item);
        if (models[index] == selected_model) {
            selected_index = static_cast<std::int32_t>(index);
        }
    }
    ModelCatalogBox().SelectedIndex(selected_index);
}

void AIAgentWorkspaceContent::resetConnectionForm() {
    ConnectionNameBox().Text(L"AI API");
    selectConnectionProtocol(zisla::core::AgentChannelProtocol::openai_compatible);
    ConnectionBaseUrlBox().Text(L"");
    ConnectionModelBox().Text(L"");
    EndpointPriorityBox().Value(0.0);
    ConnectionApiKeyBox().Password(L"");
    selectBalanceProbe(std::nullopt);
    updateModelCatalog(nullptr);
}

void AIAgentWorkspaceContent::updateComposerAvailability() {
    const bool busy = snapshot_->loading;
    const auto cli_kind = selectedCLIKind();
    const auto* connection = selectedConnection();
    const bool has_thread = selected_thread_id_.has_value();
    const bool can_submit = !busy && has_thread
        && (cli_kind.has_value()
            || (connection && connection->is_configured
                && connection->has_stored_api_key));
    NewThreadButton().IsEnabled(!busy);
    RemoveThreadButton().IsEnabled(!busy && has_thread);
    ComposerBox().IsEnabled(can_submit);
    SendButton().IsEnabled(can_submit);
    ExecutionTargetBox().IsEnabled(!busy);
    CancelRequestButton().IsEnabled(snapshot_->can_cancel);
    CancelRequestButton().Visibility(snapshot_->can_cancel
        ? Visibility::Visible
        : Visibility::Collapsed);
    ThreadList().IsEnabled(!busy);
    ConnectionSelectorBox().IsEnabled(!busy && !snapshot_->connections.empty());
    NewConnectionButton().IsEnabled(!busy);
    RemoveConnectionButton().IsEnabled(!busy && connection != nullptr);
    ConnectionNameBox().IsEnabled(!busy);
    ConnectionProtocolBox().IsEnabled(!busy);
    ConnectionBaseUrlBox().IsEnabled(!busy);
    ConnectionModelBox().IsEnabled(!busy);
    ModelCatalogBox().IsEnabled(!busy && connection
        && !connection->model_catalog.empty());
    EndpointPriorityBox().IsEnabled(!busy);
    ConnectionApiKeyBox().IsEnabled(!busy);
    BalanceProbeBox().IsEnabled(!busy);
    SaveConnectionButton().IsEnabled(!busy);
    const bool can_refresh_connection = !busy && connection && connection->is_configured
        && connection->has_stored_api_key;
    RefreshModelsButton().IsEnabled(can_refresh_connection
        && !connection->channel_id.empty());
    RefreshBalanceButton().IsEnabled(can_refresh_connection
        && !connection->account_id.empty()
        && connection->balance_probe.has_value());
    if (can_submit) {
        ComposerBox().PlaceholderText(L"输入消息");
    } else if (busy) {
        ComposerBox().PlaceholderText(L"正在处理 AI Agent 请求");
    } else if (!has_thread) {
        ComposerBox().PlaceholderText(L"选择或新建一个会话");
    } else {
        ComposerBox().PlaceholderText(L"选择或配置一个 AI API 渠道");
    }
}

void AIAgentWorkspaceContent::selectConnection(
    std::optional<std::string> channel_id) {
    if (channel_id && channel_id->empty()) {
        channel_id.reset();
    }
    if (selected_connection_channel_id_ == channel_id && !creating_connection_) {
        return;
    }
    selected_connection_channel_id_ = std::move(channel_id);
    creating_connection_ = false;
    pending_new_connection_ = false;
    pending_connection_ids_.clear();
    connection_form_initialized_ = false;
}

const AIAgentAPIConnectionSummary* AIAgentWorkspaceContent::selectedConnection() const {
    if (!selected_connection_channel_id_) {
        return nullptr;
    }
    const auto found = std::find_if(
        snapshot_->connections.begin(),
        snapshot_->connections.end(),
        [this](const auto& connection) {
            return connection.channel_id == *selected_connection_channel_id_;
        });
    return found == snapshot_->connections.end() ? nullptr : &*found;
}

std::optional<std::string> AIAgentWorkspaceContent::selectedConnectionChannelId() const {
    const auto* connection = selectedConnection();
    if (!connection || connection->channel_id.empty()) {
        return std::nullopt;
    }
    return connection->channel_id;
}

std::string AIAgentWorkspaceContent::endpointPriority() const {
    const auto value = EndpointPriorityBox().Value();
    if (!std::isfinite(value) || std::trunc(value) != value
        || value < -99.0 || value > 99.0) {
        return "invalid";
    }
    return std::to_string(static_cast<int>(value));
}

void AIAgentWorkspaceContent::selectExecutionTarget(
    std::optional<zisla::core::AgentCLIKind> cli_kind) {
    const auto desired = cli_kind
        ? std::string(zisla::core::agent_cli_kind_token(*cli_kind))
        : std::string{"api"};
    const auto items = ExecutionTargetBox().Items();
    for (std::uint32_t index = 0; index < items.Size(); ++index) {
        const auto item = items.GetAt(index).try_as<ComboBoxItem>();
        if (item && to_string(unbox_value_or<hstring>(item.Tag(), L"")) == desired) {
            ExecutionTargetBox().SelectedIndex(static_cast<std::int32_t>(index));
            return;
        }
    }
    ExecutionTargetBox().SelectedIndex(0);
}

void AIAgentWorkspaceContent::selectConnectionProtocol(
    zisla::core::AgentChannelProtocol protocol) {
    const auto desired = zisla::core::agent_channel_protocol_token(protocol);
    const auto items = ConnectionProtocolBox().Items();
    for (std::uint32_t index = 0; index < items.Size(); ++index) {
        const auto item = items.GetAt(index).try_as<ComboBoxItem>();
        if (item && to_string(unbox_value_or<hstring>(item.Tag(), L"")) == desired) {
            ConnectionProtocolBox().SelectedIndex(static_cast<std::int32_t>(index));
            return;
        }
    }
    ConnectionProtocolBox().SelectedIndex(0);
}

void AIAgentWorkspaceContent::selectBalanceProbe(
    std::optional<zisla::core::AgentBalanceProbe> probe) {
    const auto desired = probe
        ? std::string(zisla::core::agent_balance_probe_kind_token(probe->kind))
        : std::string{"none"};
    const auto items = BalanceProbeBox().Items();
    for (std::uint32_t index = 0; index < items.Size(); ++index) {
        const auto item = items.GetAt(index).try_as<ComboBoxItem>();
        if (item && to_string(unbox_value_or<hstring>(item.Tag(), L"")) == desired) {
            BalanceProbeBox().SelectedIndex(static_cast<std::int32_t>(index));
            return;
        }
    }
    BalanceProbeBox().SelectedIndex(0);
}

std::optional<zisla::core::AgentCLIKind> AIAgentWorkspaceContent::selectedCLIKind() {
    const auto item = ExecutionTargetBox().SelectedItem().try_as<ComboBoxItem>();
    if (!item) {
        return std::nullopt;
    }
    const auto token = to_string(unbox_value_or<hstring>(item.Tag(), L"api"));
    return token == "api" ? std::nullopt : zisla::core::parse_agent_cli_kind(token);
}

std::optional<zisla::core::AgentChannelProtocol>
AIAgentWorkspaceContent::selectedConnectionProtocol() {
    const auto item = ConnectionProtocolBox().SelectedItem().try_as<ComboBoxItem>();
    if (!item) {
        return std::nullopt;
    }
    return zisla::core::parse_agent_channel_protocol(
        to_string(unbox_value_or<hstring>(item.Tag(), L"")));
}

std::optional<zisla::core::AgentBalanceProbe>
AIAgentWorkspaceContent::selectedBalanceProbe() {
    const auto item = BalanceProbeBox().SelectedItem().try_as<ComboBoxItem>();
    if (!item) {
        return std::nullopt;
    }
    const auto token = to_string(unbox_value_or<hstring>(item.Tag(), L"none"));
    if (token == "none") {
        return std::nullopt;
    }
    const auto kind = zisla::core::parse_agent_balance_probe_kind(token);
    return kind ? std::optional<zisla::core::AgentBalanceProbe>{
                      zisla::core::AgentBalanceProbe{*kind}}
                : std::nullopt;
}

void AIAgentWorkspaceContent::updateMessages() {
    MessageRows().Children().Clear();
    if (!selected_thread_id_) {
        MessageEmptyText().Text(L"选择或新建一个会话");
        MessageEmptyText().Visibility(Visibility::Visible);
        return;
    }

    bool has_messages = false;
    for (const auto& message : snapshot_->state.messages) {
        if (message.thread_id != *selected_thread_id_) {
            continue;
        }
        has_messages = true;
        StackPanel row;
        row.Spacing(2);
        TextBlock role;
        role.Foreground(overlay_brush(L"OverlaySecondaryTextBrush"));
        role.FontSize(9);
        role.Text(from_utf8(role_label(message.role) + " · " + mode_label(message.mode)));
        row.Children().Append(role);
        TextBlock content;
        content.Foreground(overlay_brush(L"OverlayPrimaryTextBrush"));
        content.FontSize(11);
        content.Text(from_utf8(display_text(message.content)));
        content.TextWrapping(Microsoft::UI::Xaml::TextWrapping::Wrap);
        row.Children().Append(content);
        if (!message.skill_references.empty()) {
            std::string skills{"Skill: "};
            for (std::size_t index = 0; index < message.skill_references.size(); ++index) {
                if (index > 0) {
                    skills.append(", ");
                }
                skills.append(message.skill_references[index].name);
            }
            TextBlock skill_names;
            skill_names.Foreground(overlay_brush(L"OverlayAccentBrush"));
            skill_names.FontSize(9);
            skill_names.Text(from_utf8(display_text(skills)));
            skill_names.TextTrimming(Microsoft::UI::Xaml::TextTrimming::CharacterEllipsis);
            row.Children().Append(skill_names);
        }
        MessageRows().Children().Append(row);
    }
    MessageEmptyText().Text(L"暂无消息");
    MessageEmptyText().Visibility(has_messages ? Visibility::Collapsed : Visibility::Visible);
}

void AIAgentWorkspaceContent::NewThreadButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().createAIAgentThread();
}

void AIAgentWorkspaceContent::RemoveThreadButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (selected_thread_id_) {
        AppHost::instance().removeAIAgentThread(*selected_thread_id_);
    }
}

void AIAgentWorkspaceContent::SendButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (!selected_thread_id_) {
        return;
    }
    const auto cli_kind = selectedCLIKind();
    const auto channel_id = cli_kind
        ? std::optional<std::string>{}
        : selectedConnectionChannelId();
    if (!cli_kind && !channel_id) {
        return;
    }
    const auto content = to_string(ComposerBox().Text());
    if (content.empty()) {
        return;
    }
    ComposerBox().Text(L"");
    AppHost::instance().submitAIAgentMessage(
        *selected_thread_id_,
        content,
        cli_kind,
        channel_id);
}

void AIAgentWorkspaceContent::CancelRequestButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    CancelRequestButton().IsEnabled(false);
    AppHost::instance().cancelAIAgentRequest();
}

void AIAgentWorkspaceContent::NewConnectionButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    selected_connection_channel_id_.reset();
    populated_connection_channel_id_.reset();
    connection_form_initialized_ = false;
    creating_connection_ = true;
    pending_new_connection_ = false;
    pending_connection_ids_.clear();
    updating_ = true;
    updateConnectionView();
    updateComposerAvailability();
    updating_ = false;
}

void AIAgentWorkspaceContent::RemoveConnectionButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto channel_id = selectedConnectionChannelId();
    if (!channel_id) {
        return;
    }
    selected_connection_channel_id_.reset();
    populated_connection_channel_id_.reset();
    connection_form_initialized_ = false;
    creating_connection_ = true;
    pending_new_connection_ = false;
    pending_connection_ids_.clear();
    updating_ = true;
    updateConnectionView();
    updateComposerAvailability();
    updating_ = false;
    AppHost::instance().removeAIAgentConnection(*channel_id);
}

void AIAgentWorkspaceContent::SaveConnectionButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    auto api_key = to_string(ConnectionApiKeyBox().Password());
    ConnectionApiKeyBox().Password(L"");
    const auto protocol = selectedConnectionProtocol();
    if (!protocol) {
        return;
    }
    const auto channel_id = selectedConnectionChannelId();
    if (!channel_id) {
        pending_new_connection_ = true;
        pending_connection_ids_.clear();
        pending_connection_ids_.reserve(snapshot_->connections.size());
        for (const auto& connection : snapshot_->connections) {
            pending_connection_ids_.push_back(connection.channel_id);
        }
    }
    AppHost::instance().configureAIAgentConnection(
        channel_id,
        *protocol,
        to_string(ConnectionNameBox().Text()),
        to_string(ConnectionBaseUrlBox().Text()),
        to_string(ConnectionModelBox().Text()),
        endpointPriority(),
        std::move(api_key),
        selectedBalanceProbe());
}

void AIAgentWorkspaceContent::RefreshModelsButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (const auto channel_id = selectedConnectionChannelId()) {
        AppHost::instance().refreshAIAgentChannelModels(*channel_id);
    }
}

void AIAgentWorkspaceContent::RefreshBalanceButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (const auto* connection = selectedConnection(); connection
        && !connection->account_id.empty()) {
        AppHost::instance().refreshAIAgentAccountBalance(connection->account_id);
    }
}

void AIAgentWorkspaceContent::ThreadList_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (updating_) {
        return;
    }
    const auto item = ThreadList().SelectedItem().try_as<ListViewItem>();
    if (!item) {
        return;
    }
    const auto id = unbox_value_or<hstring>(item.Tag(), L"");
    if (id.empty()) {
        return;
    }
    selected_thread_id_ = to_string(id);
    const auto* thread = selected_thread(snapshot_->state, selected_thread_id_);
    if (thread && !thread->cli_kind && thread->channel_id) {
        const auto found = std::find_if(
            snapshot_->connections.begin(),
            snapshot_->connections.end(),
            [thread](const auto& connection) {
                return connection.channel_id == *thread->channel_id;
            });
        if (found != snapshot_->connections.end()) {
            updating_ = true;
            selectConnection(thread->channel_id);
            updateConnectionView();
            updating_ = false;
        }
    }
    selectExecutionTarget(thread ? thread->cli_kind : std::nullopt);
    updateComposerAvailability();
    updateMessages();
}

void AIAgentWorkspaceContent::ExecutionTargetBox_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (!updating_) {
        updateComposerAvailability();
    }
}

void AIAgentWorkspaceContent::ConnectionSelectorBox_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (updating_) {
        return;
    }
    const auto item = ConnectionSelectorBox().SelectedItem().try_as<ComboBoxItem>();
    if (!item) {
        return;
    }
    const auto channel_id = unbox_value_or<hstring>(item.Tag(), L"");
    if (channel_id.empty()) {
        return;
    }
    updating_ = true;
    selectConnection(to_string(channel_id));
    updateConnectionView();
    updateComposerAvailability();
    updating_ = false;
}

void AIAgentWorkspaceContent::ModelCatalogBox_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (updating_) {
        return;
    }
    const auto item = ModelCatalogBox().SelectedItem().try_as<ComboBoxItem>();
    if (!item) {
        return;
    }
    const auto model = unbox_value_or<hstring>(item.Tag(), L"");
    if (!model.empty()) {
        ConnectionModelBox().Text(model);
    }
}

}
