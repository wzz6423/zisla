#pragma once

#include "PDFiumAdapter.hpp"

#include <zisla/core/PDFProcessing.hpp>

#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace zisla::pdf {

enum class PDFProcessingOperation {
    none,
    inspect,
    read_metadata,
    merge,
    export_pages,
    split,
    rotate,
    crop,
    update_metadata,
    protect,
    unlock,
    export_text,
    render_pages,
    images_to_pdf,
    text_watermark,
    image_watermark,
    page_numbers,
    office_to_pdf,
};

enum class PDFProcessingPhase {
    idle,
    queued,
    running,
    succeeded,
    failed,
};

struct PDFProcessingSnapshot {
    std::uint64_t revision{0};
    std::uint64_t request_id{0};
    PDFProcessingOperation operation{PDFProcessingOperation::none};
    PDFProcessingPhase phase{PDFProcessingPhase::idle};
    std::optional<zisla::core::PDFDocumentSummary> summary;
    std::optional<zisla::core::PDFDocumentMetadata> metadata;
    std::vector<std::filesystem::path> outputs;
    std::string message;

    [[nodiscard]] bool terminal() const noexcept;
};

// UI 与宿主只提交值对象，后台队列不持有 WinRT 或 XAML 对象。
struct PDFProcessingRequest {
    PDFProcessingOperation operation{PDFProcessingOperation::none};
    std::vector<std::filesystem::path> inputs;
    std::vector<std::filesystem::path> outputs;
    std::vector<std::size_t> page_indexes;
    std::vector<std::vector<std::size_t>> page_groups;
    int rotation_degrees{0};
    zisla::core::PDFCropBox crop_box;
    zisla::core::PDFDocumentMetadata metadata;
    zisla::core::PDFPasswordProtection protection;
    std::string password;
    std::filesystem::path output_directory;
    PDFRasterImageFormat raster_image_format{PDFRasterImageFormat::png};
    int render_dpi{144};
    PDFTextWatermark text_watermark;
    PDFImageWatermark image_watermark;
    PDFPageNumberStyle page_number_style;
};

class PDFProcessingService {
public:
    // 回调在提交任务或工作线程中执行，只应投递 UI 更新，不能停止或销毁服务。
    using ChangeCallback = std::function<void()>;

    explicit PDFProcessingService(ChangeCallback on_change = {});
    ~PDFProcessingService();

    PDFProcessingService(const PDFProcessingService&) = delete;
    PDFProcessingService& operator=(const PDFProcessingService&) = delete;

    [[nodiscard]] bool start();
    void stop() noexcept;
    [[nodiscard]] bool running() const;
    [[nodiscard]] std::shared_ptr<const PDFProcessingSnapshot> snapshot() const;

    [[nodiscard]] std::uint64_t submit(PDFProcessingRequest request);

    [[nodiscard]] std::uint64_t inspect(std::filesystem::path input);
    [[nodiscard]] std::uint64_t read_metadata(std::filesystem::path input);
    [[nodiscard]] std::uint64_t merge(
        std::vector<std::filesystem::path> inputs,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t export_pages(
        std::filesystem::path input,
        std::vector<std::size_t> page_indexes,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t split(
        std::filesystem::path input,
        std::vector<std::vector<std::size_t>> page_groups,
        std::vector<std::filesystem::path> outputs);
    [[nodiscard]] std::uint64_t rotate(
        std::filesystem::path input,
        std::vector<std::size_t> page_indexes,
        int degrees,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t crop(
        std::filesystem::path input,
        std::vector<std::size_t> page_indexes,
        zisla::core::PDFCropBox crop_box,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t update_metadata(
        std::filesystem::path input,
        zisla::core::PDFDocumentMetadata metadata,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t protect(
        std::filesystem::path input,
        zisla::core::PDFPasswordProtection protection,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t unlock(
        std::filesystem::path input,
        std::string password,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t export_text(
        std::filesystem::path input,
        std::vector<std::size_t> page_indexes,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t render_pages(
        std::filesystem::path input,
        std::filesystem::path output_directory,
        PDFRasterImageFormat format = PDFRasterImageFormat::png,
        int dpi = 144);
    [[nodiscard]] std::uint64_t convert_images_to_pdf(
        std::vector<std::filesystem::path> inputs,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t add_text_watermark(
        std::filesystem::path input,
        PDFTextWatermark watermark,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t add_image_watermark(
        std::filesystem::path input,
        PDFImageWatermark watermark,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t add_page_numbers(
        std::filesystem::path input,
        PDFPageNumberStyle style,
        std::filesystem::path output);
    [[nodiscard]] std::uint64_t convert_office_to_pdf(
        std::filesystem::path input,
        std::filesystem::path output);

private:
    struct OperationResult {
        std::optional<zisla::core::PDFDocumentSummary> summary;
        std::optional<zisla::core::PDFDocumentMetadata> metadata;
        std::vector<std::filesystem::path> outputs;
        std::string message;
    };

    struct Command {
        std::uint64_t request_id{0};
        PDFProcessingOperation operation{PDFProcessingOperation::none};
        std::function<OperationResult()> execute;
    };

    [[nodiscard]] static OperationResult execute(PDFProcessingRequest request);
    [[nodiscard]] std::uint64_t enqueue(
        PDFProcessingOperation operation,
        std::function<OperationResult()> execute);
    void run();
    void publish(
        std::uint64_t request_id,
        PDFProcessingOperation operation,
        PDFProcessingPhase phase,
        OperationResult result);
    void notify() noexcept;

    ChangeCallback on_change_;
    mutable std::mutex mutex_;
    std::condition_variable command_ready_;
    std::deque<Command> commands_;
    std::thread worker_;
    std::shared_ptr<const PDFProcessingSnapshot> snapshot_;
    std::uint64_t next_request_id_{1};
    std::uint64_t next_revision_{0};
    bool running_{false};
    bool stopping_{false};
};

}  // namespace zisla::pdf
