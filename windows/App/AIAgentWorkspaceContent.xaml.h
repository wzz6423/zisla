#pragma once

#include "AIAgentWorkspaceContent.g.h"

#include "AIAgentWorkspaceService.h"

#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace winrt::Zisla::implementation {

struct AIAgentWorkspaceContent : AIAgentWorkspaceContentT<AIAgentWorkspaceContent> {
    AIAgentWorkspaceContent();

    void setSnapshot(std::shared_ptr<const AIAgentWorkspaceServiceSnapshot> snapshot);

    void NewThreadButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void RemoveThreadButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void SendButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void CancelRequestButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void NewConnectionButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void RemoveConnectionButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void SaveConnectionButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void RefreshModelsButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void RefreshBalanceButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ThreadList_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void ExecutionTargetBox_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void ConnectionSelectorBox_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void ModelCatalogBox_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);

private:
    void updateView();
    void updateConnectionView();
    void updateConnectionSelector();
    void populateConnectionForm(const AIAgentAPIConnectionSummary* connection);
    void updateModelCatalog(const AIAgentAPIConnectionSummary* connection);
    void resetConnectionForm();
    void updateMessages();
    void updateComposerAvailability();
    void selectExecutionTarget(std::optional<zisla::core::AgentCLIKind> cli_kind);
    void selectConnection(std::optional<std::string> channel_id);
    void selectConnectionProtocol(zisla::core::AgentChannelProtocol protocol);
    void selectBalanceProbe(std::optional<zisla::core::AgentBalanceProbe> probe);
    [[nodiscard]] const AIAgentAPIConnectionSummary* selectedConnection() const;
    [[nodiscard]] std::optional<std::string> selectedConnectionChannelId() const;
    [[nodiscard]] std::string endpointPriority();
    [[nodiscard]] std::optional<zisla::core::AgentCLIKind> selectedCLIKind();
    [[nodiscard]] std::optional<zisla::core::AgentChannelProtocol>
        selectedConnectionProtocol();
    [[nodiscard]] std::optional<zisla::core::AgentBalanceProbe> selectedBalanceProbe();

    std::shared_ptr<const AIAgentWorkspaceServiceSnapshot> snapshot_{
        std::make_shared<const AIAgentWorkspaceServiceSnapshot>()};
    std::optional<std::string> selected_thread_id_;
    std::optional<std::string> selected_connection_channel_id_;
    std::optional<std::string> populated_connection_channel_id_;
    bool connection_form_initialized_{false};
    bool creating_connection_{false};
    bool pending_new_connection_{false};
    std::vector<std::string> pending_connection_ids_;
    bool updating_{false};
};

}

namespace winrt::Zisla::factory_implementation {

struct AIAgentWorkspaceContent : AIAgentWorkspaceContentT<
    AIAgentWorkspaceContent,
    implementation::AIAgentWorkspaceContent> {};

}
