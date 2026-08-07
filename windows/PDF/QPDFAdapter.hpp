#pragma once

#include <zisla/core/PDFProcessing.hpp>

#include <cstddef>
#include <filesystem>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::pdf {

enum class QPDFAdapterErrorCode {
    invalid_input,
    invalid_document,
    locked_document,
    incorrect_password,
    invalid_page_selection,
    invalid_rotation,
    invalid_crop_box,
    invalid_password,
    output_validation,
    cannot_create_output_directory,
    cannot_write_output,
};

class QPDFAdapterError : public std::runtime_error {
public:
    QPDFAdapterError(QPDFAdapterErrorCode code, std::string message);

    [[nodiscard]] QPDFAdapterErrorCode code() const noexcept;

private:
    QPDFAdapterErrorCode code_;
};

class QPDFAdapter {
public:
    [[nodiscard]] zisla::core::PDFDocumentSummary inspect(
        const std::filesystem::path& input) const;
    [[nodiscard]] zisla::core::PDFDocumentMetadata metadata(
        const std::filesystem::path& input) const;

    void merge(
        std::span<const std::filesystem::path> inputs,
        const std::filesystem::path& output) const;
    void export_pages(
        const std::filesystem::path& input,
        std::span<const std::size_t> page_indexes,
        const std::filesystem::path& output) const;
    void split(
        const std::filesystem::path& input,
        std::span<const std::vector<std::size_t>> page_groups,
        std::span<const std::filesystem::path> outputs) const;
    void rotate(
        const std::filesystem::path& input,
        std::span<const std::size_t> page_indexes,
        int degrees,
        const std::filesystem::path& output) const;
    void crop(
        const std::filesystem::path& input,
        std::span<const std::size_t> page_indexes,
        const zisla::core::PDFCropBox& crop_box,
        const std::filesystem::path& output) const;
    void update_metadata(
        const std::filesystem::path& input,
        const zisla::core::PDFDocumentMetadata& metadata,
        const std::filesystem::path& output) const;
    void protect(
        const std::filesystem::path& input,
        const zisla::core::PDFPasswordProtection& protection,
        const std::filesystem::path& output) const;
    void unlock(
        const std::filesystem::path& input,
        std::string_view password,
        const std::filesystem::path& output) const;
};

}  // namespace zisla::pdf
