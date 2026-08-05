#include "zisla/core/PDFProcessing.hpp"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <optional>
#include <unordered_set>

namespace zisla::core {
namespace {

bool is_ascii_space(unsigned char value) noexcept {
    return value == ' ' || value == '\t' || value == '\n'
        || value == '\r' || value == '\f' || value == '\v';
}

std::string_view trim_ascii_space(std::string_view value) noexcept {
    while (!value.empty() && is_ascii_space(
        static_cast<unsigned char>(value.front()))) {
        value.remove_prefix(1);
    }
    while (!value.empty() && is_ascii_space(
        static_cast<unsigned char>(value.back()))) {
        value.remove_suffix(1);
    }
    return value;
}

bool has_bytes_at(
    std::string_view value,
    std::size_t index,
    unsigned char first,
    unsigned char second,
    unsigned char third) noexcept {
    return index + 3 <= value.size()
        && static_cast<unsigned char>(value[index]) == first
        && static_cast<unsigned char>(value[index + 1]) == second
        && static_cast<unsigned char>(value[index + 2]) == third;
}

std::string normalize_selection(std::string_view selection) {
    std::string normalized;
    normalized.reserve(selection.size());
    for (std::size_t index = 0; index < selection.size();) {
        const auto current = static_cast<unsigned char>(selection[index]);
        if (has_bytes_at(selection, index, 0xef, 0xbc, 0x90)
            || has_bytes_at(selection, index, 0xef, 0xbc, 0x91)
            || has_bytes_at(selection, index, 0xef, 0xbc, 0x92)
            || has_bytes_at(selection, index, 0xef, 0xbc, 0x93)
            || has_bytes_at(selection, index, 0xef, 0xbc, 0x94)
            || has_bytes_at(selection, index, 0xef, 0xbc, 0x95)
            || has_bytes_at(selection, index, 0xef, 0xbc, 0x96)
            || has_bytes_at(selection, index, 0xef, 0xbc, 0x97)
            || has_bytes_at(selection, index, 0xef, 0xbc, 0x98)
            || has_bytes_at(selection, index, 0xef, 0xbc, 0x99)) {
            normalized.push_back(static_cast<char>('0' + (
                static_cast<unsigned char>(selection[index + 2]) - 0x90)));
            index += 3;
        } else if (has_bytes_at(selection, index, 0xef, 0xbc, 0x8c)
            || has_bytes_at(selection, index, 0xef, 0xbc, 0x9b)
            || has_bytes_at(selection, index, 0xe3, 0x80, 0x81)) {
            normalized.push_back(',');
            index += 3;
        } else if (has_bytes_at(selection, index, 0xef, 0xbc, 0x8d)
            || has_bytes_at(selection, index, 0xe2, 0x80, 0x93)
            || has_bytes_at(selection, index, 0xe2, 0x80, 0x94)
            || has_bytes_at(selection, index, 0xe2, 0x88, 0x92)
            || has_bytes_at(selection, index, 0xe8, 0x87, 0xb3)
            || has_bytes_at(selection, index, 0xef, 0xbd, 0x9e)) {
            normalized.push_back('-');
            index += 3;
        } else if (has_bytes_at(selection, index, 0xe3, 0x80, 0x80)) {
            normalized.push_back(' ');
            index += 3;
        } else if (current == ';') {
            normalized.push_back(',');
            ++index;
        } else if (current == '~') {
            normalized.push_back('-');
            ++index;
        } else {
            normalized.push_back(static_cast<char>(current));
            ++index;
        }
    }
    return normalized;
}

std::optional<std::size_t> parse_one_based_page(
    std::string_view value) noexcept {
    value = trim_ascii_space(value);
    if (value.empty()) {
        return std::nullopt;
    }

    std::size_t page = 0;
    const auto [pointer, error] = std::from_chars(
        value.data(),
        value.data() + value.size(),
        page);
    if (error != std::errc{} || pointer != value.data() + value.size()
        || page == 0) {
        return std::nullopt;
    }
    return page;
}

std::optional<std::filesystem::path> normalized_path(
    const std::filesystem::path& path) {
    if (path.empty()) {
        return std::nullopt;
    }

    std::error_code error;
    const auto absolute = std::filesystem::absolute(path, error);
    if (error) {
        return std::nullopt;
    }
    const auto canonical = std::filesystem::weakly_canonical(absolute, error);
    return error ? std::optional{absolute.lexically_normal()}
                 : std::optional{canonical.lexically_normal()};
}

bool paths_match(
    const std::filesystem::path& first,
    const std::filesystem::path& second) noexcept {
    if (first == second) {
        return true;
    }

    std::error_code error;
    return std::filesystem::equivalent(first, second, error) && !error;
}

}  // namespace

bool PDFPageSelectionResult::is_valid() const noexcept {
    return error == PDFPageSelectionError::none;
}

PDFPageSelectionResult PDFProcessing::parse_page_selection(
    std::string_view selection,
    std::size_t page_count) {
    const auto normalized = normalize_selection(selection);
    const auto trimmed = trim_ascii_space(normalized);
    if (trimmed.empty()) {
        return {.error = PDFPageSelectionError::empty_selection};
    }
    if (page_count == 0) {
        return {.error = PDFPageSelectionError::invalid_selection};
    }

    std::vector<std::size_t> indexes;
    std::unordered_set<std::size_t> seen;
    std::size_t component_start = 0;
    while (component_start <= trimmed.size()) {
        const auto separator = trimmed.find(',', component_start);
        const auto component = trim_ascii_space(trimmed.substr(
            component_start,
            separator == std::string_view::npos
                ? std::string_view::npos
                : separator - component_start));
        const auto range_separator = component.find('-');
        if (component.empty()
            || (range_separator != std::string_view::npos
                && component.find('-', range_separator + 1)
                    != std::string_view::npos)) {
            return {.error = PDFPageSelectionError::invalid_selection};
        }

        const auto first = parse_one_based_page(component.substr(
            0,
            range_separator));
        const auto last = range_separator == std::string_view::npos
            ? first
            : parse_one_based_page(component.substr(range_separator + 1));
        if (!first || !last || *first > *last || *last > page_count) {
            return {.error = PDFPageSelectionError::invalid_selection};
        }

        for (auto page = *first;; ++page) {
            const auto index = page - 1;
            if (seen.insert(index).second) {
                indexes.push_back(index);
            }
            if (page == *last) {
                break;
            }
        }

        if (separator == std::string_view::npos) {
            break;
        }
        component_start = separator + 1;
    }
    return {.page_indexes = std::move(indexes)};
}

bool PDFProcessing::has_valid_page_indexes(
    std::span<const std::size_t> page_indexes,
    std::size_t page_count) noexcept {
    return page_count > 0 && !page_indexes.empty()
        && std::all_of(
            page_indexes.begin(),
            page_indexes.end(),
            [page_count](std::size_t page_index) {
                return page_index < page_count;
            });
}

bool PDFProcessing::is_valid_rotation(int degrees) noexcept {
    return degrees % 90 == 0;
}

int PDFProcessing::normalized_rotation(int degrees) noexcept {
    const auto normalized = degrees % 360;
    return normalized < 0 ? normalized + 360 : normalized;
}

bool PDFProcessing::is_valid_crop_box(const PDFCropBox& crop_box) noexcept {
    return std::isfinite(crop_box.x) && std::isfinite(crop_box.y)
        && std::isfinite(crop_box.width) && std::isfinite(crop_box.height)
        && crop_box.width > 0 && crop_box.height > 0;
}

bool PDFProcessing::has_password(
    const PDFPasswordProtection& protection) noexcept {
    return !protection.user_password.empty() || !protection.owner_password.empty();
}

PDFOutputValidationError PDFProcessing::validate_outputs(
    std::span<const std::filesystem::path> input_paths,
    std::span<const std::filesystem::path> output_paths) {
    std::vector<std::filesystem::path> normalized_inputs;
    normalized_inputs.reserve(input_paths.size());
    for (const auto& input : input_paths) {
        if (const auto normalized = normalized_path(input)) {
            normalized_inputs.push_back(*normalized);
        }
    }

    std::vector<std::filesystem::path> normalized_outputs;
    normalized_outputs.reserve(output_paths.size());
    for (const auto& output : output_paths) {
        if (output.empty()) {
            return PDFOutputValidationError::empty_output_path;
        }
        const auto normalized = normalized_path(output);
        if (!normalized) {
            return PDFOutputValidationError::invalid_output_path;
        }
        for (const auto& input : normalized_inputs) {
            if (paths_match(input, *normalized)) {
                return PDFOutputValidationError::output_matches_input;
            }
        }
        for (const auto& existing : normalized_outputs) {
            if (paths_match(existing, *normalized)) {
                return PDFOutputValidationError::duplicate_output;
            }
        }
        normalized_outputs.push_back(*normalized);
    }

    for (const auto& output : normalized_outputs) {
        std::error_code error;
        if (std::filesystem::exists(output, error)) {
            return PDFOutputValidationError::output_already_exists;
        }
        if (error) {
            return PDFOutputValidationError::invalid_output_path;
        }
    }
    return PDFOutputValidationError::none;
}

}  // namespace zisla::core
