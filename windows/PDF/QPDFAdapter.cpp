#include "QPDFAdapter.hpp"

#pragma warning(push)
#pragma warning(disable : 4458)
#include <qpdf/Constants.h>
#include <qpdf/QPDF.hh>
#include <qpdf/QPDFExc.hh>
#include <qpdf/QPDFObjectHandle.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFPageObjectHelper.hh>
#include <qpdf/QPDFWriter.hh>
#pragma warning(pop)

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

namespace zisla::pdf {
namespace {

using zisla::core::PDFCropBox;
using zisla::core::PDFDocumentMetadata;
using zisla::core::PDFDocumentSummary;
using zisla::core::PDFOutputValidationError;
using zisla::core::PDFPasswordProtection;
using zisla::core::PDFProcessing;

namespace fs = std::filesystem;

[[noreturn]] void fail(QPDFAdapterErrorCode code, std::string message) {
    throw QPDFAdapterError(code, std::move(message));
}

std::string path_as_utf8(const fs::path& path) {
    const auto encoded = path.u8string();
    std::string result;
    result.reserve(encoded.size());
    for (const auto character : encoded) {
        result.push_back(static_cast<char>(character));
    }
    return result;
}

std::string display_name(const fs::path& path) {
    const auto name = path.filename();
    return path_as_utf8(name.empty() ? path : name);
}

bool contains_nul(std::string_view value) noexcept {
    return value.find('\0') != std::string_view::npos;
}

fs::path normalized_input_path(const fs::path& input) {
    if (input.empty()) {
        fail(QPDFAdapterErrorCode::invalid_input, "未选择 PDF 文件");
    }

    std::error_code error;
    const auto absolute = fs::absolute(input, error);
    if (error) {
        fail(QPDFAdapterErrorCode::invalid_input, "无法定位 PDF 文件：" + path_as_utf8(input));
    }
    const auto canonical = fs::weakly_canonical(absolute, error);
    const auto normalized = error ? absolute.lexically_normal() : canonical.lexically_normal();
    error.clear();
    if (!fs::is_regular_file(normalized, error) || error) {
        fail(
            QPDFAdapterErrorCode::invalid_input,
            "不是可访问的本地 PDF 文件：" + display_name(normalized));
    }
    return normalized;
}

fs::path normalized_output_path(const fs::path& output) {
    if (output.empty()) {
        fail(QPDFAdapterErrorCode::output_validation, "未选择 PDF 输出文件");
    }
    std::error_code error;
    const auto absolute = fs::absolute(output, error);
    if (error) {
        fail(QPDFAdapterErrorCode::output_validation, "无法定位 PDF 输出文件");
    }
    return absolute.lexically_normal();
}

[[noreturn]] void fail_output_validation(PDFOutputValidationError error) {
    switch (error) {
    case PDFOutputValidationError::empty_output_path:
        fail(QPDFAdapterErrorCode::output_validation, "未选择 PDF 输出文件");
    case PDFOutputValidationError::invalid_output_path:
        fail(QPDFAdapterErrorCode::output_validation, "PDF 输出路径无效");
    case PDFOutputValidationError::output_matches_input:
        fail(QPDFAdapterErrorCode::output_validation, "输出文件不能覆盖输入 PDF");
    case PDFOutputValidationError::output_already_exists:
        fail(QPDFAdapterErrorCode::output_validation, "PDF 输出文件已存在，未覆盖");
    case PDFOutputValidationError::duplicate_output:
        fail(QPDFAdapterErrorCode::output_validation, "同一任务不能重复使用 PDF 输出文件");
    case PDFOutputValidationError::none:
        break;
    }
    fail(QPDFAdapterErrorCode::output_validation, "PDF 输出路径无效");
}

void validate_outputs(
    std::span<const fs::path> inputs,
    std::span<const fs::path> outputs) {
    const auto error = PDFProcessing::validate_outputs(inputs, outputs);
    if (error != PDFOutputValidationError::none) {
        fail_output_validation(error);
    }
}

class PendingOutput {
public:
    explicit PendingOutput(const fs::path& output)
        : destination_(normalized_output_path(output)) {
        const auto parent = destination_.parent_path();
        std::error_code error;
        fs::create_directories(parent, error);
        if (error || !fs::is_directory(parent, error) || error) {
            fail(
                QPDFAdapterErrorCode::cannot_create_output_directory,
                "无法创建 PDF 输出目录：" + path_as_utf8(parent));
        }

        for (std::size_t attempt = 0; attempt < 64; ++attempt) {
            auto candidate = destination_;
            candidate += temporary_suffix();
            error.clear();
            if (!fs::exists(candidate, error) && !error) {
                temporary_ = std::move(candidate);
                return;
            }
        }
        fail(QPDFAdapterErrorCode::cannot_write_output, "无法创建临时 PDF 输出文件");
    }

    ~PendingOutput() {
        cleanup();
    }

    PendingOutput(const PendingOutput&) = delete;
    PendingOutput& operator=(const PendingOutput&) = delete;

    PendingOutput(PendingOutput&& other) noexcept
        : destination_(std::move(other.destination_)),
          temporary_(std::move(other.temporary_)),
          committed_(std::exchange(other.committed_, false)) {}

    PendingOutput& operator=(PendingOutput&&) = delete;

    [[nodiscard]] const fs::path& temporary() const noexcept {
        return temporary_;
    }

    void commit() {
        std::error_code error;
        if (fs::exists(destination_, error)) {
            fail(QPDFAdapterErrorCode::output_validation, "PDF 输出文件已存在，未覆盖");
        }
        if (error) {
            fail(QPDFAdapterErrorCode::cannot_write_output, "无法检查 PDF 输出文件");
        }
        fs::rename(temporary_, destination_, error);
        if (error) {
            fail(
                QPDFAdapterErrorCode::cannot_write_output,
                "无法提交 PDF 输出文件：" + display_name(destination_));
        }
        committed_ = true;
    }

    void rollback() noexcept {
        std::error_code error;
        if (!temporary_.empty()) {
            fs::remove(temporary_, error);
        }
        if (committed_) {
            error.clear();
            fs::remove(destination_, error);
            committed_ = false;
        }
    }

private:
    [[nodiscard]] static std::string temporary_suffix() {
        static std::atomic<std::uint64_t> sequence{0};
        const auto now = std::chrono::steady_clock::now().time_since_epoch().count();
        return ".zisla-qpdf-" + std::to_string(now) + "-"
            + std::to_string(sequence.fetch_add(1, std::memory_order_relaxed)) + ".tmp";
    }

    void cleanup() noexcept {
        std::error_code error;
        if (!committed_ && !temporary_.empty()) {
            fs::remove(temporary_, error);
        }
    }

    fs::path destination_;
    fs::path temporary_;
    bool committed_{false};
};

void commit_outputs(std::vector<PendingOutput>& outputs) {
    try {
        for (auto& output : outputs) {
            output.commit();
        }
    } catch (...) {
        for (auto& output : outputs) {
            output.rollback();
        }
        throw;
    }
}

void ensure_pages_selected(
    std::span<const std::size_t> page_indexes,
    std::size_t page_count) {
    if (!PDFProcessing::has_valid_page_indexes(page_indexes, page_count)) {
        fail(QPDFAdapterErrorCode::invalid_page_selection, "至少需要选择有效的 PDF 页面");
    }
}

std::vector<QPDFPageObjectHelper> pages_for(QPDF& document) {
    try {
        auto pages = QPDFPageDocumentHelper(document).getAllPages();
        if (pages.empty()) {
            fail(QPDFAdapterErrorCode::invalid_document, "PDF 不包含可处理的页面");
        }
        return pages;
    } catch (const QPDFAdapterError&) {
        throw;
    } catch (const std::exception&) {
        fail(QPDFAdapterErrorCode::invalid_document, "无法读取 PDF 页面结构");
    }
}

std::unique_ptr<QPDF> load_document(
    const fs::path& input,
    std::string_view password = {},
    bool password_was_supplied = false) {
    const auto path = path_as_utf8(input);
    std::string password_copy(password);
    auto document = std::make_unique<QPDF>();
    try {
        document->processFile(
            path.c_str(),
            password_was_supplied ? password_copy.c_str() : nullptr);
    } catch (const QPDFExc& error) {
        if (error.getErrorCode() == qpdf_e_password) {
            fail(
                password_was_supplied
                    ? QPDFAdapterErrorCode::incorrect_password
                    : QPDFAdapterErrorCode::locked_document,
                password_was_supplied
                    ? "PDF 密码不正确"
                    : "PDF 已加密且尚未解锁");
        }
        fail(QPDFAdapterErrorCode::invalid_document, "无法读取 PDF：" + display_name(input));
    } catch (const std::exception&) {
        fail(
            password_was_supplied
                ? QPDFAdapterErrorCode::incorrect_password
                : QPDFAdapterErrorCode::invalid_document,
            password_was_supplied
                ? "PDF 密码不正确或文档无法解密"
                : "无法读取 PDF：" + display_name(input));
    }

    if (document->isEncrypted()
        && !document->ownerPasswordMatched()
        && !document->userPasswordMatched()) {
        fail(
            password_was_supplied
                ? QPDFAdapterErrorCode::incorrect_password
                : QPDFAdapterErrorCode::locked_document,
            password_was_supplied ? "PDF 密码不正确" : "PDF 已加密且尚未解锁");
    }
    (void)pages_for(*document);
    return document;
}

PDFDocumentSummary inspect_document(const fs::path& input) {
    const auto path = path_as_utf8(input);
    std::error_code error;
    const auto size = fs::file_size(input, error);
    if (error) {
        fail(QPDFAdapterErrorCode::invalid_input, "无法读取 PDF 文件大小");
    }

    QPDF document;
    try {
        document.processFile(path.c_str());
    } catch (const QPDFExc& exception) {
        if (exception.getErrorCode() == qpdf_e_password) {
            return {
                .page_count = 0,
                .file_size = size,
                .is_encrypted = true,
                .is_locked = true,
            };
        }
        fail(QPDFAdapterErrorCode::invalid_document, "无法读取 PDF：" + display_name(input));
    } catch (const std::exception&) {
        fail(QPDFAdapterErrorCode::invalid_document, "无法读取 PDF：" + display_name(input));
    }

    const auto encrypted = document.isEncrypted();
    const auto locked = encrypted
        && !document.ownerPasswordMatched()
        && !document.userPasswordMatched();
    return {
        .page_count = locked ? 0 : pages_for(document).size(),
        .file_size = size,
        .is_encrypted = encrypted,
        .is_locked = locked,
    };
}

void write_document(QPDF& document, PendingOutput& output) {
    try {
        const auto destination = path_as_utf8(output.temporary());
        QPDFWriter writer(document, destination.c_str());
        writer.setPreserveEncryption(false);
        writer.write();
    } catch (const std::exception&) {
        fail(QPDFAdapterErrorCode::cannot_write_output, "无法写入 PDF 输出文件");
    }
}

void write_protected_document(
    QPDF& document,
    const PDFPasswordProtection& protection,
    PendingOutput& output) {
    try {
        const auto destination = path_as_utf8(output.temporary());
        QPDFWriter writer(document, destination.c_str());
        writer.setPreserveEncryption(false);
        writer.setR6EncryptionParameters(
            protection.user_password.c_str(),
            protection.owner_password.c_str(),
            true,
            true,
            true,
            true,
            true,
            true,
            qpdf_r3p_full,
            true);
        writer.write();
    } catch (const std::exception&) {
        fail(QPDFAdapterErrorCode::cannot_write_output, "无法加密并写入 PDF 输出文件");
    }
}

struct PDFRectangle {
    double minimum_x{0};
    double minimum_y{0};
    double maximum_x{0};
    double maximum_y{0};
};

PDFRectangle media_box_for(QPDFPageObjectHelper& page) {
    const auto box = page.getMediaBox();
    if (!box.isRectangle()) {
        fail(QPDFAdapterErrorCode::invalid_document, "PDF 页面缺少有效的 MediaBox");
    }
    const auto values = box.getArrayAsVector();
    if (values.size() != 4) {
        fail(QPDFAdapterErrorCode::invalid_document, "PDF 页面 MediaBox 无效");
    }
    const auto first_x = values[0].getNumericValue();
    const auto first_y = values[1].getNumericValue();
    const auto second_x = values[2].getNumericValue();
    const auto second_y = values[3].getNumericValue();
    return {
        .minimum_x = std::min(first_x, second_x),
        .minimum_y = std::min(first_y, second_y),
        .maximum_x = std::max(first_x, second_x),
        .maximum_y = std::max(first_y, second_y),
    };
}

void apply_crop_box(QPDFPageObjectHelper& page, const PDFCropBox& crop_box) {
    const auto right = crop_box.x + crop_box.width;
    const auto top = crop_box.y + crop_box.height;
    if (!PDFProcessing::is_valid_crop_box(crop_box)
        || !std::isfinite(right)
        || !std::isfinite(top)) {
        fail(QPDFAdapterErrorCode::invalid_crop_box, "PDF 裁剪区域无效");
    }

    const auto media_box = media_box_for(page);
    if (crop_box.x < media_box.minimum_x || crop_box.y < media_box.minimum_y
        || right > media_box.maximum_x || top > media_box.maximum_y) {
        fail(QPDFAdapterErrorCode::invalid_crop_box, "PDF 裁剪区域超出页面范围");
    }

    const std::vector<QPDFObjectHandle> values{
        QPDFObjectHandle::newReal(crop_box.x, 8),
        QPDFObjectHandle::newReal(crop_box.y, 8),
        QPDFObjectHandle::newReal(right, 8),
        QPDFObjectHandle::newReal(top, 8),
    };
    page.getObjectHandle().replaceKey("/CropBox", QPDFObjectHandle::newArray(values));
}

std::optional<std::string> metadata_value(
    const QPDFObjectHandle& info,
    std::string_view key) {
    if (!info.hasKey(std::string(key))) {
        return std::nullopt;
    }
    const auto value = info.getKey(std::string(key));
    return value.isString() ? std::optional{value.getUTF8Value()} : std::nullopt;
}

std::vector<std::string> split_keywords(std::string_view keywords) {
    std::vector<std::string> result;
    std::size_t start = 0;
    while (start <= keywords.size()) {
        const auto comma = keywords.find(',', start);
        auto item = keywords.substr(
            start,
            comma == std::string_view::npos ? std::string_view::npos : comma - start);
        while (!item.empty() && (item.front() == ' ' || item.front() == '\t')) {
            item.remove_prefix(1);
        }
        while (!item.empty() && (item.back() == ' ' || item.back() == '\t')) {
            item.remove_suffix(1);
        }
        if (!item.empty()) {
            result.emplace_back(item);
        }
        if (comma == std::string_view::npos) {
            break;
        }
        start = comma + 1;
    }
    return result;
}

std::string join_keywords(std::span<const std::string> keywords) {
    std::string result;
    for (std::size_t index = 0; index < keywords.size(); ++index) {
        if (index != 0) {
            result += ", ";
        }
        result += keywords[index];
    }
    return result;
}

void set_metadata_value(
    QPDFObjectHandle& info,
    std::string_view key,
    const std::optional<std::string>& value) {
    if (value) {
        info.replaceKey(std::string(key), QPDFObjectHandle::newUnicodeString(*value));
    }
}

}  // namespace

QPDFAdapterError::QPDFAdapterError(QPDFAdapterErrorCode code, std::string message)
    : std::runtime_error(std::move(message)),
      code_(code) {}

QPDFAdapterErrorCode QPDFAdapterError::code() const noexcept {
    return code_;
}

PDFDocumentSummary QPDFAdapter::inspect(const fs::path& input) const {
    return inspect_document(normalized_input_path(input));
}

PDFDocumentMetadata QPDFAdapter::metadata(const fs::path& input) const {
    const auto source = normalized_input_path(input);
    auto document = load_document(source);
    try {
        const auto trailer = document->getTrailer();
        if (!trailer.hasKey("/Info")) {
            return {};
        }
        const auto info = trailer.getKey("/Info");
        if (!info.isDictionary()) {
            return {};
        }
        PDFDocumentMetadata metadata{
            .title = metadata_value(info, "/Title"),
            .author = metadata_value(info, "/Author"),
            .subject = metadata_value(info, "/Subject"),
            .creator = metadata_value(info, "/Creator"),
        };
        if (const auto keywords = metadata_value(info, "/Keywords")) {
            metadata.keywords = split_keywords(*keywords);
        }
        return metadata;
    } catch (const QPDFAdapterError&) {
        throw;
    } catch (const std::exception&) {
        fail(QPDFAdapterErrorCode::invalid_document, "无法读取 PDF 元数据");
    }
}

void QPDFAdapter::merge(
    std::span<const fs::path> inputs,
    const fs::path& output) const {
    if (inputs.empty()) {
        fail(QPDFAdapterErrorCode::invalid_page_selection, "至少需要选择一个 PDF 文件");
    }

    std::vector<fs::path> sources;
    sources.reserve(inputs.size());
    for (const auto& input : inputs) {
        sources.push_back(normalized_input_path(input));
    }
    const std::vector<fs::path> outputs{output};
    validate_outputs(sources, outputs);

    PendingOutput pending(output);
    QPDF merged;
    merged.emptyPDF();
    QPDFPageDocumentHelper merged_pages(merged);
    for (const auto& source : sources) {
        auto document = load_document(source);
        for (auto page : pages_for(*document)) {
            merged_pages.addPage(page, false);
        }
    }
    write_document(merged, pending);
    pending.commit();
}

void QPDFAdapter::export_pages(
    const fs::path& input,
    std::span<const std::size_t> page_indexes,
    const fs::path& output) const {
    const auto source = normalized_input_path(input);
    const std::vector<fs::path> inputs{source};
    const std::vector<fs::path> outputs{output};
    validate_outputs(inputs, outputs);

    auto document = load_document(source);
    const auto pages = pages_for(*document);
    ensure_pages_selected(page_indexes, pages.size());

    PendingOutput pending(output);
    QPDF extracted;
    extracted.emptyPDF();
    QPDFPageDocumentHelper extracted_pages(extracted);
    for (const auto page_index : page_indexes) {
        extracted_pages.addPage(pages[page_index], false);
    }
    write_document(extracted, pending);
    pending.commit();
}

void QPDFAdapter::split(
    const fs::path& input,
    std::span<const std::vector<std::size_t>> page_groups,
    std::span<const fs::path> outputs) const {
    if (page_groups.empty() || page_groups.size() != outputs.size()) {
        fail(QPDFAdapterErrorCode::invalid_page_selection, "PDF 拆分页面和输出文件数量不一致");
    }

    const auto source = normalized_input_path(input);
    auto document = load_document(source);
    const auto pages = pages_for(*document);
    for (const auto& page_group : page_groups) {
        ensure_pages_selected(page_group, pages.size());
    }

    const std::vector<fs::path> inputs{source};
    validate_outputs(inputs, outputs);

    std::vector<PendingOutput> pending_outputs;
    pending_outputs.reserve(outputs.size());
    for (const auto& output : outputs) {
        pending_outputs.emplace_back(output);
    }

    for (std::size_t group_index = 0; group_index < page_groups.size(); ++group_index) {
        QPDF split_document;
        split_document.emptyPDF();
        QPDFPageDocumentHelper split_pages(split_document);
        for (const auto page_index : page_groups[group_index]) {
            split_pages.addPage(pages[page_index], false);
        }
        write_document(split_document, pending_outputs[group_index]);
    }
    commit_outputs(pending_outputs);
}

void QPDFAdapter::rotate(
    const fs::path& input,
    std::span<const std::size_t> page_indexes,
    int degrees,
    const fs::path& output) const {
    if (!PDFProcessing::is_valid_rotation(degrees)) {
        fail(QPDFAdapterErrorCode::invalid_rotation, "PDF 旋转角度必须是 90 度的整数倍");
    }

    const auto source = normalized_input_path(input);
    const std::vector<fs::path> inputs{source};
    const std::vector<fs::path> outputs{output};
    validate_outputs(inputs, outputs);

    auto document = load_document(source);
    auto pages = pages_for(*document);
    ensure_pages_selected(page_indexes, pages.size());
    for (const auto page_index : page_indexes) {
        pages[page_index].rotatePage(degrees, true);
    }

    PendingOutput pending(output);
    write_document(*document, pending);
    pending.commit();
}

void QPDFAdapter::crop(
    const fs::path& input,
    std::span<const std::size_t> page_indexes,
    const PDFCropBox& crop_box,
    const fs::path& output) const {
    if (!PDFProcessing::is_valid_crop_box(crop_box)) {
        fail(QPDFAdapterErrorCode::invalid_crop_box, "PDF 裁剪区域无效");
    }

    const auto source = normalized_input_path(input);
    const std::vector<fs::path> inputs{source};
    const std::vector<fs::path> outputs{output};
    validate_outputs(inputs, outputs);

    auto document = load_document(source);
    auto pages = pages_for(*document);
    ensure_pages_selected(page_indexes, pages.size());
    for (const auto page_index : page_indexes) {
        apply_crop_box(pages[page_index], crop_box);
    }

    PendingOutput pending(output);
    write_document(*document, pending);
    pending.commit();
}

void QPDFAdapter::update_metadata(
    const fs::path& input,
    const PDFDocumentMetadata& metadata,
    const fs::path& output) const {
    const auto source = normalized_input_path(input);
    const std::vector<fs::path> inputs{source};
    const std::vector<fs::path> outputs{output};
    validate_outputs(inputs, outputs);

    auto document = load_document(source);
    try {
        auto trailer = document->getTrailer();
        auto info = trailer.hasKey("/Info") ? trailer.getKey("/Info") : QPDFObjectHandle{};
        if (!info.isDictionary()) {
            info = QPDFObjectHandle::newDictionary();
            trailer.replaceKey("/Info", info);
        }
        set_metadata_value(info, "/Title", metadata.title);
        set_metadata_value(info, "/Author", metadata.author);
        set_metadata_value(info, "/Subject", metadata.subject);
        set_metadata_value(info, "/Creator", metadata.creator);
        if (metadata.keywords) {
            info.replaceKey(
                "/Keywords",
                QPDFObjectHandle::newUnicodeString(join_keywords(*metadata.keywords)));
        }
    } catch (const QPDFAdapterError&) {
        throw;
    } catch (const std::exception&) {
        fail(QPDFAdapterErrorCode::invalid_document, "无法更新 PDF 元数据");
    }

    PendingOutput pending(output);
    write_document(*document, pending);
    pending.commit();
}

void QPDFAdapter::protect(
    const fs::path& input,
    const PDFPasswordProtection& protection,
    const fs::path& output) const {
    if (!PDFProcessing::has_password(protection)
        || contains_nul(protection.user_password)
        || contains_nul(protection.owner_password)) {
        fail(QPDFAdapterErrorCode::invalid_password, "PDF 密码不能为空且不能包含空字符");
    }

    const auto source = normalized_input_path(input);
    const std::vector<fs::path> inputs{source};
    const std::vector<fs::path> outputs{output};
    validate_outputs(inputs, outputs);

    auto document = load_document(source);
    PendingOutput pending(output);
    write_protected_document(*document, protection, pending);
    pending.commit();
}

void QPDFAdapter::unlock(
    const fs::path& input,
    std::string_view password,
    const fs::path& output) const {
    if (contains_nul(password)) {
        fail(QPDFAdapterErrorCode::incorrect_password, "PDF 密码无效");
    }

    const auto source = normalized_input_path(input);
    const std::vector<fs::path> inputs{source};
    const std::vector<fs::path> outputs{output};
    validate_outputs(inputs, outputs);

    auto document = load_document(source, password, true);
    if (!document->isEncrypted()) {
        fail(QPDFAdapterErrorCode::invalid_document, "PDF 未加密，无需解锁");
    }

    PendingOutput pending(output);
    write_document(*document, pending);
    pending.commit();
}

}  // namespace zisla::pdf
