#pragma once

#include "AIAgentSkillsContent.g.h"

#include "AIAgentSkillsService.h"

#include <memory>

namespace winrt::Zisla::implementation {

struct AIAgentSkillsContent : AIAgentSkillsContentT<AIAgentSkillsContent> {
    AIAgentSkillsContent();

    void setSnapshot(std::shared_ptr<const AIAgentSkillsServiceSnapshot> snapshot);

    void OpenLibraryButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void RefreshButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void SynchronizeButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void SyncModeButton_Click(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void DestinationToggle_Toggled(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void SkillToggle_Toggled(
        Windows::Foundation::IInspectable const& sender,
        Microsoft::UI::Xaml::RoutedEventArgs const&);

private:
    void updateView();
    void updateDestination(
        const AIAgentSkillDestinationState& destination);
    void updateSkillRows();

    std::shared_ptr<const AIAgentSkillsServiceSnapshot> snapshot_{
        std::make_shared<const AIAgentSkillsServiceSnapshot>()};
    bool updating_{false};
};

}

namespace winrt::Zisla::factory_implementation {

struct AIAgentSkillsContent : AIAgentSkillsContentT<
    AIAgentSkillsContent,
    implementation::AIAgentSkillsContent> {};

}
