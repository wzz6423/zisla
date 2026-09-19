#include "PDFiumAdapter.hpp"

#include <jpeglib.h>
#include <zlib.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <csetjmp>
#include <cstddef>
#include <cstdint>
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

using zisla::pdf::PDFImageWatermark;
using zisla::pdf::PDFOverlayPosition;
using zisla::pdf::PDFPageNumberStyle;
using zisla::pdf::PDFRasterImageFormat;
using zisla::pdf::PDFTextWatermark;
using zisla::pdf::PDFiumAdapter;
using zisla::pdf::PDFiumAdapterError;
using zisla::pdf::PDFiumAdapterErrorCode;

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
            / ("zisla-windows-pdfium-adapter-" + std::to_string(suffix));
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

struct RasterImage {
    std::uint32_t width{0};
    std::uint32_t height{0};
    std::vector<std::uint8_t> rgba;
};

void write_pdf(const fs::path& output, std::string contents) {
    std::vector<std::string> objects(6);
    objects[1] = "<< /Type /Catalog /Pages 2 0 R >>";
    objects[2] = "<< /Type /Pages /Kids [ 3 0 R ] /Count 1 >>";
    objects[3] = "<< /Type /Page /Parent 2 0 R /MediaBox [ 0 0 200 200 ]"
        " /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>";
    objects[4] = "<< /Length " + std::to_string(contents.size())
        + " >>\nstream\n" + contents + "endstream";
    objects[5] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>";

    std::ofstream stream(output, std::ios::binary);
    if (!stream) {
        throw std::runtime_error("cannot create PDF fixture");
    }
    stream << "%PDF-1.4\n";
    std::vector<std::streamoff> offsets(objects.size());
    for (std::size_t object = 1; object < objects.size(); ++object) {
        offsets[object] = stream.tellp();
        stream << object << " 0 obj\n" << objects[object] << "\nendobj\n";
    }
    const auto xref_offset = stream.tellp();
    stream << "xref\n0 " << objects.size() << "\n0000000000 65535 f \n";
    for (std::size_t object = 1; object < objects.size(); ++object) {
        stream.width(10);
        stream.fill('0');
        stream << offsets[object] << " 00000 n \n";
    }
    stream << "trailer\n<< /Size " << objects.size()
           << " /Root 1 0 R >>\nstartxref\n" << xref_offset << "\n%%EOF\n";
    if (!stream) {
        throw std::runtime_error("cannot write PDF fixture");
    }
}

void write_text_pdf(const fs::path& output) {
    write_pdf(output, "BT\n/F1 18 Tf\n24 120 Td\n(Hello PDFium) Tj\nET\n");
}

void write_blank_pdf(const fs::path& output) {
    write_pdf(output, {});
}

std::vector<std::uint8_t> read_bytes(const fs::path& input) {
    std::ifstream stream(input, std::ios::binary);
    if (!stream) {
        throw std::runtime_error("cannot read fixture output");
    }
    return {
        std::istreambuf_iterator<char>{stream},
        std::istreambuf_iterator<char>{},
    };
}

std::uint32_t read_big_endian_u32(
    const std::vector<std::uint8_t>& bytes,
    std::size_t offset) {
    expect(offset + 4U <= bytes.size(), "PNG field must be complete");
    return (static_cast<std::uint32_t>(bytes[offset]) << 24U)
        | (static_cast<std::uint32_t>(bytes[offset + 1U]) << 16U)
        | (static_cast<std::uint32_t>(bytes[offset + 2U]) << 8U)
        | static_cast<std::uint32_t>(bytes[offset + 3U]);
}

void write_big_endian_u32(std::ofstream& stream, std::uint32_t value) {
    const std::array<std::uint8_t, 4> encoded{
        static_cast<std::uint8_t>(value >> 24U),
        static_cast<std::uint8_t>(value >> 16U),
        static_cast<std::uint8_t>(value >> 8U),
        static_cast<std::uint8_t>(value),
    };
    stream.write(reinterpret_cast<const char*>(encoded.data()), encoded.size());
}

void write_png_chunk(
    std::ofstream& stream,
    std::string_view type,
    const std::vector<std::uint8_t>& payload) {
    write_big_endian_u32(stream, static_cast<std::uint32_t>(payload.size()));
    stream.write(type.data(), static_cast<std::streamsize>(type.size()));
    if (!payload.empty()) {
        stream.write(
            reinterpret_cast<const char*>(payload.data()),
            static_cast<std::streamsize>(payload.size()));
    }
    auto checksum = crc32(0, Z_NULL, 0);
    checksum = crc32(
        checksum,
        reinterpret_cast<const Bytef*>(type.data()),
        static_cast<uInt>(type.size()));
    if (!payload.empty()) {
        checksum = crc32(
            checksum,
            reinterpret_cast<const Bytef*>(payload.data()),
            static_cast<uInt>(payload.size()));
    }
    write_big_endian_u32(stream, checksum);
}

void write_solid_png(
    const fs::path& output,
    std::uint32_t width,
    std::uint32_t height,
    std::array<std::uint8_t, 4> color) {
    expect(width > 0 && height > 0, "PNG fixture dimensions must be positive");
    const auto row_bytes = static_cast<std::size_t>(width) * 4U;
    std::vector<std::uint8_t> raw(static_cast<std::size_t>(height) * (row_bytes + 1U));
    for (std::uint32_t y = 0; y < height; ++y) {
        const auto row_offset = static_cast<std::size_t>(y) * (row_bytes + 1U);
        raw[row_offset] = 0;
        for (std::uint32_t x = 0; x < width; ++x) {
            const auto pixel = row_offset + 1U + static_cast<std::size_t>(x) * 4U;
            std::copy(color.begin(), color.end(), raw.begin() + static_cast<std::ptrdiff_t>(pixel));
        }
    }
    uLongf compressed_size = compressBound(static_cast<uLong>(raw.size()));
    std::vector<std::uint8_t> compressed(compressed_size);
    expect(compress2(
               compressed.data(),
               &compressed_size,
               raw.data(),
               static_cast<uLong>(raw.size()),
               Z_BEST_SPEED) == Z_OK,
        "PNG fixture pixels must compress");
    compressed.resize(compressed_size);

    std::ofstream stream(output, std::ios::binary | std::ios::trunc);
    expect(static_cast<bool>(stream), "PNG fixture must open for writing");
    constexpr std::array<std::uint8_t, 8> signature{
        0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a,
    };
    const std::vector<std::uint8_t> header{
        static_cast<std::uint8_t>(width >> 24U),
        static_cast<std::uint8_t>(width >> 16U),
        static_cast<std::uint8_t>(width >> 8U),
        static_cast<std::uint8_t>(width),
        static_cast<std::uint8_t>(height >> 24U),
        static_cast<std::uint8_t>(height >> 16U),
        static_cast<std::uint8_t>(height >> 8U),
        static_cast<std::uint8_t>(height),
        8,
        6,
        0,
        0,
        0,
    };
    stream.write(reinterpret_cast<const char*>(signature.data()), signature.size());
    write_png_chunk(stream, "IHDR", header);
    write_png_chunk(stream, "IDAT", compressed);
    write_png_chunk(stream, "IEND", {});
    expect(static_cast<bool>(stream), "PNG fixture must be written");
}

RasterImage decode_rendered_png(const fs::path& input) {
    const auto bytes = read_bytes(input);
    constexpr std::array<std::uint8_t, 8> signature{
        0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a,
    };
    expect(bytes.size() >= signature.size()
            && std::equal(signature.begin(), signature.end(), bytes.begin()),
        "render output must be a PNG file");

    std::size_t offset = signature.size();
    RasterImage image;
    std::vector<std::uint8_t> compressed;
    bool saw_end = false;
    while (offset + 12U <= bytes.size()) {
        const auto size = read_big_endian_u32(bytes, offset);
        const auto type_offset = offset + 4U;
        const auto payload_offset = type_offset + 4U;
        expect(payload_offset + size + 4U <= bytes.size(), "PNG chunk must be complete");
        const std::string_view type{
            reinterpret_cast<const char*>(bytes.data() + type_offset),
            4,
        };
        if (type == "IHDR") {
            expect(size == 13U, "PNG header must have the standard size");
            image.width = read_big_endian_u32(bytes, payload_offset);
            image.height = read_big_endian_u32(bytes, payload_offset + 4U);
            expect(bytes[payload_offset + 8U] == 8 && bytes[payload_offset + 9U] == 6,
                "render output must be 8-bit RGBA PNG");
        } else if (type == "IDAT") {
            compressed.insert(
                compressed.end(),
                bytes.begin() + static_cast<std::ptrdiff_t>(payload_offset),
                bytes.begin() + static_cast<std::ptrdiff_t>(payload_offset + size));
        } else if (type == "IEND") {
            saw_end = true;
            break;
        }
        offset = payload_offset + size + 4U;
    }
    expect(image.width > 0 && image.height > 0 && saw_end && !compressed.empty(),
        "rendered PNG must contain image data");
    const auto row_bytes = static_cast<std::size_t>(image.width) * 4U;
    const auto expected_size = static_cast<uLongf>(image.height) * (row_bytes + 1U);
    std::vector<std::uint8_t> scanlines(expected_size);
    auto actual_size = expected_size;
    expect(uncompress(
               scanlines.data(),
               &actual_size,
               compressed.data(),
               static_cast<uLong>(compressed.size())) == Z_OK
            && actual_size == expected_size,
        "render PNG pixels must be decodable");

    image.rgba.resize(static_cast<std::size_t>(image.width) * image.height * 4U);
    for (std::uint32_t y = 0; y < image.height; ++y) {
        const auto scanline_offset = static_cast<std::size_t>(y) * (row_bytes + 1U);
        expect(scanlines[scanline_offset] == 0, "PNG encoder must use unfiltered rows");
        std::copy_n(
            scanlines.data() + scanline_offset + 1U,
            row_bytes,
            image.rgba.data() + static_cast<std::size_t>(y) * row_bytes);
    }
    return image;
}

struct JPEGErrorManager {
    jpeg_error_mgr base{};
    std::jmp_buf jump{};
};

void jpeg_error_exit(j_common_ptr info) {
    auto* error = reinterpret_cast<JPEGErrorManager*>(info->err);
    longjmp(error->jump, 1);
}

RasterImage decode_jpeg(const fs::path& input) {
    const auto bytes = read_bytes(input);
    jpeg_decompress_struct info{};
    JPEGErrorManager error{};
    info.err = jpeg_std_error(&error.base);
    error.base.error_exit = jpeg_error_exit;
    jpeg_create_decompress(&info);
    if (setjmp(error.jump) != 0) {
        jpeg_destroy_decompress(&info);
        throw std::runtime_error("render output must be a decodable JPEG file");
    }
    jpeg_mem_src(
        &info,
        const_cast<unsigned char*>(bytes.data()),
        static_cast<unsigned long>(bytes.size()));
    expect(jpeg_read_header(&info, TRUE) == JPEG_HEADER_OK, "JPEG header must be valid");
    info.out_color_space = JCS_RGB;
    jpeg_start_decompress(&info);
    RasterImage image{
        .width = static_cast<std::uint32_t>(info.output_width),
        .height = static_cast<std::uint32_t>(info.output_height),
        .rgba = std::vector<std::uint8_t>(
            static_cast<std::size_t>(info.output_width) * info.output_height * 4U),
    };
    std::vector<std::uint8_t> row(
        static_cast<std::size_t>(info.output_width) * info.output_components);
    while (info.output_scanline < info.output_height) {
        JSAMPROW scanline = row.data();
        expect(jpeg_read_scanlines(&info, &scanline, 1) == 1,
            "JPEG scanline must be readable");
        const auto y = static_cast<std::size_t>(info.output_scanline - 1U);
        for (std::size_t x = 0; x < image.width; ++x) {
            const auto source = x * info.output_components;
            const auto destination = (y * image.width + x) * 4U;
            image.rgba[destination] = row[source];
            image.rgba[destination + 1U] = row[source + 1U];
            image.rgba[destination + 2U] = row[source + 2U];
            image.rgba[destination + 3U] = 0xffU;
        }
    }
    expect(jpeg_finish_decompress(&info) != FALSE, "JPEG must finish decoding");
    jpeg_destroy_decompress(&info);
    return image;
}

bool has_non_white_pixel(const RasterImage& image) {
    for (std::size_t offset = 0; offset < image.rgba.size(); offset += 4U) {
        if (image.rgba[offset + 3U] != 0
            && (image.rgba[offset] < 250U || image.rgba[offset + 1U] < 250U
                || image.rgba[offset + 2U] < 250U)) {
            return true;
        }
    }
    return false;
}

bool has_red_pixel(const RasterImage& image) {
    for (std::size_t offset = 0; offset < image.rgba.size(); offset += 4U) {
        if (image.rgba[offset] > 160U && image.rgba[offset + 1U] < 120U
            && image.rgba[offset + 2U] < 120U) {
            return true;
        }
    }
    return false;
}

RasterImage render_png(
    const PDFiumAdapter& adapter,
    const fs::path& input,
    const fs::path& directory) {
    const auto outputs = adapter.render_pages(
        input,
        directory,
        PDFRasterImageFormat::png,
        72);
    expect(outputs.size() == 1 && fs::is_regular_file(outputs.front()),
        "page rendering must create one PNG output per page");
    return decode_rendered_png(outputs.front());
}

void expect_pdfium_error(
    const std::function<void()>& operation,
    PDFiumAdapterErrorCode expected_code,
    std::string_view message) {
    try {
        operation();
    } catch (const PDFiumAdapterError& error) {
        expect(error.code() == expected_code, message);
        return;
    }
    throw std::runtime_error(std::string(message));
}

bool has_pending_output(const fs::path& directory) {
    for (const auto& entry : fs::recursive_directory_iterator(directory)) {
        if (entry.path().filename().string().find(".zisla-pdfium-") != std::string::npos) {
            return true;
        }
    }
    return false;
}

void extracts_text_and_renders_visible_page_content() {
    TemporaryDirectory temporary;
    const auto source = temporary.path() / "source.pdf";
    const auto text_output = temporary.path() / "source.txt";
    write_text_pdf(source);

    PDFiumAdapter adapter;
    adapter.extract_text(source, {0}, text_output);
    const auto text = read_bytes(text_output);
    const std::string extracted{text.begin(), text.end()};
    expect(extracted.find("Hello PDFium") != std::string::npos,
        "text extraction must preserve the PDF text layer");

    const auto image = render_png(adapter, source, temporary.path() / "images");
    expect(image.width == 200 && image.height == 200,
        "72 DPI render dimensions must match the PDF page");
    expect(has_non_white_pixel(image),
        "rendered page must contain visible text pixels instead of a blank image");
}

void renders_jpeg_and_round_trips_images_through_pdf() {
    TemporaryDirectory temporary;
    const auto source_image = temporary.path() / "source.png";
    const auto image_pdf = temporary.path() / "images.pdf";
    write_solid_png(source_image, 12, 8, {220, 30, 20, 0xff});

    PDFiumAdapter adapter;
    const std::array image_inputs{source_image};
    adapter.convert_images_to_pdf(image_inputs, image_pdf);
    const auto summary = adapter.inspect(image_pdf);
    expect(summary.page_count == 1 && fs::is_regular_file(image_pdf),
        "image conversion must produce a one-page PDF");

    const auto png = render_png(adapter, image_pdf, temporary.path() / "roundtrip-png");
    expect(png.width == 12 && png.height == 8 && has_red_pixel(png),
        "image-to-PDF output must render its source pixels");

    const auto jpeg_outputs = adapter.render_pages(
        image_pdf,
        temporary.path() / "roundtrip-jpeg",
        PDFRasterImageFormat::jpeg,
        72);
    expect(jpeg_outputs.size() == 1 && fs::is_regular_file(jpeg_outputs.front()),
        "JPEG page rendering must produce a file");
    const auto jpeg = decode_jpeg(jpeg_outputs.front());
    expect(jpeg.width == 12 && jpeg.height == 8 && has_red_pixel(jpeg),
        "JPEG rendering must preserve visible source pixels");
}

void applies_text_image_and_page_number_overlays() {
    TemporaryDirectory temporary;
    const auto source = temporary.path() / "blank.pdf";
    const auto watermark_image = temporary.path() / "stamp.png";
    const auto text_output = temporary.path() / "text-watermark.pdf";
    const auto image_output = temporary.path() / "image-watermark.pdf";
    const auto page_number_output = temporary.path() / "page-numbers.pdf";
    write_blank_pdf(source);
    write_solid_png(watermark_image, 20, 12, {220, 20, 20, 0xff});

    PDFiumAdapter adapter;
    adapter.add_text_watermark(
        source,
        PDFTextWatermark{
            .text = "CONFIDENTIAL",
            .font_size = 28,
            .opacity = 1,
            .rotation_degrees = 0,
        },
        text_output);
    expect(has_non_white_pixel(render_png(adapter, text_output, temporary.path() / "text-render")),
        "text watermark must create visible rendered pixels");

    adapter.add_image_watermark(
        source,
        PDFImageWatermark{
            .image_path = watermark_image,
            .position = PDFOverlayPosition::center,
            .scale = 0.5,
            .opacity = 1,
        },
        image_output);
    expect(has_red_pixel(render_png(adapter, image_output, temporary.path() / "image-render")),
        "image watermark must create visible source-colored pixels");

    adapter.add_page_numbers(
        source,
        PDFPageNumberStyle{
            .prefix = "Page ",
            .font_size = 14,
            .position = PDFOverlayPosition::bottom,
            .inset = 12,
        },
        page_number_output);
    expect(has_non_white_pixel(render_png(adapter, page_number_output, temporary.path() / "number-render")),
        "page number rendering must create visible pixels");
}

void rejects_conflicts_and_cleans_pending_outputs() {
    TemporaryDirectory temporary;
    const auto source = temporary.path() / "source.pdf";
    const auto existing_text = temporary.path() / "existing.txt";
    const auto bad_image = temporary.path() / "unsupported.gif";
    const auto failed_output = temporary.path() / "failed.pdf";
    write_text_pdf(source);
    std::ofstream(existing_text) << "existing";
    std::ofstream(bad_image, std::ios::binary) << "not-an-image";
    const auto source_before = read_bytes(source);

    PDFiumAdapter adapter;
    expect_pdfium_error(
        [&] { adapter.extract_text(source, {0}, source); },
        PDFiumAdapterErrorCode::output_validation,
        "text export must refuse to overwrite its input PDF");
    expect_pdfium_error(
        [&] { adapter.extract_text(source, {0}, existing_text); },
        PDFiumAdapterErrorCode::output_validation,
        "text export must refuse an existing output file");
    const auto render_directory = temporary.path() / "existing-render";
    fs::create_directories(render_directory);
    std::ofstream(render_directory / "source-001.png", std::ios::binary) << "existing";
    expect_pdfium_error(
        [&] {
            (void)adapter.render_pages(
                source,
                render_directory,
                PDFRasterImageFormat::png,
                72);
        },
        PDFiumAdapterErrorCode::output_validation,
        "page rendering must refuse an existing generated output");
    expect_pdfium_error(
        [&] {
            adapter.add_image_watermark(
                source,
                PDFImageWatermark{.image_path = bad_image},
                failed_output);
        },
        PDFiumAdapterErrorCode::unsupported_image,
        "invalid image watermark must report its decoder failure");

    expect(read_bytes(source) == source_before,
        "failed operations must preserve the input PDF");
    expect(!fs::exists(failed_output) && !has_pending_output(temporary.path()),
        "failed operations must remove all pending output files");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"extracts text and renders visible page content", extracts_text_and_renders_visible_page_content},
        {"renders JPEG and round trips images through PDF", renders_jpeg_and_round_trips_images_through_pdf},
        {"applies text image and page number overlays", applies_text_image_and_page_number_overlays},
        {"rejects conflicts and cleans pending outputs", rejects_conflicts_and_cleans_pending_outputs},
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
