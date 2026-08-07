#include "LocalOfficeAdapter.hpp"

#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

namespace fs = std::filesystem;

using zisla::pdf::LocalOfficeAdapter;
using zisla::pdf::LocalOfficeAdapterError;
using zisla::pdf::LocalOfficeAdapterErrorCode;

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
            / ("zisla-windows-office-adapter-" + std::to_string(suffix));
        fs::create_directories(path_);
    }

    ~TemporaryDirectory() {
        std::error_code error;
        fs::remove_all(path_, error);
    }

    [[nodiscard]] const fs::path& path() const noexcept {
        return path_;
    }

private:
    fs::path path_;
};

void expect_error(
    const std::function<void()>& operation,
    LocalOfficeAdapterErrorCode expected_code,
    std::string_view message) {
    try {
        operation();
    } catch (const LocalOfficeAdapterError& error) {
        expect(error.code() == expected_code, message);
        return;
    }
    throw std::runtime_error(std::string(message));
}

void recognizes_supported_office_formats() {
    expect(LocalOfficeAdapter::supports("report.docx"), "DOCX must be supported");
    expect(LocalOfficeAdapter::supports("report.PPTX"), "PPTX matching must ignore case");
    expect(LocalOfficeAdapter::supports("report.xlsx"), "XLSX must be supported");
    expect(LocalOfficeAdapter::supports("report.ods"), "ODS must be supported");
    expect(LocalOfficeAdapter::supports("report.csv"), "CSV must be supported");
    expect(!LocalOfficeAdapter::supports("report.pdf"), "PDF must not be re-converted as Office");
    expect(!LocalOfficeAdapter::supports("report.pages"), "unsupported office formats must be rejected");
}

void creates_an_isolated_profile_argument() {
    const auto arguments = LocalOfficeAdapter::conversion_arguments(
        "/zisla-tests/input.docx",
        "/zisla-tests/output",
        "/zisla-tests/profile folder");

    expect(arguments.size() == 7, "LibreOffice conversion must have the expected argument count");
    expect(arguments.front() == "-env:UserInstallation=file:///zisla-tests/profile%20folder/",
        "LibreOffice profile must be an isolated file URI");
    expect(arguments[1] == "--headless" && arguments[2] == "--convert-to"
            && arguments[3] == "pdf",
        "LibreOffice conversion must be headless PDF conversion");
    expect(arguments[4] == "--outdir" && arguments[5] == "/zisla-tests/output"
            && arguments[6] == "/zisla-tests/input.docx",
        "LibreOffice conversion must keep input and output separate");
}

void validates_inputs_outputs_and_missing_converter() {
    TemporaryDirectory temporary;
    const auto document = temporary.path() / "document.docx";
    const auto output = temporary.path() / "document.pdf";
    std::ofstream(document, std::ios::binary) << "not-a-real-docx";

    LocalOfficeAdapter adapter{std::vector<fs::path>{}};
    expect_error(
        [&] { adapter.convert_to_pdf(temporary.path() / "unsupported.pdf", output); },
        LocalOfficeAdapterErrorCode::invalid_input,
        "unsupported input must fail before process launch");
    expect_error(
        [&] { adapter.convert_to_pdf(document, output); },
        LocalOfficeAdapterErrorCode::converter_not_installed,
        "missing local LibreOffice must be reported without downloading anything");

    std::ofstream(output, std::ios::binary) << "existing";
    expect_error(
        [&] { adapter.convert_to_pdf(document, output); },
        LocalOfficeAdapterErrorCode::output_validation,
        "Office conversion must not overwrite an existing PDF");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"recognizes supported office formats", recognizes_supported_office_formats},
        {"creates an isolated profile argument", creates_an_isolated_profile_argument},
        {"validates inputs outputs and missing converter", validates_inputs_outputs_and_missing_converter},
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
