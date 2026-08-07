#include "pch.h"
#include "PDFToolsContent.xaml.h"

#include "AppHost.h"
#include "TransientUIHold.h"

#include <winrt/Windows.Storage.Pickers.h>

#include <algorithm>
#include <array>
#include <charconv>
#include <cmath>
#include <cwctype>
#include <span>
#include <string_view>
#include <system_error>

#if __has_include("PDFToolsContent.g.cpp")
#include "PDFToolsContent.g.cpp"
#endif

namespace winrt::Zisla::implementation {
namespace {

using zisla::core::PDFOutputValidationError;
using zisla::core::PDFPageSelectionError;
using zisla::core::PDFProcessing;
using zisla::pdf::PDFProcessingOperation;
using zisla::pdf::PDFProcessingPhase;

hstring fromUtf8(std::string_view value) {
    return value.empty() ? hstring{} : to_hstring(std::string(value));
}

hstring operationLabel(PDFProcessingOperation operation) {
    switch (operation) {
    case PDFProcessingOperation::inspect:
        return L"读取信息";
    case PDFProcessingOperation::read_metadata:
        return L"读取元数据";
    case PDFProcessingOperation::merge:
        return L"合并 PDF";
    case PDFProcessingOperation::export_pages:
        return L"导出页面";
    case PDFProcessingOperation::split:
        return L"拆分 PDF";
    case PDFProcessingOperation::rotate:
        return L"旋转页面";
    case PDFProcessingOperation::crop:
        return L"裁剪页面";
    case PDFProcessingOperation::update_metadata:
        return L"更新元数据";
    case PDFProcessingOperation::protect:
        return L"设置密码";
    case PDFProcessingOperation::unlock:
        return L"解除密码";
    case PDFProcessingOperation::export_text:
        return L"导出文字";
    case PDFProcessingOperation::render_pages:
        return L"渲染图片";
    case PDFProcessingOperation::images_to_pdf:
        return L"图片转 PDF";
    case PDFProcessingOperation::text_watermark:
        return L"添加文字水印";
    case PDFProcessingOperation::image_watermark:
        return L"添加图片水印";
    case PDFProcessingOperation::page_numbers:
        return L"添加页码";
    case PDFProcessingOperation::office_to_pdf:
        return L"Office 转 PDF";
    case PDFProcessingOperation::none:
        break;
    }
    return L"执行";
}

PDFProcessingOperation operationFromTag(hstring const& tag) {
    if (tag == L"inspect") {
        return PDFProcessingOperation::inspect;
    }
    if (tag == L"read_metadata") {
        return PDFProcessingOperation::read_metadata;
    }
    if (tag == L"merge") {
        return PDFProcessingOperation::merge;
    }
    if (tag == L"export_pages") {
        return PDFProcessingOperation::export_pages;
    }
    if (tag == L"split") {
        return PDFProcessingOperation::split;
    }
    if (tag == L"rotate") {
        return PDFProcessingOperation::rotate;
    }
    if (tag == L"crop") {
        return PDFProcessingOperation::crop;
    }
    if (tag == L"update_metadata") {
        return PDFProcessingOperation::update_metadata;
    }
    if (tag == L"protect") {
        return PDFProcessingOperation::protect;
    }
    if (tag == L"unlock") {
        return PDFProcessingOperation::unlock;
    }
    if (tag == L"export_text") {
        return PDFProcessingOperation::export_text;
    }
    if (tag == L"render_pages") {
        return PDFProcessingOperation::render_pages;
    }
    if (tag == L"images_to_pdf") {
        return PDFProcessingOperation::images_to_pdf;
    }
    if (tag == L"text_watermark") {
        return PDFProcessingOperation::text_watermark;
    }
    if (tag == L"image_watermark") {
        return PDFProcessingOperation::image_watermark;
    }
    if (tag == L"page_numbers") {
        return PDFProcessingOperation::page_numbers;
    }
    if (tag == L"office_to_pdf") {
        return PDFProcessingOperation::office_to_pdf;
    }
    return PDFProcessingOperation::none;
}

bool needsOutput(PDFProcessingOperation operation) noexcept {
    return operation != PDFProcessingOperation::none
        && operation != PDFProcessingOperation::inspect
        && operation != PDFProcessingOperation::read_metadata;
}

bool needsOutputFile(PDFProcessingOperation operation) noexcept {
    return needsOutput(operation)
        && operation != PDFProcessingOperation::render_pages;
}

bool needsPageSelection(PDFProcessingOperation operation) noexcept {
    return operation == PDFProcessingOperation::export_pages
        || operation == PDFProcessingOperation::export_text
        || operation == PDFProcessingOperation::rotate
        || operation == PDFProcessingOperation::crop;
}

bool needsSingleInput(PDFProcessingOperation operation) noexcept {
    return operation != PDFProcessingOperation::merge
        && operation != PDFProcessingOperation::images_to_pdf
        && operation != PDFProcessingOperation::none;
}

bool usesPdfInputs(PDFProcessingOperation operation) noexcept {
    return operation != PDFProcessingOperation::images_to_pdf
        && operation != PDFProcessingOperation::office_to_pdf;
}

bool usesImageInputs(PDFProcessingOperation operation) noexcept {
    return operation == PDFProcessingOperation::images_to_pdf;
}

bool usesOfficeInputs(PDFProcessingOperation operation) noexcept {
    return operation == PDFProcessingOperation::office_to_pdf;
}

std::optional<int> integerValue(hstring const& value) {
    const auto text = to_string(value);
    if (text.empty()) {
        return std::nullopt;
    }
    int result = 0;
    const auto [pointer, error] = std::from_chars(
        text.data(), text.data() + text.size(), result);
    if (error != std::errc{} || pointer != text.data() + text.size()) {
        return std::nullopt;
    }
    return result;
}

std::optional<zisla::pdf::PDFOverlayPosition> overlayPosition(hstring const& tag) {
    using zisla::pdf::PDFOverlayPosition;
    if (tag == L"top_leading") {
        return PDFOverlayPosition::top_leading;
    }
    if (tag == L"top") {
        return PDFOverlayPosition::top;
    }
    if (tag == L"top_trailing") {
        return PDFOverlayPosition::top_trailing;
    }
    if (tag == L"center") {
        return PDFOverlayPosition::center;
    }
    if (tag == L"bottom_leading") {
        return PDFOverlayPosition::bottom_leading;
    }
    if (tag == L"bottom") {
        return PDFOverlayPosition::bottom;
    }
    if (tag == L"bottom_trailing") {
        return PDFOverlayPosition::bottom_trailing;
    }
    return std::nullopt;
}

std::optional<hstring> selectedTag(
    Microsoft::UI::Xaml::Controls::ComboBox const& picker) {
    const auto item = picker.SelectedItem().try_as<
        Microsoft::UI::Xaml::Controls::ComboBoxItem>();
    if (!item) {
        return std::nullopt;
    }
    return unbox_value_or<hstring>(item.Tag(), L"");
}

hstring byteCount(std::uintmax_t bytes) {
    if (bytes < 1024U * 1024U) {
        return hstring{std::to_wstring((bytes + 1023U) / 1024U) + L" KiB"};
    }
    const auto tenths = (bytes * 10U + 512U * 1024U) / (1024U * 1024U);
    return hstring{
        std::to_wstring(tenths / 10U) + L"." + std::to_wstring(tenths % 10U)
        + L" MiB"};
}

hstring displayInputs(std::span<const std::filesystem::path> inputs) {
    if (inputs.empty()) {
        return L"尚未选择";
    }
    if (inputs.size() == 1) {
        const auto name = inputs.front().filename();
        return hstring{(name.empty() ? inputs.front() : name).c_str()};
    }
    const auto name = inputs.front().filename();
    std::wstring result{(name.empty() ? inputs.front() : name).c_str()};
    result.append(L" 等 ");
    result.append(std::to_wstring(inputs.size()));
    result.append(L" 个文件");
    return hstring{result};
}

std::optional<double> finiteNumber(hstring const& value) {
    const auto utf8 = to_string(value);
    if (utf8.empty()) {
        return std::nullopt;
    }
    double result = 0;
    const auto [pointer, error] = std::from_chars(
        utf8.data(),
        utf8.data() + utf8.size(),
        result,
        std::chars_format::general);
    if (error != std::errc{} || pointer != utf8.data() + utf8.size()
        || !std::isfinite(result)) {
        return std::nullopt;
    }
    return result;
}

std::optional<std::string> nonEmptyText(hstring const& value) {
    const auto result = to_string(value);
    return result.empty() ? std::nullopt : std::optional{result};
}

std::optional<std::vector<std::string>> splitKeywords(hstring const& value) {
    const auto text = to_string(value);
    std::vector<std::string> keywords;
    std::size_t offset = 0;
    while (offset <= text.size()) {
        const auto next = text.find(',', offset);
        const auto token = text.substr(
            offset,
            next == std::string::npos ? std::string::npos : next - offset);
        if (!token.empty()) {
            keywords.push_back(token);
        }
        if (next == std::string::npos) {
            break;
        }
        offset = next + 1;
    }
    return keywords.empty() ? std::nullopt : std::optional{std::move(keywords)};
}

hstring outputValidationMessage(PDFOutputValidationError error) {
    switch (error) {
    case PDFOutputValidationError::empty_output_path:
        return L"请填写输出文件名";
    case PDFOutputValidationError::invalid_output_path:
        return L"输出路径无效";
    case PDFOutputValidationError::output_matches_input:
        return L"输出文件不能覆盖输入 PDF";
    case PDFOutputValidationError::output_already_exists:
        return L"输出文件已存在，不会覆盖";
    case PDFOutputValidationError::duplicate_output:
        return L"拆分输出文件名重复";
    case PDFOutputValidationError::none:
        break;
    }
    return L"输出路径无效";
}

}  // namespace

PDFToolsContent::PDFToolsContent()
    : snapshot_(std::make_shared<const zisla::pdf::PDFProcessingSnapshot>()) {
    InitializeComponent();
    initialized_ = true;
    updateView();
}

void PDFToolsContent::setSnapshot(
    std::shared_ptr<const zisla::pdf::PDFProcessingSnapshot> snapshot) {
    snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const zisla::pdf::PDFProcessingSnapshot>();
    manual_status_.clear();

    if (snapshot_->operation == PDFProcessingOperation::inspect
        && snapshot_->phase == PDFProcessingPhase::succeeded
        && snapshot_->summary) {
        inspected_summary_ = snapshot_->summary;
    }
    if (snapshot_->operation == PDFProcessingOperation::read_metadata
        && snapshot_->phase == PDFProcessingPhase::succeeded
        && snapshot_->metadata) {
        const auto& metadata = *snapshot_->metadata;
        PDFTitleBox().Text(fromUtf8(metadata.title.value_or("")));
        PDFAuthorBox().Text(fromUtf8(metadata.author.value_or("")));
        PDFSubjectBox().Text(fromUtf8(metadata.subject.value_or("")));
        PDFCreatorBox().Text(fromUtf8(metadata.creator.value_or("")));
        std::string keywords;
        if (metadata.keywords) {
            for (const auto& keyword : *metadata.keywords) {
                if (!keywords.empty()) {
                    keywords.append(",");
                }
                keywords.append(keyword);
            }
        }
        PDFKeywordsBox().Text(fromUtf8(keywords));
    }
    updateView();
}

void PDFToolsContent::setManualStatus(hstring value) {
    manual_status_ = std::move(value);
    updateView();
}

PDFProcessingOperation PDFToolsContent::selectedOperation() {
    const auto item = PDFOperationPicker().SelectedItem().try_as<
        Microsoft::UI::Xaml::Controls::ComboBoxItem>();
    return item
        ? operationFromTag(unbox_value_or<hstring>(item.Tag(), L""))
        : PDFProcessingOperation::none;
}

void PDFToolsContent::updateOperationControls() {
    using Microsoft::UI::Xaml::Visibility;

    const auto operation = selectedOperation();
    PDFPagesPanel().Visibility(needsPageSelection(operation)
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFSplitPanel().Visibility(operation == PDFProcessingOperation::split
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFRotationPanel().Visibility(operation == PDFProcessingOperation::rotate
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFCropPanel().Visibility(operation == PDFProcessingOperation::crop
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFMetadataPanel().Visibility(
        operation == PDFProcessingOperation::read_metadata
            || operation == PDFProcessingOperation::update_metadata
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFProtectionPanel().Visibility(operation == PDFProcessingOperation::protect
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFUnlockPanel().Visibility(operation == PDFProcessingOperation::unlock
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFRenderPanel().Visibility(operation == PDFProcessingOperation::render_pages
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFTextWatermarkPanel().Visibility(operation == PDFProcessingOperation::text_watermark
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFImageWatermarkPanel().Visibility(operation == PDFProcessingOperation::image_watermark
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFPageNumbersPanel().Visibility(operation == PDFProcessingOperation::page_numbers
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFOutputPanel().Visibility(needsOutput(operation)
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFOutputNameBox().Visibility(needsOutputFile(operation)
        ? Visibility::Visible
        : Visibility::Collapsed);
    PDFOutputNameBox().IsEnabled(needsOutputFile(operation));
    PDFOutputNameBox().PlaceholderText(
        operation == PDFProcessingOperation::export_text ? L"output.txt" : L"output.pdf");
    PDFRunButtonText().Text(operationLabel(operation));
}

void PDFToolsContent::updateView() {
    using Microsoft::UI::Xaml::Visibility;

    updateOperationControls();
    const auto operation = selectedOperation();
    const bool working = snapshot_
        && (snapshot_->phase == PDFProcessingPhase::queued
            || snapshot_->phase == PDFProcessingPhase::running);
    PDFProgressRing().IsActive(working);
    PDFProgressRing().Visibility(working ? Visibility::Visible : Visibility::Collapsed);
    PDFChooseInputsButton().IsEnabled(!picker_active_ && !working);
    PDFChooseOutputFolderButton().IsEnabled(!picker_active_ && !working);
    PDFChooseWatermarkImageButton().IsEnabled(
        !picker_active_ && !working
        && operation == PDFProcessingOperation::image_watermark);
    PDFRunButton().IsEnabled(!picker_active_ && !working && !inputs_.empty()
        && operation != PDFProcessingOperation::none);
    PDFResetButton().IsEnabled(!picker_active_ && !working && !inputs_.empty());
    PDFInputText().Text(displayInputs(inputs_));

    if (output_directory_.empty()) {
        PDFOutputFolderText().Text(L"请选择输出文件夹");
    } else {
        PDFOutputFolderText().Text(hstring{output_directory_.c_str()});
    }

    hstring status = manual_status_;
    if (status.empty() && snapshot_ && !snapshot_->message.empty()) {
        status = fromUtf8(snapshot_->message);
    }
    if (status.empty()) {
        status = inputs_.empty() ? L"请选择 PDF 文件" : L"准备就绪";
    }
    PDFStatusText().Text(status);

    PDFSummaryText().Visibility(Visibility::Collapsed);
    if (inspected_summary_) {
        std::wstring summary = std::to_wstring(inspected_summary_->page_count);
        summary.append(L" 页 · ");
        summary.append(byteCount(inspected_summary_->file_size).c_str());
        if (inspected_summary_->is_locked) {
            summary.append(L" · 需要密码");
        } else if (inspected_summary_->is_encrypted) {
            summary.append(L" · 已加密");
        }
        PDFSummaryText().Text(hstring{summary});
        PDFSummaryText().Visibility(Visibility::Visible);
    }

    PDFMetadataSummaryText().Visibility(Visibility::Collapsed);
    if (snapshot_ && snapshot_->operation == PDFProcessingOperation::read_metadata
        && snapshot_->phase == PDFProcessingPhase::succeeded
        && snapshot_->metadata) {
        std::wstring detail = L"元数据已读取";
        if (snapshot_->metadata->title && !snapshot_->metadata->title->empty()) {
            detail.append(L" · ");
            detail.append(fromUtf8(*snapshot_->metadata->title).c_str());
        }
        PDFMetadataSummaryText().Text(hstring{detail});
        PDFMetadataSummaryText().Visibility(Visibility::Visible);
    }
}

std::optional<std::vector<std::size_t>> PDFToolsContent::selectedPages() {
    if (!inspected_summary_ || inspected_summary_->page_count == 0) {
        setManualStatus(L"请先等待 PDF 信息读取完成");
        return std::nullopt;
    }
    const auto result = PDFProcessing::parse_page_selection(
        to_string(PDFPageRangeBox().Text()),
        inspected_summary_->page_count);
    if (result.is_valid()) {
        return result.page_indexes;
    }
    setManualStatus(result.error == PDFPageSelectionError::empty_selection
        ? L"请填写页码范围"
        : L"页码范围无效");
    return std::nullopt;
}

std::optional<std::vector<std::vector<std::size_t>>> PDFToolsContent::splitPageGroups() {
    if (!inspected_summary_ || inspected_summary_->page_count == 0) {
        setManualStatus(L"请先等待 PDF 信息读取完成");
        return std::nullopt;
    }

    std::wstring normalized_ranges{PDFSplitRangesBox().Text().c_str()};
    std::replace(
        normalized_ranges.begin(),
        normalized_ranges.end(),
        L'\uff1b',
        L';');
    const auto ranges = to_string(hstring{normalized_ranges});
    std::vector<std::vector<std::size_t>> groups;
    std::size_t offset = 0;
    while (offset <= ranges.size()) {
        const auto delimiter = ranges.find(';', offset);
        const auto range = ranges.substr(
            offset,
            delimiter == std::string::npos
                ? std::string::npos
                : delimiter - offset);
        const auto parsed = PDFProcessing::parse_page_selection(
            range,
            inspected_summary_->page_count);
        if (!parsed.is_valid()) {
            setManualStatus(L"拆分页码分组无效");
            return std::nullopt;
        }
        groups.push_back(parsed.page_indexes);
        if (delimiter == std::string::npos) {
            break;
        }
        offset = delimiter + 1;
    }
    if (groups.empty()) {
        setManualStatus(L"请填写拆分页码分组");
        return std::nullopt;
    }
    return groups;
}

std::optional<std::vector<std::filesystem::path>> PDFToolsContent::outputPaths(
    PDFProcessingOperation operation,
    std::size_t split_count) {
    if (!needsOutput(operation)) {
        return std::vector<std::filesystem::path>{};
    }
    if (output_directory_.empty()) {
        setManualStatus(L"请选择输出文件夹");
        return std::nullopt;
    }

    if (operation == PDFProcessingOperation::render_pages) {
        return std::vector<std::filesystem::path>{};
    }

    auto filename = std::filesystem::path{PDFOutputNameBox().Text().c_str()};
    if (filename.empty() || filename.filename().empty()
        || filename.has_parent_path()
        || filename == std::filesystem::path{L"."}
        || filename == std::filesystem::path{L".."}) {
        setManualStatus(L"输出文件名无效");
        return std::nullopt;
    }
    const auto expected_extension = operation == PDFProcessingOperation::export_text
        ? std::filesystem::path{L".txt"}
        : std::filesystem::path{L".pdf"};
    if (filename.extension().empty()) {
        filename += expected_extension;
        PDFOutputNameBox().Text(hstring{filename.c_str()});
    }
    std::wstring extension = filename.extension().wstring();
    std::transform(extension.begin(), extension.end(), extension.begin(), [](wchar_t value) {
        return static_cast<wchar_t>(std::towlower(value));
    });
    if (extension != expected_extension.wstring()) {
        setManualStatus(operation == PDFProcessingOperation::export_text
            ? L"文本输出文件名必须以 .txt 结尾"
            : L"输出文件名必须以 .pdf 结尾");
        return std::nullopt;
    }

    std::vector<std::filesystem::path> outputs;
    if (operation == PDFProcessingOperation::split) {
        const auto stem = filename.stem();
        if (stem.empty() || split_count == 0) {
            setManualStatus(L"拆分输出文件名无效");
            return std::nullopt;
        }
        outputs.reserve(split_count);
        for (std::size_t index = 0; index < split_count; ++index) {
            auto output_name = stem;
            output_name += L"-";
            output_name += std::to_wstring(index + 1);
            output_name += filename.extension();
            outputs.push_back(output_directory_ / output_name);
        }
    } else {
        outputs.push_back(output_directory_ / filename);
    }

    const auto validation = PDFProcessing::validate_outputs(inputs_, outputs);
    if (validation != PDFOutputValidationError::none) {
        setManualStatus(outputValidationMessage(validation));
        return std::nullopt;
    }
    return outputs;
}

std::optional<zisla::pdf::PDFProcessingRequest> PDFToolsContent::makeRequest() {
    const auto operation = selectedOperation();
    if (operation == PDFProcessingOperation::none || inputs_.empty()) {
        setManualStatus(L"请选择输入文件和操作");
        return std::nullopt;
    }
    if (operation == PDFProcessingOperation::merge) {
        if (inputs_.size() < 2) {
            setManualStatus(L"合并至少需要两个 PDF 文件");
            return std::nullopt;
        }
    } else if (needsSingleInput(operation) && inputs_.size() != 1) {
        setManualStatus(L"该操作只支持一个输入文件");
        return std::nullopt;
    }

    const auto expected_extension = [](const std::filesystem::path& path) {
        auto extension = path.extension().wstring();
        std::transform(extension.begin(), extension.end(), extension.begin(), [](wchar_t value) {
            return static_cast<wchar_t>(std::towlower(value));
        });
        return extension;
    };
    if (usesPdfInputs(operation)) {
        const auto invalid = std::find_if(inputs_.begin(), inputs_.end(), [&](const auto& path) {
            return expected_extension(path) != L".pdf";
        });
        if (invalid != inputs_.end()) {
            setManualStatus(L"该操作只能使用 PDF 文件");
            return std::nullopt;
        }
    } else if (usesImageInputs(operation)) {
        const auto is_image = [&](const auto& path) {
            const auto extension = expected_extension(path);
            return extension == L".png" || extension == L".jpg"
                || extension == L".jpeg";
        };
        if (std::find_if(inputs_.begin(), inputs_.end(), [&](const auto& path) {
                return !is_image(path);
            }) != inputs_.end()) {
            setManualStatus(L"图片转 PDF 只支持 PNG 或 JPEG");
            return std::nullopt;
        }
    } else if (usesOfficeInputs(operation)) {
        const auto is_office = [&](const auto& path) {
            const auto extension = expected_extension(path);
            constexpr std::array supported{
                L".doc", L".docx", L".dot", L".dotx", L".rtf", L".odt",
                L".ppt", L".pptx", L".pps", L".ppsx", L".odp", L".xls",
                L".xlsx", L".xlsm", L".ods", L".csv",
            };
            return std::find(supported.begin(), supported.end(), extension)
                != supported.end();
        };
        if (!is_office(inputs_.front())) {
            setManualStatus(L"不支持的 Office 文件格式");
            return std::nullopt;
        }
    }

    zisla::pdf::PDFProcessingRequest request{
        .operation = operation,
        .inputs = inputs_,
    };
    if (needsPageSelection(operation)) {
        const auto pages = selectedPages();
        if (!pages) {
            return std::nullopt;
        }
        request.page_indexes = *pages;
    }
    if (operation == PDFProcessingOperation::split) {
        const auto groups = splitPageGroups();
        if (!groups) {
            return std::nullopt;
        }
        request.page_groups = *groups;
    }
    if (operation == PDFProcessingOperation::rotate) {
        const auto item = PDFRotationPicker().SelectedItem().try_as<
            Microsoft::UI::Xaml::Controls::ComboBoxItem>();
        const auto tag = item ? unbox_value_or<hstring>(item.Tag(), L"") : hstring{};
        int degrees = 0;
        const auto text = to_string(tag);
        const auto [pointer, error] = std::from_chars(
            text.data(), text.data() + text.size(), degrees);
        if (error != std::errc{} || pointer != text.data() + text.size()
            || !PDFProcessing::is_valid_rotation(degrees)) {
            setManualStatus(L"旋转角度无效");
            return std::nullopt;
        }
        request.rotation_degrees = degrees;
    }
    if (operation == PDFProcessingOperation::crop) {
        const auto x = finiteNumber(PDFCropXBox().Text());
        const auto y = finiteNumber(PDFCropYBox().Text());
        const auto width = finiteNumber(PDFCropWidthBox().Text());
        const auto height = finiteNumber(PDFCropHeightBox().Text());
        if (!x || !y || !width || !height) {
            setManualStatus(L"裁剪框必须是有效数字");
            return std::nullopt;
        }
        request.crop_box = {.x = *x, .y = *y, .width = *width, .height = *height};
        if (!PDFProcessing::is_valid_crop_box(request.crop_box)) {
            setManualStatus(L"裁剪框宽度和高度必须大于零");
            return std::nullopt;
        }
    }
    if (operation == PDFProcessingOperation::update_metadata) {
        request.metadata = {
            .title = nonEmptyText(PDFTitleBox().Text()),
            .author = nonEmptyText(PDFAuthorBox().Text()),
            .subject = nonEmptyText(PDFSubjectBox().Text()),
            .creator = nonEmptyText(PDFCreatorBox().Text()),
            .keywords = splitKeywords(PDFKeywordsBox().Text()),
        };
    }
    if (operation == PDFProcessingOperation::protect) {
        request.protection = {
            .user_password = to_string(PDFUserPasswordBox().Password()),
            .owner_password = to_string(PDFOwnerPasswordBox().Password()),
        };
        if (!PDFProcessing::has_password(request.protection)) {
            setManualStatus(L"请至少设置一个密码");
            return std::nullopt;
        }
    }
    if (operation == PDFProcessingOperation::unlock) {
        request.password = to_string(PDFUnlockPasswordBox().Password());
    }
    if (operation == PDFProcessingOperation::render_pages) {
        const auto format_tag = selectedTag(PDFRenderFormatPicker());
        if (!format_tag || (*format_tag != L"png" && *format_tag != L"jpeg")) {
            setManualStatus(L"渲染图片格式无效");
            return std::nullopt;
        }
        request.raster_image_format = *format_tag == L"jpeg"
            ? zisla::pdf::PDFRasterImageFormat::jpeg
            : zisla::pdf::PDFRasterImageFormat::png;
        const auto dpi = integerValue(PDFRenderDpiBox().Text());
        if (!dpi || *dpi < 1 || *dpi > 600) {
            setManualStatus(L"渲染 DPI 必须是 1 到 600 之间的整数");
            return std::nullopt;
        }
        request.render_dpi = *dpi;
        request.output_directory = output_directory_;
        if (request.output_directory.empty()) {
            setManualStatus(L"请选择图片输出文件夹");
            return std::nullopt;
        }
    }
    if (operation == PDFProcessingOperation::text_watermark) {
        const auto text = nonEmptyText(PDFTextWatermarkTextBox().Text());
        const auto font_size = finiteNumber(PDFTextWatermarkFontSizeBox().Text());
        const auto opacity = finiteNumber(PDFTextWatermarkOpacityBox().Text());
        const auto rotation = finiteNumber(PDFTextWatermarkRotationBox().Text());
        if (!text || !font_size || *font_size <= 0 || !opacity || *opacity < 0
            || *opacity > 1 || !rotation) {
            setManualStatus(L"文字水印参数无效");
            return std::nullopt;
        }
        request.text_watermark = {
            .text = *text,
            .font_size = *font_size,
            .opacity = *opacity,
            .rotation_degrees = *rotation,
        };
    }
    if (operation == PDFProcessingOperation::image_watermark) {
        if (watermark_image_path_.empty()) {
            setManualStatus(L"请选择图片水印文件");
            return std::nullopt;
        }
        std::error_code error;
        if (!std::filesystem::is_regular_file(watermark_image_path_, error) || error) {
            setManualStatus(L"图片水印文件不可访问");
            return std::nullopt;
        }
        const auto position_tag = selectedTag(PDFImageWatermarkPositionPicker());
        const auto position = position_tag ? overlayPosition(*position_tag) : std::nullopt;
        const auto scale = finiteNumber(PDFImageWatermarkScaleBox().Text());
        const auto opacity = finiteNumber(PDFImageWatermarkOpacityBox().Text());
        if (!position || !scale || *scale <= 0 || *scale > 1 || !opacity
            || *opacity < 0 || *opacity > 1) {
            setManualStatus(L"图片水印参数无效");
            return std::nullopt;
        }
        request.image_watermark = {
            .image_path = watermark_image_path_,
            .position = *position,
            .scale = *scale,
            .opacity = *opacity,
        };
    }
    if (operation == PDFProcessingOperation::page_numbers) {
        const auto position_tag = selectedTag(PDFPageNumberPositionPicker());
        const auto position = position_tag ? overlayPosition(*position_tag) : std::nullopt;
        const auto font_size = finiteNumber(PDFPageNumberFontSizeBox().Text());
        const auto inset = finiteNumber(PDFPageNumberInsetBox().Text());
        if (!position || !font_size || *font_size <= 0 || !inset || *inset < 0) {
            setManualStatus(L"页码样式参数无效");
            return std::nullopt;
        }
        request.page_number_style = {
            .prefix = to_string(PDFPageNumberPrefixBox().Text()),
            .suffix = to_string(PDFPageNumberSuffixBox().Text()),
            .font_size = *font_size,
            .position = *position,
            .inset = *inset,
        };
    }
    if (needsOutputFile(operation) || operation == PDFProcessingOperation::render_pages) {
        const auto outputs = outputPaths(operation, request.page_groups.size());
        if (!outputs) {
            return std::nullopt;
        }
        request.outputs = *outputs;
    }
    return request;
}

winrt::fire_and_forget PDFToolsContent::ChooseInputsButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    if (picker_active_) {
        co_return;
    }
    picker_active_ = true;
    updateView();
    const TransientUIHold hold;
    try {
        const auto operation = selectedOperation();
        Windows::Storage::Pickers::FileOpenPicker picker;
        initializePicker(picker);
        if (usesImageInputs(operation)) {
            picker.SuggestedStartLocation(
                Windows::Storage::Pickers::PickerLocationId::PicturesLibrary);
            for (const auto extension : {L".png", L".jpg", L".jpeg"}) {
                picker.FileTypeFilter().Append(extension);
            }
        } else if (usesOfficeInputs(operation)) {
            for (const auto extension : {
                     L".doc", L".docx", L".dot", L".dotx", L".rtf", L".odt",
                     L".ppt", L".pptx", L".pps", L".ppsx", L".odp", L".xls",
                     L".xlsx", L".xlsm", L".ods", L".csv"}) {
                picker.FileTypeFilter().Append(extension);
            }
        } else {
            picker.FileTypeFilter().Append(L".pdf");
        }

        std::vector<std::filesystem::path> selected;
        if (operation == PDFProcessingOperation::merge
            || operation == PDFProcessingOperation::images_to_pdf) {
            const auto files = co_await picker.PickMultipleFilesAsync();
            selected.reserve(files.Size());
            for (const auto& file : files) {
                if (file && !file.Path().empty()) {
                    selected.emplace_back(file.Path().c_str());
                }
            }
        } else {
            const auto file = co_await picker.PickSingleFileAsync();
            if (file && !file.Path().empty()) {
                selected.emplace_back(file.Path().c_str());
            }
        }

        if (!selected.empty()) {
            inputs_ = std::move(selected);
            inspected_summary_.reset();
            if (output_directory_.empty()) {
                output_directory_ = inputs_.front().parent_path();
            }
            if (PDFOutputNameBox().Text().empty()) {
                auto name = inputs_.front().stem();
                if (name.empty()) {
                    name = L"zisla-output";
                }
                name += L"-output";
                name += operation == PDFProcessingOperation::export_text
                    ? L".txt"
                    : L".pdf";
                PDFOutputNameBox().Text(hstring{name.c_str()});
            }
            if (usesPdfInputs(operation)) {
                manual_status_ = L"正在读取 PDF 信息";
                const auto request_id = AppHost::instance().submitPDFProcessing({
                    .operation = PDFProcessingOperation::inspect,
                    .inputs = {inputs_.front()},
                });
                if (request_id == 0) {
                    manual_status_ = L"PDF 服务不可用";
                }
            } else {
                manual_status_ = usesOfficeInputs(operation)
                    ? L"已选择 Office 文件"
                    : L"已选择图片文件";
            }
        }
    } catch (const hresult_error& error) {
        manual_status_ = error.message().empty()
            ? L"无法打开输入文件选择器"
            : error.message();
    } catch (...) {
        manual_status_ = L"无法选择输入文件";
    }
    picker_active_ = false;
    updateView();
}

winrt::fire_and_forget PDFToolsContent::ChooseWatermarkImageButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    if (picker_active_) {
        co_return;
    }
    picker_active_ = true;
    updateView();
    const TransientUIHold hold;
    try {
        Windows::Storage::Pickers::FileOpenPicker picker;
        initializePicker(picker);
        picker.SuggestedStartLocation(
            Windows::Storage::Pickers::PickerLocationId::PicturesLibrary);
        for (const auto extension : {L".png", L".jpg", L".jpeg"}) {
            picker.FileTypeFilter().Append(extension);
        }
        const auto file = co_await picker.PickSingleFileAsync();
        if (file && !file.Path().empty()) {
            watermark_image_path_ = std::filesystem::path{file.Path().c_str()};
            PDFImageWatermarkPathBox().Text(hstring{watermark_image_path_.c_str()});
            manual_status_ = L"已选择图片水印";
        }
    } catch (const hresult_error& error) {
        manual_status_ = error.message().empty()
            ? L"无法打开图片水印选择器"
            : error.message();
    } catch (...) {
        manual_status_ = L"无法选择图片水印";
    }
    picker_active_ = false;
    updateView();
}

winrt::fire_and_forget PDFToolsContent::ChooseOutputFolderButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    if (picker_active_) {
        co_return;
    }
    picker_active_ = true;
    updateView();
    const TransientUIHold hold;
    try {
        Windows::Storage::Pickers::FolderPicker picker;
        initializePicker(picker);
        picker.FileTypeFilter().Append(L"*");
        const auto folder = co_await picker.PickSingleFolderAsync();
        if (folder && !folder.Path().empty()) {
            output_directory_ = std::filesystem::path{folder.Path().c_str()};
            manual_status_ = L"已选择输出文件夹";
        }
    } catch (const hresult_error& error) {
        manual_status_ = error.message().empty()
            ? L"无法打开输出文件夹选择器"
            : error.message();
    } catch (...) {
        manual_status_ = L"无法选择输出文件夹";
    }
    picker_active_ = false;
    updateView();
}

void PDFToolsContent::OperationPicker_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (!initialized_) {
        return;
    }
    manual_status_.clear();
    updateView();
}

void PDFToolsContent::RunButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto request = makeRequest();
    if (!request) {
        return;
    }
    const auto operation = request->operation;
    const auto request_id = AppHost::instance().submitPDFProcessing(*request);
    if (request_id == 0) {
        setManualStatus(L"PDF 服务不可用");
        return;
    }
    if (operation == PDFProcessingOperation::protect) {
        PDFUserPasswordBox().Password(L"");
        PDFOwnerPasswordBox().Password(L"");
    } else if (operation == PDFProcessingOperation::unlock) {
        PDFUnlockPasswordBox().Password(L"");
    }
    manual_status_ = L"等待处理";
    updateView();
}

void PDFToolsContent::ResetButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    inputs_.clear();
    output_directory_.clear();
    watermark_image_path_.clear();
    inspected_summary_.reset();
    PDFOutputNameBox().Text(L"");
    PDFPageRangeBox().Text(L"1");
    PDFSplitRangesBox().Text(L"1");
    PDFTitleBox().Text(L"");
    PDFAuthorBox().Text(L"");
    PDFSubjectBox().Text(L"");
    PDFCreatorBox().Text(L"");
    PDFKeywordsBox().Text(L"");
    PDFUserPasswordBox().Password(L"");
    PDFOwnerPasswordBox().Password(L"");
    PDFUnlockPasswordBox().Password(L"");
    PDFRenderFormatPicker().SelectedIndex(0);
    PDFRenderDpiBox().Text(L"144");
    PDFTextWatermarkTextBox().Text(L"");
    PDFTextWatermarkFontSizeBox().Text(L"42");
    PDFTextWatermarkOpacityBox().Text(L"0.22");
    PDFTextWatermarkRotationBox().Text(L"-35");
    PDFImageWatermarkPathBox().Text(L"");
    PDFImageWatermarkPositionPicker().SelectedIndex(0);
    PDFImageWatermarkScaleBox().Text(L"0.25");
    PDFImageWatermarkOpacityBox().Text(L"0.3");
    PDFPageNumberPrefixBox().Text(L"第 ");
    PDFPageNumberSuffixBox().Text(L" 页");
    PDFPageNumberPositionPicker().SelectedIndex(0);
    PDFPageNumberFontSizeBox().Text(L"11");
    PDFPageNumberInsetBox().Text(L"24");
    manual_status_ = L"请选择 PDF 文件";
    updateView();
}

}
