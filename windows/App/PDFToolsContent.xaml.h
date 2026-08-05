#pragma once

#include "PDFToolsContent.g.h"

#include "PDFProcessingService.hpp"

#include <zisla/core/PDFProcessing.hpp>

#include <cstddef>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace winrt::Zisla::implementation {

struct PDFToolsContent : PDFToolsContentT<PDFToolsContent> {
    PDFToolsContent();

    void setSnapshot(std::shared_ptr<const zisla::pdf::PDFProcessingSnapshot> snapshot);

    winrt::fire_and_forget ChooseInputsButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget ChooseOutputFolderButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    winrt::fire_and_forget ChooseWatermarkImageButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void OperationPicker_SelectionChanged(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&);
    void RunButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);
    void ResetButton_Click(
        Windows::Foundation::IInspectable const&,
        Microsoft::UI::Xaml::RoutedEventArgs const&);

private:
    void updateView();
    void updateOperationControls();
    void setManualStatus(hstring value);
    [[nodiscard]] zisla::pdf::PDFProcessingOperation selectedOperation() const;
    [[nodiscard]] std::optional<zisla::pdf::PDFProcessingRequest> makeRequest();
    [[nodiscard]] std::optional<std::vector<std::size_t>> selectedPages();
    [[nodiscard]] std::optional<std::vector<std::vector<std::size_t>>>
        splitPageGroups();
    [[nodiscard]] std::optional<std::vector<std::filesystem::path>> outputPaths(
        zisla::pdf::PDFProcessingOperation operation,
        std::size_t split_count);

    std::shared_ptr<const zisla::pdf::PDFProcessingSnapshot> snapshot_;
    std::vector<std::filesystem::path> inputs_;
    std::filesystem::path watermark_image_path_;
    std::filesystem::path output_directory_;
    std::optional<zisla::core::PDFDocumentSummary> inspected_summary_;
    hstring manual_status_{L"请选择 PDF 文件"};
    bool initialized_{false};
    bool picker_active_{false};
};

}

namespace winrt::Zisla::factory_implementation {

struct PDFToolsContent : PDFToolsContentT<
    PDFToolsContent,
    implementation::PDFToolsContent> {};

}
