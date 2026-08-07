#include "PDFProcessingService.hpp"

#include "LocalOfficeAdapter.hpp"
#include "QPDFAdapter.hpp"

#include <exception>
#include <span>
#include <stdexcept>
#include <utility>

namespace zisla::pdf {
namespace {

namespace fs = std::filesystem;

const fs::path& single_input(const PDFProcessingRequest& request) {
    if (request.inputs.size() != 1) {
        throw std::invalid_argument("该 PDF 操作需要且只需要一个输入文件");
    }
    return request.inputs.front();
}

const fs::path& single_output(const PDFProcessingRequest& request) {
    if (request.outputs.size() != 1) {
        throw std::invalid_argument("该 PDF 操作需要且只需要一个输出文件");
    }
    return request.outputs.front();
}

#if !defined(ZISLA_HAS_PDFIUM_ADAPTER)
[[noreturn]] void fail_pdfium_unavailable() {
    throw std::runtime_error("当前构建未包含 PDFium，无法执行此 PDF 操作");
}
#endif

}  // namespace

PDFProcessingService::OperationResult PDFProcessingService::execute(
    PDFProcessingRequest request) {
    QPDFAdapter adapter;
    switch (request.operation) {
    case PDFProcessingOperation::inspect:
        return {
            .summary = adapter.inspect(single_input(request)),
            .message = "已读取 PDF 信息",
        };
    case PDFProcessingOperation::read_metadata:
        return {
            .metadata = adapter.metadata(single_input(request)),
            .message = "已读取 PDF 元数据",
        };
    case PDFProcessingOperation::merge:
        adapter.merge(
            std::span<const fs::path>{request.inputs},
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已合并 PDF",
        };
    case PDFProcessingOperation::export_pages:
        adapter.export_pages(
            single_input(request),
            std::span<const std::size_t>{request.page_indexes},
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已导出 PDF 页面",
        };
    case PDFProcessingOperation::split:
        adapter.split(
            single_input(request),
            std::span<const std::vector<std::size_t>>{request.page_groups},
            std::span<const fs::path>{request.outputs});
        return {
            .outputs = std::move(request.outputs),
            .message = "已拆分 PDF 页面",
        };
    case PDFProcessingOperation::rotate:
        adapter.rotate(
            single_input(request),
            std::span<const std::size_t>{request.page_indexes},
            request.rotation_degrees,
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已旋转 PDF 页面",
        };
    case PDFProcessingOperation::crop:
        adapter.crop(
            single_input(request),
            std::span<const std::size_t>{request.page_indexes},
            request.crop_box,
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已裁剪 PDF 页面",
        };
    case PDFProcessingOperation::update_metadata:
        adapter.update_metadata(
            single_input(request),
            request.metadata,
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已更新 PDF 元数据",
        };
    case PDFProcessingOperation::protect:
        adapter.protect(
            single_input(request),
            request.protection,
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已加密 PDF",
        };
    case PDFProcessingOperation::unlock:
        adapter.unlock(
            single_input(request),
            request.password,
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已解除 PDF 密码",
        };
    case PDFProcessingOperation::export_text:
#if defined(ZISLA_HAS_PDFIUM_ADAPTER)
        PDFiumAdapter{}.extract_text(
            single_input(request),
            std::move(request.page_indexes),
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已导出 PDF 文本",
        };
#else
        fail_pdfium_unavailable();
#endif
    case PDFProcessingOperation::render_pages:
#if defined(ZISLA_HAS_PDFIUM_ADAPTER)
        return {
            .outputs = PDFiumAdapter{}.render_pages(
                single_input(request),
                request.output_directory,
                request.raster_image_format,
                request.render_dpi),
            .message = "已渲染 PDF 页面",
        };
#else
        fail_pdfium_unavailable();
#endif
    case PDFProcessingOperation::images_to_pdf:
#if defined(ZISLA_HAS_PDFIUM_ADAPTER)
        PDFiumAdapter{}.convert_images_to_pdf(
            std::span<const fs::path>{request.inputs},
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已将图片转换为 PDF",
        };
#else
        fail_pdfium_unavailable();
#endif
    case PDFProcessingOperation::text_watermark:
#if defined(ZISLA_HAS_PDFIUM_ADAPTER)
        PDFiumAdapter{}.add_text_watermark(
            single_input(request),
            request.text_watermark,
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已添加文字水印",
        };
#else
        fail_pdfium_unavailable();
#endif
    case PDFProcessingOperation::image_watermark:
#if defined(ZISLA_HAS_PDFIUM_ADAPTER)
        PDFiumAdapter{}.add_image_watermark(
            single_input(request),
            request.image_watermark,
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已添加图片水印",
        };
#else
        fail_pdfium_unavailable();
#endif
    case PDFProcessingOperation::page_numbers:
#if defined(ZISLA_HAS_PDFIUM_ADAPTER)
        PDFiumAdapter{}.add_page_numbers(
            single_input(request),
            request.page_number_style,
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已添加页码",
        };
#else
        fail_pdfium_unavailable();
#endif
    case PDFProcessingOperation::office_to_pdf:
        LocalOfficeAdapter{}.convert_to_pdf(
            single_input(request),
            single_output(request));
        return {
            .outputs = std::move(request.outputs),
            .message = "已转换 Office 文档为 PDF",
        };
    case PDFProcessingOperation::none:
        break;
    }
    throw std::invalid_argument("未选择 PDF 操作");
}

bool PDFProcessingSnapshot::terminal() const noexcept {
    return phase == PDFProcessingPhase::succeeded
        || phase == PDFProcessingPhase::failed;
}

PDFProcessingService::PDFProcessingService(ChangeCallback on_change)
    : on_change_(std::move(on_change)),
      snapshot_(std::make_shared<PDFProcessingSnapshot>()) {}

PDFProcessingService::~PDFProcessingService() {
    stop();
}

bool PDFProcessingService::start() {
    try {
        std::lock_guard lock(mutex_);
        if (running_) {
            return true;
        }
        if (stopping_) {
            return false;
        }
        worker_ = std::thread([this] { run(); });
        running_ = true;
        return true;
    } catch (...) {
        {
            std::lock_guard lock(mutex_);
            snapshot_ = std::make_shared<PDFProcessingSnapshot>(PDFProcessingSnapshot{
                .revision = ++next_revision_,
                .phase = PDFProcessingPhase::failed,
                .message = "无法启动 PDF 处理服务",
            });
        }
        notify();
        return false;
    }
}

void PDFProcessingService::stop() noexcept {
    try {
        std::thread worker;
        {
            std::lock_guard lock(mutex_);
            if (!running_ && !worker_.joinable()) {
                return;
            }
            stopping_ = true;
            commands_.clear();
            worker.swap(worker_);
        }
        command_ready_.notify_all();
        if (worker.joinable()) {
            worker.join();
        }
        {
            std::lock_guard lock(mutex_);
            running_ = false;
            stopping_ = false;
        }
    } catch (...) {
    }
}

bool PDFProcessingService::running() const {
    std::lock_guard lock(mutex_);
    return running_ && !stopping_;
}

std::shared_ptr<const PDFProcessingSnapshot> PDFProcessingService::snapshot() const {
    std::lock_guard lock(mutex_);
    return snapshot_;
}

std::uint64_t PDFProcessingService::enqueue(
    PDFProcessingOperation operation,
    std::function<OperationResult()> execute) {
    std::uint64_t request_id = 0;
    bool wake_worker = false;
    {
        std::lock_guard lock(mutex_);
        request_id = next_request_id_++;
        PDFProcessingSnapshot snapshot{
            .revision = ++next_revision_,
            .request_id = request_id,
            .operation = operation,
            .phase = PDFProcessingPhase::failed,
            .message = "PDF 处理服务尚未启动",
        };
        if (running_ && !stopping_) {
            commands_.push_back(Command{
                .request_id = request_id,
                .operation = operation,
                .execute = std::move(execute),
            });
            snapshot.phase = PDFProcessingPhase::queued;
            snapshot.message = "等待处理";
            wake_worker = true;
        }
        snapshot_ = std::make_shared<PDFProcessingSnapshot>(std::move(snapshot));
    }
    if (wake_worker) {
        command_ready_.notify_one();
    }
    notify();
    return request_id;
}

void PDFProcessingService::run() {
    for (;;) {
        Command command;
        {
            std::unique_lock lock(mutex_);
            command_ready_.wait(lock, [this] {
                return stopping_ || !commands_.empty();
            });
            if (stopping_) {
                return;
            }
            command = std::move(commands_.front());
            commands_.pop_front();
        }

        publish(
            command.request_id,
            command.operation,
            PDFProcessingPhase::running,
            {.message = "正在处理 PDF"});
        try {
            auto result = command.execute();
            if (result.message.empty()) {
                result.message = "PDF 处理完成";
            }
            publish(
                command.request_id,
                command.operation,
                PDFProcessingPhase::succeeded,
                std::move(result));
        } catch (const QPDFAdapterError& error) {
            publish(
                command.request_id,
                command.operation,
                PDFProcessingPhase::failed,
                {.message = error.what()});
        } catch (const PDFiumAdapterError& error) {
            publish(
                command.request_id,
                command.operation,
                PDFProcessingPhase::failed,
                {.message = error.what()});
        } catch (const LocalOfficeAdapterError& error) {
            publish(
                command.request_id,
                command.operation,
                PDFProcessingPhase::failed,
                {.message = error.what()});
        } catch (const std::exception& error) {
            publish(
                command.request_id,
                command.operation,
                PDFProcessingPhase::failed,
                {.message = error.what()});
        } catch (...) {
            publish(
                command.request_id,
                command.operation,
                PDFProcessingPhase::failed,
                {.message = "PDF 处理失败"});
        }
    }
}

void PDFProcessingService::publish(
    std::uint64_t request_id,
    PDFProcessingOperation operation,
    PDFProcessingPhase phase,
    OperationResult result) {
    {
        std::lock_guard lock(mutex_);
        if (stopping_) {
            return;
        }
        snapshot_ = std::make_shared<PDFProcessingSnapshot>(PDFProcessingSnapshot{
            .revision = ++next_revision_,
            .request_id = request_id,
            .operation = operation,
            .phase = phase,
            .summary = std::move(result.summary),
            .metadata = std::move(result.metadata),
            .outputs = std::move(result.outputs),
            .message = std::move(result.message),
        });
    }
    notify();
}

void PDFProcessingService::notify() noexcept {
    try {
        if (on_change_) {
            on_change_();
        }
    } catch (...) {
    }
}

std::uint64_t PDFProcessingService::submit(PDFProcessingRequest request) {
    const auto operation = request.operation;
    return enqueue(operation, [request = std::move(request)]() mutable {
        return PDFProcessingService::execute(std::move(request));
    });
}

std::uint64_t PDFProcessingService::inspect(fs::path input) {
    return submit({
        .operation = PDFProcessingOperation::inspect,
        .inputs = {std::move(input)},
    });
}

std::uint64_t PDFProcessingService::read_metadata(fs::path input) {
    return submit({
        .operation = PDFProcessingOperation::read_metadata,
        .inputs = {std::move(input)},
    });
}

std::uint64_t PDFProcessingService::merge(
    std::vector<fs::path> inputs,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::merge,
        .inputs = std::move(inputs),
        .outputs = {std::move(output)},
    });
}

std::uint64_t PDFProcessingService::export_pages(
    fs::path input,
    std::vector<std::size_t> page_indexes,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::export_pages,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
        .page_indexes = std::move(page_indexes),
    });
}

std::uint64_t PDFProcessingService::split(
    fs::path input,
    std::vector<std::vector<std::size_t>> page_groups,
    std::vector<fs::path> outputs) {
    return submit({
        .operation = PDFProcessingOperation::split,
        .inputs = {std::move(input)},
        .outputs = std::move(outputs),
        .page_groups = std::move(page_groups),
    });
}

std::uint64_t PDFProcessingService::rotate(
    fs::path input,
    std::vector<std::size_t> page_indexes,
    int degrees,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::rotate,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
        .page_indexes = std::move(page_indexes),
        .rotation_degrees = degrees,
    });
}

std::uint64_t PDFProcessingService::crop(
    fs::path input,
    std::vector<std::size_t> page_indexes,
    zisla::core::PDFCropBox crop_box,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::crop,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
        .page_indexes = std::move(page_indexes),
        .crop_box = crop_box,
    });
}

std::uint64_t PDFProcessingService::update_metadata(
    fs::path input,
    zisla::core::PDFDocumentMetadata metadata,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::update_metadata,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
        .metadata = std::move(metadata),
    });
}

std::uint64_t PDFProcessingService::protect(
    fs::path input,
    zisla::core::PDFPasswordProtection protection,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::protect,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
        .protection = std::move(protection),
    });
}

std::uint64_t PDFProcessingService::unlock(
    fs::path input,
    std::string password,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::unlock,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
        .password = std::move(password),
    });
}

std::uint64_t PDFProcessingService::export_text(
    fs::path input,
    std::vector<std::size_t> page_indexes,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::export_text,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
        .page_indexes = std::move(page_indexes),
    });
}

std::uint64_t PDFProcessingService::render_pages(
    fs::path input,
    fs::path output_directory,
    PDFRasterImageFormat format,
    int dpi) {
    return submit({
        .operation = PDFProcessingOperation::render_pages,
        .inputs = {std::move(input)},
        .output_directory = std::move(output_directory),
        .raster_image_format = format,
        .render_dpi = dpi,
    });
}

std::uint64_t PDFProcessingService::convert_images_to_pdf(
    std::vector<fs::path> inputs,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::images_to_pdf,
        .inputs = std::move(inputs),
        .outputs = {std::move(output)},
    });
}

std::uint64_t PDFProcessingService::add_text_watermark(
    fs::path input,
    PDFTextWatermark watermark,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::text_watermark,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
        .text_watermark = std::move(watermark),
    });
}

std::uint64_t PDFProcessingService::add_image_watermark(
    fs::path input,
    PDFImageWatermark watermark,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::image_watermark,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
        .image_watermark = std::move(watermark),
    });
}

std::uint64_t PDFProcessingService::add_page_numbers(
    fs::path input,
    PDFPageNumberStyle style,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::page_numbers,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
        .page_number_style = std::move(style),
    });
}

std::uint64_t PDFProcessingService::convert_office_to_pdf(
    fs::path input,
    fs::path output) {
    return submit({
        .operation = PDFProcessingOperation::office_to_pdf,
        .inputs = {std::move(input)},
        .outputs = {std::move(output)},
    });
}

}  // namespace zisla::pdf
