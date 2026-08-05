#include "pch.h"
#include "ClipboardHistoryService.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <cwctype>
#include <limits>
#include <optional>
#include <string_view>
#include <utility>

namespace winrt::Zisla {
namespace {

constexpr wchar_t excluded_from_history_format[] =
    L"ExcludeClipboardContentFromMonitorProcessing";
constexpr wchar_t can_include_in_history_format[] = L"CanIncludeInClipboardHistory";

std::int64_t now_unix_milliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

class ClipboardLock {
public:
    ClipboardLock() noexcept {
        for (int attempt = 0; attempt < 5 && !opened_; ++attempt) {
            opened_ = OpenClipboard(nullptr) != FALSE;
            if (!opened_) {
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
        }
    }

    ~ClipboardLock() {
        if (opened_) {
            CloseClipboard();
        }
    }

    ClipboardLock(const ClipboardLock&) = delete;
    ClipboardLock& operator=(const ClipboardLock&) = delete;

    [[nodiscard]] explicit operator bool() const noexcept {
        return opened_;
    }

private:
    bool opened_{false};
};

class GlobalMemoryLock {
public:
    explicit GlobalMemoryLock(HANDLE handle) noexcept
        : value_(handle ? GlobalLock(handle) : nullptr) {}

    ~GlobalMemoryLock() {
        if (value_) {
            GlobalUnlock(value_);
        }
    }

    GlobalMemoryLock(const GlobalMemoryLock&) = delete;
    GlobalMemoryLock& operator=(const GlobalMemoryLock&) = delete;

    [[nodiscard]] const void* get() const noexcept {
        return value_;
    }

private:
    void* value_{nullptr};
};

std::optional<std::vector<std::uint8_t>> clipboard_bytes(
    UINT format,
    std::size_t limit) {
    const auto handle = GetClipboardData(format);
    if (!handle) {
        return std::nullopt;
    }
    const auto size = GlobalSize(handle);
    if (size == 0 || size > limit) {
        return std::nullopt;
    }
    const GlobalMemoryLock lock(handle);
    const auto* data = static_cast<const std::uint8_t*>(lock.get());
    if (!data) {
        return std::nullopt;
    }
    return std::vector<std::uint8_t>(data, data + size);
}

bool clipboard_flag_is_false(UINT format) {
    if (format == 0 || !IsClipboardFormatAvailable(format)) {
        return false;
    }
    const auto handle = GetClipboardData(format);
    if (!handle || GlobalSize(handle) < sizeof(DWORD)) {
        return false;
    }
    const GlobalMemoryLock lock(handle);
    if (!lock.get()) {
        return false;
    }
    DWORD value = 0;
    std::memcpy(&value, lock.get(), sizeof(value));
    return value == 0;
}

std::optional<std::string> utf8(std::wstring_view value) {
    if (value.empty()) {
        return std::string{};
    }
    if (value.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return std::nullopt;
    }
    const auto input_size = static_cast<int>(value.size());
    const auto required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        input_size,
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) {
        return std::nullopt;
    }
    std::string result(static_cast<std::size_t>(required), '\0');
    if (WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            input_size,
            result.data(),
            required,
            nullptr,
            nullptr) != required) {
        return std::nullopt;
    }
    return result;
}

std::optional<std::string> clipboard_text() {
    if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) {
        return std::nullopt;
    }
    const auto handle = GetClipboardData(CF_UNICODETEXT);
    if (!handle) {
        return std::nullopt;
    }
    const auto bytes = GlobalSize(handle);
    if (bytes < sizeof(wchar_t)) {
        return std::nullopt;
    }
    const GlobalMemoryLock lock(handle);
    const auto* text = static_cast<const wchar_t*>(lock.get());
    if (!text) {
        return std::nullopt;
    }
    const auto capacity = bytes / sizeof(wchar_t);
    std::size_t length = 0;
    while (length < capacity && text[length] != L'\0') {
        ++length;
    }
    if (length == capacity) {
        return std::nullopt;
    }
    return utf8(std::wstring_view{text, length});
}

std::optional<std::vector<std::uint8_t>> bitmap_file_from_dib(
    UINT format,
    std::size_t limit) {
    const auto raw = clipboard_bytes(format, limit);
    if (!raw || raw->size() < sizeof(BITMAPINFOHEADER)) {
        return std::nullopt;
    }
    BITMAPINFOHEADER info{};
    std::memcpy(&info, raw->data(), sizeof(info));
    if (info.biSize < sizeof(BITMAPINFOHEADER) || info.biSize > raw->size()) {
        return std::nullopt;
    }

    std::size_t pixel_offset = info.biSize;
    if (info.biSize == sizeof(BITMAPINFOHEADER)) {
        if (info.biCompression == BI_BITFIELDS) {
            pixel_offset += 3U * sizeof(DWORD);
#ifdef BI_ALPHABITFIELDS
        } else if (info.biCompression == BI_ALPHABITFIELDS) {
            pixel_offset += 4U * sizeof(DWORD);
#endif
        }
    }
    const auto colors = info.biClrUsed != 0
        ? static_cast<std::size_t>(info.biClrUsed)
        : (info.biBitCount > 0 && info.biBitCount <= 8
            ? static_cast<std::size_t>(1U) << info.biBitCount
            : 0U);
    if (colors > (raw->size() - std::min(pixel_offset, raw->size())) / sizeof(RGBQUAD)) {
        return std::nullopt;
    }
    pixel_offset += colors * sizeof(RGBQUAD);
    if (pixel_offset > raw->size()
        || raw->size() > std::numeric_limits<DWORD>::max() - sizeof(BITMAPFILEHEADER)
        || pixel_offset > std::numeric_limits<DWORD>::max() - sizeof(BITMAPFILEHEADER)) {
        return std::nullopt;
    }

    BITMAPFILEHEADER header{};
    header.bfType = 0x4D42;
    header.bfSize = static_cast<DWORD>(sizeof(header) + raw->size());
    header.bfOffBits = static_cast<DWORD>(sizeof(header) + pixel_offset);
    std::vector<std::uint8_t> result(sizeof(header) + raw->size());
    std::memcpy(result.data(), &header, sizeof(header));
    std::memcpy(result.data() + sizeof(header), raw->data(), raw->size());
    return result;
}

std::wstring_view trimmed(std::wstring_view value) noexcept {
    while (!value.empty() && std::iswspace(value.front())) {
        value.remove_prefix(1);
    }
    while (!value.empty() && std::iswspace(value.back())) {
        value.remove_suffix(1);
    }
    return value;
}

std::string path_extension(const hstring& path) {
    const std::wstring_view value{path.c_str(), path.size()};
    const auto slash = value.find_last_of(L'/');
    const auto dot = value.find_last_of(L'.');
    if (dot == std::wstring_view::npos
        || (slash != std::wstring_view::npos && dot < slash)
        || dot + 1 >= value.size()) {
        return {};
    }
    return utf8(value.substr(dot + 1)).value_or(std::string{});
}

std::optional<zisla::core::ClipboardUrlCandidate> link_candidate(
    const std::string& value) {
    try {
        const auto wide = to_hstring(value);
        auto candidate = trimmed(std::wstring_view{wide.c_str(), wide.size()});
        if (candidate.empty()
            || std::any_of(candidate.begin(), candidate.end(), [](wchar_t character) {
                return std::iswspace(character) != 0;
            })) {
            return std::nullopt;
        }
        const Windows::Foundation::Uri uri{hstring{candidate}};
        return zisla::core::ClipboardUrlCandidate{
            .absolute = value,
            .scheme = utf8(uri.SchemeName().c_str()).value_or(std::string{}),
            .host = utf8(uri.Host().c_str()).value_or(std::string{}),
            .path_extension = path_extension(uri.Path()),
        };
    } catch (...) {
        return std::nullopt;
    }
}

}  // namespace

ClipboardHistoryService::ClipboardHistoryService(std::filesystem::path state_directory)
    : repository_(std::move(state_directory)),
      snapshot_(std::make_shared<const ItemList>()),
      detected_link_(std::shared_ptr<const DetectedClipboardLink>{}) {}

ClipboardHistoryService::~ClipboardHistoryService() {
    stop();
}

bool ClipboardHistoryService::start(
    HWND target,
    UINT history_changed_message,
    UINT link_detected_message) {
    std::lock_guard lock(mutex_);
    if (running_ || !target || history_changed_message == 0 || link_detected_message == 0) {
        return false;
    }
    target_ = target;
    history_changed_message_ = history_changed_message;
    link_detected_message_ = link_detected_message;
    running_ = true;
    commands_.push_back({CommandKind::reload});
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_ = false;
        commands_.clear();
        target_ = nullptr;
        history_changed_message_ = 0;
        link_detected_message_ = 0;
        return false;
    }
    condition_.notify_one();
    return true;
}

void ClipboardHistoryService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
    }
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    commands_.clear();
    target_ = nullptr;
    history_changed_message_ = 0;
    link_detected_message_ = 0;
}

void ClipboardHistoryService::configure(
    bool history_enabled,
    bool link_detection_enabled) noexcept {
    history_enabled_.store(history_enabled, std::memory_order_release);
    link_detection_enabled_.store(link_detection_enabled, std::memory_order_release);
}

void ClipboardHistoryService::capture(std::uint32_t sequence) {
    std::lock_guard lock(mutex_);
    if (!running_) {
        return;
    }
    std::erase_if(commands_, [](const Command& command) {
        return command.kind == CommandKind::capture;
    });
    commands_.push_back({
        .kind = CommandKind::capture,
        .sequence = sequence,
    });
    condition_.notify_one();
}

void ClipboardHistoryService::ignore_sequence(std::uint32_t sequence) noexcept {
    ignored_sequence_.store(sequence, std::memory_order_release);
}

void ClipboardHistoryService::record_pinned(zisla::core::ClipboardHistoryContent content) {
    enqueue({
        .kind = CommandKind::record_pinned,
        .content = std::move(content),
    });
}

void ClipboardHistoryService::set_pinned(std::int64_t id, bool pinned) {
    enqueue({
        .kind = CommandKind::set_pinned,
        .id = id,
        .pinned = pinned,
    });
}

void ClipboardHistoryService::remove(std::int64_t id) {
    enqueue({
        .kind = CommandKind::remove,
        .id = id,
    });
}

void ClipboardHistoryService::clear_history() {
    enqueue({CommandKind::clear_history});
}

void ClipboardHistoryService::clear_all() {
    enqueue({CommandKind::clear_all});
}

std::shared_ptr<const ClipboardHistoryService::ItemList>
ClipboardHistoryService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

std::shared_ptr<const DetectedClipboardLink>
ClipboardHistoryService::detected_link() const noexcept {
    return detected_link_.load(std::memory_order_acquire);
}

std::size_t ClipboardHistoryService::capacity() const noexcept {
    return repository_.capacity();
}

std::size_t ClipboardHistoryService::max_image_bytes() const noexcept {
    return repository_.max_image_bytes();
}

void ClipboardHistoryService::enqueue(Command command) {
    {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        commands_.push_back(std::move(command));
    }
    condition_.notify_one();
}

void ClipboardHistoryService::run() noexcept {
    bool apartment_initialized = false;
    try {
        init_apartment(apartment_type::multi_threaded);
        apartment_initialized = true;
    } catch (...) {
    }
    link_detector_.begin(GetClipboardSequenceNumber());
    while (true) {
        Command command;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !commands_.empty() || !running_;
            });
            if (commands_.empty() && !running_) {
                break;
            }
            command = std::move(commands_.front());
            commands_.pop_front();
        }
        try {
            execute(std::move(command));
        } catch (...) {
        }
    }
    if (apartment_initialized) {
        uninit_apartment();
    }
}

void ClipboardHistoryService::execute(Command command) {
    switch (command.kind) {
    case CommandKind::reload:
        publish_history();
        return;
    case CommandKind::capture: {
        if (command.sequence == ignored_sequence_.load(std::memory_order_acquire)
            || command.sequence != GetClipboardSequenceNumber()) {
            return;
        }
        auto capture = read_clipboard(command.sequence);
        if (link_detection_enabled_.load(std::memory_order_acquire)
            && capture.link_candidate) {
            if (link_detector_.detect(command.sequence, *capture.link_candidate)) {
                publish_link(*capture.link_candidate);
            }
        }
        if (history_enabled_.load(std::memory_order_acquire)
            && capture.content
            && repository_.record(
                std::move(*capture.content),
                now_unix_milliseconds())) {
            publish_history();
        }
        return;
    }
    case CommandKind::record_pinned:
        if (repository_.record(
                std::move(command.content),
                now_unix_milliseconds(),
                true)) {
            publish_history();
        }
        return;
    case CommandKind::set_pinned:
        if (repository_.set_pinned(command.id, command.pinned, now_unix_milliseconds())) {
            publish_history();
        }
        return;
    case CommandKind::remove:
        if (repository_.remove(command.id)) {
            publish_history();
        }
        return;
    case CommandKind::clear_history:
        repository_.clear_history();
        publish_history();
        return;
    case CommandKind::clear_all:
        repository_.clear_all();
        publish_history();
        return;
    }
}

ClipboardHistoryService::ClipboardReadResult ClipboardHistoryService::read_clipboard(
    std::uint32_t sequence) const {
    ClipboardReadResult result;
    if (sequence != GetClipboardSequenceNumber()) {
        return result;
    }
    const ClipboardLock clipboard;
    if (!clipboard || sequence != GetClipboardSequenceNumber()) {
        return result;
    }

    const auto excluded = RegisterClipboardFormatW(excluded_from_history_format);
    if ((excluded != 0 && IsClipboardFormatAvailable(excluded))
        || clipboard_flag_is_false(RegisterClipboardFormatW(can_include_in_history_format))) {
        return result;
    }

    const auto limit = repository_.max_image_bytes();
    const auto png_format = RegisterClipboardFormatW(L"PNG");
    if (png_format != 0 && IsClipboardFormatAvailable(png_format)) {
        if (auto data = clipboard_bytes(png_format, limit)) {
            result.content = zisla::core::ClipboardHistoryContent::make_image(std::move(*data));
            return result;
        }
    }
    for (const UINT format : {CF_DIBV5, CF_DIB}) {
        if (!IsClipboardFormatAvailable(format)) {
            continue;
        }
        if (auto data = bitmap_file_from_dib(format, limit)) {
            if (data->size() <= limit) {
                result.content = zisla::core::ClipboardHistoryContent::make_image(
                    std::move(*data));
                return result;
            }
        }
    }
    if (auto text = clipboard_text()) {
        result.link_candidate = link_candidate(*text);
        result.content = zisla::core::ClipboardHistoryContent::make_text(std::move(*text));
    }
    return result;
}

void ClipboardHistoryService::publish_history() {
    auto next = std::make_shared<const ItemList>(repository_.load());
    snapshot_.store(std::move(next), std::memory_order_release);

    HWND target = nullptr;
    UINT message = 0;
    {
        std::lock_guard lock(mutex_);
        target = target_;
        message = history_changed_message_;
    }
    if (target && message != 0) {
        (void)PostMessageW(target, message, 0, 0);
    }
}

void ClipboardHistoryService::publish_link(
    const zisla::core::ClipboardUrlCandidate& candidate) {
    detected_link_.store(
        std::make_shared<const DetectedClipboardLink>(DetectedClipboardLink{
            .url = candidate.absolute,
            .host = candidate.host,
        }),
        std::memory_order_release);

    HWND target = nullptr;
    UINT message = 0;
    {
        std::lock_guard lock(mutex_);
        target = target_;
        message = link_detected_message_;
    }
    if (target && message != 0) {
        (void)PostMessageW(target, message, 0, 0);
    }
}

}
