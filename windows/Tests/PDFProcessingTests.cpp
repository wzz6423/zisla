#include "zisla/core/PDFProcessing.hpp"

#include <array>
#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        const auto suffix = std::chrono::steady_clock::now()
            .time_since_epoch().count();
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-windows-pdf-processing-" + std::to_string(suffix));
        std::filesystem::create_directories(path_);
    }

    ~TemporaryDirectory() {
        std::error_code error;
        std::filesystem::remove_all(path_, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_;
};

void pageSelectionPreservesOrderAndDeduplicates() {
    const auto result = PDFProcessing::parse_page_selection("3, 1-2, 1", 3);
    expect(result.is_valid(), "a valid page selection should parse");
    expect(result.page_indexes == std::vector<std::size_t>{2, 0, 1},
        "page selection should preserve first-seen order and deduplicate");
}

void pageSelectionAcceptsChineseKeyboardAliases() {
    constexpr auto selection = "\xef\xbc\x93\xef\xbc\x8c\xe3\x80\x80\xef\xbc\x91\x20"
        "\xe2\x80\x94\x20\xef\xbc\x92";
    const auto result = PDFProcessing::parse_page_selection(selection, 3);
    expect(result.is_valid(), "fullwidth digits and separators should parse");
    expect(result.page_indexes == std::vector<std::size_t>{2, 0, 1},
        "fullwidth page ranges should match their ASCII form");

    const auto aliases = PDFProcessing::parse_page_selection(
        "1\xe8\x87\xb3" "2; 3~3",
        3);
    expect(aliases.is_valid()
            && aliases.page_indexes == std::vector<std::size_t>{0, 1, 2},
        "Chinese and ASCII range aliases should normalize consistently");
}

void pageSelectionReportsEmptyAndInvalidInput() {
    expect(PDFProcessing::parse_page_selection("  ", 3).error
            == PDFPageSelectionError::empty_selection,
        "an empty selection should have a distinct error");
    expect(PDFProcessing::parse_page_selection("1-4", 3).error
            == PDFPageSelectionError::invalid_selection,
        "out-of-range pages should be rejected");
    expect(PDFProcessing::parse_page_selection("1,,2", 3).error
            == PDFPageSelectionError::invalid_selection,
        "empty range components should be rejected");
    expect(PDFProcessing::parse_page_selection("0", 3).error
            == PDFPageSelectionError::invalid_selection,
        "page selection remains one-based at the UI seam");
}

void explicitPageIndexesAreValidatedWithoutChangingOrder() {
    const std::array valid{std::size_t{2}, std::size_t{0}, std::size_t{2}};
    expect(PDFProcessing::has_valid_page_indexes(valid, 3),
        "operations may intentionally repeat and reorder pages");
    const std::array out_of_range{std::size_t{3}};
    expect(!PDFProcessing::has_valid_page_indexes(out_of_range, 3),
        "out-of-range page indexes should be rejected");
    const std::array<std::size_t, 0> empty{};
    expect(!PDFProcessing::has_valid_page_indexes(empty, 3),
        "page operations require at least one page");
}

void editParametersFollowTheMacOSContract() {
    expect(PDFProcessing::is_valid_rotation(-90)
            && PDFProcessing::normalized_rotation(-90) == 270,
        "negative right-angle rotation should normalize to PDF degrees");
    expect(PDFProcessing::is_valid_rotation(450)
            && PDFProcessing::normalized_rotation(450) == 90,
        "large right-angle rotation should normalize");
    expect(!PDFProcessing::is_valid_rotation(45),
        "non-right-angle rotation should be rejected");
    expect(PDFProcessing::is_valid_crop_box({20, 20, 160, 150}),
        "positive finite crop boxes should be accepted");
    expect(!PDFProcessing::is_valid_crop_box({0, 0, 0, 150})
            && !PDFProcessing::is_valid_crop_box({
                0,
                0,
                std::numeric_limits<double>::infinity(),
                150,
            }),
        "zero or non-finite crop sizes should be rejected");
    expect(PDFProcessing::has_password({"open", ""})
            && PDFProcessing::has_password({"", "owner"})
            && !PDFProcessing::has_password({"", ""}),
        "password protection needs either an open or owner password");
}

void outputValidationProtectsInputsBeforeAnEngineWrites() {
    TemporaryDirectory temporary;
    const auto input = temporary.path() / "source.pdf";
    const auto existing = temporary.path() / "existing.pdf";
    const auto output = temporary.path() / "output.pdf";
    std::ofstream(input).put('x');
    std::ofstream(existing).put('x');

    const std::array inputs{input};
    const std::array same_as_input{input};
    expect(PDFProcessing::validate_outputs(inputs, same_as_input)
            == PDFOutputValidationError::output_matches_input,
        "an output must never overwrite an input");
    const std::array existing_output{existing};
    expect(PDFProcessing::validate_outputs(inputs, existing_output)
            == PDFOutputValidationError::output_already_exists,
        "an output must not silently replace an existing file");
    const std::array duplicate_outputs{output, output};
    expect(PDFProcessing::validate_outputs(inputs, duplicate_outputs)
            == PDFOutputValidationError::duplicate_output,
        "split outputs must be unique before any file is written");
    const std::array<std::filesystem::path, 1> empty_output{};
    expect(PDFProcessing::validate_outputs(inputs, empty_output)
            == PDFOutputValidationError::empty_output_path,
        "empty output paths should be rejected before execution");
    const std::array usable_output{output};
    expect(PDFProcessing::validate_outputs(inputs, usable_output)
            == PDFOutputValidationError::none,
        "a distinct missing output should be accepted");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"page selection preserves order", pageSelectionPreservesOrderAndDeduplicates},
        {"page selection accepts Chinese aliases", pageSelectionAcceptsChineseKeyboardAliases},
        {"page selection rejects invalid input", pageSelectionReportsEmptyAndInvalidInput},
        {"explicit page indexes validate", explicitPageIndexesAreValidatedWithoutChangingOrder},
        {"edit parameters follow contract", editParametersFollowTheMacOSContract},
        {"output validation protects inputs", outputValidationProtectsInputsBeforeAnEngineWrites},
    };

    std::size_t passed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            ++passed;
        } catch (const std::exception& error) {
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }
    std::cout << passed << '/' << std::size(tests) << " tests passed\n";
    return passed == std::size(tests) ? 0 : 1;
}
