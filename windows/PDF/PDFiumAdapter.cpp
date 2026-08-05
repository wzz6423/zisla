#include "PDFiumAdapter.hpp"

#include <zisla/core/PDFProcessing.hpp>

#include <fpdf_edit.h>
#include <fpdf_save.h>
#include <fpdf_text.h>
#include <fpdfview.h>
#include <jpeglib.h>
#include <zlib.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <csetjmp>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <limits>
#include <memory>
#include <mutex>
#include <numbers>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <system_error>
#include <type_traits>
#include <utility>
#include <vector>

namespace zisla::pdf {
namespace {

namespace fs = std::filesystem;

using zisla::core::PDFOutputValidationError;
using zisla::core::PDFProcessing;

constexpr int minimum_render_dpi = 1;
constexpr int maximum_render_dpi = 600;
constexpr std::uint64_t maximum_render_pixels = 100ULL * 1024ULL * 1024ULL;
constexpr std::uintmax_t maximum_image_bytes = 128ULL * 1024ULL * 1024ULL;

[[noreturn]] void fail(PDFiumAdapterErrorCode code, std::string message) {
    throw PDFiumAdapterError(code, std::move(message));
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

fs::path normalized_input_path(const fs::path& input) {
    if (input.empty()) {
        fail(PDFiumAdapterErrorCode::invalid_input, "未选择 PDF 文件");
    }

    std::error_code error;
    const auto absolute = fs::absolute(input, error);
    if (error) {
        fail(PDFiumAdapterErrorCode::invalid_input, "无法定位 PDF 文件");
    }
    const auto canonical = fs::weakly_canonical(absolute, error);
    const auto normalized = error ? absolute.lexically_normal() : canonical.lexically_normal();
    error.clear();
    if (!fs::is_regular_file(normalized, error) || error) {
        fail(
            PDFiumAdapterErrorCode::invalid_input,
            "不是可访问的本地 PDF 文件：" + display_name(normalized));
    }
    return normalized;
}

fs::path normalized_output_path(const fs::path& output) {
    if (output.empty()) {
        fail(PDFiumAdapterErrorCode::output_validation, "未选择输出文件");
    }
    std::error_code error;
    const auto absolute = fs::absolute(output, error);
    if (error) {
        fail(PDFiumAdapterErrorCode::output_validation, "输出路径无效");
    }
    return absolute.lexically_normal();
}

[[noreturn]] void fail_output_validation(PDFOutputValidationError error) {
    switch (error) {
    case PDFOutputValidationError::empty_output_path:
        fail(PDFiumAdapterErrorCode::output_validation, "未选择输出文件");
    case PDFOutputValidationError::invalid_output_path:
        fail(PDFiumAdapterErrorCode::output_validation, "输出路径无效");
    case PDFOutputValidationError::output_matches_input:
        fail(PDFiumAdapterErrorCode::output_validation, "输出文件不能覆盖输入 PDF");
    case PDFOutputValidationError::output_already_exists:
        fail(PDFiumAdapterErrorCode::output_validation, "输出文件已存在，未覆盖");
    case PDFOutputValidationError::duplicate_output:
        fail(PDFiumAdapterErrorCode::output_validation, "同一任务不能重复使用输出文件");
    case PDFOutputValidationError::none:
        break;
    }
    fail(PDFiumAdapterErrorCode::output_validation, "输出路径无效");
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
                PDFiumAdapterErrorCode::cannot_create_output_directory,
                "无法创建输出目录：" + path_as_utf8(parent));
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
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法创建临时输出文件");
    }

    ~PendingOutput() {
        cleanup();
    }

    PendingOutput(const PendingOutput&) = delete;
    PendingOutput& operator=(const PendingOutput&) = delete;

    PendingOutput(PendingOutput&& other) noexcept
        : destination_(std::move(other.destination_)),
          temporary_(std::move(other.temporary_)),
          committed_(other.committed_) {
        other.temporary_.clear();
        other.committed_ = true;
    }

    PendingOutput& operator=(PendingOutput&& other) noexcept {
        if (this == &other) {
            return *this;
        }
        cleanup();
        destination_ = std::move(other.destination_);
        temporary_ = std::move(other.temporary_);
        committed_ = other.committed_;
        other.temporary_.clear();
        other.committed_ = true;
        return *this;
    }

    [[nodiscard]] const fs::path& temporary() const noexcept {
        return temporary_;
    }

    void commit() {
        std::error_code error;
        fs::rename(temporary_, destination_, error);
        if (error) {
            fail(
                PDFiumAdapterErrorCode::cannot_write_output,
                "无法保存输出文件：" + display_name(destination_));
        }
        committed_ = true;
    }

private:
    static std::string temporary_suffix() {
        static std::atomic_uint64_t sequence{0};
        const auto now = std::chrono::steady_clock::now()
            .time_since_epoch().count();
        return ".zisla-pdfium-" + std::to_string(now) + "-"
            + std::to_string(sequence.fetch_add(1, std::memory_order_relaxed));
    }

    void cleanup() noexcept {
        if (committed_ || temporary_.empty()) {
            return;
        }
        std::error_code error;
        fs::remove(temporary_, error);
    }

    fs::path destination_;
    fs::path temporary_;
    bool committed_{false};
};

class PDFiumRuntime {
public:
    PDFiumRuntime() {
        FPDF_InitLibrary();
    }

    ~PDFiumRuntime() {
        FPDF_DestroyLibrary();
    }

    PDFiumRuntime(const PDFiumRuntime&) = delete;
    PDFiumRuntime& operator=(const PDFiumRuntime&) = delete;

    [[nodiscard]] std::mutex& mutex() noexcept {
        return mutex_;
    }

private:
    std::mutex mutex_;
};

PDFiumRuntime& runtime() {
    static PDFiumRuntime instance;
    return instance;
}

struct DocumentDeleter {
    void operator()(std::remove_pointer_t<FPDF_DOCUMENT>* document) const noexcept {
        if (document) {
            FPDF_CloseDocument(document);
        }
    }
};

struct PageDeleter {
    void operator()(std::remove_pointer_t<FPDF_PAGE>* page) const noexcept {
        if (page) {
            FPDF_ClosePage(page);
        }
    }
};

struct TextPageDeleter {
    void operator()(std::remove_pointer_t<FPDF_TEXTPAGE>* page) const noexcept {
        if (page) {
            FPDFText_ClosePage(page);
        }
    }
};

struct BitmapDeleter {
    void operator()(std::remove_pointer_t<FPDF_BITMAP>* bitmap) const noexcept {
        if (bitmap) {
            FPDFBitmap_Destroy(bitmap);
        }
    }
};

using DocumentHandle = std::unique_ptr<std::remove_pointer_t<FPDF_DOCUMENT>, DocumentDeleter>;
using PageHandle = std::unique_ptr<std::remove_pointer_t<FPDF_PAGE>, PageDeleter>;
using TextPageHandle = std::unique_ptr<std::remove_pointer_t<FPDF_TEXTPAGE>, TextPageDeleter>;
using BitmapHandle = std::unique_ptr<std::remove_pointer_t<FPDF_BITMAP>, BitmapDeleter>;

struct PageObjectDeleter {
    void operator()(std::remove_pointer_t<FPDF_PAGEOBJECT>* object) const noexcept {
        if (object) {
            FPDFPageObj_Destroy(object);
        }
    }
};

struct FontDeleter {
    void operator()(std::remove_pointer_t<FPDF_FONT>* font) const noexcept {
        if (font) {
            FPDFFont_Close(font);
        }
    }
};

using PageObjectHandle = std::unique_ptr<
    std::remove_pointer_t<FPDF_PAGEOBJECT>,
    PageObjectDeleter>;
using FontHandle = std::unique_ptr<std::remove_pointer_t<FPDF_FONT>, FontDeleter>;

struct RGBAImage {
    int width{0};
    int height{0};
    std::vector<std::uint8_t> pixels;
};

struct FileWriterContext {
    FPDF_FILEWRITE interface{1, nullptr};
    std::ofstream* stream{nullptr};
};

int write_file_block(
    FPDF_FILEWRITE* self,
    const void* data,
    unsigned long size) {
    auto* context = reinterpret_cast<FileWriterContext*>(self);
    if (!context || !context->stream || (!data && size != 0)) {
        return 0;
    }
    context->stream->write(
        static_cast<const char*>(data),
        static_cast<std::streamsize>(size));
    return context->stream->good() ? 1 : 0;
}

[[noreturn]] void fail_load_document(const fs::path& input) {
    switch (FPDF_GetLastError()) {
    case FPDF_ERR_PASSWORD:
        fail(PDFiumAdapterErrorCode::locked_document, "PDF 需要密码：" + display_name(input));
    case FPDF_ERR_FILE:
        fail(PDFiumAdapterErrorCode::invalid_input, "无法读取 PDF 文件：" + display_name(input));
    case FPDF_ERR_FORMAT:
    case FPDF_ERR_PAGE:
        fail(PDFiumAdapterErrorCode::invalid_document, "PDF 文件无效或已损坏：" + display_name(input));
    case FPDF_ERR_SECURITY:
        fail(PDFiumAdapterErrorCode::locked_document, "PDF 使用了不受支持的加密：" + display_name(input));
    default:
        break;
    }
    fail(PDFiumAdapterErrorCode::invalid_document, "无法打开 PDF 文件：" + display_name(input));
}

DocumentHandle load_document(const fs::path& input) {
    const auto encoded = path_as_utf8(input);
    DocumentHandle document{FPDF_LoadDocument(encoded.c_str(), nullptr)};
    if (!document) {
        fail_load_document(input);
    }
    if (FPDF_GetPageCount(document.get()) <= 0) {
        fail(PDFiumAdapterErrorCode::invalid_document, "PDF 不包含可处理页面：" + display_name(input));
    }
    return document;
}

PageHandle load_page(FPDF_DOCUMENT document, std::size_t page_index) {
    if (page_index > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        fail(PDFiumAdapterErrorCode::invalid_page_selection, "PDF 页码超出范围");
    }
    PageHandle page{FPDF_LoadPage(document, static_cast<int>(page_index))};
    if (!page) {
        fail(PDFiumAdapterErrorCode::invalid_page_selection, "PDF 页码无效");
    }
    return page;
}

void validate_page_indexes(
    std::span<const std::size_t> page_indexes,
    FPDF_DOCUMENT document) {
    const auto page_count = FPDF_GetPageCount(document);
    if (page_count <= 0 || !PDFProcessing::has_valid_page_indexes(
            page_indexes,
            static_cast<std::size_t>(page_count))) {
        fail(PDFiumAdapterErrorCode::invalid_page_selection, "PDF 页码范围无效");
    }
}

void append_utf8(std::string& output, std::uint32_t code_point) {
    if (code_point > 0x10ffffU || (code_point >= 0xd800U && code_point <= 0xdfffU)) {
        code_point = 0xfffdU;
    }
    if (code_point <= 0x7fU) {
        output.push_back(static_cast<char>(code_point));
    } else if (code_point <= 0x7ffU) {
        output.push_back(static_cast<char>(0xc0U | (code_point >> 6U)));
        output.push_back(static_cast<char>(0x80U | (code_point & 0x3fU)));
    } else if (code_point <= 0xffffU) {
        output.push_back(static_cast<char>(0xe0U | (code_point >> 12U)));
        output.push_back(static_cast<char>(0x80U | ((code_point >> 6U) & 0x3fU)));
        output.push_back(static_cast<char>(0x80U | (code_point & 0x3fU)));
    } else {
        output.push_back(static_cast<char>(0xf0U | (code_point >> 18U)));
        output.push_back(static_cast<char>(0x80U | ((code_point >> 12U) & 0x3fU)));
        output.push_back(static_cast<char>(0x80U | ((code_point >> 6U) & 0x3fU)));
        output.push_back(static_cast<char>(0x80U | (code_point & 0x3fU)));
    }
}

std::vector<std::uint16_t> utf16_from_utf8(std::string_view input) {
    std::vector<std::uint16_t> result;
    result.reserve(input.size() + 1U);
    for (std::size_t index = 0; index < input.size();) {
        const auto first = static_cast<unsigned char>(input[index++]);
        std::uint32_t code_point = 0xfffdU;
        std::size_t continuation_count = 0;
        if (first <= 0x7fU) {
            code_point = first;
        } else if (first >= 0xc2U && first <= 0xdfU) {
            code_point = first & 0x1fU;
            continuation_count = 1;
        } else if (first >= 0xe0U && first <= 0xefU) {
            code_point = first & 0x0fU;
            continuation_count = 2;
        } else if (first >= 0xf0U && first <= 0xf4U) {
            code_point = first & 0x07U;
            continuation_count = 3;
        }

        if (continuation_count != 0) {
            const auto start = index;
            bool valid = index + continuation_count <= input.size();
            for (std::size_t offset = 0; valid && offset < continuation_count; ++offset) {
                const auto byte = static_cast<unsigned char>(input[index++]);
                if ((byte & 0xc0U) != 0x80U) {
                    valid = false;
                } else {
                    code_point = (code_point << 6U) | (byte & 0x3fU);
                }
            }
            if (!valid
                || (continuation_count == 2 && code_point < 0x800U)
                || (continuation_count == 3 && code_point < 0x10000U)
                || code_point > 0x10ffffU
                || (code_point >= 0xd800U && code_point <= 0xdfffU)) {
                code_point = 0xfffdU;
                index = start + 1U;
            }
        }

        if (code_point <= 0xffffU) {
            result.push_back(static_cast<std::uint16_t>(code_point));
        } else {
            code_point -= 0x10000U;
            result.push_back(static_cast<std::uint16_t>(0xd800U | (code_point >> 10U)));
            result.push_back(static_cast<std::uint16_t>(0xdc00U | (code_point & 0x3ffU)));
        }
    }
    result.push_back(0);
    return result;
}

std::uint32_t read_big_endian_u32(
    std::span<const std::uint8_t> bytes,
    std::size_t offset) {
    if (offset > bytes.size() || bytes.size() - offset < 4U) {
        fail(PDFiumAdapterErrorCode::unsupported_image, "图片文件格式不完整");
    }
    return (static_cast<std::uint32_t>(bytes[offset]) << 24U)
        | (static_cast<std::uint32_t>(bytes[offset + 1U]) << 16U)
        | (static_cast<std::uint32_t>(bytes[offset + 2U]) << 8U)
        | static_cast<std::uint32_t>(bytes[offset + 3U]);
}

std::vector<std::uint8_t> read_binary_file(const fs::path& path) {
    std::error_code error;
    const auto size = fs::file_size(path, error);
    if (error || size == 0 || size > maximum_image_bytes) {
        fail(
            PDFiumAdapterErrorCode::unsupported_image,
            "图片文件不存在、为空或过大：" + display_name(path));
    }
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        fail(PDFiumAdapterErrorCode::unsupported_image, "无法读取图片：" + display_name(path));
    }
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(size));
    stream.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    if (!stream) {
        fail(PDFiumAdapterErrorCode::unsupported_image, "无法读取图片：" + display_name(path));
    }
    return bytes;
}

std::uint8_t paeth_predictor(
    std::uint8_t left,
    std::uint8_t up,
    std::uint8_t upper_left) noexcept {
    const auto p = static_cast<int>(left) + static_cast<int>(up)
        - static_cast<int>(upper_left);
    const auto pa = std::abs(p - static_cast<int>(left));
    const auto pb = std::abs(p - static_cast<int>(up));
    const auto pc = std::abs(p - static_cast<int>(upper_left));
    if (pa <= pb && pa <= pc) {
        return left;
    }
    if (pb <= pc) {
        return up;
    }
    return upper_left;
}

RGBAImage decode_png(std::span<const std::uint8_t> bytes) {
    constexpr std::array<std::uint8_t, 8> signature{
        0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a,
    };
    if (bytes.size() < signature.size()
        || !std::equal(signature.begin(), signature.end(), bytes.begin())) {
        fail(PDFiumAdapterErrorCode::unsupported_image, "不是有效的 PNG 图片");
    }

    std::size_t offset = signature.size();
    std::uint32_t width = 0;
    std::uint32_t height = 0;
    std::uint8_t bit_depth = 0;
    std::uint8_t color_type = 0;
    std::uint8_t interlace = 0;
    bool has_header = false;
    bool has_end = false;
    std::vector<std::uint8_t> compressed;
    while (offset <= bytes.size() && bytes.size() - offset >= 12U) {
        const auto size = read_big_endian_u32(bytes, offset);
        const auto payload_offset = offset + 8U;
        if (size > bytes.size() - payload_offset - 4U) {
            fail(PDFiumAdapterErrorCode::unsupported_image, "PNG 数据块超出文件范围");
        }
        const std::string_view type{
            reinterpret_cast<const char*>(bytes.data() + offset + 4U),
            4,
        };
        const auto payload = bytes.subspan(payload_offset, size);
        if (type == "IHDR") {
            if (size != 13U || has_header) {
                fail(PDFiumAdapterErrorCode::unsupported_image, "PNG 文件头无效");
            }
            width = read_big_endian_u32(payload, 0);
            height = read_big_endian_u32(payload, 4);
            bit_depth = payload[8];
            color_type = payload[9];
            interlace = payload[12];
            has_header = true;
        } else if (type == "IDAT") {
            compressed.insert(compressed.end(), payload.begin(), payload.end());
        } else if (type == "IEND") {
            has_end = true;
            break;
        }
        offset = payload_offset + size + 4U;
    }

    const auto channels = color_type == 0 ? 1U
        : color_type == 2 ? 3U
        : color_type == 4 ? 2U
        : color_type == 6 ? 4U
        : 0U;
    if (!has_header || !has_end || width == 0 || height == 0
        || width > static_cast<std::uint32_t>(std::numeric_limits<int>::max())
        || height > static_cast<std::uint32_t>(std::numeric_limits<int>::max())
        || bit_depth != 8 || channels == 0 || interlace != 0 || compressed.empty()) {
        fail(PDFiumAdapterErrorCode::unsupported_image, "PNG 图片使用了不支持的编码");
    }

    const auto row_bytes = static_cast<std::size_t>(width) * channels;
    const auto decoded_size = static_cast<std::size_t>(height) * (row_bytes + 1U);
    if (static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height)
        > maximum_render_pixels
        || decoded_size > std::numeric_limits<uLongf>::max()) {
        fail(PDFiumAdapterErrorCode::unsupported_image, "PNG 图片尺寸过大");
    }
    std::vector<std::uint8_t> decoded(decoded_size);
    auto output_size = static_cast<uLongf>(decoded.size());
    if (uncompress(
            decoded.data(),
            &output_size,
            compressed.data(),
            static_cast<uLong>(compressed.size())) != Z_OK
        || output_size != decoded.size()) {
        fail(PDFiumAdapterErrorCode::unsupported_image, "无法解压 PNG 图片");
    }

    std::vector<std::uint8_t> rows(static_cast<std::size_t>(height) * row_bytes);
    for (std::size_t y = 0; y < height; ++y) {
        const auto filter = decoded[y * (row_bytes + 1U)];
        const auto* source = decoded.data() + y * (row_bytes + 1U) + 1U;
        auto* target = rows.data() + y * row_bytes;
        const auto* previous = y == 0 ? nullptr : rows.data() + (y - 1U) * row_bytes;
        if (filter > 4U) {
            fail(PDFiumAdapterErrorCode::unsupported_image, "PNG 行过滤器无效");
        }
        for (std::size_t x = 0; x < row_bytes; ++x) {
            const auto left = x >= channels ? target[x - channels] : 0U;
            const auto up = previous ? previous[x] : 0U;
            const auto upper_left = previous && x >= channels ? previous[x - channels] : 0U;
            const auto value = source[x];
            target[x] = static_cast<std::uint8_t>(
                filter == 0 ? value
                : filter == 1 ? value + left
                : filter == 2 ? value + up
                : filter == 3 ? value + static_cast<std::uint8_t>(
                    (static_cast<unsigned int>(left) + up) / 2U)
                : value + paeth_predictor(left, up, upper_left));
        }
    }

    RGBAImage image{
        .width = static_cast<int>(width),
        .height = static_cast<int>(height),
        .pixels = std::vector<std::uint8_t>(
            static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U),
    };
    for (std::size_t y = 0; y < height; ++y) {
        for (std::size_t x = 0; x < width; ++x) {
            const auto source_offset = y * row_bytes + x * channels;
            const auto target_offset =
                (y * static_cast<std::size_t>(width) + x) * 4U;
            if (color_type == 0) {
                image.pixels[target_offset] = rows[source_offset];
                image.pixels[target_offset + 1U] = rows[source_offset];
                image.pixels[target_offset + 2U] = rows[source_offset];
                image.pixels[target_offset + 3U] = 0xffU;
            } else if (color_type == 2) {
                image.pixels[target_offset] = rows[source_offset];
                image.pixels[target_offset + 1U] = rows[source_offset + 1U];
                image.pixels[target_offset + 2U] = rows[source_offset + 2U];
                image.pixels[target_offset + 3U] = 0xffU;
            } else if (color_type == 4) {
                image.pixels[target_offset] = rows[source_offset];
                image.pixels[target_offset + 1U] = rows[source_offset];
                image.pixels[target_offset + 2U] = rows[source_offset];
                image.pixels[target_offset + 3U] = rows[source_offset + 1U];
            } else {
                std::copy_n(
                    rows.data() + source_offset,
                    4,
                    image.pixels.data() + target_offset);
            }
        }
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

RGBAImage decode_jpeg(std::span<const std::uint8_t> bytes) {
    jpeg_decompress_struct info{};
    JPEGErrorManager error{};
    info.err = jpeg_std_error(&error.base);
    error.base.error_exit = jpeg_error_exit;
    jpeg_create_decompress(&info);
    if (setjmp(error.jump) != 0) {
        jpeg_destroy_decompress(&info);
        fail(PDFiumAdapterErrorCode::unsupported_image, "无法读取 JPEG 图片");
    }
    jpeg_mem_src(
        &info,
        const_cast<unsigned char*>(bytes.data()),
        static_cast<unsigned long>(bytes.size()));
    if (jpeg_read_header(&info, TRUE) != JPEG_HEADER_OK) {
        jpeg_destroy_decompress(&info);
        fail(PDFiumAdapterErrorCode::unsupported_image, "JPEG 图片头无效");
    }
    info.out_color_space = JCS_RGB;
    jpeg_start_decompress(&info);
    if (info.output_width == 0 || info.output_height == 0
        || static_cast<std::uint64_t>(info.output_width)
                * static_cast<std::uint64_t>(info.output_height)
            > maximum_render_pixels) {
        jpeg_abort_decompress(&info);
        jpeg_destroy_decompress(&info);
        fail(PDFiumAdapterErrorCode::unsupported_image, "JPEG 图片尺寸过大");
    }
    RGBAImage image{
        .width = static_cast<int>(info.output_width),
        .height = static_cast<int>(info.output_height),
        .pixels = std::vector<std::uint8_t>(
            static_cast<std::size_t>(info.output_width)
            * static_cast<std::size_t>(info.output_height) * 4U),
    };
    std::vector<std::uint8_t> row(
        static_cast<std::size_t>(info.output_width) * info.output_components);
    while (info.output_scanline < info.output_height) {
        JSAMPROW scanline = row.data();
        jpeg_read_scanlines(&info, &scanline, 1);
        const auto y = static_cast<std::size_t>(info.output_scanline - 1U);
        for (std::size_t x = 0; x < static_cast<std::size_t>(info.output_width); ++x) {
            const auto source_offset = x * info.output_components;
            const auto target_offset =
                (y * static_cast<std::size_t>(image.width) + x) * 4U;
            image.pixels[target_offset] = row[source_offset];
            image.pixels[target_offset + 1U] = row[source_offset + 1U];
            image.pixels[target_offset + 2U] = row[source_offset + 2U];
            image.pixels[target_offset + 3U] = 0xffU;
        }
    }
    jpeg_finish_decompress(&info);
    jpeg_destroy_decompress(&info);
    return image;
}

RGBAImage load_image(const fs::path& path) {
    const auto normalized = normalized_input_path(path);
    const auto bytes = read_binary_file(normalized);
    constexpr std::array<std::uint8_t, 8> png_signature{
        0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a,
    };
    if (bytes.size() >= png_signature.size()
        && std::equal(png_signature.begin(), png_signature.end(), bytes.begin())) {
        return decode_png(bytes);
    }
    if (bytes.size() >= 2U && bytes[0] == 0xffU && bytes[1] == 0xd8U) {
        return decode_jpeg(bytes);
    }
    fail(
        PDFiumAdapterErrorCode::unsupported_image,
        "仅支持 PNG 或 JPEG 图片：" + display_name(normalized));
}

std::vector<std::uint8_t> encode_jpeg(
    int width,
    int height,
    std::span<const std::uint8_t> rgba,
    int quality = 90) {
    if (width <= 0 || height <= 0
        || rgba.size() != static_cast<std::size_t>(width)
            * static_cast<std::size_t>(height) * 4U) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "JPEG 输入像素无效");
    }
    jpeg_compress_struct info{};
    JPEGErrorManager error{};
    info.err = jpeg_std_error(&error.base);
    error.base.error_exit = jpeg_error_exit;
    jpeg_create_compress(&info);
    unsigned char* encoded = nullptr;
    unsigned long encoded_size = 0;
    if (setjmp(error.jump) != 0) {
        jpeg_destroy_compress(&info);
        if (encoded) {
            std::free(encoded);
        }
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法编码 JPEG 图片");
    }
    jpeg_mem_dest(&info, &encoded, &encoded_size);
    info.image_width = static_cast<JDIMENSION>(width);
    info.image_height = static_cast<JDIMENSION>(height);
    info.input_components = 3;
    info.in_color_space = JCS_RGB;
    jpeg_set_defaults(&info);
    jpeg_set_quality(&info, std::clamp(quality, 1, 100), TRUE);
    jpeg_start_compress(&info, TRUE);
    std::vector<std::uint8_t> row(static_cast<std::size_t>(width) * 3U);
    while (info.next_scanline < info.image_height) {
        const auto y = static_cast<std::size_t>(info.next_scanline);
        for (std::size_t x = 0; x < static_cast<std::size_t>(width); ++x) {
            const auto source = (y * static_cast<std::size_t>(width) + x) * 4U;
            const auto alpha = rgba[source + 3U] / 255.0;
            row[x * 3U] = static_cast<std::uint8_t>(
                std::lround(rgba[source] * alpha + 255.0 * (1.0 - alpha)));
            row[x * 3U + 1U] = static_cast<std::uint8_t>(
                std::lround(rgba[source + 1U] * alpha + 255.0 * (1.0 - alpha)));
            row[x * 3U + 2U] = static_cast<std::uint8_t>(
                std::lround(rgba[source + 2U] * alpha + 255.0 * (1.0 - alpha)));
        }
        JSAMPROW scanline = row.data();
        jpeg_write_scanlines(&info, &scanline, 1);
    }
    jpeg_finish_compress(&info);
    std::vector<std::uint8_t> result(encoded, encoded + encoded_size);
    std::free(encoded);
    jpeg_destroy_compress(&info);
    return result;
}

BitmapHandle bitmap_from_image(const RGBAImage& image, double opacity) {
    if (image.width <= 0 || image.height <= 0
        || image.pixels.size() != static_cast<std::size_t>(image.width)
            * static_cast<std::size_t>(image.height) * 4U
        || !std::isfinite(opacity) || opacity < 0 || opacity > 1) {
        fail(PDFiumAdapterErrorCode::invalid_watermark_scale, "图片水印参数无效");
    }
    BitmapHandle bitmap{FPDFBitmap_Create(image.width, image.height, 1)};
    const auto stride = bitmap ? FPDFBitmap_GetStride(bitmap.get()) : 0;
    auto* destination = bitmap
        ? static_cast<std::uint8_t*>(FPDFBitmap_GetBuffer(bitmap.get()))
        : nullptr;
    if (!destination || stride < image.width * 4) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法创建图片水印位图");
    }
    for (int y = 0; y < image.height; ++y) {
        auto* row = destination + static_cast<std::size_t>(y)
            * static_cast<std::size_t>(stride);
        for (int x = 0; x < image.width; ++x) {
            const auto source_offset = (static_cast<std::size_t>(y)
                * static_cast<std::size_t>(image.width)
                + static_cast<std::size_t>(x)) * 4U;
            const auto target_offset = static_cast<std::size_t>(x) * 4U;
            row[target_offset] = image.pixels[source_offset + 2U];
            row[target_offset + 1U] = image.pixels[source_offset + 1U];
            row[target_offset + 2U] = image.pixels[source_offset];
            row[target_offset + 3U] = static_cast<std::uint8_t>(std::lround(
                static_cast<double>(image.pixels[source_offset + 3U]) * opacity));
        }
    }
    return bitmap;
}

void save_document(
    FPDF_DOCUMENT document,
    const fs::path& output,
    bool remove_security = false) {
    std::ofstream stream(output, std::ios::binary | std::ios::trunc);
    if (!stream) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法写入 PDF 输出文件");
    }
    FileWriterContext writer{
        .interface = {1, write_file_block},
        .stream = &stream,
    };
    const auto flags = static_cast<FPDF_DWORD>(FPDF_NO_INCREMENTAL
        | (remove_security ? FPDF_REMOVE_SECURITY : 0));
    if (!FPDF_SaveAsCopy(document, &writer.interface, flags) || !stream) {
        fail(PDFiumAdapterErrorCode::cannot_save_document, "无法保存 PDF 输出文件");
    }
}

bool is_ascii(std::string_view value) noexcept {
    return std::all_of(value.begin(), value.end(), [](unsigned char character) {
        return character <= 0x7fU;
    });
}

std::optional<fs::path> first_available_font(const fs::path& preferred) {
    std::vector<fs::path> candidates;
    if (!preferred.empty()) {
        candidates.push_back(preferred);
    }
    if (const auto* environment_font = std::getenv("ZISLA_PDF_FONT"); environment_font
        && *environment_font != '\0') {
        candidates.emplace_back(environment_font);
    }
#ifdef _WIN32
    candidates.emplace_back(L"C:\\Windows\\Fonts\\msyh.ttf");
    candidates.emplace_back(L"C:\\Windows\\Fonts\\segoeui.ttf");
    candidates.emplace_back(L"C:\\Windows\\Fonts\\arial.ttf");
#elif defined(__APPLE__)
    candidates.emplace_back("/System/Library/Fonts/Supplemental/Arial Unicode.ttf");
    candidates.emplace_back("/System/Library/Fonts/Supplemental/Arial.ttf");
#endif
    std::error_code error;
    for (const auto& candidate : candidates) {
        if (fs::is_regular_file(candidate, error) && !error) {
            return candidate;
        }
        error.clear();
    }
    return std::nullopt;
}

FontHandle load_font(
    FPDF_DOCUMENT document,
    std::string_view text,
    const fs::path& preferred_font) {
    if (preferred_font.empty() && is_ascii(text)) {
        FontHandle font{FPDFText_LoadStandardFont(document, "Helvetica")};
        if (font) {
            return font;
        }
    }
    const auto font_path = first_available_font(preferred_font);
    if (!font_path) {
        fail(PDFiumAdapterErrorCode::missing_font, "未找到可嵌入的水印字体");
    }
    const auto data = read_binary_file(*font_path);
    if (data.size() > std::numeric_limits<std::uint32_t>::max()) {
        fail(PDFiumAdapterErrorCode::missing_font, "水印字体文件过大");
    }
    FontHandle font{FPDFText_LoadFont(
        document,
        data.data(),
        static_cast<std::uint32_t>(data.size()),
        FPDF_FONT_TRUETYPE,
        1)};
    if (!font) {
        fail(PDFiumAdapterErrorCode::missing_font, "无法加载水印字体：" + display_name(*font_path));
    }
    return font;
}

PageObjectHandle make_text_object(
    FPDF_DOCUMENT document,
    FPDF_FONT font,
    std::string_view text,
    double font_size,
    double opacity) {
    if (text.empty() || !std::isfinite(font_size) || font_size <= 0
        || !std::isfinite(opacity) || opacity < 0 || opacity > 1) {
        fail(PDFiumAdapterErrorCode::invalid_watermark, "文字水印参数无效");
    }
    PageObjectHandle object{FPDFPageObj_CreateTextObj(
        document,
        font,
        static_cast<float>(font_size))};
    if (!object) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法创建 PDF 文字对象");
    }
    const auto utf16 = utf16_from_utf8(text);
    if (!FPDFText_SetText(
            object.get(),
            reinterpret_cast<FPDF_WIDESTRING>(utf16.data()))
        || !FPDFPageObj_SetFillColor(
            object.get(),
            0,
            0,
            0,
            static_cast<unsigned int>(std::lround(opacity * 255.0)))) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法设置 PDF 文字对象");
    }
    return object;
}

struct ObjectBounds {
    double left{0};
    double bottom{0};
    double right{0};
    double top{0};

    [[nodiscard]] double width() const noexcept {
        return right - left;
    }

    [[nodiscard]] double height() const noexcept {
        return top - bottom;
    }
};

ObjectBounds object_bounds(FPDF_PAGEOBJECT object, double fallback_font_size) {
    float left = 0;
    float bottom = 0;
    float right = 0;
    float top = 0;
    if (FPDFPageObj_GetBounds(object, &left, &bottom, &right, &top)
        && right > left && top > bottom) {
        return {left, bottom, right, top};
    }
    return {0, 0, fallback_font_size * 0.6, fallback_font_size};
}

std::pair<double, double> overlay_origin(
    double page_width,
    double page_height,
    double width,
    double height,
    PDFOverlayPosition position,
    double inset) {
    if (!std::isfinite(page_width) || !std::isfinite(page_height)
        || !std::isfinite(width) || !std::isfinite(height)
        || !std::isfinite(inset) || inset < 0) {
        fail(PDFiumAdapterErrorCode::invalid_watermark_scale, "页面覆盖参数无效");
    }
    const auto horizontal = position == PDFOverlayPosition::top_leading
            || position == PDFOverlayPosition::leading
            || position == PDFOverlayPosition::bottom_leading
        ? inset
        : position == PDFOverlayPosition::top
                || position == PDFOverlayPosition::center
                || position == PDFOverlayPosition::bottom
            ? (page_width - width) / 2.0
            : page_width - inset - width;
    const auto vertical = position == PDFOverlayPosition::top_leading
            || position == PDFOverlayPosition::top
            || position == PDFOverlayPosition::top_trailing
        ? page_height - inset - height
        : position == PDFOverlayPosition::leading
                || position == PDFOverlayPosition::center
                || position == PDFOverlayPosition::trailing
            ? (page_height - height) / 2.0
            : inset;
    return {
        std::clamp(horizontal, 0.0, std::max(0.0, page_width - width)),
        std::clamp(vertical, 0.0, std::max(0.0, page_height - height)),
    };
}

void set_text_matrix(
    FPDF_PAGEOBJECT object,
    const ObjectBounds& bounds,
    double x,
    double y,
    double rotation_degrees) {
    if (!std::isfinite(rotation_degrees)) {
        fail(PDFiumAdapterErrorCode::invalid_watermark, "文字水印旋转角度无效");
    }
    const auto radians = rotation_degrees * std::numbers::pi / 180.0;
    const auto cosine = std::cos(radians);
    const auto sine = std::sin(radians);
    const auto local_center_x = (bounds.left + bounds.right) / 2.0;
    const auto local_center_y = (bounds.bottom + bounds.top) / 2.0;
    const auto target_center_x = x + bounds.width() / 2.0;
    const auto target_center_y = y + bounds.height() / 2.0;
    const FS_MATRIX matrix{
        static_cast<float>(cosine),
        static_cast<float>(sine),
        static_cast<float>(-sine),
        static_cast<float>(cosine),
        static_cast<float>(target_center_x - cosine * local_center_x + sine * local_center_y),
        static_cast<float>(target_center_y - sine * local_center_x - cosine * local_center_y),
    };
    if (!FPDFPageObj_SetMatrix(object, &matrix)) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法定位 PDF 文字对象");
    }
}

void insert_and_generate(FPDF_PAGE page, PageObjectHandle object) {
    const auto raw = object.release();
    if (!FPDFPage_InsertObject(page, raw)) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法写入 PDF 页面对象");
    }
    if (!FPDFPage_GenerateContent(page)) {
        fail(PDFiumAdapterErrorCode::cannot_save_document, "无法更新 PDF 页面内容");
    }
}

zisla::core::PDFDocumentSummary inspect_document(const fs::path& input) {
    std::error_code error;
    const auto file_size = fs::file_size(input, error);
    if (error) {
        fail(PDFiumAdapterErrorCode::invalid_input, "无法读取 PDF 文件大小");
    }
    const auto encoded = path_as_utf8(input);
    DocumentHandle document{FPDF_LoadDocument(encoded.c_str(), nullptr)};
    if (!document) {
        if (FPDF_GetLastError() == FPDF_ERR_PASSWORD) {
            return {
                .page_count = 0,
                .file_size = file_size,
                .is_encrypted = true,
                .is_locked = true,
            };
        }
        fail_load_document(input);
    }
    const auto page_count = FPDF_GetPageCount(document.get());
    if (page_count <= 0) {
        fail(PDFiumAdapterErrorCode::invalid_document, "PDF 不包含可处理页面：" + display_name(input));
    }
    return {
        .page_count = static_cast<std::size_t>(page_count),
        .file_size = file_size,
        .is_encrypted = FPDF_GetSecurityHandlerRevision(document.get()) >= 0,
        .is_locked = false,
    };
}

std::string extract_page_text(FPDF_PAGE page) {
    TextPageHandle text_page{FPDFText_LoadPage(page)};
    if (!text_page) {
        fail(PDFiumAdapterErrorCode::invalid_document, "无法读取 PDF 文字层");
    }
    const auto count = FPDFText_CountChars(text_page.get());
    if (count < 0) {
        fail(PDFiumAdapterErrorCode::invalid_document, "无法读取 PDF 文字层");
    }

    std::string text;
    text.reserve(static_cast<std::size_t>(count));
    for (int index = 0; index < count; ++index) {
        append_utf8(text, FPDFText_GetUnicode(text_page.get(), index));
    }
    return text;
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
    std::span<const std::uint8_t> payload) {
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

void write_png(
    const fs::path& output,
    FPDF_BITMAP bitmap,
    int width,
    int height) {
    const auto stride = FPDFBitmap_GetStride(bitmap);
    const auto* source = static_cast<const std::uint8_t*>(FPDFBitmap_GetBuffer(bitmap));
    if (!source || stride < width * 4) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法读取 PDF 渲染像素");
    }

    const auto row_bytes = static_cast<std::size_t>(width) * 4U;
    std::vector<std::uint8_t> rows(
        static_cast<std::size_t>(height) * (row_bytes + 1U));
    for (int y = 0; y < height; ++y) {
        const auto target_offset = static_cast<std::size_t>(y) * (row_bytes + 1U);
        rows[target_offset] = 0;
        const auto* source_row = source + static_cast<std::size_t>(y)
            * static_cast<std::size_t>(stride);
        auto* target_row = rows.data() + target_offset + 1U;
        for (int x = 0; x < width; ++x) {
            const auto source_offset = static_cast<std::size_t>(x) * 4U;
            const auto target_pixel = source_offset;
            target_row[target_pixel] = source_row[source_offset + 2U];
            target_row[target_pixel + 1U] = source_row[source_offset + 1U];
            target_row[target_pixel + 2U] = source_row[source_offset];
            target_row[target_pixel + 3U] = 0xffU;
        }
    }

    uLongf compressed_size = compressBound(static_cast<uLong>(rows.size()));
    std::vector<std::uint8_t> compressed(compressed_size);
    const auto compression_result = compress2(
        compressed.data(),
        &compressed_size,
        rows.data(),
        static_cast<uLong>(rows.size()),
        Z_BEST_SPEED);
    if (compression_result != Z_OK) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法压缩 PDF 渲染像素");
    }
    compressed.resize(compressed_size);

    std::ofstream stream(output, std::ios::binary | std::ios::trunc);
    if (!stream) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法写入 PNG 输出文件");
    }
    constexpr std::array<std::uint8_t, 8> signature{
        0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a,
    };
    stream.write(reinterpret_cast<const char*>(signature.data()), signature.size());
    const std::array<std::uint8_t, 13> header{
        static_cast<std::uint8_t>(static_cast<std::uint32_t>(width) >> 24U),
        static_cast<std::uint8_t>(static_cast<std::uint32_t>(width) >> 16U),
        static_cast<std::uint8_t>(static_cast<std::uint32_t>(width) >> 8U),
        static_cast<std::uint8_t>(width),
        static_cast<std::uint8_t>(static_cast<std::uint32_t>(height) >> 24U),
        static_cast<std::uint8_t>(static_cast<std::uint32_t>(height) >> 16U),
        static_cast<std::uint8_t>(static_cast<std::uint32_t>(height) >> 8U),
        static_cast<std::uint8_t>(height),
        8,
        6,
        0,
        0,
        0,
    };
    write_png_chunk(stream, "IHDR", header);
    write_png_chunk(stream, "IDAT", compressed);
    write_png_chunk(stream, "IEND", {});
    if (!stream) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法写入 PNG 输出文件");
    }
}

RGBAImage bitmap_as_rgba(FPDF_BITMAP bitmap, int width, int height) {
    const auto stride = FPDFBitmap_GetStride(bitmap);
    const auto has_alpha = FPDFBitmap_GetFormat(bitmap) == FPDFBitmap_BGRA;
    const auto* source = static_cast<const std::uint8_t*>(FPDFBitmap_GetBuffer(bitmap));
    if (!source || stride < width * 4) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法读取 PDF 渲染像素");
    }
    RGBAImage image{
        .width = width,
        .height = height,
        .pixels = std::vector<std::uint8_t>(
            static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U),
    };
    for (int y = 0; y < height; ++y) {
        const auto* source_row = source + static_cast<std::size_t>(y)
            * static_cast<std::size_t>(stride);
        auto* target_row = image.pixels.data() + static_cast<std::size_t>(y)
            * static_cast<std::size_t>(width) * 4U;
        for (int x = 0; x < width; ++x) {
            const auto offset = static_cast<std::size_t>(x) * 4U;
            target_row[offset] = source_row[offset + 2U];
            target_row[offset + 1U] = source_row[offset + 1U];
            target_row[offset + 2U] = source_row[offset];
            target_row[offset + 3U] = has_alpha ? source_row[offset + 3U] : 0xffU;
        }
    }
    return image;
}

void write_jpeg(
    const fs::path& output,
    FPDF_BITMAP bitmap,
    int width,
    int height) {
    const auto image = bitmap_as_rgba(bitmap, width, height);
    const auto encoded = encode_jpeg(
        image.width,
        image.height,
        image.pixels);
    std::ofstream stream(output, std::ios::binary | std::ios::trunc);
    if (!stream) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法写入 JPEG 输出文件");
    }
    stream.write(
        reinterpret_cast<const char*>(encoded.data()),
        static_cast<std::streamsize>(encoded.size()));
    if (!stream) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法写入 JPEG 输出文件");
    }
}

std::pair<int, int> raster_size(FPDF_PAGE page, int dpi) {
    const auto width_points = FPDF_GetPageWidthF(page);
    const auto height_points = FPDF_GetPageHeightF(page);
    const auto scale = static_cast<double>(dpi) / 72.0;
    const auto width = std::llround(static_cast<double>(width_points) * scale);
    const auto height = std::llround(static_cast<double>(height_points) * scale);
    if (width <= 0 || height <= 0
        || width > std::numeric_limits<int>::max()
        || height > std::numeric_limits<int>::max()
        || static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height)
            > maximum_render_pixels) {
        fail(PDFiumAdapterErrorCode::invalid_render_options, "PDF 页面渲染尺寸过大");
    }
    return {static_cast<int>(width), static_cast<int>(height)};
}

}  // namespace

PDFiumAdapterError::PDFiumAdapterError(
    PDFiumAdapterErrorCode code,
    std::string message)
    : std::runtime_error(std::move(message)),
      code_(code) {}

PDFiumAdapterErrorCode PDFiumAdapterError::code() const noexcept {
    return code_;
}

zisla::core::PDFDocumentSummary PDFiumAdapter::inspect(const fs::path& input) const {
    const auto normalized_input = normalized_input_path(input);
    std::lock_guard lock(runtime().mutex());
    return inspect_document(normalized_input);
}

void PDFiumAdapter::extract_text(
    const fs::path& input,
    std::vector<std::size_t> page_indexes,
    const fs::path& output) const {
    const auto normalized_input = normalized_input_path(input);
    const std::array inputs{normalized_input};
    const std::array outputs{normalized_output_path(output)};
    validate_outputs(inputs, outputs);
    PendingOutput pending_output{outputs.front()};

    std::lock_guard lock(runtime().mutex());
    const auto document = load_document(normalized_input);
    validate_page_indexes(page_indexes, document.get());

    std::ofstream stream(pending_output.temporary(), std::ios::binary | std::ios::trunc);
    if (!stream) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法写入文本输出文件");
    }
    for (std::size_t index = 0; index < page_indexes.size(); ++index) {
        const auto page = load_page(document.get(), page_indexes[index]);
        const auto text = extract_page_text(page.get());
        stream.write(text.data(), static_cast<std::streamsize>(text.size()));
        if (index + 1U < page_indexes.size()) {
            stream.put('\n');
        }
    }
    if (!stream) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法写入文本输出文件");
    }
    pending_output.commit();
}

std::vector<fs::path> PDFiumAdapter::render_pages(
    const fs::path& input,
    const fs::path& output_directory,
    PDFRasterImageFormat format,
    int dpi) const {
    if (format != PDFRasterImageFormat::png && format != PDFRasterImageFormat::jpeg) {
        fail(PDFiumAdapterErrorCode::invalid_render_options, "PDF 渲染图片格式无效");
    }
    if (dpi < minimum_render_dpi || dpi > maximum_render_dpi) {
        fail(PDFiumAdapterErrorCode::invalid_render_options, "PDF 渲染 DPI 必须在 1 到 600 之间");
    }

    const auto normalized_input = normalized_input_path(input);
    if (output_directory.empty()) {
        fail(PDFiumAdapterErrorCode::output_validation, "未选择图片输出文件夹");
    }
    std::error_code error;
    const auto normalized_directory = fs::absolute(output_directory, error).lexically_normal();
    if (error) {
        fail(PDFiumAdapterErrorCode::output_validation, "图片输出文件夹无效");
    }
    fs::create_directories(normalized_directory, error);
    if (error || !fs::is_directory(normalized_directory, error) || error) {
        fail(
            PDFiumAdapterErrorCode::cannot_create_output_directory,
            "无法创建图片输出文件夹：" + path_as_utf8(normalized_directory));
    }

    std::lock_guard lock(runtime().mutex());
    const auto document = load_document(normalized_input);
    const auto page_count = FPDF_GetPageCount(document.get());
    std::vector<fs::path> outputs;
    outputs.reserve(static_cast<std::size_t>(page_count));
    const auto base_name = normalized_input.stem().wstring();
    const auto extension = format == PDFRasterImageFormat::png ? L".png" : L".jpg";
    for (int page_index = 0; page_index < page_count; ++page_index) {
        const auto ordinal = std::to_wstring(page_index + 1);
        const auto padding = ordinal.size() < 3U ? 3U - ordinal.size() : 0U;
        outputs.push_back(
            normalized_directory / (base_name + L"-"
                + std::wstring(padding, L'0') + ordinal + extension));
    }
    const std::array inputs{normalized_input};
    validate_outputs(inputs, outputs);

    std::vector<PendingOutput> pending_outputs;
    pending_outputs.reserve(outputs.size());
    for (const auto& output : outputs) {
        pending_outputs.emplace_back(output);
    }
    for (int page_index = 0; page_index < page_count; ++page_index) {
        const auto page = load_page(document.get(), static_cast<std::size_t>(page_index));
        const auto [width, height] = raster_size(page.get(), dpi);
        BitmapHandle bitmap{FPDFBitmap_Create(width, height, 0)};
        if (!bitmap || !FPDFBitmap_FillRect(
                bitmap.get(),
                0,
                0,
                width,
                height,
                0xffffffffU)) {
            fail(PDFiumAdapterErrorCode::cannot_write_output, "无法分配 PDF 渲染位图");
        }
        FPDF_RenderPageBitmap(
            bitmap.get(),
            page.get(),
            0,
            0,
            width,
            height,
            0,
            FPDF_ANNOT);
        const auto& pending = pending_outputs[static_cast<std::size_t>(page_index)];
        if (format == PDFRasterImageFormat::png) {
            write_png(pending.temporary(), bitmap.get(), width, height);
        } else {
            write_jpeg(pending.temporary(), bitmap.get(), width, height);
        }
    }
    for (auto& output : pending_outputs) {
        output.commit();
    }
    return outputs;
}

void PDFiumAdapter::convert_images_to_pdf(
    std::span<const fs::path> inputs,
    const fs::path& output) const {
    if (inputs.empty()) {
        fail(PDFiumAdapterErrorCode::invalid_input, "至少需要选择一张图片");
    }
    std::vector<fs::path> sources;
    sources.reserve(inputs.size());
    for (const auto& input : inputs) {
        sources.push_back(normalized_input_path(input));
    }
    const std::array outputs{normalized_output_path(output)};
    validate_outputs(sources, outputs);
    PendingOutput pending{outputs.front()};

    std::lock_guard lock(runtime().mutex());
    DocumentHandle document{FPDF_CreateNewDocument()};
    if (!document) {
        fail(PDFiumAdapterErrorCode::cannot_write_output, "无法创建 PDF 文档");
    }
    std::vector<BitmapHandle> bitmaps;
    bitmaps.reserve(sources.size());
    for (std::size_t index = 0; index < sources.size(); ++index) {
        const auto image = load_image(sources[index]);
        PageHandle page{FPDFPage_New(
            document.get(),
            static_cast<int>(index),
            image.width,
            image.height)};
        if (!page) {
            fail(PDFiumAdapterErrorCode::cannot_write_output, "无法创建图片 PDF 页面");
        }
        auto bitmap = bitmap_from_image(image, 1.0);
        PageObjectHandle object{FPDFPageObj_NewImageObj(document.get())};
        if (!object || !FPDFImageObj_SetBitmap(nullptr, 0, object.get(), bitmap.get())) {
            fail(PDFiumAdapterErrorCode::cannot_write_output, "无法写入图片 PDF 页面");
        }
        const FS_MATRIX matrix{
            static_cast<float>(image.width),
            0,
            0,
            static_cast<float>(image.height),
            0,
            0,
        };
        if (!FPDFPageObj_SetMatrix(object.get(), &matrix)) {
            fail(PDFiumAdapterErrorCode::cannot_write_output, "无法设置图片 PDF 页面尺寸");
        }
        insert_and_generate(page.get(), std::move(object));
        bitmaps.push_back(std::move(bitmap));
    }
    save_document(document.get(), pending.temporary());
    pending.commit();
}

void PDFiumAdapter::add_text_watermark(
    const fs::path& input,
    const PDFTextWatermark& watermark,
    const fs::path& output) const {
    if (watermark.text.empty()) {
        fail(PDFiumAdapterErrorCode::invalid_watermark, "文字水印不能为空");
    }
    const auto source = normalized_input_path(input);
    const std::array inputs{source};
    const std::array outputs{normalized_output_path(output)};
    validate_outputs(inputs, outputs);
    PendingOutput pending{outputs.front()};

    std::lock_guard lock(runtime().mutex());
    const auto document = load_document(source);
    const auto font = load_font(document.get(), watermark.text, watermark.font_path);
    const auto page_count = FPDF_GetPageCount(document.get());
    for (int page_index = 0; page_index < page_count; ++page_index) {
        const auto page = load_page(document.get(), static_cast<std::size_t>(page_index));
        auto object = make_text_object(
            document.get(),
            font.get(),
            watermark.text,
            watermark.font_size,
            watermark.opacity);
        const auto bounds = object_bounds(object.get(), watermark.font_size);
        const auto [x, y] = overlay_origin(
            FPDF_GetPageWidthF(page.get()),
            FPDF_GetPageHeightF(page.get()),
            bounds.width(),
            bounds.height(),
            PDFOverlayPosition::center,
            0);
        set_text_matrix(object.get(), bounds, x, y, watermark.rotation_degrees);
        insert_and_generate(page.get(), std::move(object));
    }
    save_document(document.get(), pending.temporary());
    pending.commit();
}

void PDFiumAdapter::add_image_watermark(
    const fs::path& input,
    const PDFImageWatermark& watermark,
    const fs::path& output) const {
    if (watermark.image_path.empty() || !std::isfinite(watermark.scale)
        || watermark.scale <= 0 || watermark.scale > 1
        || !std::isfinite(watermark.opacity)
        || watermark.opacity < 0 || watermark.opacity > 1) {
        fail(PDFiumAdapterErrorCode::invalid_watermark_scale, "图片水印缩放或透明度无效");
    }
    const auto source = normalized_input_path(input);
    const auto image_path = normalized_input_path(watermark.image_path);
    const std::array inputs{source, image_path};
    const std::array outputs{normalized_output_path(output)};
    validate_outputs(inputs, outputs);
    PendingOutput pending{outputs.front()};

    std::lock_guard lock(runtime().mutex());
    const auto document = load_document(source);
    const auto image = load_image(image_path);
    const auto page_count = FPDF_GetPageCount(document.get());
    std::vector<BitmapHandle> bitmaps;
    bitmaps.reserve(static_cast<std::size_t>(page_count));
    for (int page_index = 0; page_index < page_count; ++page_index) {
        const auto page = load_page(document.get(), static_cast<std::size_t>(page_index));
        const auto page_width = static_cast<double>(FPDF_GetPageWidthF(page.get()));
        const auto page_height = static_cast<double>(FPDF_GetPageHeightF(page.get()));
        const auto max_side = std::min(page_width, page_height) * watermark.scale;
        const auto aspect = static_cast<double>(image.width) / image.height;
        const auto width = aspect >= 1 ? max_side : max_side * aspect;
        const auto height = aspect >= 1 ? max_side / aspect : max_side;
        const auto [x, y] = overlay_origin(
            page_width,
            page_height,
            width,
            height,
            watermark.position,
            24);
        auto bitmap = bitmap_from_image(image, watermark.opacity);
        PageObjectHandle object{FPDFPageObj_NewImageObj(document.get())};
        if (!object || !FPDFImageObj_SetBitmap(nullptr, 0, object.get(), bitmap.get())) {
            fail(PDFiumAdapterErrorCode::cannot_write_output, "无法创建图片水印对象");
        }
        const FS_MATRIX matrix{
            static_cast<float>(width),
            0,
            0,
            static_cast<float>(height),
            static_cast<float>(x),
            static_cast<float>(y),
        };
        if (!FPDFPageObj_SetMatrix(object.get(), &matrix)) {
            fail(PDFiumAdapterErrorCode::cannot_write_output, "无法定位图片水印");
        }
        insert_and_generate(page.get(), std::move(object));
        bitmaps.push_back(std::move(bitmap));
    }
    save_document(document.get(), pending.temporary());
    pending.commit();
}

void PDFiumAdapter::add_page_numbers(
    const fs::path& input,
    const PDFPageNumberStyle& style,
    const fs::path& output) const {
    if (!std::isfinite(style.font_size) || style.font_size <= 0
        || !std::isfinite(style.inset) || style.inset < 0) {
        fail(PDFiumAdapterErrorCode::invalid_watermark_scale, "页码样式无效");
    }
    const auto source = normalized_input_path(input);
    const std::array inputs{source};
    const std::array outputs{normalized_output_path(output)};
    validate_outputs(inputs, outputs);
    PendingOutput pending{outputs.front()};

    std::lock_guard lock(runtime().mutex());
    const auto document = load_document(source);
    const auto font = load_font(
        document.get(),
        style.prefix + "0" + style.suffix,
        style.font_path);
    const auto page_count = FPDF_GetPageCount(document.get());
    for (int page_index = 0; page_index < page_count; ++page_index) {
        const auto page = load_page(document.get(), static_cast<std::size_t>(page_index));
        const auto text = style.prefix + std::to_string(page_index + 1) + style.suffix;
        auto object = make_text_object(
            document.get(),
            font.get(),
            text,
            style.font_size,
            1.0);
        const auto bounds = object_bounds(object.get(), style.font_size);
        const auto [x, y] = overlay_origin(
            FPDF_GetPageWidthF(page.get()),
            FPDF_GetPageHeightF(page.get()),
            bounds.width(),
            bounds.height(),
            style.position,
            style.inset);
        set_text_matrix(object.get(), bounds, x, y, 0);
        insert_and_generate(page.get(), std::move(object));
    }
    save_document(document.get(), pending.temporary());
    pending.commit();
}

}  // namespace zisla::pdf
