#pragma once

#include <zisla/core/PDFProcessing.hpp>

#include <cstddef>
#include <filesystem>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace zisla::pdf {

enum class PDFiumAdapterErrorCode {
    invalid_input,
    invalid_document,
    locked_document,
    incorrect_password,
    invalid_page_selection,
    invalid_render_options,
    unsupported_image,
    invalid_watermark,
    invalid_watermark_scale,
    missing_font,
    output_validation,
    cannot_create_output_directory,
    cannot_write_output,
    cannot_save_document,
};

class PDFiumAdapterError : public std::runtime_error {
public:
    PDFiumAdapterError(PDFiumAdapterErrorCode code, std::string message);

    [[nodiscard]] PDFiumAdapterErrorCode code() const noexcept;

private:
    PDFiumAdapterErrorCode code_;
};

enum class PDFRasterImageFormat {
    png,
    jpeg,
};

enum class PDFOverlayPosition {
    top_leading,
    top,
    top_trailing,
    leading,
    center,
    trailing,
    bottom_leading,
    bottom,
    bottom_trailing,
};

struct PDFTextWatermark {
    std::string text;
    double font_size{42};
    double opacity{0.22};
    double rotation_degrees{-35};
    std::filesystem::path font_path;
};

struct PDFImageWatermark {
    std::filesystem::path image_path;
    PDFOverlayPosition position{PDFOverlayPosition::center};
    double scale{0.25};
    double opacity{0.3};
};

struct PDFPageNumberStyle {
    std::string prefix;
    std::string suffix;
    double font_size{11};
    PDFOverlayPosition position{PDFOverlayPosition::bottom};
    double inset{24};
    std::filesystem::path font_path;
};

class PDFiumAdapter {
public:
    [[nodiscard]] zisla::core::PDFDocumentSummary inspect(
        const std::filesystem::path& input) const;

    void extract_text(
        const std::filesystem::path& input,
        std::vector<std::size_t> page_indexes,
        const std::filesystem::path& output) const;
    [[nodiscard]] std::vector<std::filesystem::path> render_pages(
        const std::filesystem::path& input,
        const std::filesystem::path& output_directory,
        PDFRasterImageFormat format = PDFRasterImageFormat::png,
        int dpi = 144) const;

    void convert_images_to_pdf(
        std::span<const std::filesystem::path> inputs,
        const std::filesystem::path& output) const;

    void add_text_watermark(
        const std::filesystem::path& input,
        const PDFTextWatermark& watermark,
        const std::filesystem::path& output) const;

    void add_image_watermark(
        const std::filesystem::path& input,
        const PDFImageWatermark& watermark,
        const std::filesystem::path& output) const;

    void add_page_numbers(
        const std::filesystem::path& input,
        const PDFPageNumberStyle& style,
        const std::filesystem::path& output) const;
};

}  // namespace zisla::pdf
