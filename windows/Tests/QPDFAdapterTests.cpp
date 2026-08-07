#include "QPDFAdapter.hpp"

#include <qpdf/QPDF.hh>
#include <qpdf/QPDFObjectHandle.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFPageObjectHelper.hh>

#include <array>
#include <chrono>
#include <cmath>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

namespace fs = std::filesystem;

using zisla::core::PDFDocumentMetadata;
using zisla::pdf::QPDFAdapter;
using zisla::pdf::QPDFAdapterError;
using zisla::pdf::QPDFAdapterErrorCode;

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
        path_ = fs::temp_directory_path()
            / ("zisla-windows-qpdf-adapter-" + std::to_string(suffix));
        fs::create_directories(path_);
    }

    ~TemporaryDirectory() {
        std::error_code error;
        fs::remove_all(path_, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    [[nodiscard]] const fs::path& path() const noexcept {
        return path_;
    }

private:
    fs::path path_;
};

std::string path_as_utf8(const fs::path& path) {
    const auto encoded = path.u8string();
    std::string result;
    result.reserve(encoded.size());
    for (const auto character : encoded) {
        result.push_back(static_cast<char>(character));
    }
    return result;
}

void write_pdf(
    const fs::path& output,
    std::span<const int> rotations = {}) {
    const auto page_count = rotations.empty() ? std::size_t{1} : rotations.size();
    const auto object_count = 2 + page_count * 2;
    std::vector<std::string> objects(object_count + 1);
    objects[1] = "<< /Type /Catalog /Pages 2 0 R >>";

    std::string kids;
    for (std::size_t index = 0; index < page_count; ++index) {
        kids += std::to_string(3 + index * 2) + " 0 R ";
    }
    objects[2] = "<< /Type /Pages /Kids [ " + kids + "] /Count "
        + std::to_string(page_count) + " >>";

    for (std::size_t index = 0; index < page_count; ++index) {
        const auto page_object = 3 + index * 2;
        const auto content_object = page_object + 1;
        const auto rotation = rotations.empty() ? 0 : rotations[index];
        objects[page_object] = "<< /Type /Page /Parent 2 0 R /MediaBox [ 0 0 200 200 ] /Resources << >>"
            " /Rotate " + std::to_string(rotation) + " /Contents "
            + std::to_string(content_object) + " 0 R >>";
        objects[content_object] = "<< /Length 0 >>\nstream\n\nendstream";
    }

    std::ofstream stream(output, std::ios::binary);
    if (!stream) {
        throw std::runtime_error("cannot create PDF fixture");
    }
    stream << "%PDF-1.4\n";
    std::vector<std::streamoff> offsets(object_count + 1);
    for (std::size_t object = 1; object <= object_count; ++object) {
        offsets[object] = stream.tellp();
        stream << object << " 0 obj\n" << objects[object] << "\nendobj\n";
    }
    const auto xref_offset = stream.tellp();
    stream << "xref\n0 " << object_count + 1 << "\n0000000000 65535 f \n";
    for (std::size_t object = 1; object <= object_count; ++object) {
        stream.width(10);
        stream.fill('0');
        stream << offsets[object] << " 00000 n \n";
    }
    stream << "trailer\n<< /Size " << object_count + 1
           << " /Root 1 0 R >>\nstartxref\n" << xref_offset << "\n%%EOF\n";
    if (!stream) {
        throw std::runtime_error("cannot write PDF fixture");
    }
}

int page_rotation(const fs::path& input, std::size_t page_index) {
    QPDF document;
    const auto path = path_as_utf8(input);
    document.processFile(path.c_str());
    auto pages = QPDFPageDocumentHelper(document).getAllPages();
    const auto rotation = pages.at(page_index).getAttribute("/Rotate", false);
    return rotation.isNull() ? 0 : static_cast<int>(rotation.getNumericValue());
}

std::array<double, 4> page_crop_box(const fs::path& input, std::size_t page_index) {
    QPDF document;
    const auto path = path_as_utf8(input);
    document.processFile(path.c_str());
    auto pages = QPDFPageDocumentHelper(document).getAllPages();
    const auto values = pages.at(page_index).getCropBox().getArrayAsVector();
    if (values.size() != 4) {
        throw std::runtime_error("crop box must contain four values");
    }
    return {
        values[0].getNumericValue(),
        values[1].getNumericValue(),
        values[2].getNumericValue(),
        values[3].getNumericValue(),
    };
}

void expect_error(
    const std::function<void()>& operation,
    QPDFAdapterErrorCode expected_code,
    std::string_view message) {
    try {
        operation();
    } catch (const QPDFAdapterError& error) {
        expect(error.code() == expected_code, message);
        return;
    }
    throw std::runtime_error(std::string(message));
}

void inspect_reports_page_count_and_locked_encryption() {
    TemporaryDirectory temporary;
    const auto source = temporary.path() / "source.pdf";
    const auto protected_output = temporary.path() / "protected.pdf";
    const std::array rotations{0, 90};
    write_pdf(source, rotations);

    QPDFAdapter adapter;
    const auto source_summary = adapter.inspect(source);
    expect(source_summary.page_count == 2, "inspection should report every PDF page");
    expect(source_summary.file_size > 0, "inspection should report PDF file size");
    expect(!source_summary.is_encrypted && !source_summary.is_locked,
        "plain PDF inspection should report an unlocked document");

    adapter.protect(source, {"open-sesame", "owner-secret"}, protected_output);
    const auto protected_summary = adapter.inspect(protected_output);
    expect(protected_summary.page_count == 0
            && protected_summary.is_encrypted && protected_summary.is_locked,
        "inspection should expose password-protected PDFs without reading their pages");
}

void merge_export_and_split_preserve_requested_page_order() {
    TemporaryDirectory temporary;
    const auto first = temporary.path() / "first.pdf";
    const auto second = temporary.path() / "second.pdf";
    const auto merged = temporary.path() / "merged.pdf";
    const auto exported = temporary.path() / "exported.pdf";
    const auto part_one = temporary.path() / "part-one.pdf";
    const auto part_two = temporary.path() / "part-two.pdf";
    const std::array first_rotations{90};
    const std::array second_rotations{180, 270};
    write_pdf(first, first_rotations);
    write_pdf(second, second_rotations);

    QPDFAdapter adapter;
    const std::array inputs{first, second};
    adapter.merge(inputs, merged);
    expect(adapter.inspect(merged).page_count == 3, "merge should include every source page");
    expect(page_rotation(merged, 0) == 90 && page_rotation(merged, 1) == 180
            && page_rotation(merged, 2) == 270,
        "merge should preserve source order");

    const std::array selected_pages{std::size_t{2}, std::size_t{0}};
    adapter.export_pages(merged, selected_pages, exported);
    expect(adapter.inspect(exported).page_count == 2, "export should retain selected pages");
    expect(page_rotation(exported, 0) == 270 && page_rotation(exported, 1) == 90,
        "export should preserve the selected page order");

    const std::vector<std::vector<std::size_t>> groups{{0}, {1, 2}};
    const std::array outputs{part_one, part_two};
    adapter.split(merged, groups, outputs);
    expect(adapter.inspect(part_one).page_count == 1 && adapter.inspect(part_two).page_count == 2,
        "split should create every requested page group");
}

void rotate_and_crop_only_change_selected_pages() {
    TemporaryDirectory temporary;
    const auto source = temporary.path() / "source.pdf";
    const auto rotated = temporary.path() / "rotated.pdf";
    const auto cropped = temporary.path() / "cropped.pdf";
    const std::array rotations{0, 90};
    write_pdf(source, rotations);

    QPDFAdapter adapter;
    const std::array selected_page{std::size_t{1}};
    adapter.rotate(source, selected_page, 90, rotated);
    expect(page_rotation(rotated, 0) == 0 && page_rotation(rotated, 1) == 180,
        "rotation should apply only to the chosen page");

    adapter.crop(rotated, selected_page, {20, 20, 160, 150}, cropped);
    const auto first = page_crop_box(cropped, 0);
    const auto second = page_crop_box(cropped, 1);
    expect(first == std::array<double, 4>{0, 0, 200, 200},
        "crop should preserve the unselected page box");
    expect(second == std::array<double, 4>{20, 20, 180, 170},
        "crop should write the selected page CropBox");
}

void metadata_updates_are_structural_and_non_destructive() {
    TemporaryDirectory temporary;
    const auto source = temporary.path() / "source.pdf";
    const auto output = temporary.path() / "metadata.pdf";
    write_pdf(source);

    QPDFAdapter adapter;
    adapter.update_metadata(
        source,
        {
            .title = "Project Plan",
            .author = "zisla",
            .keywords = std::vector<std::string>{"internal", "2026"},
        },
        output);

    const auto metadata = adapter.metadata(output);
    expect(metadata.title == std::optional<std::string>{"Project Plan"}
            && metadata.author == std::optional<std::string>{"zisla"},
        "metadata updates should persist standard strings");
    expect(metadata.keywords
            == std::optional<std::vector<std::string>>{{"internal", "2026"}},
        "metadata updates should persist keywords");
    expect(adapter.inspect(source).page_count == 1,
        "metadata updates must leave the source PDF unchanged");
}

void protection_unlock_and_output_guards_are_enforced() {
    TemporaryDirectory temporary;
    const auto source = temporary.path() / "source.pdf";
    const auto protected_output = temporary.path() / "protected.pdf";
    const auto unlocked_output = temporary.path() / "unlocked.pdf";
    write_pdf(source);

    QPDFAdapter adapter;
    adapter.protect(source, {"open-sesame", "owner-secret"}, protected_output);
    expect_error(
        [&] { adapter.unlock(protected_output, "incorrect", unlocked_output); },
        QPDFAdapterErrorCode::incorrect_password,
        "unlock should reject an incorrect password");
    expect(!fs::exists(unlocked_output), "failed unlock should not create an output file");

    adapter.unlock(protected_output, "open-sesame", unlocked_output);
    const auto unlocked_summary = adapter.inspect(unlocked_output);
    expect(!unlocked_summary.is_encrypted && unlocked_summary.page_count == 1,
        "unlock should write an unencrypted copy");

    const std::array source_page{std::size_t{0}};
    expect_error(
        [&] { adapter.export_pages(source, source_page, source); },
        QPDFAdapterErrorCode::output_validation,
        "operations must refuse to replace their input PDF");
    expect(adapter.inspect(source).page_count == 1,
        "output validation must preserve the source PDF");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"inspection reports encryption", inspect_reports_page_count_and_locked_encryption},
        {"merge export and split preserve page order", merge_export_and_split_preserve_requested_page_order},
        {"rotate and crop selected pages", rotate_and_crop_only_change_selected_pages},
        {"metadata updates are structural", metadata_updates_are_structural_and_non_destructive},
        {"protection unlock and output guards", protection_unlock_and_output_guards_are_enforced},
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
