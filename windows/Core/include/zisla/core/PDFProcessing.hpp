#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace zisla::core {

enum class PDFPageSelectionError {
    none,
    empty_selection,
    invalid_selection,
};

struct PDFPageSelectionResult {
    PDFPageSelectionError error{PDFPageSelectionError::none};
    std::vector<std::size_t> page_indexes;

    [[nodiscard]] bool is_valid() const noexcept;
};

struct PDFCropBox {
    double x{0};
    double y{0};
    double width{0};
    double height{0};

    friend bool operator==(const PDFCropBox&, const PDFCropBox&) = default;
};

struct PDFPasswordProtection {
    std::string user_password;
    std::string owner_password;

    friend bool operator==(
        const PDFPasswordProtection&,
        const PDFPasswordProtection&) = default;
};

struct PDFDocumentSummary {
    std::size_t page_count{0};
    std::uintmax_t file_size{0};
    bool is_encrypted{false};
    bool is_locked{false};

    friend bool operator==(const PDFDocumentSummary&, const PDFDocumentSummary&) = default;
};

struct PDFDocumentMetadata {
    std::optional<std::string> title;
    std::optional<std::string> author;
    std::optional<std::string> subject;
    std::optional<std::string> creator;
    std::optional<std::vector<std::string>> keywords;

    friend bool operator==(const PDFDocumentMetadata&, const PDFDocumentMetadata&) = default;
};

enum class PDFOutputValidationError {
    none,
    empty_output_path,
    invalid_output_path,
    output_matches_input,
    output_already_exists,
    duplicate_output,
};

class PDFProcessing {
public:
    [[nodiscard]] static PDFPageSelectionResult parse_page_selection(
        std::string_view selection,
        std::size_t page_count);
    [[nodiscard]] static bool has_valid_page_indexes(
        std::span<const std::size_t> page_indexes,
        std::size_t page_count) noexcept;
    [[nodiscard]] static bool is_valid_rotation(int degrees) noexcept;
    [[nodiscard]] static int normalized_rotation(int degrees) noexcept;
    [[nodiscard]] static bool is_valid_crop_box(
        const PDFCropBox& crop_box) noexcept;
    [[nodiscard]] static bool has_password(
        const PDFPasswordProtection& protection) noexcept;
    [[nodiscard]] static PDFOutputValidationError validate_outputs(
        std::span<const std::filesystem::path> input_paths,
        std::span<const std::filesystem::path> output_paths);
};

}  // namespace zisla::core
