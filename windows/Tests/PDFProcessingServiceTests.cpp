#include "PDFProcessingService.hpp"

#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iterator>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <utility>

namespace {

namespace fs = std::filesystem;

using zisla::pdf::PDFProcessingPhase;
using zisla::pdf::PDFProcessingOperation;
using zisla::pdf::PDFProcessingRequest;
using zisla::pdf::PDFRasterImageFormat;
using zisla::pdf::PDFProcessingService;
using zisla::pdf::PDFProcessingSnapshot;

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
            / ("zisla-windows-pdf-service-" + std::to_string(suffix));
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

void write_pdf(const fs::path& output) {
    std::ofstream stream(output, std::ios::binary);
    if (!stream) {
        throw std::runtime_error("cannot create PDF fixture");
    }
    constexpr std::string_view catalog = "<< /Type /Catalog /Pages 2 0 R >>";
    constexpr std::string_view pages = "<< /Type /Pages /Kids [ 3 0 R ] /Count 1 >>";
    constexpr std::string_view page =
        "<< /Type /Page /Parent 2 0 R /MediaBox [ 0 0 200 200 ] "
        "/Resources << >> /Contents 4 0 R >>";
    constexpr std::string_view contents = "<< /Length 0 >>\nstream\n\nendstream";
    const std::string_view objects[]{catalog, pages, page, contents};

    stream << "%PDF-1.4\n";
    std::streamoff offsets[4]{};
    for (std::size_t index = 0; index < std::size(objects); ++index) {
        offsets[index] = stream.tellp();
        stream << index + 1 << " 0 obj\n" << objects[index] << "\nendobj\n";
    }
    const auto xref_offset = stream.tellp();
    stream << "xref\n0 5\n0000000000 65535 f \n";
    for (const auto offset : offsets) {
        stream.width(10);
        stream.fill('0');
        stream << offset << " 00000 n \n";
    }
    stream << "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n"
           << xref_offset << "\n%%EOF\n";
    if (!stream) {
        throw std::runtime_error("cannot write PDF fixture");
    }
}

std::shared_ptr<const PDFProcessingSnapshot> wait_for_terminal(
    PDFProcessingService& service,
    std::uint64_t request_id) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (std::chrono::steady_clock::now() < deadline) {
        const auto current = service.snapshot();
        if (current && current->request_id == request_id && current->terminal()) {
            return current;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    throw std::runtime_error("PDF service request did not finish");
}

void reads_and_updates_document_metadata() {
    TemporaryDirectory temporary;
    const auto source = temporary.path() / "source.pdf";
    const auto output = temporary.path() / "metadata.pdf";
    write_pdf(source);

    PDFProcessingService service;
    expect(service.start(), "PDF service should start");
    const auto inspect = wait_for_terminal(service, service.inspect(source));
    expect(inspect->phase == PDFProcessingPhase::succeeded
            && inspect->summary && inspect->summary->page_count == 1,
        "inspection should publish the document summary");

    const auto update = wait_for_terminal(
        service,
        service.update_metadata(
            source,
            {.title = "Windows PDF", .author = "zisla"},
            output));
    expect(update->phase == PDFProcessingPhase::succeeded
            && update->outputs == std::vector<fs::path>{output},
        "metadata updates should publish their output");

    const auto metadata = wait_for_terminal(service, service.read_metadata(output));
    expect(metadata->metadata && metadata->metadata->title == std::optional<std::string>{"Windows PDF"}
            && metadata->metadata->author == std::optional<std::string>{"zisla"},
        "metadata reads should publish standard metadata");
}

void serializes_dependent_operations() {
    TemporaryDirectory temporary;
    const auto first = temporary.path() / "first.pdf";
    const auto second = temporary.path() / "second.pdf";
    const auto merged = temporary.path() / "merged.pdf";
    const auto exported = temporary.path() / "exported.pdf";
    write_pdf(first);
    write_pdf(second);

    PDFProcessingService service;
    expect(service.start(), "PDF service should start");
    const auto merge_id = service.submit({
        .operation = PDFProcessingOperation::merge,
        .inputs = {first, second},
        .outputs = {merged},
    });
    const auto export_id = service.submit({
        .operation = PDFProcessingOperation::export_pages,
        .inputs = {merged},
        .outputs = {exported},
        .page_indexes = {1},
    });
    const auto export_result = wait_for_terminal(service, export_id);
    expect(export_result->phase == PDFProcessingPhase::succeeded
            && export_result->outputs == std::vector<fs::path>{exported},
        "dependent export should run after merge on the same queue");
    expect(fs::is_regular_file(merged) && fs::is_regular_file(exported),
        "serialized operations should create both outputs");

    const auto merge_result = service.snapshot();
    expect(merge_result->request_id == export_id && merge_id < export_id,
        "later requests should replace the visible snapshot after earlier work finishes");
    const auto inspected = wait_for_terminal(service, service.inspect(exported));
    expect(inspected->summary && inspected->summary->page_count == 1,
        "exported output should remain readable by the service");
}

void reports_adapter_failures_without_writing_output() {
    TemporaryDirectory temporary;
    const auto source = temporary.path() / "source.pdf";
    const auto output = temporary.path() / "invalid.pdf";
    write_pdf(source);

    PDFProcessingService service;
    expect(service.start(), "PDF service should start");
    const auto failure = wait_for_terminal(
        service,
        service.rotate(source, {0}, 45, output));
    expect(failure->phase == PDFProcessingPhase::failed && !failure->message.empty(),
        "adapter errors should become failed service snapshots");
    expect(!fs::exists(output), "failed operations must not leave an output file");
}

#if defined(ZISLA_HAS_PDFIUM_ADAPTER)
void routes_pdfium_operations_and_surfaces_failures() {
    TemporaryDirectory temporary;
    const auto source = temporary.path() / "source.pdf";
    const auto text_output = temporary.path() / "source.txt";
    const auto image_pdf = temporary.path() / "images.pdf";
    const auto watermark_output = temporary.path() / "watermarked.pdf";
    const auto render_directory = temporary.path() / "rendered";
    write_pdf(source);

    PDFProcessingService service;
    expect(service.start(), "PDF service should start");

    const auto extracted = wait_for_terminal(
        service,
        service.export_text(source, {0}, text_output));
    expect(extracted->phase == PDFProcessingPhase::succeeded
            && extracted->outputs == std::vector<fs::path>{text_output}
            && fs::is_regular_file(text_output),
        "text export should be dispatched to PDFium");

    const auto rendered = wait_for_terminal(
        service,
        service.render_pages(source, render_directory, PDFRasterImageFormat::png, 72));
    expect(rendered->phase == PDFProcessingPhase::succeeded
            && rendered->outputs.size() == 1
            && fs::is_regular_file(rendered->outputs.front()),
        "page rendering should publish every generated image");

    const auto converted = wait_for_terminal(
        service,
        service.convert_images_to_pdf(rendered->outputs, image_pdf));
    expect(converted->phase == PDFProcessingPhase::succeeded
            && converted->outputs == std::vector<fs::path>{image_pdf}
            && fs::is_regular_file(image_pdf),
        "image conversion should consume PDFium render output");

    const auto failed_watermark = wait_for_terminal(
        service,
        service.add_image_watermark(
            source,
            {.image_path = temporary.path() / "missing.png"},
            watermark_output));
    expect(failed_watermark->phase == PDFProcessingPhase::failed
            && !failed_watermark->message.empty() && !fs::exists(watermark_output),
        "PDFium failures should become failed snapshots without an output file");
}
#endif

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"reads and updates metadata", reads_and_updates_document_metadata},
        {"serializes dependent operations", serializes_dependent_operations},
        {"reports adapter failures", reports_adapter_failures_without_writing_output},
#if defined(ZISLA_HAS_PDFIUM_ADAPTER)
        {"routes PDFium operations", routes_pdfium_operations_and_surfaces_failures},
#endif
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
