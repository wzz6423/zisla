#include "pch.h"
#include "OverlayContent.xaml.h"
#include "AppHost.h"
#include "AIAgentSkillsContent.xaml.h"
#include "AIAgentWorkspaceContent.xaml.h"
#include "PDFToolsContent.xaml.h"
#include "TransientUIHold.h"

#include <zisla/core/AIActivityPresentation.hpp>
#include <zisla/core/DashboardPresentation.hpp>

#include <winrt/Microsoft.UI.Xaml.Documents.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Text.h>

#include <algorithm>
#include <array>
#include <charconv>
#include <chrono>
#include <cctype>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <system_error>

#if __has_include("OverlayContent.g.cpp")
#include "OverlayContent.g.cpp"
#endif

namespace winrt::Zisla::implementation {
namespace {

hstring from_utf8(std::string_view value) {
    return value.empty() ? hstring{} : to_hstring(std::string(value));
}

bool is_safe_markdown_link(std::string_view link) noexcept {
    try {
        const Windows::Foundation::Uri uri(from_utf8(link));
        const auto scheme = to_string(uri.SchemeName());
        return scheme == "http" || scheme == "https";
    } catch (...) {
        return false;
    }
}

void append_quick_note_preview_inline(
    Microsoft::UI::Xaml::Documents::Paragraph const& paragraph,
    const zisla::core::QuickNoteMarkdownInline& inline_item) {
    using namespace Microsoft::UI::Xaml::Documents;

    if (inline_item.kind == zisla::core::QuickNoteMarkdownInlineKind::link
        && is_safe_markdown_link(inline_item.link)) {
        try {
            Hyperlink hyperlink;
            hyperlink.NavigateUri(Windows::Foundation::Uri(from_utf8(inline_item.link)));
            Run run;
            run.Text(from_utf8(inline_item.text));
            hyperlink.Inlines().Append(run);
            paragraph.Inlines().Append(hyperlink);
            return;
        } catch (...) {
            // Fall through and show the link label as ordinary text.
        }
    }

    Run run;
    run.Text(from_utf8(inline_item.text));
    switch (inline_item.kind) {
    case zisla::core::QuickNoteMarkdownInlineKind::emphasis:
        run.FontStyle(Windows::UI::Text::FontStyle::Italic);
        break;
    case zisla::core::QuickNoteMarkdownInlineKind::strong:
        run.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
        break;
    case zisla::core::QuickNoteMarkdownInlineKind::strikethrough:
        run.TextDecorations(Windows::UI::Text::TextDecorations::Strikethrough);
        break;
    case zisla::core::QuickNoteMarkdownInlineKind::code:
        run.FontFamily(Microsoft::UI::Xaml::Media::FontFamily(L"Cascadia Mono"));
        break;
    case zisla::core::QuickNoteMarkdownInlineKind::text:
    case zisla::core::QuickNoteMarkdownInlineKind::link:
        break;
    }
    paragraph.Inlines().Append(run);
}

void append(std::wstring& target, const hstring& value) {
    target.append(value.c_str(), value.size());
}

hstring status_text(zisla::core::AIProgressStatus status) {
    switch (status) {
    case zisla::core::AIProgressStatus::queued:
        return L"等待运行";
    case zisla::core::AIProgressStatus::running:
        return L"正在运行";
    case zisla::core::AIProgressStatus::blocked:
        return L"等待你的操作";
    case zisla::core::AIProgressStatus::error:
        return L"发生错误";
    case zisla::core::AIProgressStatus::succeeded:
        return L"已完成";
    case zisla::core::AIProgressStatus::failed:
        return L"已失败";
    }
    return L"状态未知";
}

bool blank_text(std::string_view value) noexcept;

hstring voice_failure_text(
    std::optional<zisla::core::VoiceInputFailure> failure) {
    using zisla::core::VoiceInputFailure;
    switch (failure.value_or(VoiceInputFailure::recognition_failed)) {
    case VoiceInputFailure::speech_permission_denied:
        return L"未获得语音识别权限";
    case VoiceInputFailure::microphone_permission_denied:
        return L"未获得麦克风权限";
    case VoiceInputFailure::recognizer_unavailable:
        return L"当前语言的语音识别不可用";
    case VoiceInputFailure::no_audio_input:
        return L"未检测到可用的麦克风输入";
    case VoiceInputFailure::startup_failed:
        return L"无法启动语音输入";
    case VoiceInputFailure::recognition_failed:
        return L"语音识别已中断";
    }
    return L"语音识别已中断";
}

hstring voice_status_text(const zisla::core::VoiceInputSnapshot& snapshot) {
    using zisla::core::VoiceInputPhase;
    switch (snapshot.phase) {
    case VoiceInputPhase::requesting_speech_permission:
        return L"正在准备语音识别";
    case VoiceInputPhase::requesting_microphone_permission:
        return L"正在请求麦克风权限";
    case VoiceInputPhase::starting:
        return L"正在启动语音输入";
    case VoiceInputPhase::listening:
        return blank_text(snapshot.partial_text)
            ? hstring{L"正在聆听"}
            : from_utf8(snapshot.partial_text);
    case VoiceInputPhase::finalizing:
        return blank_text(snapshot.partial_text)
            ? hstring{L"正在完成听写"}
            : from_utf8(snapshot.partial_text);
    case VoiceInputPhase::failed:
        return voice_failure_text(snapshot.failure);
    case VoiceInputPhase::idle:
        return L"";
    }
    return L"";
}

bool shows_progress(zisla::core::AIProgressStatus status) noexcept {
    return status == zisla::core::AIProgressStatus::queued
        || status == zisla::core::AIProgressStatus::running;
}

std::int64_t now_unix_milliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

std::optional<std::int64_t> local_calendar_id(
    const zisla::core::CalendarEventSnapshot& item) noexcept {
    if (item.is_projected_occurrence || !item.source_identifier) {
        return std::nullopt;
    }
    constexpr std::string_view prefix = "local:";
    const std::string_view identifier = *item.source_identifier;
    if (!identifier.starts_with(prefix)) {
        return std::nullopt;
    }

    std::int64_t id = 0;
    const auto first = identifier.data() + prefix.size();
    const auto last = identifier.data() + identifier.size();
    const auto [end, error] = std::from_chars(first, last, id);
    return error == std::errc{} && end == last && id > 0
        ? std::optional{id}
        : std::nullopt;
}

Windows::Foundation::DateTime calendar_picker_date(
    zisla::core::CalendarCivilDate date) {
    const auto unix_ms = CalendarService::unixMilliseconds({
        .date = date,
        .hour = 12,
        .minute = 0,
    });
    return winrt::clock::from_sys(std::chrono::system_clock::time_point{
        std::chrono::milliseconds{unix_ms},
    });
}

zisla::core::CalendarCivilDate calendar_picker_civil_date(
    const Microsoft::UI::Xaml::Controls::DatePicker& picker) {
    const auto unix_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        winrt::clock::to_sys(picker.Date()).time_since_epoch()).count();
    return CalendarService::localDateTime(unix_ms).date;
}

std::pair<int, int> calendar_picker_time(
    const Microsoft::UI::Xaml::Controls::TimePicker& picker) {
    const auto total_minutes = std::chrono::duration_cast<std::chrono::minutes>(
        picker.Time()).count();
    if (total_minutes < 0 || total_minutes >= 24 * 60) {
        throw std::runtime_error("时间无效");
    }
    return {
        static_cast<int>(total_minutes / 60),
        static_cast<int>(total_minutes % 60),
    };
}

void set_calendar_picker_time(
    const Microsoft::UI::Xaml::Controls::TimePicker& picker,
    int hour,
    int minute) {
    picker.Time(std::chrono::hours{hour} + std::chrono::minutes{minute});
}

hstring calendar_local_time_text(std::int64_t unix_ms) {
    const auto local = CalendarService::localDateTime(unix_ms);
    const SYSTEMTIME value{
        .wYear = static_cast<WORD>(local.date.year),
        .wMonth = static_cast<WORD>(local.date.month),
        .wDay = static_cast<WORD>(local.date.day),
        .wHour = static_cast<WORD>(local.hour),
        .wMinute = static_cast<WORD>(local.minute),
    };
    std::array<wchar_t, 64> buffer{};
    if (GetTimeFormatEx(
            LOCALE_NAME_USER_DEFAULT,
            TIME_NOSECONDS,
            &value,
            nullptr,
            buffer.data(),
            static_cast<int>(buffer.size())) > 0) {
        return hstring{buffer.data()};
    }

    std::wstring fallback;
    if (local.hour < 10) {
        fallback.push_back(L'0');
    }
    fallback.append(std::to_wstring(local.hour));
    fallback.push_back(L':');
    if (local.minute < 10) {
        fallback.push_back(L'0');
    }
    fallback.append(std::to_wstring(local.minute));
    return hstring{fallback};
}

hstring image_size_text(std::size_t size) {
    if (size < 1024U * 1024U) {
        return hstring{std::to_wstring((size + 1023U) / 1024U) + L" KiB"};
    }
    const auto tenths = (size * 10U + 512U * 1024U) / (1024U * 1024U);
    return hstring{
        std::to_wstring(tenths / 10U)
        + L"."
        + std::to_wstring(tenths % 10U)
        + L" MiB"};
}

hstring duration_text(double seconds) {
    if (!std::isfinite(seconds) || seconds < 0) {
        seconds = 0;
    }
    const auto total = static_cast<std::int64_t>(seconds);
    const auto hours = total / 3'600;
    const auto minutes = (total % 3'600) / 60;
    const auto remaining_seconds = total % 60;
    std::wstring result;
    if (hours > 0) {
        result = std::to_wstring(hours);
        result.push_back(L':');
        if (minutes < 10) {
            result.push_back(L'0');
        }
        result.append(std::to_wstring(minutes));
        result.push_back(L':');
    } else {
        result = std::to_wstring(minutes);
        result.push_back(L':');
    }
    if (remaining_seconds < 10) {
        result.push_back(L'0');
    }
    result.append(std::to_wstring(remaining_seconds));
    return hstring{result};
}

hstring quick_note_time(std::int64_t modified_at_unix_ms) {
    const auto elapsed = std::max<std::int64_t>(
        0,
        now_unix_milliseconds() - modified_at_unix_ms);
    if (elapsed < 60'000) {
        return L"刚刚";
    }
    if (elapsed < 3'600'000) {
        return hstring{std::to_wstring(elapsed / 60'000) + L" 分钟前"};
    }
    if (elapsed < 86'400'000) {
        return hstring{std::to_wstring(elapsed / 3'600'000) + L" 小时前"};
    }
    return hstring{std::to_wstring(elapsed / 86'400'000) + L" 天前"};
}

bool blank_text(std::string_view value) noexcept {
    return value.empty() || std::all_of(value.begin(), value.end(), [](char character) {
        return std::isspace(static_cast<unsigned char>(character)) != 0;
    });
}

std::string trimmed_mail_field(std::string_view value) {
    const auto first = std::find_if_not(value.begin(), value.end(), [](char character) {
        return std::isspace(static_cast<unsigned char>(character)) != 0;
    });
    if (first == value.end()) {
        return {};
    }
    const auto last = std::find_if_not(value.rbegin(), value.rend(), [](char character) {
        return std::isspace(static_cast<unsigned char>(character)) != 0;
    }).base();
    return std::string(first, last);
}

hstring mail_preview(std::string_view value) {
    constexpr std::size_t maximum_preview_code_units = 320;
    const auto text = from_utf8(value);
    const std::wstring_view source{text.c_str(), text.size()};
    std::wstring result;
    result.reserve(std::min<std::size_t>(source.size(), maximum_preview_code_units));
    bool previous_space = false;
    bool truncated = false;
    for (std::size_t index = 0; index < source.size();) {
        const auto character = source[index];
        const bool surrogate_pair = character >= 0xD800 && character <= 0xDBFF
            && index + 1 < source.size()
            && source[index + 1] >= 0xDC00 && source[index + 1] <= 0xDFFF;
        const auto code_units = surrogate_pair ? 2U : 1U;
        if (result.size() + code_units > maximum_preview_code_units) {
            truncated = true;
            break;
        }
        index += code_units;
        if (character <= L' ') {
            if (!result.empty() && !previous_space) {
                result.push_back(L' ');
            }
            previous_space = true;
            continue;
        }
        result.append(source.data() + index - code_units, code_units);
        previous_space = false;
    }
    while (!result.empty() && result.back() == L' ') {
        result.pop_back();
    }
    if (truncated) {
        result.append(L"...");
    }
    return result.empty() ? hstring{L"无正文"} : hstring{result};
}

hstring weather_temperature(double value) {
    if (!std::isfinite(value)) {
        return L"--°";
    }
    return hstring{std::to_wstring(static_cast<long long>(std::llround(value)))
        + L"°"};
}

hstring weather_decimal(double value) {
    if (!std::isfinite(value)) {
        return L"--";
    }
    const auto tenths = static_cast<long long>(std::llround(value * 10.0));
    const auto magnitude = tenths < 0 ? -tenths : tenths;
    std::wstring result = tenths < 0 ? L"-" : L"";
    result.append(std::to_wstring(magnitude / 10));
    result.push_back(L'.');
    result.append(std::to_wstring(magnitude % 10));
    return hstring{result};
}

hstring weather_time(std::string_view value) {
    const auto separator = value.rfind('T');
    return from_utf8(separator == std::string_view::npos
        ? value
        : value.substr(separator + 1));
}

hstring system_percent(double value) {
    if (!std::isfinite(value)) {
        return L"--%";
    }
    const auto percent = static_cast<long long>(std::llround(
        zisla::core::SystemMonitorMath::clamp_fraction(value) * 100.0));
    return hstring{std::to_wstring(percent) + L"%"};
}

hstring disk_cleanup_kind_text(zisla::core::DiskCleanupKind kind) {
    using zisla::core::DiskCleanupKind;
    switch (kind) {
    case DiskCleanupKind::application_cache:
        return L"Zisla 缓存";
    case DiskCleanupKind::cache:
        return L"缓存";
    case DiskCleanupKind::log:
        return L"日志";
    case DiskCleanupKind::crash_report:
        return L"崩溃报告";
    case DiskCleanupKind::temporary_file:
        return L"临时文件";
    case DiskCleanupKind::package_cache:
        return L"软件包缓存";
    case DiskCleanupKind::developer_artifact:
        return L"开发产物";
    case DiskCleanupKind::large_file:
        return L"大文件";
    }
    return L"可清理项目";
}

void update_fraction_history(
    const Microsoft::UI::Xaml::Shapes::Polyline& line,
    const Microsoft::UI::Xaml::Controls::Canvas& canvas,
    const std::vector<double>& values) {
    auto points = line.Points();
    points.Clear();
    const auto width = canvas.ActualWidth();
    const auto height = canvas.ActualHeight();
    if (values.size() < 2 || width <= 0 || height <= 0) {
        return;
    }
    const auto denominator = static_cast<double>(values.size() - 1);
    for (std::size_t index = 0; index < values.size(); ++index) {
        const auto fraction = zisla::core::SystemMonitorMath::clamp_fraction(
            values[index]);
        points.Append(Windows::Foundation::Point{
            static_cast<float>(width * static_cast<double>(index) / denominator),
            static_cast<float>(height * (1.0 - fraction)),
        });
    }
}

wchar_t const* weather_glyph(int code) noexcept {
    switch (code) {
    case 0:
    case 1:
        return L"\uE706";
    case 45:
    case 48:
        return L"\uE9CA";
    default:
        return L"\uE753";
    }
}

hstring alert_severity_text(zisla::core::WeatherAlertSeverity severity) {
    switch (severity) {
    case zisla::core::WeatherAlertSeverity::minor:
        return L"一般";
    case zisla::core::WeatherAlertSeverity::moderate:
        return L"较重";
    case zisla::core::WeatherAlertSeverity::severe:
        return L"严重";
    case zisla::core::WeatherAlertSeverity::extreme:
        return L"极端";
    }
    return L"预警";
}

hstring task_metadata(const zisla::core::AIProgressTask& task) {
    std::wstring result;
    if (task.detail && !task.detail->empty()) {
        append(result, from_utf8(*task.detail));
    }
    if (task.effort && !task.effort->empty()) {
        if (!result.empty()) {
            result.append(L" · ");
        }
        append(result, from_utf8(*task.effort));
    }
    return hstring{result};
}

winrt::fire_and_forget prepare_shelf_drag(
    std::filesystem::path path,
    Microsoft::UI::Xaml::DragStartingEventArgs args) {
    using namespace Windows::ApplicationModel::DataTransfer;
    using namespace Windows::Storage;

    const auto deferral = args.GetDeferral();
    try {
        IStorageItem item{nullptr};
        try {
            item = co_await StorageFile::GetFileFromPathAsync(path.c_str());
        } catch (...) {
        }
        if (!item) {
            item = co_await StorageFolder::GetFolderFromPathAsync(path.c_str());
        }
        std::vector<IStorageItem> items;
        items.push_back(std::move(item));
        args.Data().RequestedOperation(DataPackageOperation::Copy);
        args.Data().SetStorageItems(single_threaded_vector<IStorageItem>(
            std::move(items)));
    } catch (...) {
        args.Cancel(true);
    }
    deferral.Complete();
}

}

OverlayContent::OverlayContent() {
    InitializeComponent();
    quick_note_save_timer_ = Microsoft::UI::Xaml::DispatcherTimer();
    quick_note_save_timer_.Interval(std::chrono::milliseconds(800));
    quick_note_save_timer_.Tick([this](auto&&, auto&&) {
        quick_note_save_timer_.Stop();
        flushQuickNoteSave();
    });
}

void OverlayContent::setOpaqueSurface(bool opaque) {
    try {
        const auto key = box_value(
            opaque ? L"OverlayOpaqueSurfaceBrush" : L"OverlaySurfaceBrush");
        const auto brush = Microsoft::UI::Xaml::Application::Current().Resources().Lookup(key)
            .try_as<Microsoft::UI::Xaml::Media::Brush>();
        if (brush) {
            SurfaceBorder().Background(brush);
        }
    } catch (...) {
        // 材质不可用时保留 XAML 的主题回退，不让视觉失败影响浮层状态机。
    }
}

zisla::core::DipSize OverlayContent::preferredInteractiveCardSize() const noexcept {
    constexpr auto dashboard_base_height = 264.0F;
    constexpr auto dashboard_item_height = 60.0F;
    constexpr auto page_min_height = 300.0F;
    constexpr auto page_max_height = 600.0F;
    const auto bounded_height = [page_min_height, page_max_height](float value) noexcept {
        return std::clamp(value, page_min_height, page_max_height);
    };
    const auto with_voice_status = [this, &bounded_height](
                                       zisla::core::DipSize size) noexcept {
        if (voice_input_enabled_
            && voice_input_.phase != zisla::core::VoiceInputPhase::idle) {
            size.height = bounded_height(size.height + 34.0F);
        }
        return size;
    };
    const auto visible_dashboard_items = [this]() noexcept {
        std::size_t count = ai_tasks_.empty() ? 0 : 1;
        count += pomodoro_.active() ? 1 : 0;
        count += download_snapshot_ && download_snapshot_->active() ? 1 : 0;
        count += browser_download_snapshot_
                && browser_download_snapshot_->summary.total_active_count > 0
            ? 1
            : 0;
        count += now_playing_ ? 1 : 0;
        count += weather_enabled_ && weather_snapshot_
                && !weather_snapshot_->weather.empty()
            ? 1
            : 0;
        return count;
    };

    if (selected_module_ == L"dashboard") {
        return with_voice_status({660.0F, bounded_height(
            dashboard_base_height + dashboard_item_height * visible_dashboard_items())});
    }
    if (selected_module_ == L"shelf") {
        return with_voice_status({660.0F, bounded_height(300.0F
            + 50.0F * static_cast<float>(std::min<std::size_t>(shelf_items_.size(), 5)))});
    }
    if (selected_module_ == L"clipboard") {
        const auto item_count = clipboard_items_ ? clipboard_items_->size() : 0;
        return with_voice_status({660.0F, bounded_height(320.0F
            + 54.0F * static_cast<float>(std::min<std::size_t>(item_count, 4)))});
    }
    if (selected_module_ == L"ai") {
        return with_voice_status({820.0F, bounded_height(330.0F
            + 58.0F * static_cast<float>(std::min<std::size_t>(ai_tasks_.size(), 4)))});
    }
    if (selected_module_ == L"agent") {
        return with_voice_status({860.0F, 540.0F});
    }
    if (selected_module_ == L"download") {
        return with_voice_status({660.0F, download_snapshot_ && download_snapshot_->active()
            ? 390.0F
            : 330.0F});
    }
    if (selected_module_ == L"agenda") {
        const auto item_count = calendar_snapshot_ ? calendar_snapshot_->items.size() : 0;
        return with_voice_status({660.0F, bounded_height(330.0F
            + 44.0F * static_cast<float>(std::min<std::size_t>(item_count, 4)))});
    }
    if (selected_module_ == L"mail") {
        return with_voice_status({860.0F, 520.0F});
    }
    if (selected_module_ == L"notes") {
        return with_voice_status({720.0F, 560.0F});
    }
    if (selected_module_ == L"pdf") {
        return with_voice_status({660.0F, 600.0F});
    }
    if (selected_module_ == L"toolbox") {
        return with_voice_status({660.0F, 500.0F});
    }
    if (selected_module_ == L"system") {
        return with_voice_status({660.0F, 560.0F});
    }
    return with_voice_status({660.0F, 420.0F});
}

void OverlayContent::setInteractive(bool interactive) {
    interactive_ = interactive;
    PeekLayout().Visibility(interactive
        ? Microsoft::UI::Xaml::Visibility::Collapsed
        : Microsoft::UI::Xaml::Visibility::Visible);
    InteractiveLayout().Visibility(interactive
        ? Microsoft::UI::Xaml::Visibility::Visible
        : Microsoft::UI::Xaml::Visibility::Collapsed);
    updatePeek();
    updateVoiceInputView();
    updateSystemMonitorActivity();
}

void OverlayContent::setVisible(bool visible) {
    if (!visible) {
        quick_note_save_timer_.Stop();
        flushQuickNoteSave();
    }
    visible_ = visible;
    updatePeek();
    updateSystemMonitorActivity();
}

void OverlayContent::setPinned(bool pinned) {
    PinIcon().Glyph(pinned ? L"\uE77A" : L"\uE840");
    const auto label = pinned ? L"取消固定" : L"固定窗口";
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        PinButton(),
        label);
    Microsoft::UI::Xaml::Controls::ToolTipService::SetToolTip(
        PinButton(),
        box_value(label));
}

void OverlayContent::setVoiceInput(
    zisla::core::VoiceInputSnapshot snapshot,
    bool enabled) {
    voice_input_ = std::move(snapshot);
    voice_input_enabled_ = enabled;
    updateVoiceInputView();
    updatePeek();
}

void OverlayContent::setAIActivities(
    std::span<const zisla::core::AIProgressTask> tasks) {
    ai_tasks_ = zisla::core::AIActivityPresenter::active_tasks(tasks);
    updatePeek();
    updateAIView();
    updateDashboardView();
}

void OverlayContent::setNowPlaying(
    std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot) {
    const auto previous = now_playing_;
    if (snapshot && snapshot->valid()) {
        now_playing_ = std::move(snapshot);
    } else {
        now_playing_.reset();
    }

    if (previous.get() != now_playing_.get()) {
        const auto next_artwork = now_playing_
            ? now_playing_->artwork
            : nullptr;
        if (displayed_artwork_.get() == next_artwork.get()) {
            updateMediaView();
            updateDashboardView();
            updatePeek();
            return;
        }
        displayed_artwork_ = next_artwork;
        const auto generation = ++artwork_generation_;
        clearArtwork();
        if (!displayed_artwork_) {
            updatePeek();
        } else {
            loadArtwork(displayed_artwork_, generation);
        }
    }
    updateMediaView();
    updateDashboardView();
    updatePeek();
}

void OverlayContent::setShelfItems(
    std::span<const zisla::core::FileShelfItem> items,
    std::size_t capacity) {
    shelf_items_.assign(items.begin(), items.end());
    shelf_capacity_ = std::max<std::size_t>(1, capacity);
    updateShelfView();
}

void OverlayContent::setClipboardItems(
    std::shared_ptr<const std::vector<zisla::core::ClipboardHistoryItem>> items,
    std::size_t capacity) {
    clipboard_items_ = items
        ? std::move(items)
        : std::make_shared<const std::vector<zisla::core::ClipboardHistoryItem>>();
    clipboard_capacity_ = std::max<std::size_t>(1, capacity);
    ++clipboard_generation_;
    if (selected_module_ == L"clipboard") {
        updateClipboardView();
    } else {
        ClipboardList().Items().Clear();
    }
}

void OverlayContent::setQuickNotes(
    std::shared_ptr<const QuickNotesServiceSnapshot> snapshot) {
    quick_notes_snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const QuickNotesServiceSnapshot>();
    if (quick_notes_snapshot_->preferred_selection_id) {
        selected_quick_note_id_ = quick_notes_snapshot_->preferred_selection_id;
        displayed_quick_note_id_.reset();
    }
    updateQuickNotesView();
}

void OverlayContent::setPDFProcessing(
    std::shared_ptr<const zisla::pdf::PDFProcessingSnapshot> snapshot) {
    get_self<PDFToolsContent>(PDFToolsView())->setSnapshot(std::move(snapshot));
}

void OverlayContent::setAIAgentSkills(
    std::shared_ptr<const AIAgentSkillsServiceSnapshot> snapshot) {
    get_self<AIAgentSkillsContent>(AIAgentSkillsView())->setSnapshot(
        std::move(snapshot));
}

void OverlayContent::setAIAgentWorkspace(
    std::shared_ptr<const AIAgentWorkspaceServiceSnapshot> snapshot) {
    get_self<AIAgentWorkspaceContent>(AIAgentWorkspaceView())->setSnapshot(
        std::move(snapshot));
}

void OverlayContent::setDetectedClipboardLink(std::string link) {
    detected_clipboard_link_ = std::move(link);
    if (!download_snapshot_ || !download_snapshot_->active()) {
        updating_download_url_ = true;
        DownloadUrlBox().Text(from_utf8(detected_clipboard_link_));
        updating_download_url_ = false;
    }
    updateDownloadView();
}

void OverlayContent::setDownload(
    std::shared_ptr<const zisla::core::DownloadSnapshot> snapshot,
    std::filesystem::path output_directory) {
    download_snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const zisla::core::DownloadSnapshot>();
    if (!output_directory.empty()) {
        download_output_directory_ = std::move(output_directory);
    }
    if (download_snapshot_->active() && !download_snapshot_->request.url.empty()) {
        updating_download_url_ = true;
        DownloadUrlBox().Text(from_utf8(download_snapshot_->request.url));
        updating_download_url_ = false;
        DownloadVideoMode().IsChecked(box_value(
            download_snapshot_->request.mode == zisla::core::DownloadMode::video).as<
                Windows::Foundation::IReference<bool>>());
        DownloadAudioMode().IsChecked(box_value(
            download_snapshot_->request.mode == zisla::core::DownloadMode::audio).as<
                Windows::Foundation::IReference<bool>>());
    }
    updateDownloadView();
    updateDashboardView();
    updatePeek();
}

void OverlayContent::setBrowserDownloads(
    std::shared_ptr<const BrowserDownloadServiceSnapshot> snapshot) {
    browser_download_snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const BrowserDownloadServiceSnapshot>();
    updateDashboardView();
    updatePeek();
}

void OverlayContent::setPomodoro(zisla::core::PomodoroSnapshot snapshot) {
    pomodoro_ = std::move(snapshot);
    updatePeek();
    updateDashboardView();
    updateToolboxView();
}

void OverlayContent::setAlarms(
    std::span<const zisla::core::AlarmItem> alarms,
    std::optional<zisla::core::NextAlarm> next_alarm,
    std::string error) {
    alarms_.assign(alarms.begin(), alarms.end());
    next_alarm_ = std::move(next_alarm);
    alarm_error_ = std::move(error);
    updatePeek();
    updateAlarmView();
}

void OverlayContent::setPowerRequests(zisla::core::PowerRequestSnapshot snapshot) {
    power_requests_ = std::move(snapshot);
    updateToolboxView();
}

void OverlayContent::setCleaning(zisla::core::CleaningMode mode) {
    cleaning_mode_ = mode;
    updateToolboxView();
}

void OverlayContent::setWeather(
    std::shared_ptr<const WeatherServiceSnapshot> snapshot,
    std::span<const zisla::core::WeatherLocation> locations,
    bool enabled,
    bool loading,
    std::string status_override) {
    weather_snapshot_ = std::move(snapshot);
    weather_locations_.assign(locations.begin(), locations.end());
    weather_enabled_ = enabled;
    weather_loading_ = loading;
    weather_status_override_ = std::move(status_override);
    updatePeek();
    updateDashboardView();
    updateWeatherView();
}

void OverlayContent::setSystemMonitor(
    std::shared_ptr<const SystemMonitorServiceSnapshot> snapshot) {
    system_monitor_snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const SystemMonitorServiceSnapshot>();
    updateSystemMonitorView();
}

void OverlayContent::setDesktopTools(
    std::shared_ptr<const zisla::core::DesktopToolsSnapshot> snapshot) {
    desktop_tools_snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const zisla::core::DesktopToolsSnapshot>();
    updateToolboxView();
    updateSystemMonitorView();
}

void OverlayContent::setDiskCleanup(
    std::shared_ptr<const DiskCleanupServiceSnapshot> snapshot) {
    disk_cleanup_snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const DiskCleanupServiceSnapshot>();
    updateDiskCleanupView();
}

void OverlayContent::showAlarmEditor() {
    selectNavigationModule(L"toolbox");
    updateAlarmView();
    if (const auto flyout = AlarmButton().Flyout()) {
        flyout.ShowAt(AlarmButton());
    }
}

void OverlayContent::showPomodoro() {
    selectNavigationModule(L"toolbox");
    updateToolboxView();
}

void OverlayContent::updatePeek() {
    if (voice_input_enabled_
        && voice_input_.phase != zisla::core::VoiceInputPhase::idle) {
        const auto detail = voice_status_text(voice_input_);
        PeekTitle().Text(L"语音输入");
        PeekDetail().Text(detail);
        const bool pending = voice_input_.phase
                == zisla::core::VoiceInputPhase::requesting_speech_permission
            || voice_input_.phase
                == zisla::core::VoiceInputPhase::requesting_microphone_permission
            || voice_input_.phase == zisla::core::VoiceInputPhase::starting
            || voice_input_.phase == zisla::core::VoiceInputPhase::finalizing;
        const bool progress = pending && visible_ && !interactive_;
        PeekProgressRing().IsActive(progress);
        PeekProgressRing().Visibility(progress
            ? Microsoft::UI::Xaml::Visibility::Visible
            : Microsoft::UI::Xaml::Visibility::Collapsed);
        PeekPlaybackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        PeekArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        PeekFallbackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
        PeekFallbackIcon().Glyph(voice_input_.phase
            == zisla::core::VoiceInputPhase::failed
            ? L"\uE7BA"
            : L"\uE720");
        std::wstring accessible_name{L"语音输入"};
        accessible_name.append(L"，");
        append(accessible_name, detail);
        Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
            PeekLayout(),
            hstring{accessible_name});
        return;
    }
    if (pomodoro_.active()) {
        const auto title = pomodoro_.mode == zisla::core::PomodoroMode::focus
            ? L"专注倒计时"
            : L"休息倒计时";
        const auto clock = from_utf8(zisla::core::PomodoroEngine::format_clock(
            pomodoro_.remaining_seconds));
        const auto phase = pomodoro_.phase == zisla::core::PomodoroPhase::running
            ? L"进行中"
            : L"已暂停";
        PeekTitle().Text(title);
        std::wstring detail;
        append(detail, clock);
        detail.append(L" · ");
        detail.append(phase);
        PeekDetail().Text(hstring{detail});
        PeekProgressRing().IsActive(false);
        PeekProgressRing().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        PeekPlaybackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        PeekArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        PeekFallbackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
        PeekFallbackIcon().Glyph(L"\uE823");
        std::wstring accessible_name{title};
        accessible_name.append(L"，");
        append(accessible_name, clock);
        accessible_name.append(L"，");
        accessible_name.append(phase);
        Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
            PeekLayout(),
            hstring{accessible_name});
        return;
    }
    if (ai_tasks_.empty()) {
        if (download_snapshot_ && download_snapshot_->active()) {
            PeekTitle().Text(download_snapshot_->request.mode
                    == zisla::core::DownloadMode::video
                ? L"视频下载"
                : L"音频下载");
            std::wstring detail;
            if (download_snapshot_->phase == zisla::core::DownloadPhase::preparing) {
                detail = L"正在准备";
            } else if (download_snapshot_->phase
                == zisla::core::DownloadPhase::cancelling) {
                detail = L"正在取消";
            } else {
                const auto tenths = static_cast<long long>(std::llround(
                    std::clamp(download_snapshot_->fraction, 0.0, 1.0) * 1'000.0));
                detail = std::to_wstring(tenths / 10);
                detail.push_back(L'.');
                detail.append(std::to_wstring(tenths % 10));
                detail.push_back(L'%');
                if (!download_snapshot_->speed.empty()) {
                    detail.append(L" · ");
                    append(detail, from_utf8(download_snapshot_->speed));
                }
            }
            PeekDetail().Text(hstring{detail});
            const bool progress = visible_ && !interactive_
                && download_snapshot_->phase != zisla::core::DownloadPhase::cancelling;
            PeekProgressRing().IsActive(progress);
            PeekProgressRing().Visibility(progress
                ? Microsoft::UI::Xaml::Visibility::Visible
                : Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekPlaybackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekFallbackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
            PeekFallbackIcon().Glyph(L"\uE896");
            std::wstring accessible_name = PeekTitle().Text().c_str();
            accessible_name.append(L"，");
            accessible_name.append(detail);
            Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
                PeekLayout(),
                hstring{accessible_name});
            return;
        }
        if (browser_download_snapshot_
            && browser_download_snapshot_->summary.total_active_count > 0) {
            const auto& summary = browser_download_snapshot_->summary;
            PeekTitle().Text(L"浏览器下载");
            std::wstring detail = std::to_wstring(summary.total_active_count);
            detail.append(L" 个进行中");
            if (summary.combined_progress) {
                detail.append(L" · ");
                const auto percent = static_cast<long long>(std::llround(
                    std::clamp(*summary.combined_progress, 0.0, 1.0)
                        * 100.0));
                detail.append(std::to_wstring(percent));
                detail.push_back(L'%');
            }
            PeekDetail().Text(hstring{detail});
            const bool progress = visible_ && !interactive_;
            PeekProgressRing().IsActive(progress);
            PeekProgressRing().Visibility(progress
                ? Microsoft::UI::Xaml::Visibility::Visible
                : Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekPlaybackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekFallbackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
            PeekFallbackIcon().Glyph(L"\uE896");
            std::wstring accessible_name = L"浏览器下载，";
            accessible_name.append(detail);
            Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
                PeekLayout(),
                hstring{accessible_name});
            return;
        }
        if (now_playing_) {
            PeekTitle().Text(from_utf8(now_playing_->title));
            std::wstring detail;
            append(detail, from_utf8(now_playing_->artist));
            if (!detail.empty()) {
                detail.append(L" · ");
            }
            detail.append(now_playing_->playback_status
                    == zisla::core::MediaPlaybackStatus::playing
                ? L"正在播放"
                : L"已暂停");
            PeekDetail().Text(hstring{detail});
            PeekProgressRing().IsActive(false);
            PeekProgressRing().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekPlaybackIcon().Glyph(now_playing_->playback_status
                    == zisla::core::MediaPlaybackStatus::playing
                ? L"\uE768"
                : L"\uE769");
            PeekPlaybackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
            PeekFallbackIcon().Glyph(L"\uE8D6");
            const bool has_artwork = static_cast<bool>(PeekArtwork().Source());
            PeekArtwork().Visibility(has_artwork
                ? Microsoft::UI::Xaml::Visibility::Visible
                : Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekFallbackIcon().Visibility(has_artwork
                ? Microsoft::UI::Xaml::Visibility::Collapsed
                : Microsoft::UI::Xaml::Visibility::Visible);

            std::wstring accessible_name;
            append(accessible_name, from_utf8(now_playing_->title));
            accessible_name.append(L"，");
            accessible_name.append(detail);
            Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
                PeekLayout(),
                hstring{accessible_name});
            return;
        }

        if (next_alarm_) {
            const auto& alarm = next_alarm_->alarm;
            PeekTitle().Text(alarm.label.empty()
                ? hstring{L"下一个闹钟"}
                : from_utf8(alarm.label));
            std::wstring detail;
            append(detail, from_utf8(zisla::core::AlarmBook::format_time(alarm)));
            detail.append(L" · ");
            append(detail, from_utf8(
                zisla::core::AlarmBook::format_repeat(alarm.weekday_mask)));
            PeekDetail().Text(hstring{detail});
            PeekProgressRing().IsActive(false);
            PeekProgressRing().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekPlaybackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekFallbackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
            PeekFallbackIcon().Glyph(L"\uE823");
            std::wstring accessible_name{L"下一个闹钟，"};
            accessible_name.append(detail);
            Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
                PeekLayout(),
                hstring{accessible_name});
            return;
        }

        if (weather_enabled_ && weather_snapshot_
            && !weather_snapshot_->weather.empty()) {
            const auto& weather = weather_snapshot_->weather.front();
            PeekTitle().Text(from_utf8(weather.location_name));
            std::wstring detail;
            append(detail, from_utf8(
                zisla::core::WeatherParser::condition_summary(
                    weather.weather_code)));
            detail.append(L" · ");
            append(detail, weather_temperature(weather.temperature));
            PeekDetail().Text(hstring{detail});
            PeekProgressRing().IsActive(false);
            PeekProgressRing().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekPlaybackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
            PeekFallbackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
            PeekFallbackIcon().Glyph(weather_glyph(weather.weather_code));
            std::wstring accessible_name = L"天气，";
            append(accessible_name, from_utf8(weather.location_name));
            accessible_name.append(L"，");
            accessible_name.append(detail);
            Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
                PeekLayout(),
                hstring{accessible_name});
            return;
        }

        PeekTitle().Text(L"Zisla");
        PeekDetail().Text(L"暂无进行中的活动");
        PeekProgressRing().IsActive(false);
        PeekProgressRing().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        PeekPlaybackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        PeekArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        PeekFallbackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
        PeekFallbackIcon().Glyph(L"\uE945");
        Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
            PeekLayout(),
            L"Zisla 状态预览，暂无进行中的活动");
        return;
    }

    PeekArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
    PeekFallbackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
    PeekFallbackIcon().Glyph(L"\uE945");
    PeekPlaybackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
    const auto& primary = ai_tasks_.front();
    std::wstring title;
    if (ai_tasks_.size() == 1) {
        append(title, from_utf8(primary.title));
    } else {
        title = std::to_wstring(ai_tasks_.size());
        title.append(L" 个 AI 任务");
    }

    std::wstring detail;
    if (ai_tasks_.size() > 1) {
        append(detail, from_utf8(primary.title));
        detail.append(L" · ");
    }
    append(detail, status_text(primary.status));
    const auto metadata = task_metadata(primary);
    if (!metadata.empty()) {
        detail.append(L" · ");
        append(detail, metadata);
    }

    PeekTitle().Text(hstring{title});
    PeekDetail().Text(hstring{detail});
    const bool progress = visible_ && !interactive_
        && shows_progress(primary.status);
    PeekProgressRing().IsActive(progress);
    PeekProgressRing().Visibility(progress
        ? Microsoft::UI::Xaml::Visibility::Visible
        : Microsoft::UI::Xaml::Visibility::Collapsed);

    auto accessible_name = title;
    accessible_name.append(L"，");
    accessible_name.append(detail);
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        PeekLayout(),
        hstring{accessible_name});
}

void OverlayContent::updateVoiceInputView() {
    using Microsoft::UI::Xaml::Visibility;
    using zisla::core::VoiceInputPhase;

    const bool enabled = voice_input_enabled_;
    VoiceInputButton().Visibility(enabled
        ? Visibility::Visible
        : Visibility::Collapsed);
    if (!enabled) {
        VoiceInputStatusBar().Visibility(Visibility::Collapsed);
        VoiceInputProgressRing().IsActive(false);
        return;
    }

    const auto phase = voice_input_.phase;
    const bool visible = phase != VoiceInputPhase::idle;
    const bool pending = phase == VoiceInputPhase::requesting_speech_permission
        || phase == VoiceInputPhase::requesting_microphone_permission
        || phase == VoiceInputPhase::starting
        || phase == VoiceInputPhase::finalizing;
    const bool listening = phase == VoiceInputPhase::listening;
    const bool failed = phase == VoiceInputPhase::failed;

    VoiceInputStatusBar().Visibility(visible
        ? Visibility::Visible
        : Visibility::Collapsed);
    const auto status = voice_status_text(voice_input_);
    VoiceInputStatusText().Text(status);
    std::wstring status_name{L"语音输入，"};
    append(status_name, status);
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        VoiceInputStatusBar(),
        hstring{status_name});
    VoiceInputStatusIcon().Glyph(failed ? L"\uE7BA" : L"\uE720");
    VoiceInputProgressRing().IsActive(pending);
    VoiceInputProgressRing().Visibility(pending
        ? Visibility::Visible
        : Visibility::Collapsed);
    VoiceInputIcon().Glyph(listening ? L"\uE71A" : L"\uE720");
    const auto label = listening
        ? hstring{L"结束语音输入"}
        : pending && phase != VoiceInputPhase::finalizing
            ? hstring{L"取消语音输入"}
            : hstring{L"开始语音输入"};
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        VoiceInputButton(),
        label);
    Microsoft::UI::Xaml::Controls::ToolTipService::SetToolTip(
        VoiceInputButton(),
        box_value(label));
}

void OverlayContent::updateAIView() {
    if (selected_module_ != L"ai") {
        AITaskScroll().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        return;
    }

    AITaskRows().Children().Clear();
    if (ai_tasks_.empty()) {
        AITaskScroll().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        ModuleState().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
        ModuleStateText().Text(L"暂无进行中的 AI 任务");
        ModuleStateIcon().Glyph(L"\uE73E");
        return;
    }

    ModuleState().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
    AITaskScroll().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
    for (const auto& task : ai_tasks_) {
        Microsoft::UI::Xaml::Controls::StackPanel text;
        text.Spacing(2);

        std::wstring heading;
        append(heading, from_utf8(task.title));
        heading.append(L" · ");
        append(heading, status_text(task.status));

        Microsoft::UI::Xaml::Controls::TextBlock title;
        title.Text(hstring{heading});
        title.FontSize(13);
        title.TextWrapping(Microsoft::UI::Xaml::TextWrapping::Wrap);
        text.Children().Append(title);

        const auto metadata = task_metadata(task);
        if (!metadata.empty()) {
            Microsoft::UI::Xaml::Controls::TextBlock detail;
            detail.Text(metadata);
            detail.FontSize(11);
            detail.Opacity(0.68);
            detail.TextTrimming(Microsoft::UI::Xaml::TextTrimming::CharacterEllipsis);
            text.Children().Append(detail);
        }

        Microsoft::UI::Xaml::Controls::Border row;
        row.Padding(Microsoft::UI::Xaml::Thickness{0, 7, 0, 7});
        row.Child(text);
        Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
            row,
            hstring{heading});
        AITaskRows().Children().Append(row);
    }
}

void OverlayContent::updateMediaView() {
    if (!now_playing_) {
        return;
    }

    const auto& snapshot = *now_playing_;
    MediaTitle().Text(from_utf8(snapshot.title));
    MediaArtist().Text(from_utf8(snapshot.artist));
    MediaSource().Text(from_utf8(snapshot.source_application));

    const auto duration = snapshot.duration_seconds
        && std::isfinite(*snapshot.duration_seconds)
        && *snapshot.duration_seconds > 0
        ? *snapshot.duration_seconds
        : 0.0;
    const auto elapsed = snapshot.elapsedAt(now_unix_milliseconds()).value_or(0.0);
    updating_media_progress_ = true;
    MediaProgress().Maximum(duration > 0 ? duration : 1.0);
    MediaProgress().Value(std::clamp(elapsed, 0.0, MediaProgress().Maximum()));
    updating_media_progress_ = false;
    MediaElapsed().Text(duration_text(elapsed));
    MediaDuration().Text(duration_text(duration));
    MediaProgress().IsEnabled(snapshot.controls.can_seek && duration > 0);
    MediaPreviousButton().IsEnabled(snapshot.controls.can_previous);
    MediaNextButton().IsEnabled(snapshot.controls.can_next);
    MediaPlayPauseButton().IsEnabled(snapshot.controls.can_toggle_play_pause);

    const bool playing = snapshot.playback_status
        == zisla::core::MediaPlaybackStatus::playing;
    const auto play_pause_label = playing ? L"暂停" : L"播放";
    MediaPlayPauseIcon().Glyph(playing ? L"\uE769" : L"\uE768");
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        MediaPlayPauseButton(),
        play_pause_label);
    Microsoft::UI::Xaml::Controls::ToolTipService::SetToolTip(
        MediaPlayPauseButton(),
        box_value(play_pause_label));

    std::wstring accessible_name;
    append(accessible_name, from_utf8(snapshot.title));
    if (!snapshot.artist.empty()) {
        accessible_name.append(L"，");
        append(accessible_name, from_utf8(snapshot.artist));
    }
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        MediaView(),
        hstring{accessible_name});
}

void OverlayContent::updateDashboardView() {
    const auto visible = Microsoft::UI::Xaml::Visibility::Visible;
    const auto collapsed = Microsoft::UI::Xaml::Visibility::Collapsed;
    if (selected_module_ != L"dashboard") {
        DashboardScroll().Visibility(collapsed);
        DashboardFocusButton().Visibility(collapsed);
        DashboardFocusDivider().Visibility(collapsed);
        DashboardWeatherButton().Visibility(collapsed);
        DashboardWeatherDivider().Visibility(collapsed);
        DashboardAIButton().Visibility(collapsed);
        DashboardDivider().Visibility(collapsed);
        DashboardDownloadButton().Visibility(collapsed);
        DashboardDownloadDivider().Visibility(collapsed);
        DashboardBrowserDownloadButton().Visibility(collapsed);
        DashboardBrowserDownloadDivider().Visibility(collapsed);
        MediaView().Visibility(collapsed);
        return;
    }

    zisla::core::DashboardAvailability availability;
    availability.focus_countdown_active = pomodoro_.active();
    availability.ai_activity_active = !ai_tasks_.empty();
    availability.native_download_active = download_snapshot_
        && download_snapshot_->active();
    availability.browser_download_count = browser_download_snapshot_
        ? browser_download_snapshot_->summary.total_active_count
        : 0;
    availability.media_active = static_cast<bool>(now_playing_);
    const auto items = zisla::core::DashboardPresentation::items(availability);
    const auto includes = [&items](zisla::core::DashboardItemKind kind) {
        return std::any_of(items.begin(), items.end(), [kind](const auto& item) {
            return item.kind == kind;
        });
    };
    const bool has_focus = includes(zisla::core::DashboardItemKind::focus_countdown);
    const bool has_ai = includes(zisla::core::DashboardItemKind::ai_activity);
    const bool has_download = includes(
        zisla::core::DashboardItemKind::native_download);
    const bool has_browser_download = includes(
        zisla::core::DashboardItemKind::browser_download);
    const bool has_media = includes(zisla::core::DashboardItemKind::media);
    const bool has_weather = weather_enabled_ && weather_snapshot_
        && !weather_snapshot_->weather.empty();
    const bool has_any = !items.empty() || has_weather;

    DashboardScroll().Visibility(has_any ? visible : collapsed);
    DashboardFocusButton().Visibility(has_focus ? visible : collapsed);
    DashboardFocusDivider().Visibility(
        has_focus && (has_weather || has_ai || has_download
            || has_browser_download || has_media)
            ? visible
            : collapsed);
    DashboardWeatherButton().Visibility(has_weather ? visible : collapsed);
    DashboardWeatherDivider().Visibility(
        has_weather && (has_ai || has_download || has_browser_download || has_media)
            ? visible
            : collapsed);
    DashboardAIButton().Visibility(has_ai ? visible : collapsed);
    DashboardDivider().Visibility(
        has_ai && (has_download || has_browser_download || has_media)
            ? visible
            : collapsed);
    DashboardDownloadButton().Visibility(has_download ? visible : collapsed);
    DashboardDownloadDivider().Visibility(
        has_download && (has_browser_download || has_media)
            ? visible
            : collapsed);
    DashboardBrowserDownloadButton().Visibility(
        has_browser_download ? visible : collapsed);
    DashboardBrowserDownloadDivider().Visibility(
        has_browser_download && has_media ? visible : collapsed);
    MediaView().Visibility(has_media ? visible : collapsed);
    AITaskScroll().Visibility(collapsed);
    ModuleState().Visibility(has_any ? collapsed : visible);
    if (!has_any) {
        ModuleStateText().Text(L"暂无进行中的活动");
        ModuleStateIcon().Glyph(L"\uE73E");
        return;
    }

    if (has_focus) {
        const bool running = pomodoro_.phase == zisla::core::PomodoroPhase::running;
        DashboardFocusTitle().Text(
            pomodoro_.mode == zisla::core::PomodoroMode::focus
                ? L"专注倒计时"
                : L"休息倒计时");
        DashboardFocusStatus().Text(running ? L"进行中" : L"已暂停");
        DashboardFocusClock().Text(from_utf8(
            zisla::core::PomodoroEngine::format_clock(
                pomodoro_.remaining_seconds)));
        std::wstring accessible_name = DashboardFocusTitle().Text().c_str();
        accessible_name.append(L"，");
        append(accessible_name, DashboardFocusClock().Text());
        accessible_name.append(L"，");
        append(accessible_name, DashboardFocusStatus().Text());
        Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
            DashboardFocusButton(),
            hstring{accessible_name});
    }

    if (has_weather) {
        const auto& weather = weather_snapshot_->weather.front();
        DashboardWeatherTitle().Text(from_utf8(weather.location_name));
        std::wstring status;
        append(status, from_utf8(
            zisla::core::WeatherParser::condition_summary(weather.weather_code)));
        status.append(L" · 体感 ");
        append(status, weather_temperature(weather.apparent_temperature));
        DashboardWeatherStatus().Text(hstring{status});
        DashboardWeatherTemperature().Text(weather_temperature(weather.temperature));
        std::wstring accessible_name = L"天气，";
        append(accessible_name, from_utf8(weather.location_name));
        accessible_name.append(L"，");
        accessible_name.append(status);
        Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
            DashboardWeatherButton(),
            hstring{accessible_name});
    }

    if (has_download && download_snapshot_) {
        DashboardDownloadTitle().Text(download_snapshot_->request.mode
                == zisla::core::DownloadMode::video
            ? L"视频下载"
            : L"音频下载");
        const bool downloading = download_snapshot_->phase
            == zisla::core::DownloadPhase::downloading;
        const bool indeterminate = download_snapshot_->phase
                == zisla::core::DownloadPhase::preparing
            || download_snapshot_->phase == zisla::core::DownloadPhase::cancelling;
        DashboardDownloadProgress().IsIndeterminate(indeterminate);
        DashboardDownloadProgress().Value(
            std::clamp(download_snapshot_->fraction, 0.0, 1.0));
        if (download_snapshot_->phase == zisla::core::DownloadPhase::preparing) {
            DashboardDownloadStatus().Text(L"正在准备下载");
        } else if (download_snapshot_->phase
            == zisla::core::DownloadPhase::cancelling) {
            DashboardDownloadStatus().Text(L"正在取消");
        } else {
            std::wstring status;
            append(status, from_utf8(download_snapshot_->speed));
            if (!download_snapshot_->eta.empty()) {
                if (!status.empty()) {
                    status.append(L" · ");
                }
                status.append(L"ETA ");
                append(status, from_utf8(download_snapshot_->eta));
            }
            DashboardDownloadStatus().Text(hstring{status});
        }
        if (downloading) {
            const auto percent = static_cast<long long>(std::llround(
                std::clamp(download_snapshot_->fraction, 0.0, 1.0) * 100.0));
            DashboardDownloadPercent().Text(
                hstring{std::to_wstring(percent) + L"%"});
        } else {
            DashboardDownloadPercent().Text(hstring{});
        }
        std::wstring accessible_name = DashboardDownloadTitle().Text().c_str();
        accessible_name.append(L"，");
        append(accessible_name, DashboardDownloadStatus().Text());
        Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
            DashboardDownloadButton(),
            hstring{accessible_name});
    }

    if (has_browser_download && browser_download_snapshot_) {
        const auto& summary = browser_download_snapshot_->summary;
        DashboardBrowserDownloadTitle().Text(L"浏览器下载");
        std::wstring status = std::to_wstring(summary.total_active_count);
        status.append(L" 个进行中");
        if (summary.combined_progress) {
            status.append(L" · 平均 ");
            const auto percent = static_cast<long long>(std::llround(
                std::clamp(*summary.combined_progress, 0.0, 1.0)
                    * 100.0));
            status.append(std::to_wstring(percent));
            status.push_back(L'%');
        }
        DashboardBrowserDownloadStatus().Text(hstring{status});
        DashboardBrowserDownloadProgress().IsIndeterminate(
            !summary.combined_progress.has_value());
        DashboardBrowserDownloadProgress().Value(
            summary.combined_progress.value_or(0.0));
        DashboardBrowserDownloadPercent().Text(summary.combined_progress
            ? hstring{std::to_wstring(static_cast<long long>(std::llround(
                std::clamp(*summary.combined_progress, 0.0, 1.0) * 100.0)))
                + L"%"}
            : hstring{});
        std::wstring accessible_name = L"浏览器下载，";
        accessible_name.append(status);
        Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
            DashboardBrowserDownloadButton(),
            hstring{accessible_name});
    }

    if (!has_ai) {
        return;
    }
    const auto& primary = ai_tasks_.front();
    DashboardAITitle().Text(from_utf8(primary.title));

    std::wstring detail;
    append(detail, status_text(primary.status));
    const auto metadata = task_metadata(primary);
    if (!metadata.empty()) {
        detail.append(L" · ");
        append(detail, metadata);
    }
    DashboardAIStatus().Text(hstring{detail});
    DashboardAICount().Text(ai_tasks_.size() > 1
        ? hstring{std::to_wstring(ai_tasks_.size()) + L" 个任务"}
        : hstring{});

    const bool determinate_progress = primary.progress
        && std::isfinite(*primary.progress);
    const bool indeterminate_progress = !determinate_progress
        && shows_progress(primary.status);
    DashboardAIProgress().IsIndeterminate(indeterminate_progress);
    DashboardAIProgress().Visibility(
        determinate_progress || indeterminate_progress ? visible : collapsed);
    if (determinate_progress) {
        DashboardAIProgress().Value(std::clamp(*primary.progress, 0.0, 1.0));
    }

    std::wstring accessible_name = L"AI 工作，";
    append(accessible_name, from_utf8(primary.title));
    accessible_name.append(L"，");
    accessible_name.append(detail);
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        DashboardAIButton(),
        hstring{accessible_name});
}

void OverlayContent::selectNavigationModule(hstring const& tag) {
    for (const auto& value : ModuleNavigation().MenuItems()) {
        const auto item = value.try_as<
            Microsoft::UI::Xaml::Controls::NavigationViewItem>();
        if (item && unbox_value_or<hstring>(item.Tag(), hstring{}) == tag) {
            ModuleNavigation().SelectedItem(item);
            return;
        }
    }
}

void OverlayContent::updateShelfView() {
    using namespace Microsoft::UI::Xaml;

    const bool selected = selected_module_ == L"shelf";
    ShelfView().Visibility(selected ? Visibility::Visible : Visibility::Collapsed);
    if (!selected) {
        return;
    }

    ModuleState().Visibility(Visibility::Collapsed);
    DashboardScroll().Visibility(Visibility::Collapsed);
    AITaskScroll().Visibility(Visibility::Collapsed);
    ShelfRows().Children().Clear();
    for (const auto& item : shelf_items_) {
        ShelfRows().Children().Append(makeShelfRow(item));
    }

    ShelfCount().Text(hstring{
        std::to_wstring(shelf_items_.size())
        + L"/"
        + std::to_wstring(shelf_capacity_)});
    const bool empty = shelf_items_.empty();
    ShelfEmptyState().Visibility(empty ? Visibility::Visible : Visibility::Collapsed);
    ShelfScroll().Visibility(empty ? Visibility::Collapsed : Visibility::Visible);
    ShelfCopyAllButton().IsEnabled(!empty);
    ShelfShareButton().IsEnabled(!empty);
    ShelfClearButton().IsEnabled(!empty);

    std::wstring accessible_name = L"文件中转站，";
    accessible_name.append(std::to_wstring(shelf_items_.size()));
    accessible_name.append(L" 个项目");
    Automation::AutomationProperties::SetName(
        ShelfView(),
        hstring{accessible_name});
}

Microsoft::UI::Xaml::Controls::Grid OverlayContent::makeShelfRow(
    const zisla::core::FileShelfItem& item) {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    Grid row;
    row.Height(58);
    row.Padding(Thickness{4, 5, 2, 5});

    ColumnDefinition icon_column;
    icon_column.Width(GridLength{34, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(icon_column);
    ColumnDefinition text_column;
    text_column.Width(GridLength{1, GridUnitType::Star});
    row.ColumnDefinitions().Append(text_column);
    for (int index = 0; index < 4; ++index) {
        ColumnDefinition action_column;
        action_column.Width(GridLength{30, GridUnitType::Pixel});
        row.ColumnDefinitions().Append(action_column);
    }

    FontIcon file_icon;
    file_icon.Glyph(L"\uE8A5");
    file_icon.FontSize(17);
    file_icon.HorizontalAlignment(HorizontalAlignment::Left);
    file_icon.VerticalAlignment(VerticalAlignment::Center);
    row.Children().Append(file_icon);

    StackPanel text;
    text.Spacing(1);
    text.VerticalAlignment(VerticalAlignment::Center);
    Grid::SetColumn(text, 1);

    TextBlock name;
    const auto filename = item.path.filename().wstring();
    name.Text(filename.empty() ? hstring{item.path.c_str()} : hstring{filename});
    name.FontSize(12);
    name.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    name.MaxLines(1);
    name.TextTrimming(TextTrimming::CharacterEllipsis);
    text.Children().Append(name);

    TextBlock parent;
    parent.Text(hstring{item.path.parent_path().c_str()});
    parent.FontSize(10);
    parent.Opacity(0.62);
    parent.MaxLines(1);
    parent.TextTrimming(TextTrimming::CharacterEllipsis);
    text.Children().Append(parent);
    row.Children().Append(text);

    const auto path = item.path;
    row.CanDrag(true);
    row.DragStarting([path](
        Windows::Foundation::IInspectable const&,
        DragStartingEventArgs const& args) {
        prepare_shelf_drag(path, args);
    });
    const auto append_action = [&row, &path](
        int column,
        wchar_t const* glyph,
        wchar_t const* label,
        auto action) {
        Button button;
        button.Width(28);
        button.Height(28);
        button.Padding(Thickness{});
        button.VerticalAlignment(VerticalAlignment::Center);
        Grid::SetColumn(button, column);
        FontIcon icon;
        icon.Glyph(glyph);
        icon.FontSize(12);
        button.Content(icon);
        Automation::AutomationProperties::SetName(button, label);
        ToolTipService::SetToolTip(button, box_value(label));
        button.Click([path, action](
            Windows::Foundation::IInspectable const&,
            RoutedEventArgs const&) {
            action(path);
        });
        row.Children().Append(button);
    };

    append_action(2, L"\uE8E5", L"打开", [](const auto& path) {
        AppHost::instance().openShelfPath(path);
    });
    append_action(3, L"\uE838", L"在资源管理器中显示", [](const auto& path) {
        AppHost::instance().revealShelfPath(path);
    });
    append_action(4, L"\uE8C8", L"复制", [](const auto& path) {
        AppHost::instance().copyShelfPath(path);
    });
    append_action(5, L"\uE8BB", L"移除", [](const auto& path) {
        AppHost::instance().removeShelfPath(path);
    });

    Automation::AutomationProperties::SetName(row, hstring{item.path.c_str()});
    return row;
}

void OverlayContent::updateClipboardView() {
    using namespace Microsoft::UI::Xaml;

    const bool selected = selected_module_ == L"clipboard";
    ClipboardView().Visibility(selected ? Visibility::Visible : Visibility::Collapsed);
    if (!selected) {
        return;
    }

    ModuleState().Visibility(Visibility::Collapsed);
    DashboardScroll().Visibility(Visibility::Collapsed);
    AITaskScroll().Visibility(Visibility::Collapsed);
    ShelfView().Visibility(Visibility::Collapsed);
    DownloadView().Visibility(Visibility::Collapsed);

    const auto checked = [](bool value) {
        return box_value(value).as<Windows::Foundation::IReference<bool>>();
    };
    ClipboardAllFilter().IsChecked(checked(
        clipboard_filter_ == zisla::core::ClipboardHistoryFilter::all));
    ClipboardPinnedFilter().IsChecked(checked(
        clipboard_filter_ == zisla::core::ClipboardHistoryFilter::pinned));
    ClipboardHistoryFilterButton().IsChecked(checked(
        clipboard_filter_ == zisla::core::ClipboardHistoryFilter::history));

    const auto query = to_string(ClipboardSearch().Text());
    const auto snapshot = clipboard_items_;
    const auto generation = ++clipboard_generation_;
    ClipboardList().Items().Clear();
    std::size_t matched = 0;
    for (const auto& item : *snapshot) {
        if (!zisla::core::clipboard_history_matches(item, clipboard_filter_, query)) {
            continue;
        }
        ClipboardList().Items().Append(
            makeClipboardRow(item, snapshot, generation));
        ++matched;
    }

    ClipboardCount().Text(hstring{
        std::to_wstring(matched)
        + L" 项 · 历史上限 "
        + std::to_wstring(clipboard_capacity_)});
    ClipboardClearButton().IsEnabled(!snapshot->empty());
    ClipboardEmptyState().Visibility(
        matched == 0 ? Visibility::Visible : Visibility::Collapsed);
    ClipboardList().Visibility(
        matched == 0 ? Visibility::Collapsed : Visibility::Visible);

    if (matched == 0) {
        if (!query.empty()) {
            ClipboardEmptyStateText().Text(L"没有匹配项");
        } else if (clipboard_filter_ == zisla::core::ClipboardHistoryFilter::pinned) {
            ClipboardEmptyStateText().Text(L"暂无常用项");
        } else if (clipboard_filter_ == zisla::core::ClipboardHistoryFilter::history
            && !AppHost::instance().isClipboardHistoryEnabled()) {
            ClipboardEmptyStateText().Text(L"剪贴板历史已关闭");
        } else {
            ClipboardEmptyStateText().Text(L"暂无剪贴板项目");
        }
    }

    Automation::AutomationProperties::SetName(
        ClipboardView(),
        hstring{L"剪贴板历史，" + std::to_wstring(matched) + L" 项"});
}

Microsoft::UI::Xaml::Controls::Grid OverlayContent::makeClipboardRow(
    const zisla::core::ClipboardHistoryItem& item,
    std::shared_ptr<const std::vector<zisla::core::ClipboardHistoryItem>> snapshot,
    std::uint64_t generation) {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    Grid row;
    row.MinHeight(62);
    row.Padding(Thickness{4, 5, 2, 5});

    ColumnDefinition preview_column;
    preview_column.Width(GridLength{50, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(preview_column);
    ColumnDefinition text_column;
    text_column.Width(GridLength{1, GridUnitType::Star});
    row.ColumnDefinitions().Append(text_column);
    for (int index = 0; index < 3; ++index) {
        ColumnDefinition action_column;
        action_column.Width(GridLength{30, GridUnitType::Pixel});
        row.ColumnDefinitions().Append(action_column);
    }

    Grid preview;
    preview.Width(42);
    preview.Height(42);
    preview.HorizontalAlignment(HorizontalAlignment::Left);
    preview.VerticalAlignment(VerticalAlignment::Center);

    hstring title_text;
    hstring detail_text;
    switch (item.content.kind) {
    case zisla::core::ClipboardContentKind::text: {
        FontIcon icon;
        icon.Glyph(L"\uE8D2");
        icon.FontSize(19);
        preview.Children().Append(icon);
        title_text = from_utf8(item.content.text);
        detail_text = L"文字";
        break;
    }
    case zisla::core::ClipboardContentKind::image: {
        Image thumbnail;
        thumbnail.Width(42);
        thumbnail.Height(42);
        thumbnail.Stretch(Microsoft::UI::Xaml::Media::Stretch::UniformToFill);
        const auto weak_self = get_weak();
        const weak_ref<Image> weak_image{thumbnail};
        const auto id = item.id;
        thumbnail.Loaded([
            weak_self,
            weak_image,
            snapshot,
            id,
            generation](
                Windows::Foundation::IInspectable const&,
                RoutedEventArgs const&) {
            const auto self = weak_self.get();
            const auto image = weak_image.get();
            if (self && image && !image.Source()) {
                self->loadClipboardImage(image, snapshot, id, generation);
            }
        });
        preview.Children().Append(thumbnail);
        title_text = L"图片";
        detail_text = image_size_text(item.content.image.size());
        break;
    }
    case zisla::core::ClipboardContentKind::file: {
        FontIcon icon;
        icon.Glyph(L"\uE8A5");
        icon.FontSize(19);
        preview.Children().Append(icon);
        if (!item.content.file_display_name.empty()) {
            title_text = from_utf8(item.content.file_display_name);
        } else {
            const auto name = item.content.file_path.filename().wstring();
            title_text = name.empty()
                ? hstring{item.content.file_path.c_str()}
                : hstring{name};
        }
        detail_text = hstring{item.content.file_path.parent_path().c_str()};
        break;
    }
    }
    row.Children().Append(preview);

    StackPanel text;
    text.Spacing(1);
    text.VerticalAlignment(VerticalAlignment::Center);
    Grid::SetColumn(text, 1);
    TextBlock title;
    title.Text(title_text);
    title.FontSize(12);
    title.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    title.MaxLines(item.content.kind == zisla::core::ClipboardContentKind::text ? 2 : 1);
    title.TextTrimming(TextTrimming::CharacterEllipsis);
    title.TextWrapping(TextWrapping::Wrap);
    text.Children().Append(title);
    TextBlock detail;
    detail.Text(detail_text);
    detail.FontSize(10);
    detail.Opacity(0.62);
    detail.MaxLines(1);
    detail.TextTrimming(TextTrimming::CharacterEllipsis);
    text.Children().Append(detail);
    row.Children().Append(text);

    const auto append_action = [&row](
        int column,
        wchar_t const* glyph,
        wchar_t const* label,
        auto action) {
        Button button;
        button.Width(28);
        button.Height(28);
        button.Padding(Thickness{});
        button.VerticalAlignment(VerticalAlignment::Center);
        Grid::SetColumn(button, column);
        FontIcon icon;
        icon.Glyph(glyph);
        icon.FontSize(12);
        button.Content(icon);
        Automation::AutomationProperties::SetName(button, label);
        ToolTipService::SetToolTip(button, box_value(label));
        button.Click([action = std::move(action)](
            Windows::Foundation::IInspectable const&,
            RoutedEventArgs const&) {
            action();
        });
        row.Children().Append(button);
    };

    const auto id = item.id;
    append_action(2, L"\uE8C8", L"复制", [id] {
        AppHost::instance().copyClipboardItem(id);
    });
    const bool pinned = item.pinned;
    append_action(
        3,
        pinned ? L"\uE77A" : L"\uE840",
        pinned ? L"取消常用" : L"设为常用",
        [id, pinned] {
            AppHost::instance().setClipboardItemPinned(id, !pinned);
        });
    append_action(4, L"\uE74D", L"删除", [id] {
        AppHost::instance().removeClipboardItem(id);
    });

    Automation::AutomationProperties::SetName(row, title_text);
    return row;
}

void OverlayContent::updateQuickNotesView() {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    const bool selected = selected_module_ == L"notes";
    NotesView().Visibility(selected ? Visibility::Visible : Visibility::Collapsed);
    if (!selected) {
        return;
    }

    ModuleState().Visibility(Visibility::Collapsed);
    DashboardScroll().Visibility(Visibility::Collapsed);
    AITaskScroll().Visibility(Visibility::Collapsed);
    ShelfView().Visibility(Visibility::Collapsed);
    ClipboardView().Visibility(Visibility::Collapsed);
    DownloadView().Visibility(Visibility::Collapsed);
    WeatherView().Visibility(Visibility::Collapsed);
    ToolboxView().Visibility(Visibility::Collapsed);

    const auto snapshot = quick_notes_snapshot_;
    const auto exists = [&snapshot](std::int64_t id) {
        return std::any_of(snapshot->notes.begin(), snapshot->notes.end(), [id](const auto& note) {
            return note.id == id;
        });
    };
    if (selected_quick_note_id_ && !exists(*selected_quick_note_id_)) {
        selected_quick_note_id_.reset();
        displayed_quick_note_id_.reset();
    }
    if (!selected_quick_note_id_ && !snapshot->notes.empty()) {
        selected_quick_note_id_ = snapshot->notes.front().id;
    }

    const auto query = to_string(NotesSearch().Text());
    updating_quick_notes_ = true;
    NotesList().Items().Clear();
    Windows::Foundation::IInspectable selected_item{nullptr};
    std::size_t matched = 0;
    for (const auto& note : snapshot->notes) {
        if (!zisla::core::quick_note_matches(note, query)) {
            continue;
        }
        auto row = makeQuickNoteRow(note);
        if (selected_quick_note_id_ && note.id == *selected_quick_note_id_) {
            selected_item = row;
        }
        NotesList().Items().Append(row);
        ++matched;
    }
    NotesList().SelectedItem(selected_item);
    updating_quick_notes_ = false;

    const bool list_empty = matched == 0;
    NotesListEmptyState().Visibility(
        list_empty ? Visibility::Visible : Visibility::Collapsed);
    NotesList().Visibility(list_empty ? Visibility::Collapsed : Visibility::Visible);
    if (list_empty) {
        NotesListEmptyText().Text(query.empty() ? L"暂无随记" : L"没有匹配项");
    }

    const bool has_selection = selected_quick_note_id_.has_value();
    NotesModeSelector().IsEnabled(has_selection);
    NotesEditor().IsEnabled(has_selection && !quick_note_preview_);
    NotesEditor().Visibility(
        has_selection && !quick_note_preview_ ? Visibility::Visible : Visibility::Collapsed);
    NotesPreviewScroll().Visibility(
        has_selection && quick_note_preview_ ? Visibility::Visible : Visibility::Collapsed);
    NotesEditorEmptyState().Visibility(
        has_selection ? Visibility::Collapsed : Visibility::Visible);
    NotesDeleteButton().IsEnabled(has_selection);
    loadQuickNoteEditor(force_quick_note_reload_);
    force_quick_note_reload_ = false;

    const auto editor_text = has_selection ? to_string(NotesEditor().Text()) : std::string{};
    if (has_selection && quick_note_preview_) {
        renderQuickNotePreview(editor_text);
    } else {
        NotesPreview().Blocks().Clear();
    }
    const bool has_content = !blank_text(editor_text);
    NotesCopyButton().IsEnabled(has_content);
    NotesTeleprompterButton().IsEnabled(has_content);

    if (!snapshot->error.empty()) {
        NotesStatusText().Text(from_utf8(snapshot->error));
    } else if (snapshot->loading) {
        NotesStatusText().Text(L"正在加载");
    } else if (quick_note_dirty_) {
        NotesStatusText().Text(L"未保存");
    } else {
        std::wstring status = std::to_wstring(matched);
        if (matched != snapshot->notes.size()) {
            status.append(L"/");
            status.append(std::to_wstring(snapshot->notes.size()));
        }
        status.append(L" 条");
        NotesStatusText().Text(hstring{status});
    }

    Automation::AutomationProperties::SetName(
        NotesView(),
        hstring{L"随记，" + std::to_wstring(snapshot->notes.size()) + L" 条"});
}

Microsoft::UI::Xaml::Controls::Grid OverlayContent::makeQuickNoteRow(
    const zisla::core::QuickNote& note) {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    Grid row;
    row.MinHeight(50);
    row.Padding(Thickness{6, 5, 4, 5});
    row.Tag(box_value(note.id));

    StackPanel content;
    content.Spacing(2);
    content.VerticalAlignment(VerticalAlignment::Center);

    TextBlock title;
    title.Text(from_utf8(note.title));
    title.FontSize(11);
    title.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    title.MaxLines(1);
    title.TextTrimming(TextTrimming::CharacterEllipsis);
    content.Children().Append(title);

    TextBlock modified;
    modified.Text(quick_note_time(note.modified_at_unix_ms));
    modified.FontSize(9);
    modified.Opacity(0.62);
    content.Children().Append(modified);
    row.Children().Append(content);

    std::wstring accessible_name = title.Text().c_str();
    accessible_name.append(L"，");
    append(accessible_name, modified.Text());
    Automation::AutomationProperties::SetName(row, hstring{accessible_name});
    return row;
}

void OverlayContent::loadQuickNoteEditor(bool force) {
    if (!selected_quick_note_id_) {
        quick_note_save_timer_.Stop();
        quick_note_dirty_ = false;
        displayed_quick_note_id_.reset();
        updating_quick_note_editor_ = true;
        NotesEditor().Text(L"");
        updating_quick_note_editor_ = false;
        return;
    }
    if (!force && displayed_quick_note_id_ == selected_quick_note_id_) {
        return;
    }
    const auto found = std::find_if(
        quick_notes_snapshot_->notes.begin(),
        quick_notes_snapshot_->notes.end(),
        [this](const auto& note) { return note.id == *selected_quick_note_id_; });
    if (found == quick_notes_snapshot_->notes.end()) {
        return;
    }

    quick_note_save_timer_.Stop();
    quick_note_dirty_ = false;
    updating_quick_note_editor_ = true;
    NotesEditor().Text(from_utf8(found->markdown));
    updating_quick_note_editor_ = false;
    displayed_quick_note_id_ = found->id;
}

void OverlayContent::renderQuickNotePreview(std::string_view markdown) {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Documents;

    const auto blocks = zisla::core::quick_note_markdown_blocks(markdown);
    auto preview = NotesPreview();
    preview.Blocks().Clear();
    for (const auto& block : blocks) {
        Paragraph paragraph;
        paragraph.Margin(Thickness{0, 0, 0, 8});
        paragraph.FontSize(14);

        switch (block.kind) {
        case zisla::core::QuickNoteMarkdownBlockKind::heading: {
            const auto level = std::clamp<int>(block.heading_level, 1, 6);
            paragraph.FontSize(26 - level * 2);
            paragraph.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
            break;
        }
        case zisla::core::QuickNoteMarkdownBlockKind::quote:
            paragraph.FontStyle(Windows::UI::Text::FontStyle::Italic);
            paragraph.TextIndent(12);
            break;
        case zisla::core::QuickNoteMarkdownBlockKind::unordered_list_item: {
            Run prefix;
            prefix.Text(L"\u2022 ");
            paragraph.Inlines().Append(prefix);
            break;
        }
        case zisla::core::QuickNoteMarkdownBlockKind::ordered_list_item: {
            Run prefix;
            prefix.Text(
                hstring{std::to_wstring(block.list_ordinal == 0 ? 1 : block.list_ordinal)
                        + L". "});
            paragraph.Inlines().Append(prefix);
            break;
        }
        case zisla::core::QuickNoteMarkdownBlockKind::thematic_break: {
            Run line;
            line.Text(L"--------------------");
            paragraph.Inlines().Append(line);
            preview.Blocks().Append(paragraph);
            continue;
        }
        case zisla::core::QuickNoteMarkdownBlockKind::code_block: {
            Run code;
            code.FontFamily(Microsoft::UI::Xaml::Media::FontFamily(L"Cascadia Mono"));
            code.Text(from_utf8(block.code));
            paragraph.Inlines().Append(code);
            preview.Blocks().Append(paragraph);
            continue;
        }
        case zisla::core::QuickNoteMarkdownBlockKind::paragraph:
            break;
        }

        for (const auto& inline_item : block.inlines) {
            append_quick_note_preview_inline(paragraph, inline_item);
        }
        preview.Blocks().Append(paragraph);
    }
}

void OverlayContent::flushQuickNoteSave() {
    if (!quick_note_dirty_ || !selected_quick_note_id_) {
        return;
    }
    quick_note_dirty_ = false;
    NotesStatusText().Text(L"正在保存");
    AppHost::instance().updateQuickNote(
        *selected_quick_note_id_,
        to_string(NotesEditor().Text()));
}

void OverlayContent::updatePDFToolsView() {
    using namespace Microsoft::UI::Xaml;

    const bool selected = selected_module_ == L"pdf";
    PDFToolsView().Visibility(selected ? Visibility::Visible : Visibility::Collapsed);
    if (!selected) {
        return;
    }

    ModuleState().Visibility(Visibility::Collapsed);
    DashboardScroll().Visibility(Visibility::Collapsed);
    AITaskScroll().Visibility(Visibility::Collapsed);
    ShelfView().Visibility(Visibility::Collapsed);
    ClipboardView().Visibility(Visibility::Collapsed);
    DownloadView().Visibility(Visibility::Collapsed);
    NotesView().Visibility(Visibility::Collapsed);
    AgendaView().Visibility(Visibility::Collapsed);
    WeatherView().Visibility(Visibility::Collapsed);
    ToolboxView().Visibility(Visibility::Collapsed);
    SystemView().Visibility(Visibility::Collapsed);
}

void OverlayContent::updateAIAgentSkillsView() {
    using namespace Microsoft::UI::Xaml;

    const bool selected = selected_module_ == L"agent";
    AIAgentView().Visibility(selected ? Visibility::Visible : Visibility::Collapsed);
    if (!selected) {
        return;
    }

    ModuleState().Visibility(Visibility::Collapsed);
    DashboardScroll().Visibility(Visibility::Collapsed);
    AITaskScroll().Visibility(Visibility::Collapsed);
    ShelfView().Visibility(Visibility::Collapsed);
    ClipboardView().Visibility(Visibility::Collapsed);
    DownloadView().Visibility(Visibility::Collapsed);
    NotesView().Visibility(Visibility::Collapsed);
    PDFToolsView().Visibility(Visibility::Collapsed);
    AgendaView().Visibility(Visibility::Collapsed);
    WeatherView().Visibility(Visibility::Collapsed);
    ToolboxView().Visibility(Visibility::Collapsed);
    SystemView().Visibility(Visibility::Collapsed);
}

void OverlayContent::updateDownloadView() {
    using namespace Microsoft::UI::Xaml;

    const bool selected = selected_module_ == L"download";
    DownloadView().Visibility(selected ? Visibility::Visible : Visibility::Collapsed);
    if (!selected) {
        return;
    }

    ModuleState().Visibility(Visibility::Collapsed);
    DashboardScroll().Visibility(Visibility::Collapsed);
    AITaskScroll().Visibility(Visibility::Collapsed);
    ShelfView().Visibility(Visibility::Collapsed);
    ClipboardView().Visibility(Visibility::Collapsed);
    WeatherView().Visibility(Visibility::Collapsed);
    ToolboxView().Visibility(Visibility::Collapsed);
    NotesView().Visibility(Visibility::Collapsed);
    SystemView().Visibility(Visibility::Collapsed);

    const auto snapshot = download_snapshot_
        ? download_snapshot_
        : std::make_shared<const zisla::core::DownloadSnapshot>();
    const bool active = snapshot->active();
    DownloadUrlBox().IsEnabled(!active);
    DownloadVideoMode().IsEnabled(!active);
    DownloadAudioMode().IsEnabled(!active);
    DownloadFolderButton().IsEnabled(!active);
    DownloadStartButton().Visibility(active ? Visibility::Collapsed : Visibility::Visible);
    DownloadCancelButton().Visibility(active ? Visibility::Visible : Visibility::Collapsed);
    DownloadCancelButton().IsEnabled(
        snapshot->phase != zisla::core::DownloadPhase::cancelling);
    DownloadStartButton().IsEnabled(
        !active
        && !blank_text(to_string(DownloadUrlBox().Text()))
        && !download_output_directory_.empty());

    if (!download_output_directory_.empty()) {
        const auto filename = download_output_directory_.filename();
        DownloadFolderName().Text(hstring{
            (filename.empty() ? download_output_directory_ : filename).c_str()});
    } else {
        DownloadFolderName().Text(L"选择文件夹");
    }

    DownloadProgress().Visibility(active ? Visibility::Visible : Visibility::Collapsed);
    DownloadProgress().IsIndeterminate(
        snapshot->phase == zisla::core::DownloadPhase::preparing
        || snapshot->phase == zisla::core::DownloadPhase::cancelling);
    DownloadProgress().Value(std::clamp(snapshot->fraction, 0.0, 1.0));
    DownloadRevealButton().Visibility(
        snapshot->phase == zisla::core::DownloadPhase::completed
            && snapshot->completed_file
        ? Visibility::Visible
        : Visibility::Collapsed);

    hstring status = L"准备就绪";
    hstring detail;
    hstring glyph = L"\uE896";
    switch (snapshot->phase) {
    case zisla::core::DownloadPhase::idle:
        detail = detected_clipboard_link_.empty()
            ? L"支持视频与音频下载"
            : L"已从剪贴板填入链接";
        break;
    case zisla::core::DownloadPhase::preparing:
        status = L"正在准备下载";
        detail = L"正在检查链接和输出目录";
        break;
    case zisla::core::DownloadPhase::downloading: {
        const auto tenths = static_cast<long long>(std::llround(
            std::clamp(snapshot->fraction, 0.0, 1.0) * 1'000.0));
        status = hstring{
            std::to_wstring(tenths / 10) + L"."
            + std::to_wstring(tenths % 10) + L"%"};
        std::wstring metadata;
        append(metadata, from_utf8(snapshot->speed));
        if (!snapshot->eta.empty()) {
            if (!metadata.empty()) {
                metadata.append(L"  ");
            }
            metadata.append(L"ETA ");
            append(metadata, from_utf8(snapshot->eta));
        }
        detail = hstring{metadata};
        break;
    }
    case zisla::core::DownloadPhase::cancelling:
        status = L"正在取消";
        detail = L"正在停止下载进程";
        glyph = L"\uE71A";
        break;
    case zisla::core::DownloadPhase::completed:
        status = L"下载完成";
        glyph = L"\uE73E";
        if (snapshot->completed_file) {
            detail = hstring{snapshot->completed_file->filename().c_str()};
        }
        break;
    case zisla::core::DownloadPhase::failed:
        status = L"下载失败";
        detail = from_utf8(snapshot->error);
        glyph = L"\uE7BA";
        break;
    case zisla::core::DownloadPhase::cancelled:
        status = L"已取消";
        detail = L"未保留未完成的临时文件";
        glyph = L"\uE711";
        break;
    }
    DownloadStatusText().Text(status);
    DownloadDetailText().Text(detail);
    DownloadStatusIcon().Glyph(glyph);

    std::wstring accessible_name = L"下载，";
    append(accessible_name, status);
    if (!detail.empty()) {
        accessible_name.append(L"，");
        append(accessible_name, detail);
    }
    Automation::AutomationProperties::SetName(
        DownloadView(),
        hstring{accessible_name});
}

void OverlayContent::updateWeatherView() {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    const bool selected = selected_module_ == L"agenda";
    WeatherView().Visibility(selected ? Visibility::Visible : Visibility::Collapsed);
    if (!selected) {
        return;
    }

    ModuleState().Visibility(Visibility::Collapsed);
    DashboardScroll().Visibility(Visibility::Collapsed);
    AITaskScroll().Visibility(Visibility::Collapsed);
    ShelfView().Visibility(Visibility::Collapsed);
    ClipboardView().Visibility(Visibility::Collapsed);
    DownloadView().Visibility(Visibility::Collapsed);
    ToolboxView().Visibility(Visibility::Collapsed);

    const bool loading = weather_enabled_
        && (weather_loading_
            || (weather_snapshot_
                && weather_snapshot_->phase == WeatherServicePhase::loading));
    WeatherProgress().IsActive(loading);
    WeatherProgress().Visibility(loading ? Visibility::Visible : Visibility::Collapsed);
    WeatherSearch().IsEnabled(weather_enabled_ && !loading);

    hstring status = L"等待刷新";
    if (!weather_enabled_) {
        status = L"天气已关闭";
    } else if (!weather_status_override_.empty()) {
        status = from_utf8(weather_status_override_);
    } else if (weather_snapshot_ && !weather_snapshot_->message.empty()) {
        status = from_utf8(weather_snapshot_->message);
    }
    WeatherStatusText().Text(status);

    WeatherRows().Children().Clear();
    if (weather_snapshot_) {
        for (const auto& weather : weather_snapshot_->weather) {
            WeatherRows().Children().Append(makeWeatherRow(weather));
        }
    }
    const bool empty = !weather_snapshot_ || weather_snapshot_->weather.empty();
    WeatherEmptyState().Visibility(empty ? Visibility::Visible : Visibility::Collapsed);
    WeatherScroll().Visibility(empty ? Visibility::Collapsed : Visibility::Visible);
    if (empty) {
        WeatherEmptyStateText().Text(status);
    }

    std::wstring accessible_name = L"天气，";
    accessible_name.append(status.c_str(), status.size());
    Automation::AutomationProperties::SetName(
        WeatherView(),
        hstring{accessible_name});
}

void OverlayContent::updateSystemMonitorActivity() noexcept {
    AppHost::instance().setSystemMonitorActive(
        visible_ && interactive_ && selected_module_ == L"system");
}

void OverlayContent::updateSystemMonitorView() {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    const bool selected = selected_module_ == L"system";
    if (!selected) {
        SystemView().Visibility(Visibility::Collapsed);
        return;
    }

    const auto snapshot = system_monitor_snapshot_;
    const bool has_sample = snapshot
        && snapshot->metrics.sampled_at_unix_ms > 0;
    if (!has_sample) {
        SystemView().Visibility(Visibility::Collapsed);
        ModuleState().Visibility(Visibility::Visible);
        ModuleStateIcon().Glyph(L"\uE9D9");
        ModuleStateText().Text(
            snapshot && !snapshot->error.empty()
                ? from_utf8(snapshot->error)
                : hstring{L"正在读取系统快照"});
        return;
    }

    SystemView().Visibility(Visibility::Visible);
    ModuleState().Visibility(Visibility::Collapsed);
    const auto& metrics = snapshot->metrics;

    const bool has_cpu = metrics.cpu.has_value()
        || !metrics.hardware.cpu_name.empty()
        || metrics.hardware.logical_processor_count > 0;
    const bool has_gpu = metrics.gpu.has_value()
        || !metrics.hardware.gpu_name.empty();
    SystemCPUSection().Visibility(has_cpu ? Visibility::Visible : Visibility::Collapsed);
    SystemGPUSection().Visibility(has_gpu ? Visibility::Visible : Visibility::Collapsed);
    Grid::SetColumnSpan(SystemCPUSection(), has_gpu ? 1 : 2);
    if (has_cpu) {
        std::wstring cpu_name = metrics.hardware.cpu_name.empty()
            ? std::wstring{}
            : std::wstring{from_utf8(metrics.hardware.cpu_name).c_str()};
        if (metrics.hardware.logical_processor_count > 0) {
            if (!cpu_name.empty()) {
                cpu_name.append(L" · ");
            }
            cpu_name.append(std::to_wstring(metrics.hardware.logical_processor_count));
            cpu_name.append(L" 逻辑处理器");
        }
        SystemCPUName().Text(hstring{cpu_name});
        SystemCPUName().Visibility(
            cpu_name.empty() ? Visibility::Collapsed : Visibility::Visible);
    }
    SystemCPUUsage().Visibility(
        metrics.cpu ? Visibility::Visible : Visibility::Collapsed);
    SystemCPUProgress().Visibility(
        metrics.cpu ? Visibility::Visible : Visibility::Collapsed);
    SystemCPUHistoryCanvas().Visibility(
        metrics.cpu ? Visibility::Visible : Visibility::Collapsed);
    SystemCPUDetail().Visibility(
        metrics.cpu ? Visibility::Visible : Visibility::Collapsed);
    const auto cpu_usage = metrics.cpu ? metrics.cpu->usage : 0.0;
    SystemCPUUsage().Text(metrics.cpu ? system_percent(cpu_usage) : hstring{});
    SystemCPUProgress().IsIndeterminate(false);
    SystemCPUProgress().Value(cpu_usage);
    if (metrics.cpu) {
        SystemCPUUserDetail().Text(hstring{
            L"用户 " + std::wstring{system_percent(metrics.cpu->user_fraction).c_str()}});
        SystemCPUSystemDetail().Text(hstring{
            L"系统 " + std::wstring{system_percent(metrics.cpu->system_fraction).c_str()}});
        SystemCPUIdleDetail().Text(hstring{
            L"闲置 " + std::wstring{system_percent(metrics.cpu->idle_fraction).c_str()}});
    }
    update_fraction_history(
        SystemCPUUserHistoryLine(),
        SystemCPUHistoryCanvas(),
        snapshot->history.cpu_user());
    update_fraction_history(
        SystemCPUSystemHistoryLine(),
        SystemCPUHistoryCanvas(),
        snapshot->history.cpu_system());
    update_fraction_history(
        SystemCPUIdleHistoryLine(),
        SystemCPUHistoryCanvas(),
        snapshot->history.cpu_idle());

    SystemGPUName().Text(from_utf8(metrics.hardware.gpu_name));
    SystemGPUName().Visibility(metrics.hardware.gpu_name.empty()
        ? Visibility::Collapsed
        : Visibility::Visible);
    const auto gpu_usage = metrics.gpu ? metrics.gpu->usage_fraction : 0.0;
    SystemGPUUsage().Text(metrics.gpu ? system_percent(gpu_usage) : hstring{});
    SystemGPUUsage().Visibility(
        metrics.gpu ? Visibility::Visible : Visibility::Collapsed);
    SystemGPUProgress().IsIndeterminate(false);
    SystemGPUProgress().Value(gpu_usage);
    SystemGPUProgress().Visibility(
        metrics.gpu ? Visibility::Visible : Visibility::Collapsed);
    SystemGPUHistoryCanvas().Visibility(
        metrics.gpu ? Visibility::Visible : Visibility::Collapsed);
    SystemGPUDetail().Text(metrics.gpu
        ? hstring{L"GPU Engine 实时利用率"}
        : hstring{});
    SystemGPUDetail().Visibility(
        metrics.gpu ? Visibility::Visible : Visibility::Collapsed);
    update_fraction_history(
        SystemGPUHistoryLine(),
        SystemGPUHistoryCanvas(),
        snapshot->history.gpu_usage());

    SystemMemorySection().Visibility(
        metrics.memory.available ? Visibility::Visible : Visibility::Collapsed);
    SystemMemoryUsage().Text(metrics.memory.available
        ? system_percent(metrics.memory.usage_fraction)
        : hstring{});
    SystemMemoryProgress().Value(
        metrics.memory.available ? metrics.memory.usage_fraction : 0.0);
    std::wstring memory_detail;
    if (metrics.memory.available) {
        append(memory_detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
            metrics.memory.used_bytes)));
        memory_detail.append(L" / ");
        append(memory_detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
            metrics.memory.total_bytes)));
        memory_detail.append(L" · 可用 ");
        append(memory_detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
            metrics.memory.available_bytes)));
    }
    SystemMemoryDetail().Text(hstring{memory_detail});

    const auto desktop_tools = desktop_tools_snapshot_;
    const bool desktop_busy = desktop_tools && desktop_tools->busy;
    const bool releasing_memory = desktop_busy
        && desktop_tools->active_action
            == zisla::core::DesktopToolAction::release_system_memory;
    SystemMemoryTrimButton().IsEnabled(!desktop_busy);
    SystemMemoryTrimProgress().IsActive(releasing_memory);
    SystemMemoryTrimProgress().Visibility(
        releasing_memory ? Visibility::Visible : Visibility::Collapsed);
    hstring trim_status;
    if (desktop_tools
        && desktop_tools->last_action
            == zisla::core::DesktopToolAction::release_system_memory) {
        trim_status = !desktop_tools->error.empty()
            ? from_utf8(desktop_tools->error)
            : from_utf8(desktop_tools->status);
    }
    SystemMemoryTrimStatusText().Text(trim_status);
    SystemMemoryTrimStatusText().Visibility(
        trim_status.empty() ? Visibility::Collapsed : Visibility::Visible);

    auto disks = metrics.disks;
    if (disks.empty() && metrics.disk.available) {
        disks.push_back(metrics.disk);
    }
    const bool has_disks = !disks.empty();
    SystemDiskSection().Visibility(
        has_disks ? Visibility::Visible : Visibility::Collapsed);
    SystemResourceSeparator().Visibility(
        (has_cpu || has_gpu) && (metrics.memory.available || has_disks)
            ? Visibility::Visible
            : Visibility::Collapsed);
    SystemDiskUsage().Text(metrics.disk.available
        ? system_percent(metrics.disk.usage_fraction)
        : hstring{});
    std::wstring disk_detail;
    if (metrics.disk.available) {
        disk_detail.append(std::to_wstring(disks.size()));
        disk_detail.append(L" 个分区 · 已用 ");
        append(disk_detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
            metrics.disk.used_bytes)));
        disk_detail.append(L" / ");
        append(disk_detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
            metrics.disk.total_bytes)));
        disk_detail.append(L" · 可用 ");
        append(disk_detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
            metrics.disk.free_bytes)));
        if (metrics.disk.read_bytes_per_second) {
            disk_detail.append(L" · 读 ");
            append(disk_detail, from_utf8(zisla::core::SystemMonitorFormat::rate(
                *metrics.disk.read_bytes_per_second)));
        }
        if (metrics.disk.write_bytes_per_second) {
            disk_detail.append(L" · 写 ");
            append(disk_detail, from_utf8(zisla::core::SystemMonitorFormat::rate(
                *metrics.disk.write_bytes_per_second)));
        }
    }
    SystemDiskDetail().Text(hstring{disk_detail});
    const auto disk_key = [](const zisla::core::DiskMetrics& disk) {
        std::wstring key = from_utf8(disk.volume_path).c_str();
        key.push_back(L'\x1f');
        key.append(from_utf8(disk.volume_name).c_str());
        return key;
    };
    const auto disk_label = [](const zisla::core::DiskMetrics& disk) {
        std::wstring label;
        if (!disk.volume_path.empty()) {
            label = from_utf8(disk.volume_path).c_str();
            while (!label.empty()
                && (label.back() == L'\\' || label.back() == L'/')) {
                label.pop_back();
            }
        }
        if (!disk.volume_name.empty()) {
            if (!label.empty()) {
                label.append(L" · ");
            }
            append(label, from_utf8(disk.volume_name));
        }
        return label.empty() ? std::wstring{L"本地磁盘"} : label;
    };
    const auto disk_detail_text = [](const zisla::core::DiskMetrics& disk) {
        std::wstring detail = L"已用 ";
        append(detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
            disk.used_bytes)));
        detail.append(L" / ");
        append(detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
            disk.total_bytes)));
        detail.append(L" · 可用 ");
        append(detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
            disk.free_bytes)));
        return detail;
    };

    std::vector<std::wstring> disk_keys;
    disk_keys.reserve(disks.size());
    for (const auto& disk : disks) {
        disk_keys.push_back(disk_key(disk));
    }
    auto volume_children = SystemDiskVolumes().Children();
    const bool rebuild_disk_volumes = system_disk_volume_keys_ != disk_keys
        || volume_children.Size() != static_cast<std::uint32_t>(disks.size());
    if (rebuild_disk_volumes) {
        volume_children.Clear();
        system_disk_volume_keys_ = disk_keys;
        for (std::size_t index = 0; index < disks.size(); ++index) {
            StackPanel volume;
            volume.Spacing(3);

            Grid header;
            ColumnDefinition label_column;
            label_column.Width(GridLength{1, GridUnitType::Star});
            header.ColumnDefinitions().Append(label_column);
            ColumnDefinition usage_column;
            usage_column.Width(GridLength{1, GridUnitType::Auto});
            header.ColumnDefinitions().Append(usage_column);

            TextBlock name;
            name.FontSize(10);
            name.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
            name.MaxLines(1);
            name.TextTrimming(TextTrimming::CharacterEllipsis);
            header.Children().Append(name);

            TextBlock usage;
            usage.FontFamily(Microsoft::UI::Xaml::Media::FontFamily{L"Consolas"});
            usage.FontSize(10);
            Grid::SetColumn(usage, 1);
            header.Children().Append(usage);
            volume.Children().Append(header);

            ProgressBar progress;
            progress.Height(3);
            progress.Maximum(1);
            volume.Children().Append(progress);

            TextBlock detail;
            detail.FontSize(9);
            detail.Foreground(Microsoft::UI::Xaml::Application::Current()
                .Resources().Lookup(box_value(L"OverlaySecondaryTextBrush"))
                .as<Microsoft::UI::Xaml::Media::Brush>());
            volume.Children().Append(detail);
            volume_children.Append(volume);
        }
    }
    for (std::size_t index = 0; index < disks.size(); ++index) {
        const auto& disk = disks[index];
        const auto volume = volume_children.GetAt(static_cast<std::uint32_t>(index))
            .as<StackPanel>();
        const auto header = volume.Children().GetAt(0).as<Grid>();
        header.Children().GetAt(0).as<TextBlock>().Text(hstring{disk_label(disk)});
        header.Children().GetAt(1).as<TextBlock>().Text(
            system_percent(disk.usage_fraction));
        volume.Children().GetAt(1).as<ProgressBar>().Value(disk.usage_fraction);
        volume.Children().GetAt(2).as<TextBlock>().Text(
            hstring{disk_detail_text(disk)});
    }

    const bool has_network_traffic = metrics.network.available;
    const bool has_network_addresses = !metrics.network.private_ip_address.empty()
        || !metrics.network.public_ip_address.empty();
    SystemNetworkSection().Visibility(
        has_network_traffic || has_network_addresses
            ? Visibility::Visible
            : Visibility::Collapsed);
    SystemNetworkTraffic().Visibility(
        has_network_traffic ? Visibility::Visible : Visibility::Collapsed);
    SystemNetworkAddresses().Visibility(
        has_network_addresses ? Visibility::Visible : Visibility::Collapsed);
    SystemNetworkDownload().Text(metrics.network.available
        ? hstring{L"下载 "
            + std::wstring{from_utf8(zisla::core::SystemMonitorFormat::rate(
                metrics.network.receive_bytes_per_second)).c_str()}}
        : hstring{});
    SystemNetworkUpload().Text(metrics.network.available
        ? hstring{L"上传 "
            + std::wstring{from_utf8(zisla::core::SystemMonitorFormat::rate(
                metrics.network.send_bytes_per_second)).c_str()}}
        : hstring{});
    SystemPrivateIP().Text(metrics.network.private_ip_address.empty()
        ? hstring{}
        : hstring{L"内网 IP "
            + std::wstring{from_utf8(metrics.network.private_ip_address).c_str()}});
    SystemPrivateIP().Visibility(metrics.network.private_ip_address.empty()
        ? Visibility::Collapsed
        : Visibility::Visible);
    SystemPublicIP().Text(metrics.network.public_ip_address.empty()
        ? hstring{}
        : hstring{L"公网 IP "
            + std::wstring{from_utf8(metrics.network.public_ip_address).c_str()}});
    SystemPublicIP().Visibility(metrics.network.public_ip_address.empty()
        ? Visibility::Collapsed
        : Visibility::Visible);

    const bool has_battery = metrics.battery && metrics.battery->present;
    const bool has_uptime = metrics.uptime_seconds > 0;
    SystemPowerPanel().Visibility(
        has_battery || has_uptime ? Visibility::Visible : Visibility::Collapsed);
    SystemBattery().Visibility(has_battery ? Visibility::Visible : Visibility::Collapsed);
    SystemUptime().Visibility(has_uptime ? Visibility::Visible : Visibility::Collapsed);
    Grid::SetColumn(SystemUptime(), has_battery ? 1 : 0);
    Grid::SetColumnSpan(SystemUptime(), has_battery ? 1 : 2);
    std::wstring battery;
    if (has_battery) {
        battery = L"电池 ";
        battery.append(metrics.battery->percent
            ? std::to_wstring(static_cast<unsigned>(*metrics.battery->percent))
                + L"%"
            : std::wstring{});
        if (metrics.battery->charging) {
            battery.append(L" · 正在充电");
        } else if (metrics.battery->power_source == zisla::core::PowerSource::ac) {
            battery.append(L" · 交流电源");
        } else if (metrics.battery->power_source
            == zisla::core::PowerSource::battery) {
            battery.append(L" · 电池供电");
        }
        if (metrics.battery->battery_saver) {
            battery.append(L" · 节电模式");
        }
    }
    SystemBattery().Text(hstring{battery});
    SystemUptime().Text(has_uptime
        ? hstring{L"运行时间 "
            + std::wstring{from_utf8(zisla::core::SystemMonitorFormat::uptime(
                metrics.uptime_seconds)).c_str()}}
        : hstring{});

    std::wstring sensor_status;
    if (metrics.cpu_temperature.celsius) {
        sensor_status.append(L"温度 ");
        sensor_status.append(std::to_wstring(
            static_cast<int>(std::lround(*metrics.cpu_temperature.celsius))));
        sensor_status.append(L" °C");
    }
    if (!metrics.fan.rpm.empty()) {
        if (!sensor_status.empty()) {
            sensor_status.append(L" · ");
        }
        sensor_status.append(L"风扇 ");
        for (std::size_t index = 0; index < metrics.fan.rpm.size(); ++index) {
            if (index > 0) {
                sensor_status.append(L" / ");
            }
            sensor_status.append(std::to_wstring(
                static_cast<int>(std::lround(metrics.fan.rpm[index]))));
            sensor_status.append(L" RPM");
        }
    }
    SystemSensorStatus().Text(hstring{sensor_status});
    SystemSensorStatus().Visibility(sensor_status.empty()
        ? Visibility::Collapsed
        : Visibility::Visible);

    std::wstring accessible_name = L"系统监控";
    if (metrics.cpu) {
        accessible_name.append(L"，CPU ");
        append(accessible_name, SystemCPUUsage().Text());
    }
    if (metrics.memory.available) {
        accessible_name.append(L"，内存 ");
        append(accessible_name, SystemMemoryUsage().Text());
    }
    if (metrics.network.available) {
        accessible_name.append(L"，下载 ");
        append(accessible_name, from_utf8(zisla::core::SystemMonitorFormat::rate(
            metrics.network.receive_bytes_per_second)));
    }
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        SystemView(),
        hstring{accessible_name});
}

void OverlayContent::updateDiskCleanupView() {
    using namespace Microsoft::UI::Xaml;

    const auto previously_selected = selectedDiskCleanupPaths();
    DiskCleanupRows().Children().Clear();

    const auto snapshot = disk_cleanup_snapshot_;
    const bool busy = snapshot && (snapshot->scanning || snapshot->cleaning);
    DiskCleanupScanButton().IsEnabled(!busy);
    DiskCleanupProgress().Visibility(
        busy ? Visibility::Visible : Visibility::Collapsed);

    if (snapshot) {
        for (const auto& candidate : snapshot->candidates) {
            const bool selected = std::find(
                previously_selected.begin(),
                previously_selected.end(),
                candidate.path) != previously_selected.end();
            auto row = makeDiskCleanupRow(candidate, selected);
            row.IsEnabled(!busy);
            DiskCleanupRows().Children().Append(row);
        }
    }

    const bool empty = !snapshot || snapshot->candidates.empty();
    const bool has_scan_result = snapshot && snapshot->revision > 0;
    DiskCleanupInlineContent().Visibility(
        busy || has_scan_result ? Visibility::Visible : Visibility::Collapsed);
    DiskCleanupEmptyText().Visibility(
        has_scan_result && empty && !busy ? Visibility::Visible : Visibility::Collapsed);
    DiskCleanupScroll().Visibility(
        empty ? Visibility::Collapsed : Visibility::Visible);
    if (has_scan_result && empty && !busy) {
        DiskCleanupEmptyText().Text(L"没有可清理项目");
    }

    hstring status;
    if (snapshot) {
        status = !snapshot->error.empty()
            ? from_utf8(snapshot->error)
            : from_utf8(snapshot->status);
    }
    DiskCleanupStatusText().Text(status);
    DiskCleanupStatusText().Visibility(
        status.empty() ? Visibility::Collapsed : Visibility::Visible);
    updateDiskCleanupSelection();
}

Microsoft::UI::Xaml::Controls::CheckBox OverlayContent::makeDiskCleanupRow(
    const zisla::core::DiskCleanupCandidate& candidate,
    bool selected) {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    CheckBox checkbox;
    checkbox.HorizontalAlignment(HorizontalAlignment::Stretch);
    checkbox.HorizontalContentAlignment(HorizontalAlignment::Stretch);
    checkbox.Padding(Thickness{0, 4, 0, 4});
    checkbox.Tag(box_value(hstring{candidate.path.wstring()}));
    checkbox.IsChecked(box_value(selected).as<Windows::Foundation::IReference<bool>>());

    Grid content;
    ColumnDefinition detail_column;
    detail_column.Width(GridLength{1, GridUnitType::Star});
    content.ColumnDefinitions().Append(detail_column);
    ColumnDefinition size_column;
    size_column.Width(GridLength{1, GridUnitType::Auto});
    content.ColumnDefinitions().Append(size_column);

    StackPanel detail;
    detail.Spacing(1);
    TextBlock title;
    const auto filename = candidate.path.filename().wstring();
    title.Text(filename.empty() ? hstring{candidate.path.wstring()} : hstring{filename});
    title.FontSize(10);
    title.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    title.MaxLines(1);
    title.TextTrimming(TextTrimming::CharacterEllipsis);
    detail.Children().Append(title);

    TextBlock path;
    std::wstring path_text;
    append(path_text, disk_cleanup_kind_text(candidate.kind));
    const auto parent = candidate.path.parent_path().wstring();
    if (!parent.empty()) {
        path_text.append(L" · ");
        path_text.append(parent);
    }
    path.Text(hstring{path_text});
    path.FontSize(9);
    path.Opacity(0.64);
    path.MaxLines(1);
    path.TextTrimming(TextTrimming::CharacterEllipsis);
    detail.Children().Append(path);
    content.Children().Append(detail);

    TextBlock size;
    size.Text(from_utf8(zisla::core::SystemMonitorFormat::bytes(
        candidate.size_bytes)));
    size.FontFamily(Microsoft::UI::Xaml::Media::FontFamily{L"Consolas"});
    size.FontSize(9);
    size.Opacity(0.64);
    size.VerticalAlignment(VerticalAlignment::Center);
    Grid::SetColumn(size, 1);
    content.Children().Append(size);
    checkbox.Content(content);

    std::wstring accessible_name;
    append(accessible_name, disk_cleanup_kind_text(candidate.kind));
    accessible_name.append(L"，");
    accessible_name.append(candidate.path.wstring());
    accessible_name.append(L"，");
    append(accessible_name, size.Text());
    Automation::AutomationProperties::SetName(checkbox, hstring{accessible_name});

    const auto weak_self = get_weak();
    const auto selection_changed = [weak_self](
        Windows::Foundation::IInspectable const&,
        RoutedEventArgs const&) {
        if (const auto self = weak_self.get()) {
            self->updateDiskCleanupSelection();
        }
    };
    checkbox.Checked(selection_changed);
    checkbox.Unchecked(selection_changed);
    return checkbox;
}

std::vector<std::filesystem::path> OverlayContent::selectedDiskCleanupPaths() {
    using namespace Microsoft::UI::Xaml::Controls;

    std::vector<std::filesystem::path> result;
    for (const auto& child : DiskCleanupRows().Children()) {
        const auto checkbox = child.try_as<CheckBox>();
        if (!checkbox || !unbox_value_or<bool>(checkbox.IsChecked(), false)) {
            continue;
        }
        const auto path = unbox_value_or<hstring>(checkbox.Tag(), hstring{});
        if (!path.empty()) {
            result.emplace_back(path.c_str());
        }
    }
    return result;
}

void OverlayContent::updateDiskCleanupSelection() {
    using namespace Microsoft::UI::Xaml;

    const auto selected = selectedDiskCleanupPaths();
    std::uint64_t selected_bytes = 0;
    if (disk_cleanup_snapshot_) {
        for (const auto& candidate : disk_cleanup_snapshot_->candidates) {
            if (std::find(selected.begin(), selected.end(), candidate.path)
                == selected.end()) {
                continue;
            }
            selected_bytes += std::min(
                candidate.size_bytes,
                std::numeric_limits<std::uint64_t>::max() - selected_bytes);
        }
    }

    if (selected.empty()) {
        DiskCleanupSelectionText().Text(L"未选择项目");
    } else {
        std::wstring summary = L"已选择 ";
        summary.append(std::to_wstring(selected.size()));
        summary.append(L" 项");
        if (selected_bytes > 0) {
            summary.append(L" · ");
            append(summary, from_utf8(zisla::core::SystemMonitorFormat::bytes(
                selected_bytes)));
        }
        DiskCleanupSelectionText().Text(hstring{summary});
    }
    const bool busy = disk_cleanup_snapshot_
        && (disk_cleanup_snapshot_->scanning || disk_cleanup_snapshot_->cleaning);
    DiskCleanupCleanButton().IsEnabled(!selected.empty() && !busy);
}

Microsoft::UI::Xaml::Controls::Grid OverlayContent::makeWeatherRow(
    const zisla::core::WeatherSnapshot& weather) {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    Grid row;
    row.MinHeight(92);
    row.Padding(Thickness{4, 8, 2, 8});

    ColumnDefinition icon_column;
    icon_column.Width(GridLength{34, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(icon_column);
    ColumnDefinition content_column;
    content_column.Width(GridLength{1, GridUnitType::Star});
    row.ColumnDefinitions().Append(content_column);
    ColumnDefinition action_column;
    action_column.Width(GridLength{34, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(action_column);

    FontIcon icon;
    icon.Glyph(weather_glyph(weather.weather_code));
    icon.FontSize(20);
    icon.HorizontalAlignment(HorizontalAlignment::Left);
    icon.VerticalAlignment(VerticalAlignment::Top);
    icon.Margin(Thickness{2, 3, 0, 0});
    row.Children().Append(icon);

    StackPanel content;
    content.Spacing(2);
    Grid::SetColumn(content, 1);

    Grid heading;
    ColumnDefinition name_column;
    name_column.Width(GridLength{1, GridUnitType::Star});
    heading.ColumnDefinitions().Append(name_column);
    ColumnDefinition temperature_column;
    temperature_column.Width(GridLength{1, GridUnitType::Auto});
    heading.ColumnDefinitions().Append(temperature_column);
    TextBlock name;
    name.Text(from_utf8(weather.location_name));
    name.FontSize(12);
    name.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    name.MaxLines(1);
    name.TextTrimming(TextTrimming::CharacterEllipsis);
    heading.Children().Append(name);
    TextBlock temperature;
    temperature.Text(weather_temperature(weather.temperature));
    temperature.FontSize(16);
    temperature.FontWeight(Windows::UI::Text::FontWeights::Bold());
    Grid::SetColumn(temperature, 1);
    heading.Children().Append(temperature);
    content.Children().Append(heading);

    std::wstring condition;
    append(condition, from_utf8(
        zisla::core::WeatherParser::condition_summary(weather.weather_code)));
    condition.append(L" · 体感 ");
    append(condition, weather_temperature(weather.apparent_temperature));
    TextBlock condition_text;
    condition_text.Text(hstring{condition});
    condition_text.FontSize(10);
    condition_text.Opacity(0.68);
    content.Children().Append(condition_text);

    std::wstring metrics = L"日出 ";
    append(metrics, weather_time(weather.sunrise));
    metrics.append(L" · 日落 ");
    append(metrics, weather_time(weather.sunset));
    metrics.append(L" · 降水 ");
    append(metrics, weather_decimal(weather.current_precipitation));
    metrics.append(L" mm · 今日 ");
    metrics.append(std::to_wstring(weather.precipitation_probability));
    metrics.append(L"% / ");
    append(metrics, weather_decimal(weather.precipitation_sum));
    metrics.append(L" mm");
    TextBlock metrics_text;
    metrics_text.Text(hstring{metrics});
    metrics_text.FontSize(9);
    metrics_text.Opacity(0.62);
    metrics_text.TextWrapping(TextWrapping::Wrap);
    content.Children().Append(metrics_text);

    for (const auto& alert : weather.official_alerts) {
        try {
            std::wstring label;
            append(label, alert_severity_text(alert.severity));
            label.append(L" · ");
            append(label, from_utf8(alert.summary));
            HyperlinkButton link;
            link.Padding(Thickness{});
            link.HorizontalAlignment(HorizontalAlignment::Left);
            link.FontSize(9);
            link.Content(box_value(hstring{label}));
            link.NavigateUri(Windows::Foundation::Uri{from_utf8(alert.details_url)});
            Automation::AutomationProperties::SetName(link, hstring{label});
            content.Children().Append(link);
        } catch (...) {
        }
    }
    if (weather.official_alerts.empty() && weather.alert_error) {
        TextBlock alert_error;
        alert_error.Text(L"官方预警不可用");
        alert_error.FontSize(9);
        alert_error.Opacity(0.62);
        ToolTipService::SetToolTip(
            alert_error,
            box_value(from_utf8(*weather.alert_error)));
        content.Children().Append(alert_error);
    }
    row.Children().Append(content);

    const auto location = std::find_if(
        weather_locations_.begin(),
        weather_locations_.end(),
        [&weather](const auto& value) { return value.id == weather.location_id; });
    if (location != weather_locations_.end()
        && location->kind == zisla::core::WeatherLocationKind::saved) {
        Button remove;
        remove.Width(30);
        remove.Height(30);
        remove.Padding(Thickness{});
        remove.VerticalAlignment(VerticalAlignment::Top);
        Grid::SetColumn(remove, 2);
        FontIcon remove_icon;
        remove_icon.Glyph(L"\uE74D");
        remove_icon.FontSize(12);
        remove.Content(remove_icon);
        const auto id = location->id;
        const auto label = L"删除 " + std::wstring(name.Text().c_str());
        Automation::AutomationProperties::SetName(remove, label);
        ToolTipService::SetToolTip(remove, box_value(label));
        remove.Click([id](
            Windows::Foundation::IInspectable const&,
            RoutedEventArgs const&) {
            AppHost::instance().removeWeatherLocation(id);
        });
        row.Children().Append(remove);
    }

    std::wstring accessible_name;
    append(accessible_name, from_utf8(weather.location_name));
    accessible_name.append(L"，");
    accessible_name.append(condition);
    Automation::AutomationProperties::SetName(row, hstring{accessible_name});
    return row;
}

void OverlayContent::updateToolboxView() {
    using namespace Microsoft::UI::Xaml;

    const bool selected = selected_module_ == L"toolbox";
    ToolboxView().Visibility(selected ? Visibility::Visible : Visibility::Collapsed);
    if (!selected) {
        return;
    }

    ModuleState().Visibility(Visibility::Collapsed);
    const bool focus = pomodoro_.mode == zisla::core::PomodoroMode::focus;
    const bool running = pomodoro_.phase == zisla::core::PomodoroPhase::running;
    const bool idle = pomodoro_.phase == zisla::core::PomodoroPhase::idle;
    PomodoroModeText().Text(focus ? L"专注" : L"休息");
    PomodoroClock().Text(from_utf8(zisla::core::PomodoroEngine::format_clock(
        pomodoro_.remaining_seconds)));
    PomodoroPhaseText().Text(running
        ? L"进行中"
        : idle ? L"待开始" : L"已暂停");
    PomodoroStartPauseText().Text(running ? L"暂停" : L"开始");
    PomodoroStartPauseIcon().Glyph(running ? L"\uE769" : L"\uE768");
    PomodoroDurationButton().IsEnabled(idle);
    PomodoroDurationChevron().Visibility(
        idle ? Visibility::Visible : Visibility::Collapsed);
    const auto action = running ? L"暂停番茄钟" : L"开始番茄钟";
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        PomodoroStartPauseButton(),
        action);

    if (idle) {
        const auto duration = focus
            ? pomodoro_.focus_duration_seconds
            : pomodoro_.rest_duration_seconds;
        PomodoroHours().Value(static_cast<double>(duration / 3'600));
        PomodoroMinutes().Value(static_cast<double>((duration / 60) % 60));
        PomodoroSeconds().Value(static_cast<double>(duration % 60));
    }

    const auto checked = [](bool value) {
        return box_value(value).as<Windows::Foundation::IReference<bool>>();
    };
    PowerDisplayToggle().IsChecked(checked(power_requests_.keep_display_awake));
    PowerSystemToggle().IsChecked(checked(
        power_requests_.prevent_idle_system_sleep));
    const bool keyboard_cleaning =
        cleaning_mode_ == zisla::core::CleaningMode::keyboard;
    KeyboardCleaningText().Text(keyboard_cleaning ? L"结束清洁" : L"清理键盘");
    const auto keyboard_action = keyboard_cleaning ? L"结束键盘清洁" : L"清理键盘";
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        KeyboardCleaningButton(),
        keyboard_action);

    const auto desktop_tools = desktop_tools_snapshot_;
    const bool desktop_busy = desktop_tools && desktop_tools->busy;
    DesktopArrangeButton().IsEnabled(!desktop_busy);
    StoreUpdatesButton().IsEnabled(!desktop_busy);
    RecycleBinButton().IsEnabled(!desktop_busy);
    DesktopToolsProgress().IsActive(desktop_busy);
    DesktopToolsProgress().Visibility(
        desktop_busy ? Visibility::Visible : Visibility::Collapsed);

    hstring recycle_detail = L"状态不可用";
    if (desktop_tools && desktop_tools->recycle_bin.available) {
        std::wstring detail = std::to_wstring(
            desktop_tools->recycle_bin.item_count);
        detail.append(L" 项");
        if (desktop_tools->recycle_bin.size_bytes > 0) {
            detail.append(L" · ");
            append(detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
                desktop_tools->recycle_bin.size_bytes)));
        }
        recycle_detail = hstring{detail};
    }
    RecycleBinDetail().Text(recycle_detail);

    hstring desktop_status;
    if (desktop_tools) {
        desktop_status = !desktop_tools->error.empty()
            ? from_utf8(desktop_tools->error)
            : from_utf8(desktop_tools->status);
    }
    DesktopToolsStatusText().Text(desktop_status);
    DesktopToolsStatusText().Visibility(
        desktop_status.empty() ? Visibility::Collapsed : Visibility::Visible);

    std::wstring recycle_accessible_name = L"回收站，";
    append(recycle_accessible_name, recycle_detail);
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        RecycleBinButton(),
        hstring{recycle_accessible_name});
    updateAlarmView();
}

void OverlayContent::updateAlarmView() {
    using namespace Microsoft::UI::Xaml;

    AlarmRows().Children().Clear();
    for (const auto& alarm : alarms_) {
        AlarmRows().Children().Append(makeAlarmRow(alarm));
    }
    const bool empty = alarms_.empty();
    AlarmEmptyText().Visibility(empty ? Visibility::Visible : Visibility::Collapsed);
    AlarmScroll().Visibility(empty ? Visibility::Collapsed : Visibility::Visible);

    if (next_alarm_) {
        std::wstring detail;
        append(detail, from_utf8(
            zisla::core::AlarmBook::format_time(next_alarm_->alarm)));
        if (!next_alarm_->alarm.label.empty()) {
            detail.append(L" · ");
            append(detail, from_utf8(next_alarm_->alarm.label));
        }
        AlarmButtonDetail().Text(hstring{detail});
    } else {
        AlarmButtonDetail().Text(L"暂无已启用闹钟");
    }

    const bool has_error = !alarm_error_.empty();
    AlarmError().Text(has_error ? from_utf8(alarm_error_) : hstring{});
    AlarmError().Visibility(has_error ? Visibility::Visible : Visibility::Collapsed);

    if (!editing_alarm_id_.empty()) {
        const auto existing = std::find_if(
            alarms_.begin(), alarms_.end(), [this](const auto& alarm) {
                return alarm.id == editing_alarm_id_;
            });
        if (existing == alarms_.end()) {
            resetAlarmEditor();
        }
    }
    AlarmSaveText().Text(editing_alarm_id_.empty() ? L"添加" : L"保存");
    AlarmCancelButton().Visibility(
        editing_alarm_id_.empty() ? Visibility::Collapsed : Visibility::Visible);
    AlarmRepeatHint().Text(
        selectedAlarmWeekdays() == 0 ? L"仅响一次" : L"每周重复");

    std::wstring accessible_name = L"闹钟，";
    accessible_name.append(std::to_wstring(alarms_.size()));
    accessible_name.append(L" 项");
    Microsoft::UI::Xaml::Automation::AutomationProperties::SetName(
        AlarmButton(),
        hstring{accessible_name});
}

Microsoft::UI::Xaml::Controls::Grid OverlayContent::makeAlarmRow(
    const zisla::core::AlarmItem& alarm) {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    Grid row;
    row.MinHeight(52);
    row.Padding(Thickness{5, 4, 2, 4});

    ColumnDefinition text_column;
    text_column.Width(GridLength{1, GridUnitType::Star});
    row.ColumnDefinitions().Append(text_column);
    ColumnDefinition toggle_column;
    toggle_column.Width(GridLength{54, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(toggle_column);
    for (int index = 0; index < 2; ++index) {
        ColumnDefinition action_column;
        action_column.Width(GridLength{30, GridUnitType::Pixel});
        row.ColumnDefinitions().Append(action_column);
    }

    StackPanel text;
    text.Spacing(1);
    text.VerticalAlignment(VerticalAlignment::Center);
    TextBlock time;
    time.Text(from_utf8(zisla::core::AlarmBook::format_time(alarm)));
    time.FontFamily(Microsoft::UI::Xaml::Media::FontFamily{L"Consolas"});
    time.FontSize(15);
    time.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    time.Opacity(alarm.enabled ? 1.0 : 0.48);
    text.Children().Append(time);

    std::wstring detail;
    append(detail, from_utf8(
        zisla::core::AlarmBook::format_repeat(alarm.weekday_mask)));
    if (!alarm.label.empty()) {
        detail.append(L" · ");
        append(detail, from_utf8(alarm.label));
    }
    TextBlock description;
    description.Text(hstring{detail});
    description.FontSize(10);
    description.Opacity(0.64);
    description.MaxLines(1);
    description.TextTrimming(TextTrimming::CharacterEllipsis);
    text.Children().Append(description);
    row.Children().Append(text);

    ToggleSwitch enabled;
    enabled.Width(44);
    enabled.MinWidth(0);
    enabled.HorizontalAlignment(HorizontalAlignment::Center);
    enabled.VerticalAlignment(VerticalAlignment::Center);
    enabled.IsOn(alarm.enabled);
    Grid::SetColumn(enabled, 1);
    const auto id = alarm.id;
    enabled.Toggled([id](
        Windows::Foundation::IInspectable const& sender,
        RoutedEventArgs const&) {
        if (const auto toggle = sender.try_as<ToggleSwitch>()) {
            AppHost::instance().setAlarmEnabled(id, toggle.IsOn());
        }
    });
    Automation::AutomationProperties::SetName(
        enabled,
        alarm.enabled ? L"停用闹钟" : L"启用闹钟");
    row.Children().Append(enabled);

    Button edit;
    edit.Width(28);
    edit.Height(28);
    edit.Padding(Thickness{});
    edit.VerticalAlignment(VerticalAlignment::Center);
    Grid::SetColumn(edit, 2);
    FontIcon edit_icon;
    edit_icon.Glyph(L"\uE70F");
    edit_icon.FontSize(12);
    edit.Content(edit_icon);
    Automation::AutomationProperties::SetName(edit, L"编辑闹钟");
    ToolTipService::SetToolTip(edit, box_value(L"编辑"));
    const auto weak_self = get_weak();
    edit.Click([weak_self, id](
        Windows::Foundation::IInspectable const&,
        RoutedEventArgs const&) {
        if (const auto self = weak_self.get()) {
            self->beginAlarmEdit(id);
        }
    });
    row.Children().Append(edit);

    Button remove;
    remove.Width(28);
    remove.Height(28);
    remove.Padding(Thickness{});
    remove.VerticalAlignment(VerticalAlignment::Center);
    Grid::SetColumn(remove, 3);
    FontIcon remove_icon;
    remove_icon.Glyph(L"\uE74D");
    remove_icon.FontSize(12);
    remove.Content(remove_icon);
    Automation::AutomationProperties::SetName(remove, L"删除闹钟");
    ToolTipService::SetToolTip(remove, box_value(L"删除"));
    remove.Click([id](
        Windows::Foundation::IInspectable const&,
        RoutedEventArgs const&) {
        AppHost::instance().removeAlarm(id);
    });
    row.Children().Append(remove);

    std::wstring accessible_name;
    append(accessible_name, time.Text());
    accessible_name.append(L"，");
    accessible_name.append(detail);
    Automation::AutomationProperties::SetName(row, hstring{accessible_name});
    return row;
}

void OverlayContent::beginAlarmEdit(std::string_view id) {
    const auto match = std::find_if(
        alarms_.begin(), alarms_.end(), [id](const auto& alarm) {
            return alarm.id == id;
        });
    if (match == alarms_.end()) {
        return;
    }
    editing_alarm_id_ = match->id;
    AlarmHour().Value(match->hour);
    AlarmMinute().Value(match->minute);
    AlarmLabel().Text(from_utf8(match->label));

    const std::array buttons{
        AlarmSunday(), AlarmMonday(), AlarmTuesday(), AlarmWednesday(),
        AlarmThursday(), AlarmFriday(), AlarmSaturday(),
    };
    for (std::uint8_t weekday = 1; weekday <= 7; ++weekday) {
        buttons[weekday - 1].IsChecked(box_value(
            (match->weekday_mask & zisla::core::alarm_weekday_bit(weekday)) != 0)
            .as<Windows::Foundation::IReference<bool>>());
    }
    AlarmSaveText().Text(L"保存");
    AlarmCancelButton().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
    AlarmRepeatHint().Text(
        match->weekday_mask == 0 ? L"仅响一次" : L"每周重复");
}

void OverlayContent::resetAlarmEditor() {
    editing_alarm_id_.clear();
    AlarmLabel().Text(L"");
    const std::array buttons{
        AlarmSunday(), AlarmMonday(), AlarmTuesday(), AlarmWednesday(),
        AlarmThursday(), AlarmFriday(), AlarmSaturday(),
    };
    for (const auto& button : buttons) {
        button.IsChecked(box_value(false).as<
            Windows::Foundation::IReference<bool>>());
    }
    AlarmSaveText().Text(L"添加");
    AlarmCancelButton().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
    AlarmRepeatHint().Text(L"仅响一次");
}

zisla::core::AlarmWeekdayMask OverlayContent::selectedAlarmWeekdays() {
    const std::array buttons{
        AlarmSunday(), AlarmMonday(), AlarmTuesday(), AlarmWednesday(),
        AlarmThursday(), AlarmFriday(), AlarmSaturday(),
    };
    zisla::core::AlarmWeekdayMask result = 0;
    for (std::uint8_t weekday = 1; weekday <= 7; ++weekday) {
        if (unbox_value_or<bool>(buttons[weekday - 1].IsChecked(), false)) {
            result = static_cast<zisla::core::AlarmWeekdayMask>(
                result | zisla::core::alarm_weekday_bit(weekday));
        }
    }
    return result;
}

Windows::Foundation::IAsyncAction OverlayContent::addStorageItemsAsync(
    Windows::ApplicationModel::DataTransfer::DataPackageView const& data) {
    const auto items = co_await data.GetStorageItemsAsync();
    std::vector<std::filesystem::path> paths;
    paths.reserve(items.Size());
    for (const auto& item : items) {
        const auto path = item.Path();
        if (!path.empty()) {
            paths.emplace_back(path.c_str());
        }
    }
    AppHost::instance().addShelfPaths(std::move(paths));
}

void OverlayContent::clearArtwork() {
    const auto empty = Microsoft::UI::Xaml::Media::ImageSource{nullptr};
    PeekArtwork().Source(empty);
    MediaArtwork().Source(empty);
    PeekArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
    MediaArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
    PeekFallbackIcon().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
    MediaArtworkFallback().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
}

winrt::fire_and_forget OverlayContent::loadArtwork(
    zisla::core::MediaArtwork artwork,
    std::uint64_t generation) {
    const auto lifetime = get_strong();
    (void)lifetime;
    try {
        Windows::Storage::Streams::InMemoryRandomAccessStream stream;
        Windows::Storage::Streams::DataWriter writer{stream};
        if (!artwork || artwork->empty()) {
            co_return;
        }
        writer.WriteBytes(*artwork);
        const auto stored = co_await writer.StoreAsync();
        if (stored != artwork->size()) {
            co_return;
        }
        (void)writer.DetachStream();
        stream.Seek(0);

        Microsoft::UI::Xaml::Media::Imaging::BitmapImage image;
        co_await image.SetSourceAsync(stream);
        if (generation != artwork_generation_) {
            co_return;
        }
        PeekArtwork().Source(image);
        MediaArtwork().Source(image);
        MediaArtwork().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
        MediaArtworkFallback().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
        updatePeek();
    } catch (...) {
        if (generation == artwork_generation_) {
            clearArtwork();
            updatePeek();
        }
    }
}

winrt::fire_and_forget OverlayContent::loadClipboardImage(
    Microsoft::UI::Xaml::Controls::Image image,
    std::shared_ptr<const std::vector<zisla::core::ClipboardHistoryItem>> snapshot,
    std::int64_t id,
    std::uint64_t generation) {
    const auto lifetime = get_strong();
    (void)lifetime;
    try {
        if (!snapshot || generation != clipboard_generation_) {
            co_return;
        }
        const auto found = std::find_if(
            snapshot->begin(),
            snapshot->end(),
            [id](const auto& item) { return item.id == id; });
        if (found == snapshot->end()
            || found->content.kind != zisla::core::ClipboardContentKind::image
            || found->content.image.empty()) {
            co_return;
        }

        Windows::Storage::Streams::InMemoryRandomAccessStream stream;
        Windows::Storage::Streams::DataWriter writer{stream};
        writer.WriteBytes(found->content.image);
        const auto stored = co_await writer.StoreAsync();
        if (stored != found->content.image.size()) {
            co_return;
        }
        (void)writer.DetachStream();
        stream.Seek(0);

        Microsoft::UI::Xaml::Media::Imaging::BitmapImage bitmap;
        bitmap.DecodePixelWidth(42);
        co_await bitmap.SetSourceAsync(stream);
        if (generation == clipboard_generation_) {
            image.Source(bitmap);
        }
    } catch (...) {
    }
}

Windows::Foundation::IAsyncAction OverlayContent::showClipboardMessage(
    hstring title,
    hstring message) {
    if (!XamlRoot()) {
        co_return;
    }
    Microsoft::UI::Xaml::Controls::ContentDialog dialog;
    dialog.XamlRoot(XamlRoot());
    dialog.Title(box_value(title));
    dialog.Content(box_value(message));
    dialog.CloseButtonText(L"知道了");
    (void)(co_await dialog.ShowAsync());
}

void OverlayContent::ClipboardFilterButton_Click(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto button = sender.try_as<
        Microsoft::UI::Xaml::Controls::Primitives::ToggleButton>();
    if (!button) {
        return;
    }
    const auto tag = unbox_value_or<hstring>(button.Tag(), L"all");
    if (tag == L"pinned") {
        clipboard_filter_ = zisla::core::ClipboardHistoryFilter::pinned;
    } else if (tag == L"history") {
        clipboard_filter_ = zisla::core::ClipboardHistoryFilter::history;
    } else {
        clipboard_filter_ = zisla::core::ClipboardHistoryFilter::all;
    }
    updateClipboardView();
}

void OverlayContent::ClipboardSearch_TextChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&) {
    updateClipboardView();
}

winrt::fire_and_forget OverlayContent::ClipboardAddText_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    const TransientUIHold hold;
    try {
        if (!XamlRoot()) {
            co_return;
        }
        Microsoft::UI::Xaml::Controls::TextBox editor;
        editor.AcceptsReturn(true);
        editor.MinWidth(360);
        editor.MaxHeight(220);
        editor.PlaceholderText(L"输入要保存的文字");
        editor.TextWrapping(Microsoft::UI::Xaml::TextWrapping::Wrap);

        Microsoft::UI::Xaml::Controls::ContentDialog dialog;
        dialog.XamlRoot(XamlRoot());
        dialog.Title(box_value(L"添加常用文字"));
        dialog.Content(editor);
        dialog.PrimaryButtonText(L"添加");
        dialog.CloseButtonText(L"取消");
        dialog.DefaultButton(Microsoft::UI::Xaml::Controls::ContentDialogButton::Primary);
        const auto result = co_await dialog.ShowAsync();
        if (result == Microsoft::UI::Xaml::Controls::ContentDialogResult::Primary) {
            AppHost::instance().addPinnedClipboardContent(
                zisla::core::ClipboardHistoryContent::make_text(
                    to_string(editor.Text())));
        }
    } catch (...) {
    }
}

winrt::fire_and_forget OverlayContent::ClipboardAddImage_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    const TransientUIHold hold;
    try {
        Windows::Storage::Pickers::FileOpenPicker picker;
        initializePicker(picker);
        picker.SuggestedStartLocation(
            Windows::Storage::Pickers::PickerLocationId::PicturesLibrary);
        for (const auto extension : {
                 L".png", L".jpg", L".jpeg", L".bmp", L".gif", L".webp"}) {
            picker.FileTypeFilter().Append(extension);
        }
        const auto file = co_await picker.PickSingleFileAsync();
        if (!file) {
            co_return;
        }

        const auto limit = AppHost::instance().clipboardImageLimit();
        const auto properties = co_await file.GetBasicPropertiesAsync();
        if (properties.Size() == 0 || properties.Size() > limit) {
            co_await showClipboardMessage(
                L"无法添加图片",
                L"图片必须大于 0 字节且不超过 10 MiB。");
            co_return;
        }
        const auto buffer = co_await Windows::Storage::FileIO::ReadBufferAsync(file);
        if (buffer.Length() == 0 || buffer.Length() > limit) {
            co_await showClipboardMessage(
                L"无法添加图片",
                L"读取后的图片大小不符合限制。");
            co_return;
        }
        std::vector<std::uint8_t> bytes(buffer.Length());
        auto reader = Windows::Storage::Streams::DataReader::FromBuffer(buffer);
        reader.ReadBytes(bytes);
        AppHost::instance().addPinnedClipboardContent(
            zisla::core::ClipboardHistoryContent::make_image(std::move(bytes)));
    } catch (...) {
    }
}

winrt::fire_and_forget OverlayContent::ClipboardAddFile_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    const TransientUIHold hold;
    try {
        Windows::Storage::Pickers::FileOpenPicker picker;
        initializePicker(picker);
        picker.FileTypeFilter().Append(L"*");
        const auto files = co_await picker.PickMultipleFilesAsync();
        for (const auto& file : files) {
            if (!file.Path().empty()) {
                AppHost::instance().addPinnedClipboardContent(
                    zisla::core::ClipboardHistoryContent::make_file(
                        std::filesystem::path{file.Path().c_str()},
                        to_string(file.Name())));
            }
        }
    } catch (...) {
    }
}

void OverlayContent::ClipboardClearHistory_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().clearClipboardHistory();
}

void OverlayContent::NotesSearch_TextChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&) {
    updateQuickNotesView();
}

void OverlayContent::NotesList_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    if (updating_quick_notes_) {
        return;
    }
    const auto row = NotesList().SelectedItem().try_as<
        Microsoft::UI::Xaml::Controls::Grid>();
    if (!row) {
        return;
    }
    const auto id = unbox_value_or<std::int64_t>(row.Tag(), 0);
    if (id <= 0 || (selected_quick_note_id_ && *selected_quick_note_id_ == id)) {
        return;
    }
    quick_note_save_timer_.Stop();
    flushQuickNoteSave();
    selected_quick_note_id_ = id;
    displayed_quick_note_id_.reset();
    loadQuickNoteEditor(true);
    updateQuickNotesView();
}

void OverlayContent::NotesEditor_TextChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&) {
    if (updating_quick_note_editor_ || !selected_quick_note_id_) {
        return;
    }
    quick_note_dirty_ = true;
    NotesStatusText().Text(L"未保存");
    const auto content = to_string(NotesEditor().Text());
    const bool has_content = !blank_text(content);
    NotesCopyButton().IsEnabled(has_content);
    NotesTeleprompterButton().IsEnabled(has_content);
    quick_note_save_timer_.Stop();
    quick_note_save_timer_.Start();
}

void OverlayContent::NotesMode_SelectionChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const&) {
    const bool preview = NotesModeSelector().SelectedIndex() == 1;
    if (quick_note_preview_ == preview) {
        return;
    }
    quick_note_preview_ = preview;
    updateQuickNotesView();
}

void OverlayContent::NotesNewButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (quick_note_preview_) {
        quick_note_preview_ = false;
        NotesModeSelector().SelectedIndex(0);
    }
    quick_note_save_timer_.Stop();
    flushQuickNoteSave();
    NotesStatusText().Text(L"正在新建");
    AppHost::instance().createQuickNote("# 新随记\n\n");
}

void OverlayContent::NotesRefreshButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    quick_note_save_timer_.Stop();
    flushQuickNoteSave();
    force_quick_note_reload_ = true;
    NotesStatusText().Text(L"正在刷新");
    AppHost::instance().reloadQuickNotes();
}

winrt::fire_and_forget OverlayContent::NotesDeleteButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    const TransientUIHold hold;
    try {
        if (!selected_quick_note_id_ || !XamlRoot()) {
            co_return;
        }
        const auto id = *selected_quick_note_id_;
        const auto found = std::find_if(
            quick_notes_snapshot_->notes.begin(),
            quick_notes_snapshot_->notes.end(),
            [id](const auto& note) { return note.id == id; });
        if (found == quick_notes_snapshot_->notes.end()) {
            co_return;
        }

        Microsoft::UI::Xaml::Controls::ContentDialog dialog;
        dialog.XamlRoot(XamlRoot());
        dialog.Title(box_value(L"删除这条随记？"));
        dialog.Content(box_value(from_utf8(found->title)));
        dialog.PrimaryButtonText(L"删除");
        dialog.CloseButtonText(L"取消");
        dialog.DefaultButton(Microsoft::UI::Xaml::Controls::ContentDialogButton::Close);
        const auto result = co_await dialog.ShowAsync();
        if (result == Microsoft::UI::Xaml::Controls::ContentDialogResult::Primary) {
            quick_note_save_timer_.Stop();
            quick_note_dirty_ = false;
            NotesEditor().IsEnabled(false);
            NotesDeleteButton().IsEnabled(false);
            NotesStatusText().Text(L"正在删除");
            AppHost::instance().removeQuickNote(id);
        }
    } catch (...) {
    }
}

void OverlayContent::NotesCopyButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto content = to_string(NotesEditor().Text());
    if (!blank_text(content)) {
        AppHost::instance().copyTextToClipboard(content);
    }
}

void OverlayContent::NotesTeleprompterButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto content = to_string(NotesEditor().Text());
    if (blank_text(content)) {
        return;
    }
    quick_note_save_timer_.Stop();
    flushQuickNoteSave();
    AppHost::instance().setTeleprompterScript(content);
    AppHost::instance().showTeleprompter();
}

winrt::fire_and_forget OverlayContent::ClipboardClearAll_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    const TransientUIHold hold;
    try {
        if (!XamlRoot()) {
            co_return;
        }
        Microsoft::UI::Xaml::Controls::ContentDialog dialog;
        dialog.XamlRoot(XamlRoot());
        dialog.Title(box_value(L"清空全部剪贴板项目？"));
        dialog.Content(box_value(L"历史和常用项都会被永久删除。"));
        dialog.PrimaryButtonText(L"清空全部");
        dialog.CloseButtonText(L"取消");
        dialog.DefaultButton(Microsoft::UI::Xaml::Controls::ContentDialogButton::Close);
        const auto result = co_await dialog.ShowAsync();
        if (result == Microsoft::UI::Xaml::Controls::ContentDialogResult::Primary) {
            AppHost::instance().clearAllClipboardItems();
        }
    } catch (...) {
    }
}

void OverlayContent::DownloadUrl_TextChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::TextChangedEventArgs const&) {
    if (!updating_download_url_) {
        updateDownloadView();
    }
}

void OverlayContent::DownloadStartButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto mode = unbox_value_or<bool>(DownloadAudioMode().IsChecked(), false)
        ? zisla::core::DownloadMode::audio
        : zisla::core::DownloadMode::video;
    (void)AppHost::instance().startDownload(
        to_string(DownloadUrlBox().Text()),
        mode,
        download_output_directory_);
}

void OverlayContent::DownloadCancelButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().cancelDownload();
}

winrt::fire_and_forget OverlayContent::DownloadFolderButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    const TransientUIHold hold;
    try {
        Windows::Storage::Pickers::FolderPicker picker;
        initializePicker(picker);
        picker.SuggestedStartLocation(
            Windows::Storage::Pickers::PickerLocationId::Downloads);
        picker.FileTypeFilter().Append(L"*");
        const auto folder = co_await picker.PickSingleFolderAsync();
        if (!folder || folder.Path().empty()) {
            co_return;
        }
        download_output_directory_ = std::filesystem::path{folder.Path().c_str()};
        updateDownloadView();
    } catch (...) {
    }
}

void OverlayContent::DownloadRevealButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().revealDownloadedFile();
}

void OverlayContent::PinButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().togglePin();
}

void OverlayContent::VoiceInputButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().toggleVoiceInput();
}

void OverlayContent::SettingsButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().showSettings();
}

void OverlayContent::CloseButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().dismissOverlay();
}

void OverlayContent::DashboardAIButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    selectNavigationModule(L"ai");
}

void OverlayContent::DashboardFocusButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    selectNavigationModule(L"toolbox");
}

void OverlayContent::DashboardWeatherButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    selectNavigationModule(L"agenda");
}

void OverlayContent::DashboardDownloadButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    selectNavigationModule(L"download");
}

void OverlayContent::DashboardBrowserDownloadButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    selectNavigationModule(L"download");
}

void OverlayContent::WeatherRefreshButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().refreshWeather();
}

void OverlayContent::WeatherSearch_QuerySubmitted(
    Microsoft::UI::Xaml::Controls::AutoSuggestBox const&,
    Microsoft::UI::Xaml::Controls::AutoSuggestBoxQuerySubmittedEventArgs const& args) {
    const auto query = to_string(args.QueryText());
    if (query.empty()) {
        return;
    }
    WeatherSearch().Text(L"");
    AppHost::instance().searchWeatherLocation(query);
}

void OverlayContent::PomodoroStartPauseButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().togglePomodoro();
}

void OverlayContent::PomodoroResetButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().resetPomodoro();
}

void OverlayContent::PomodoroApplyDurationButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto component = [](double value, std::int64_t maximum) {
        if (!std::isfinite(value)) {
            return std::int64_t{0};
        }
        return static_cast<std::int64_t>(std::clamp(value, 0.0, static_cast<double>(maximum)));
    };
    const auto hours = component(PomodoroHours().Value(), 999);
    const auto minutes = component(PomodoroMinutes().Value(), 59);
    const auto seconds = component(PomodoroSeconds().Value(), 59);
    const auto duration = std::max<std::int64_t>(
        1,
        hours * 3'600 + minutes * 60 + seconds);
    AppHost::instance().setPomodoroDuration(pomodoro_.mode, duration);
    if (const auto flyout = PomodoroDurationButton().Flyout()) {
        flyout.Hide();
    }
}

void OverlayContent::AlarmSaveButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto component = [](double value, int maximum) {
        if (!std::isfinite(value)) {
            return 0;
        }
        return static_cast<int>(std::clamp(value, 0.0, static_cast<double>(maximum)));
    };
    const auto hour = component(AlarmHour().Value(), 23);
    const auto minute = component(AlarmMinute().Value(), 59);
    const auto label = to_string(AlarmLabel().Text());
    const auto weekdays = selectedAlarmWeekdays();
    const bool saved = editing_alarm_id_.empty()
        ? AppHost::instance().addAlarm(hour, minute, label, weekdays)
        : AppHost::instance().updateAlarm(
            editing_alarm_id_, hour, minute, label, weekdays);
    if (saved) {
        resetAlarmEditor();
    }
}

void OverlayContent::AlarmCancelButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    resetAlarmEditor();
}

void OverlayContent::AlarmWeekdayButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AlarmRepeatHint().Text(
        selectedAlarmWeekdays() == 0 ? L"仅响一次" : L"每周重复");
}

void OverlayContent::AlarmOpenClockButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().openSystemClock();
}

void OverlayContent::PowerDisplayToggle_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setKeepDisplayAwake(unbox_value_or<bool>(
        PowerDisplayToggle().IsChecked(),
        false));
}

void OverlayContent::PowerSystemToggle_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().setPreventIdleSystemSleep(unbox_value_or<bool>(
        PowerSystemToggle().IsChecked(),
        false));
}

void OverlayContent::ScreenCleaningButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().startScreenCleaning();
}

void OverlayContent::KeyboardCleaningButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (cleaning_mode_ == zisla::core::CleaningMode::keyboard) {
        AppHost::instance().requestEndCleaning();
    } else {
        AppHost::instance().startKeyboardCleaning();
    }
}

void OverlayContent::TeleprompterButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().showTeleprompter();
}

void OverlayContent::CameraMirrorButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().showCameraMirror();
}

void OverlayContent::DesktopArrangeButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().arrangeDesktop();
}

void OverlayContent::StoreUpdatesButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().openStoreUpdates();
}

winrt::fire_and_forget OverlayContent::RecycleBinButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    const TransientUIHold hold;
    try {
        const auto snapshot = desktop_tools_snapshot_;
        if (!snapshot || snapshot->busy || !snapshot->recycle_bin.available) {
            AppHost::instance().refreshDesktopTools();
            co_return;
        }
        if (snapshot->recycle_bin.item_count == 0) {
            AppHost::instance().refreshDesktopTools();
            co_return;
        }
        if (!XamlRoot()) {
            co_return;
        }

        std::wstring detail = L"将永久删除回收站中的 ";
        detail.append(std::to_wstring(snapshot->recycle_bin.item_count));
        detail.append(L" 个项目");
        if (snapshot->recycle_bin.size_bytes > 0) {
            detail.append(L"（");
            append(detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
                snapshot->recycle_bin.size_bytes)));
            detail.append(L"）");
        }
        detail.append(L"。此操作无法撤销。");

        Microsoft::UI::Xaml::Controls::ContentDialog dialog;
        dialog.XamlRoot(XamlRoot());
        dialog.Title(box_value(L"清空回收站？"));
        dialog.Content(box_value(hstring{detail}));
        dialog.PrimaryButtonText(L"清空");
        dialog.CloseButtonText(L"取消");
        dialog.DefaultButton(
            Microsoft::UI::Xaml::Controls::ContentDialogButton::Close);
        const auto result = co_await dialog.ShowAsync();
        if (result
            == Microsoft::UI::Xaml::Controls::ContentDialogResult::Primary) {
            AppHost::instance().emptyRecycleBin();
        }
    } catch (...) {
    }
}

void OverlayContent::DiskCleanupScanButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().scanDiskCleanup();
}

void OverlayContent::SystemMemoryReleaseButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().releaseSystemMemory();
}

winrt::fire_and_forget OverlayContent::DiskCleanupCleanButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    const TransientUIHold hold;
    try {
        const auto selected = selectedDiskCleanupPaths();
        const auto snapshot = disk_cleanup_snapshot_;
        if (selected.empty() || !snapshot || snapshot->scanning
            || snapshot->cleaning || !XamlRoot()) {
            co_return;
        }

        std::uint64_t selected_bytes = 0;
        for (const auto& candidate : snapshot->candidates) {
            if (std::find(selected.begin(), selected.end(), candidate.path)
                == selected.end()) {
                continue;
            }
            selected_bytes += std::min(
                candidate.size_bytes,
                std::numeric_limits<std::uint64_t>::max() - selected_bytes);
        }

        std::wstring detail = L"将 ";
        detail.append(std::to_wstring(selected.size()));
        detail.append(L" 个项目");
        if (selected_bytes > 0) {
            detail.append(L"（");
            append(detail, from_utf8(zisla::core::SystemMonitorFormat::bytes(
                selected_bytes)));
            detail.append(L"）");
        }
        detail.append(L"移入回收站。之后仍可从回收站恢复。");

        Microsoft::UI::Xaml::Controls::ContentDialog dialog;
        dialog.XamlRoot(XamlRoot());
        dialog.Title(box_value(L"移入回收站？"));
        dialog.Content(box_value(hstring{detail}));
        dialog.PrimaryButtonText(L"移入回收站");
        dialog.CloseButtonText(L"取消");
        dialog.DefaultButton(
            Microsoft::UI::Xaml::Controls::ContentDialogButton::Close);
        const auto result = co_await dialog.ShowAsync();
        if (result
            == Microsoft::UI::Xaml::Controls::ContentDialogResult::Primary) {
            AppHost::instance().cleanDiskCleanup(selected);
        }
    } catch (...) {
    }
}

void OverlayContent::ShelfView_DragOver(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::DragEventArgs const& args) {
    using namespace Windows::ApplicationModel::DataTransfer;
    if (!args.DataView().Contains(StandardDataFormats::StorageItems())) {
        return;
    }
    args.AcceptedOperation(DataPackageOperation::Copy);
    args.DragUIOverride().Caption(L"加入中转站");
    args.DragUIOverride().IsCaptionVisible(true);
    ShelfDropHint().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
    args.Handled(true);
}

void OverlayContent::ShelfView_DragLeave(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::DragEventArgs const&) {
    ShelfDropHint().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
}

winrt::fire_and_forget OverlayContent::ShelfView_Drop(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::DragEventArgs const& args) {
    const auto lifetime = get_strong();
    (void)lifetime;
    ShelfDropHint().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
    try {
        co_await addStorageItemsAsync(args.DataView());
    } catch (...) {
    }
}

winrt::fire_and_forget OverlayContent::ShelfPasteButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    try {
        const auto data = Windows::ApplicationModel::DataTransfer::Clipboard::GetContent();
        if (data.Contains(
                Windows::ApplicationModel::DataTransfer::StandardDataFormats::StorageItems())) {
            co_await addStorageItemsAsync(data);
        }
    } catch (...) {
    }
}

void OverlayContent::ShelfCopyAllButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().copyAllShelfPaths();
}

void OverlayContent::ShelfShareButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().shareAllShelfPaths();
}

void OverlayContent::ShelfClearButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().clearShelf();
}

void OverlayContent::MediaPreviousButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().playPreviousMedia();
}

void OverlayContent::MediaPlayPauseButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().toggleMediaPlayback();
}

void OverlayContent::MediaNextButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().playNextMedia();
}

void OverlayContent::MediaProgress_ValueChanged(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const& args) {
    if (!updating_media_progress_ && now_playing_
        && now_playing_->controls.can_seek) {
        AppHost::instance().seekMedia(args.NewValue());
    }
}

void OverlayContent::ModuleNavigation_SelectionChanged(
    Microsoft::UI::Xaml::Controls::NavigationView const&,
    Microsoft::UI::Xaml::Controls::NavigationViewSelectionChangedEventArgs const& args) {
    const auto item = args.SelectedItem().try_as<
        Microsoft::UI::Xaml::Controls::NavigationViewItem>();
    if (!item) {
        return;
    }

    const auto tag = unbox_value_or<hstring>(item.Tag(), L"dashboard");
    selected_module_ = tag;
    hstring title = L"首页";
    hstring state = L"一切就绪";
    hstring glyph = L"\uE73E";

    if (tag == L"shelf") {
        title = L"中转";
        state = L"暂无文件";
        glyph = L"\uE838";
    } else if (tag == L"clipboard") {
        title = L"剪贴板";
        state = L"剪贴板历史已关闭";
        glyph = L"\uE8C8";
    } else if (tag == L"ai") {
        title = L"AI 监控";
        state = L"暂无进行中的 AI 任务";
        glyph = L"\uE9D2";
    } else if (tag == L"agent") {
        title = L"AI Agent";
        state = L"会话与 Skills";
        glyph = L"\uE945";
        AppHost::instance().reloadAIAgentWorkspace();
        AppHost::instance().reloadAIAgentSkills();
    } else if (tag == L"download") {
        title = L"下载";
        state = L"暂无下载任务";
        glyph = L"\uE896";
    } else if (tag == L"agenda") {
        title = L"日程";
        state = L"今天没有日程";
        glyph = L"\uE787";
    } else if (tag == L"mail") {
        title = L"邮件";
        state = L"邮件尚未连接";
        glyph = L"\uE715";
    } else if (tag == L"notes") {
        title = L"随记";
        state = L"暂无随记";
        glyph = L"\uE70B";
    } else if (tag == L"pdf") {
        title = L"PDF";
        state = L"未选择 PDF";
        glyph = L"\uE8A5";
    } else if (tag == L"toolbox") {
        title = L"小工具";
        state = L"计时器未启动";
        glyph = L"\uE90F";
        AppHost::instance().refreshDesktopTools();
    } else if (tag == L"system") {
        title = L"系统";
        state = L"正在等待系统快照";
        glyph = L"\uE9D9";
    }

    ModuleTitle().Text(title);
    ModuleStateText().Text(state);
    ModuleStateIcon().Glyph(glyph);
    updateAIView();
    updateMediaView();
    updateDashboardView();
    updateShelfView();
    updateClipboardView();
    updateDownloadView();
    updateWeatherView();
    updateToolboxView();
    updateQuickNotesView();
    updatePDFToolsView();
    updateAIAgentSkillsView();
    updateCalendarView();
    updateMailView();
    updateSystemMonitorView();
    updateDiskCleanupView();
    updateSystemMonitorActivity();
    AppHost::instance().requestOverlayRelayout();
}

void OverlayContent::setCalendar(
    std::shared_ptr<const CalendarServiceSnapshot> snapshot) {
    calendar_snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const CalendarServiceSnapshot>();
    if (selected_module_ == L"agenda") {
        updateCalendarView();
    }
}

void OverlayContent::setMail(
    std::shared_ptr<const MailServiceSnapshot> snapshot) {
    mail_snapshot_ = snapshot
        ? std::move(snapshot)
        : std::make_shared<const MailServiceSnapshot>();
    if (selected_module_ == L"mail") {
        updateMailView();
    }
}

void OverlayContent::updateMailView() {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    const bool selected = selected_module_ == L"mail";
    MailView().Visibility(selected ? Visibility::Visible : Visibility::Collapsed);
    if (!selected) {
        return;
    }

    ModuleState().Visibility(Visibility::Collapsed);
    DashboardScroll().Visibility(Visibility::Collapsed);
    AITaskScroll().Visibility(Visibility::Collapsed);
    ShelfView().Visibility(Visibility::Collapsed);
    ClipboardView().Visibility(Visibility::Collapsed);
    AIAgentView().Visibility(Visibility::Collapsed);
    DownloadView().Visibility(Visibility::Collapsed);
    AgendaView().Visibility(Visibility::Collapsed);
    WeatherView().Visibility(Visibility::Collapsed);
    NotesView().Visibility(Visibility::Collapsed);
    PDFToolsView().Visibility(Visibility::Collapsed);
    ToolboxView().Visibility(Visibility::Collapsed);
    SystemView().Visibility(Visibility::Collapsed);

    const auto snapshot = mail_snapshot_
        ? mail_snapshot_
        : std::make_shared<const MailServiceSnapshot>();
    const bool configured = !snapshot->connection.client_id.empty();
    const bool loading = snapshot->phase == MailServicePhase::loading;
    const bool authorizing = snapshot->phase
        == MailServicePhase::authorization_required;
    const bool ready = snapshot->phase == MailServicePhase::ready;

    hstring status = snapshot->message.empty()
        ? hstring{L"请在设置中连接 Microsoft Graph 邮箱"}
        : from_utf8(snapshot->message);
    switch (snapshot->phase) {
    case MailServicePhase::not_configured:
        status = snapshot->message.empty()
            ? hstring{L"请在设置中连接 Microsoft Graph 邮箱"}
            : from_utf8(snapshot->message);
        break;
    case MailServicePhase::idle:
        break;
    case MailServicePhase::loading:
        status = snapshot->message.empty()
            ? hstring{L"正在处理邮件"}
            : from_utf8(snapshot->message);
        break;
    case MailServicePhase::authorization_required:
        status = snapshot->message.empty()
            ? hstring{L"请在浏览器中完成 Microsoft 登录"}
            : from_utf8(snapshot->message);
        break;
    case MailServicePhase::ready: {
        std::wstring ready_text = snapshot->message.empty()
            ? L"收件箱已更新"
            : std::wstring{from_utf8(snapshot->message).c_str()};
        ready_text.append(L" · ");
        ready_text.append(std::to_wstring(snapshot->messages.size()));
        ready_text.append(L" 封邮件");
        status = hstring{ready_text};
        break;
    }
    case MailServicePhase::failed:
        status = snapshot->message.empty()
            ? hstring{L"邮件服务失败"}
            : from_utf8(snapshot->message);
        break;
    }

    MailStatusText().Text(status);
    MailProgress().IsActive(loading);
    MailProgress().Visibility(loading ? Visibility::Visible : Visibility::Collapsed);
    MailRefreshButton().IsEnabled(configured && !loading && !authorizing);
    MailAuthorizeButton().IsEnabled(configured && !loading && !authorizing);
    MailComposeExpander().IsEnabled(ready);
    MailSendButton().IsEnabled(ready);

    const bool shows_device_code = snapshot->phase
        == MailServicePhase::authorization_required && snapshot->device_code.has_value();
    MailDeviceCodePanel().Visibility(
        shows_device_code ? Visibility::Visible : Visibility::Collapsed);
    if (shows_device_code) {
        const auto& device_code = *snapshot->device_code;
        MailVerificationCodeText().Text(from_utf8(device_code.user_code));
        mail_verification_uri_ = from_utf8(device_code.verification_uri);
        std::wstring uri = L"登录地址：";
        uri.append(mail_verification_uri_.c_str(), mail_verification_uri_.size());
        MailVerificationUriText().Text(hstring{uri});
        MailOpenAuthorizationButton().IsEnabled(!mail_verification_uri_.empty());
    } else {
        mail_verification_uri_ = {};
        MailVerificationCodeText().Text(L"");
        MailVerificationUriText().Text(L"");
        MailOpenAuthorizationButton().IsEnabled(false);
    }

    MailRows().Items().Clear();
    for (const auto& message : snapshot->messages) {
        MailRows().Items().Append(makeMailRow(message));
    }
    const bool empty = snapshot->messages.empty();
    MailRows().Visibility(empty ? Visibility::Collapsed : Visibility::Visible);
    MailEmptyState().Visibility(empty ? Visibility::Visible : Visibility::Collapsed);
    if (empty) {
        MailEmptyStateText().Text(status);
    }

    const bool replying_to_visible_message = !replying_to_mail_id_.empty()
        && std::any_of(
            snapshot->messages.begin(),
            snapshot->messages.end(),
            [this](const auto& message) { return message.id == replying_to_mail_id_; });
    if (!replying_to_visible_message) {
        replying_to_mail_id_.clear();
        MailReplyBodyBox().Text(L"");
    }
    MailReplyPanel().Visibility(
        replying_to_visible_message ? Visibility::Visible : Visibility::Collapsed);
    MailReplySendButton().IsEnabled(
        replying_to_visible_message && ready);

    std::wstring accessible_name = L"邮件，";
    accessible_name.append(status.c_str(), status.size());
    Automation::AutomationProperties::SetName(MailView(), hstring{accessible_name});
}

void OverlayContent::updateCalendarView() {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    const bool selected = selected_module_ == L"agenda";
    AgendaView().Visibility(selected ? Visibility::Visible : Visibility::Collapsed);
    if (!selected) {
        return;
    }

    ModuleState().Visibility(Visibility::Collapsed);
    DashboardScroll().Visibility(Visibility::Collapsed);
    AITaskScroll().Visibility(Visibility::Collapsed);
    ShelfView().Visibility(Visibility::Collapsed);
    ClipboardView().Visibility(Visibility::Collapsed);
    DownloadView().Visibility(Visibility::Collapsed);
    NotesView().Visibility(Visibility::Collapsed);
    WeatherView().Visibility(Visibility::Collapsed);
    ToolboxView().Visibility(Visibility::Collapsed);
    SystemView().Visibility(Visibility::Collapsed);

    const auto snapshot = calendar_snapshot_;
    const bool loading = snapshot->loading;
    const bool has_error = !snapshot->error.empty();

    if (!snapshot->day_intervals.empty()) {
        const auto selection_exists = [snapshot](std::int64_t ordinal) {
            return std::any_of(
                snapshot->day_intervals.begin(),
                snapshot->day_intervals.end(),
                [ordinal](const auto& interval) {
                    return interval.day_ordinal == ordinal;
                });
        };
        if (!selected_calendar_day_ordinal_
            || !selection_exists(*selected_calendar_day_ordinal_)) {
            const auto reference_ordinal =
                zisla::core::CalendarEngine::civil_day(
                    snapshot->reference_date).day_ordinal;
            selected_calendar_day_ordinal_ = selection_exists(reference_ordinal)
                ? reference_ordinal
                : snapshot->day_intervals.front().day_ordinal;
        }
    } else {
        selected_calendar_day_ordinal_.reset();
    }

    AgendaProgress().IsActive(loading);
    AgendaProgress().Visibility(loading ? Visibility::Visible : Visibility::Collapsed);
    AgendaEmptyIcon().Visibility(loading ? Visibility::Collapsed : Visibility::Visible);

    if (has_error) {
        AgendaStatusText().Text(from_utf8(snapshot->error));
    } else if (loading) {
        AgendaStatusText().Text(L"正在载入日程");
    } else {
        AgendaStatusText().Text(L"所选日期暂无事项");
    }

    const std::array<Microsoft::UI::Xaml::Controls::Button, 7> day_buttons = {
        AgendaDay0(), AgendaDay1(), AgendaDay2(), AgendaDay3(),
        AgendaDay4(), AgendaDay5(), AgendaDay6()
    };
    const std::array<Microsoft::UI::Xaml::Controls::TextBlock, 7> weekday_labels = {
        AgendaDay0Weekday(), AgendaDay1Weekday(), AgendaDay2Weekday(),
        AgendaDay3Weekday(), AgendaDay4Weekday(), AgendaDay5Weekday(),
        AgendaDay6Weekday()
    };
    const std::array<Microsoft::UI::Xaml::Controls::TextBlock, 7> date_labels = {
        AgendaDay0Date(), AgendaDay1Date(), AgendaDay2Date(),
        AgendaDay3Date(), AgendaDay4Date(), AgendaDay5Date(),
        AgendaDay6Date()
    };

    const std::array<hstring, 7> weekday_names = {
        L"一", L"二", L"三", L"四", L"五", L"六", L"日"
    };

    if (!snapshot->week_days.empty() && snapshot->week_days.size() == 7) {
        const auto& first = snapshot->week_days.front().date;
        const auto& last = snapshot->week_days.back().date;
        std::wstring week_title = std::to_wstring(first.year) + L"年"
            + std::to_wstring(first.month) + L"月"
            + std::to_wstring(first.day) + L"日 - ";
        if (last.year != first.year) {
            week_title.append(std::to_wstring(last.year) + L"年");
        }
        if (last.year != first.year || last.month != first.month) {
            week_title.append(std::to_wstring(last.month) + L"月");
        }
        week_title.append(std::to_wstring(last.day) + L"日");
        AgendaWeekTitle().Text(hstring{week_title});

        std::optional<std::int64_t> today_ordinal;
        try {
            today_ordinal = zisla::core::CalendarEngine::civil_day(
                CalendarService::localDateTime(now_unix_milliseconds()).date).day_ordinal;
        } catch (...) {
        }

        for (std::size_t i = 0; i < 7; ++i) {
            const auto& day = snapshot->week_days[i];
            const auto weekday_index = (day.weekday + 5) % 7;
            weekday_labels[i].Text(weekday_names[weekday_index]);
            date_labels[i].Text(hstring{std::to_wstring(day.date.day)});
            day_buttons[i].Tag(box_value(day.day_ordinal));
            day_buttons[i].IsEnabled(!loading && !has_error);

            const bool is_selected = selected_calendar_day_ordinal_
                && *selected_calendar_day_ordinal_ == day.day_ordinal;
            const bool is_today = today_ordinal && *today_ordinal == day.day_ordinal;
            date_labels[i].FontWeight(is_selected || is_today
                ? Windows::UI::Text::FontWeights::Bold()
                : Windows::UI::Text::FontWeights::SemiBold());
            day_buttons[i].Opacity(is_selected ? 1.0 : 0.82);

            std::wstring accessible_name = std::to_wstring(day.date.year) + L"年"
                + std::to_wstring(day.date.month) + L"月"
                + std::to_wstring(day.date.day) + L"日";
            if (is_today) {
                accessible_name.append(L"，今天");
            }
            if (is_selected) {
                accessible_name.append(L"，已选择");
            }
            Automation::AutomationProperties::SetName(
                day_buttons[i],
                hstring{accessible_name});

            try {
                if (is_selected) {
                    const auto style = Microsoft::UI::Xaml::Application::Current().Resources()
                        .Lookup(box_value(L"AccentButtonStyle"))
                        .try_as<Microsoft::UI::Xaml::Style>();
                    if (style) {
                        day_buttons[i].Style(style);
                    }
                } else {
                    day_buttons[i].ClearValue(FrameworkElement::StyleProperty());
                }
            } catch (...) {
            }
        }
    }

    AgendaList().Items().Clear();
    if (selected_calendar_day_ordinal_) {
        const auto selected_ordinal = *selected_calendar_day_ordinal_;
        const auto day_iter = std::find_if(
            snapshot->day_intervals.begin(),
            snapshot->day_intervals.end(),
            [selected_ordinal](const auto& interval) {
                return interval.day_ordinal == selected_ordinal;
            });

        if (day_iter != snapshot->day_intervals.end()) {
            for (const auto& item : snapshot->items) {
                if (zisla::core::CalendarEngine::item_occurs_on_day(item, *day_iter)) {
                    AgendaList().Items().Append(makeCalendarRow(item));
                }
            }
        }
    }

    const bool empty = AgendaList().Items().Size() == 0;
    AgendaEmptyState().Visibility(empty ? Visibility::Visible : Visibility::Collapsed);
    AgendaList().Visibility(empty ? Visibility::Collapsed : Visibility::Visible);
}

Microsoft::UI::Xaml::Controls::Grid OverlayContent::makeCalendarRow(
    const zisla::core::CalendarEventSnapshot& item) {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    const auto local_id = local_calendar_id(item);
    Grid row;
    row.MinHeight(52);
    row.Padding(Thickness{4, 5, 2, 5});
    if (local_id) {
        row.Tag(box_value(*local_id));
    }

    ColumnDefinition icon_column;
    icon_column.Width(GridLength{30, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(icon_column);
    ColumnDefinition text_column;
    text_column.Width(GridLength{1, GridUnitType::Star});
    row.ColumnDefinitions().Append(text_column);
    ColumnDefinition action_column;
    action_column.Width(GridLength{local_id ? 30.0 : 0.0, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(action_column);

    if (item.kind == zisla::core::CalendarItemKind::reminder && local_id) {
        CheckBox checkbox;
        checkbox.Width(24);
        checkbox.Height(24);
        checkbox.MinWidth(0);
        checkbox.HorizontalAlignment(HorizontalAlignment::Left);
        checkbox.VerticalAlignment(VerticalAlignment::Center);
        checkbox.IsChecked(box_value(item.is_completed).as<
            Windows::Foundation::IReference<bool>>());
        checkbox.Tag(box_value(*local_id));
        checkbox.Click({this, &OverlayContent::AgendaReminderCheckBox_Click});
        Automation::AutomationProperties::SetName(
            checkbox,
            item.is_completed ? L"标记为未完成" : L"标记为已完成");
        row.Children().Append(checkbox);
    } else {
        FontIcon icon;
        icon.Glyph(item.kind == zisla::core::CalendarItemKind::reminder
            ? L"\uE8A1"
            : L"\uE787");
        icon.FontSize(14);
        icon.HorizontalAlignment(HorizontalAlignment::Left);
        icon.VerticalAlignment(VerticalAlignment::Center);
        row.Children().Append(icon);
    }

    StackPanel text;
    text.Spacing(1);
    text.VerticalAlignment(VerticalAlignment::Center);
    Grid::SetColumn(text, 1);

    TextBlock title;
    title.Text(from_utf8(item.title));
    title.FontSize(12);
    title.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
    title.MaxLines(1);
    title.TextTrimming(TextTrimming::CharacterEllipsis);
    if (item.is_completed) {
        title.Opacity(0.5);
        title.TextDecorations(Windows::UI::Text::TextDecorations::Strikethrough);
    }
    text.Children().Append(title);

    std::wstring detail;
    if (item.kind == zisla::core::CalendarItemKind::reminder) {
        detail = item.is_projected_occurrence
            ? L"重复待办 · "
            : item.is_completed ? L"待办 · 已完成 · " : L"待办 · ";
    }
    if (item.is_all_day) {
        detail.append(L"全天");
    } else {
        try {
            append(detail, calendar_local_time_text(item.start_unix_ms));
        } catch (...) {
            detail.append(L"时间不可用");
        }
    }
    if (!item.calendar_title.empty()) {
        detail.append(L" · ");
        append(detail, from_utf8(item.calendar_title));
    }

    TextBlock detail_text;
    detail_text.Text(hstring{detail});
    detail_text.FontSize(10);
    detail_text.Opacity(0.64);
    text.Children().Append(detail_text);
    row.Children().Append(text);

    if (local_id) {
        Button delete_button;
        delete_button.Width(28);
        delete_button.Height(28);
        delete_button.Padding(Thickness{});
        delete_button.VerticalAlignment(VerticalAlignment::Center);
        Grid::SetColumn(delete_button, 2);
        FontIcon delete_icon;
        delete_icon.Glyph(L"\uE74D");
        delete_icon.FontSize(12);
        delete_button.Content(delete_icon);
        delete_button.Tag(box_value(*local_id));
        Automation::AutomationProperties::SetName(delete_button, L"删除");
        ToolTipService::SetToolTip(delete_button, box_value(L"删除"));
        delete_button.Click({this, &OverlayContent::AgendaDeleteButton_Click});
        row.Children().Append(delete_button);
    }

    std::wstring accessible_name;
    append(accessible_name, title.Text());
    accessible_name.append(L"，");
    accessible_name.append(detail);
    Automation::AutomationProperties::SetName(row, hstring{accessible_name});
    return row;
}

Microsoft::UI::Xaml::Controls::Grid OverlayContent::makeMailRow(
    const zisla::core::MailMessage& message) {
    using namespace Microsoft::UI::Xaml;
    using namespace Microsoft::UI::Xaml::Controls;

    Grid row;
    row.MinHeight(70);
    row.Padding(Thickness{4, 6, 2, 6});

    ColumnDefinition icon_column;
    icon_column.Width(GridLength{28, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(icon_column);
    ColumnDefinition content_column;
    content_column.Width(GridLength{1, GridUnitType::Star});
    row.ColumnDefinitions().Append(content_column);
    ColumnDefinition action_column;
    action_column.Width(GridLength{120, GridUnitType::Pixel});
    row.ColumnDefinitions().Append(action_column);

    FontIcon icon;
    icon.Glyph(message.is_read ? L"\uE715" : L"\uE8A5");
    icon.FontSize(14);
    icon.HorizontalAlignment(HorizontalAlignment::Left);
    icon.VerticalAlignment(VerticalAlignment::Top);
    icon.Margin(Thickness{2, 4, 0, 0});
    row.Children().Append(icon);

    StackPanel content;
    content.Spacing(2);
    Grid::SetColumn(content, 1);

    Grid heading;
    ColumnDefinition sender_column;
    sender_column.Width(GridLength{1, GridUnitType::Star});
    heading.ColumnDefinitions().Append(sender_column);
    ColumnDefinition time_column;
    time_column.Width(GridLength{1, GridUnitType::Auto});
    heading.ColumnDefinitions().Append(time_column);

    const auto sender = message.sender.empty()
        ? (message.sender_address.empty() ? hstring{L"未知发件人"} : from_utf8(message.sender_address))
        : from_utf8(message.sender);
    TextBlock sender_text;
    sender_text.Text(sender);
    sender_text.FontSize(11);
    sender_text.FontWeight(message.is_read
        ? Windows::UI::Text::FontWeights::Normal()
        : Windows::UI::Text::FontWeights::SemiBold());
    sender_text.MaxLines(1);
    sender_text.TextTrimming(TextTrimming::CharacterEllipsis);
    heading.Children().Append(sender_text);

    TextBlock received;
    received.Text(from_utf8(message.received_at));
    received.FontSize(9);
    received.Opacity(0.62);
    received.MaxLines(1);
    received.TextTrimming(TextTrimming::CharacterEllipsis);
    Grid::SetColumn(received, 1);
    heading.Children().Append(received);
    content.Children().Append(heading);

    TextBlock subject;
    subject.Text(message.subject.empty() ? hstring{L"(无主题)"} : from_utf8(message.subject));
    subject.FontSize(12);
    subject.FontWeight(message.is_read
        ? Windows::UI::Text::FontWeights::Normal()
        : Windows::UI::Text::FontWeights::SemiBold());
    subject.MaxLines(1);
    subject.TextTrimming(TextTrimming::CharacterEllipsis);
    content.Children().Append(subject);

    TextBlock preview;
    preview.Text(mail_preview(message.body));
    preview.FontSize(10);
    preview.Opacity(0.64);
    preview.MaxLines(2);
    preview.TextTrimming(TextTrimming::CharacterEllipsis);
    content.Children().Append(preview);
    row.Children().Append(content);

    const auto message_id = from_utf8(message.id);
    const bool can_mutate_mail = mail_snapshot_
        && mail_snapshot_->phase == MailServicePhase::ready;
    StackPanel actions;
    actions.HorizontalAlignment(HorizontalAlignment::Right);
    actions.VerticalAlignment(VerticalAlignment::Center);
    actions.Orientation(Orientation::Horizontal);
    actions.Spacing(2);
    Grid::SetColumn(actions, 2);

    Button reply_button;
    reply_button.Width(28);
    reply_button.Height(28);
    reply_button.Padding(Thickness{});
    reply_button.Tag(box_value(message_id));
    reply_button.IsEnabled(can_mutate_mail);
    FontIcon reply_icon;
    reply_icon.Glyph(L"\uE97A");
    reply_icon.FontSize(12);
    reply_button.Content(reply_icon);
    reply_button.Click({this, &OverlayContent::MailReplyButton_Click});
    Automation::AutomationProperties::SetName(reply_button, L"回复");
    ToolTipService::SetToolTip(reply_button, box_value(L"回复"));
    actions.Children().Append(reply_button);

    if (!message.is_read) {
        Button read_button;
        read_button.Width(28);
        read_button.Height(28);
        read_button.Padding(Thickness{});
        read_button.Tag(box_value(message_id));
        read_button.IsEnabled(can_mutate_mail);
        FontIcon read_icon;
        read_icon.Glyph(L"\uE8C8");
        read_icon.FontSize(12);
        read_button.Content(read_icon);
        read_button.Click({this, &OverlayContent::MailMarkReadButton_Click});
        Automation::AutomationProperties::SetName(read_button, L"标记为已读");
        ToolTipService::SetToolTip(read_button, box_value(L"标记为已读"));
        actions.Children().Append(read_button);
    }

    Button junk_button;
    junk_button.Width(28);
    junk_button.Height(28);
    junk_button.Padding(Thickness{});
    junk_button.Tag(box_value(message_id));
    junk_button.IsEnabled(can_mutate_mail);
    FontIcon junk_icon;
    junk_icon.Glyph(L"\uE74D");
    junk_icon.FontSize(12);
    junk_button.Content(junk_icon);
    junk_button.Click({this, &OverlayContent::MailJunkButton_Click});
    Automation::AutomationProperties::SetName(junk_button, L"移至垃圾邮件");
    ToolTipService::SetToolTip(junk_button, box_value(L"移至垃圾邮件"));
    actions.Children().Append(junk_button);

    Button delete_button;
    delete_button.Width(28);
    delete_button.Height(28);
    delete_button.Padding(Thickness{});
    delete_button.Tag(box_value(message_id));
    delete_button.IsEnabled(can_mutate_mail);
    FontIcon delete_icon;
    delete_icon.Glyph(L"\uE74D");
    delete_icon.FontSize(12);
    delete_button.Content(delete_icon);
    delete_button.Click({this, &OverlayContent::MailDeleteButton_Click});
    Automation::AutomationProperties::SetName(delete_button, L"删除");
    ToolTipService::SetToolTip(delete_button, box_value(L"删除"));
    actions.Children().Append(delete_button);
    row.Children().Append(actions);

    std::wstring accessible_name;
    append(accessible_name, sender);
    accessible_name.append(L"，");
    append(accessible_name, subject.Text());
    if (!message.is_read) {
        accessible_name.append(L"，未读");
    }
    Automation::AutomationProperties::SetName(row, hstring{accessible_name});
    return row;
}

void OverlayContent::AgendaPreviousWeekButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (!calendar_snapshot_ || calendar_snapshot_->week_days.empty()) {
        return;
    }
    const auto first_day = calendar_snapshot_->week_days.front().date;
    const auto previous_week = zisla::core::CalendarEngine::add_days(first_day, -7);
    AppHost::instance().setCalendarReferenceDate(previous_week);
}

void OverlayContent::AgendaTodayButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    AppHost::instance().showCurrentCalendarWeek();
}

void OverlayContent::AgendaNextWeekButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (!calendar_snapshot_ || calendar_snapshot_->week_days.empty()) {
        return;
    }
    const auto first_day = calendar_snapshot_->week_days.front().date;
    const auto next_week = zisla::core::CalendarEngine::add_days(first_day, 7);
    AppHost::instance().setCalendarReferenceDate(next_week);
}

void OverlayContent::AgendaDayButton_Click(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto button = sender.try_as<Microsoft::UI::Xaml::Controls::Button>();
    if (!button) {
        return;
    }
    const auto day_ordinal = unbox_value_or<std::int64_t>(button.Tag(), 0);
    if (day_ordinal == 0) {
        return;
    }
    selected_calendar_day_ordinal_ = day_ordinal;
    updateCalendarView();
}

winrt::fire_and_forget OverlayContent::AgendaNewEventButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    showCalendarEditor(false);
    co_return;
}

winrt::fire_and_forget OverlayContent::AgendaNewReminderButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    showCalendarEditor(true);
    co_return;
}

void OverlayContent::AgendaReminderCheckBox_Click(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto checkbox = sender.try_as<Microsoft::UI::Xaml::Controls::CheckBox>();
    if (!checkbox) {
        return;
    }
    const auto id = unbox_value_or<std::int64_t>(checkbox.Tag(), 0);
    const auto completed = unbox_value_or<bool>(checkbox.IsChecked(), false);
    if (id > 0) {
        checkbox.IsEnabled(false);
        AgendaStatusText().Text(L"正在更新待办");
        AppHost::instance().setCalendarReminderCompleted(id, completed);
    }
}

winrt::fire_and_forget OverlayContent::AgendaDeleteButton_Click(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    const TransientUIHold hold;
    try {
        const auto button = sender.try_as<Microsoft::UI::Xaml::Controls::Button>();
        if (!button || !XamlRoot()) {
            co_return;
        }
        const auto id = unbox_value_or<std::int64_t>(button.Tag(), 0);
        if (id <= 0) {
            co_return;
        }

        const auto snapshot = calendar_snapshot_;
        const auto found = std::find_if(
            snapshot->items.begin(),
            snapshot->items.end(),
            [id](const auto& item) {
                return local_calendar_id(item) == id;
            });
        if (found == snapshot->items.end()) {
            co_return;
        }

        Microsoft::UI::Xaml::Controls::ContentDialog dialog;
        dialog.XamlRoot(XamlRoot());
        dialog.Title(box_value(found->kind == zisla::core::CalendarItemKind::event
            ? L"删除日程？"
            : L"删除待办？"));
        dialog.Content(box_value(from_utf8(found->title)));
        dialog.PrimaryButtonText(L"删除");
        dialog.CloseButtonText(L"取消");
        dialog.DefaultButton(Microsoft::UI::Xaml::Controls::ContentDialogButton::Close);
        const auto result = co_await dialog.ShowAsync();
        if (result == Microsoft::UI::Xaml::Controls::ContentDialogResult::Primary) {
            button.IsEnabled(false);
            AgendaStatusText().Text(L"正在删除");
            AppHost::instance().removeCalendarItem(id);
        }
    } catch (const winrt::hresult_error& error) {
        AgendaStatusText().Text(error.message());
    } catch (const std::exception& error) {
        AgendaStatusText().Text(from_utf8(error.what()));
    } catch (...) {
        AgendaStatusText().Text(L"删除失败");
    }
}

void OverlayContent::MailRefreshButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (!mail_snapshot_ || mail_snapshot_->connection.client_id.empty()) {
        MailStatusText().Text(L"请先在设置中填写 Microsoft Graph 客户端 ID");
        return;
    }
    AppHost::instance().refreshMail();
}

void OverlayContent::MailAuthorizeButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    if (!mail_snapshot_ || mail_snapshot_->connection.client_id.empty()) {
        MailStatusText().Text(L"请先在设置中填写 Microsoft Graph 客户端 ID");
        return;
    }
    AppHost::instance().beginMailAuthorization();
}

winrt::fire_and_forget OverlayContent::MailOpenAuthorizationButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto lifetime = get_strong();
    (void)lifetime;
    if (mail_verification_uri_.empty()) {
        co_return;
    }
    try {
        const auto opened = co_await Windows::System::Launcher::LaunchUriAsync(
            Windows::Foundation::Uri{mail_verification_uri_});
        if (!opened) {
            MailStatusText().Text(L"无法打开 Microsoft 登录页面");
        }
    } catch (...) {
        MailStatusText().Text(L"无法打开 Microsoft 登录页面");
    }
}

void OverlayContent::MailSendButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    auto recipients = mailRecipients();
    if (recipients.empty()) {
        MailStatusText().Text(L"请至少填写一个收件人");
        return;
    }
    AppHost::instance().sendMail(
        std::move(recipients),
        to_string(MailSubjectBox().Text()),
        to_string(MailBodyBox().Text()));
    MailStatusText().Text(L"正在发送邮件");
}

void OverlayContent::MailReplyButton_Click(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto button = sender.try_as<Microsoft::UI::Xaml::Controls::Button>();
    if (!button) {
        return;
    }
    const auto message_id = to_string(unbox_value_or<hstring>(button.Tag(), L""));
    if (message_id.empty()) {
        return;
    }
    replying_to_mail_id_ = message_id;
    MailReplyBodyBox().Text(L"");

    std::wstring target = L"回复";
    if (mail_snapshot_) {
        const auto found = std::find_if(
            mail_snapshot_->messages.begin(),
            mail_snapshot_->messages.end(),
            [&message_id](const auto& message) { return message.id == message_id; });
        if (found != mail_snapshot_->messages.end()) {
            target.append(L"：");
            append(target, found->subject.empty()
                ? hstring{L"(无主题)"}
                : from_utf8(found->subject));
        }
    }
    MailReplyTargetText().Text(hstring{target});
    MailReplyPanel().Visibility(Microsoft::UI::Xaml::Visibility::Visible);
    MailReplySendButton().IsEnabled(true);
}

void OverlayContent::MailReplySendButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto body = to_string(MailReplyBodyBox().Text());
    if (replying_to_mail_id_.empty() || blank_text(body)) {
        MailStatusText().Text(L"请输入回复内容");
        return;
    }
    AppHost::instance().replyMail(replying_to_mail_id_, body);
    replying_to_mail_id_.clear();
    MailReplyBodyBox().Text(L"");
    MailReplyPanel().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
    MailStatusText().Text(L"正在发送回复");
}

void OverlayContent::MailReplyCancelButton_Click(
    Windows::Foundation::IInspectable const&,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    replying_to_mail_id_.clear();
    MailReplyBodyBox().Text(L"");
    MailReplyPanel().Visibility(Microsoft::UI::Xaml::Visibility::Collapsed);
}

void OverlayContent::MailMarkReadButton_Click(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto button = sender.try_as<Microsoft::UI::Xaml::Controls::Button>();
    if (!button) {
        return;
    }
    const auto message_id = to_string(unbox_value_or<hstring>(button.Tag(), L""));
    if (message_id.empty()) {
        return;
    }
    AppHost::instance().markMailRead(std::move(message_id));
    MailStatusText().Text(L"正在标记邮件为已读");
}

void OverlayContent::MailJunkButton_Click(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto button = sender.try_as<Microsoft::UI::Xaml::Controls::Button>();
    if (!button) {
        return;
    }
    const auto message_id = to_string(unbox_value_or<hstring>(button.Tag(), L""));
    if (message_id.empty()) {
        return;
    }
    AppHost::instance().moveMailToJunk(std::move(message_id));
    MailStatusText().Text(L"正在移至垃圾邮件");
}

void OverlayContent::MailDeleteButton_Click(
    Windows::Foundation::IInspectable const& sender,
    Microsoft::UI::Xaml::RoutedEventArgs const&) {
    const auto button = sender.try_as<Microsoft::UI::Xaml::Controls::Button>();
    if (!button) {
        return;
    }
    const auto message_id = to_string(unbox_value_or<hstring>(button.Tag(), L""));
    if (message_id.empty()) {
        return;
    }
    AppHost::instance().deleteMail(std::move(message_id));
    MailStatusText().Text(L"正在删除邮件");
}

std::vector<zisla::core::MailRecipient> OverlayContent::mailRecipients() {
    const auto input = to_string(MailRecipientsBox().Text());
    std::vector<zisla::core::MailRecipient> recipients;
    std::size_t offset = 0;
    while (offset < input.size()) {
        const auto delimiter = input.find_first_of(",;\r\n", offset);
        const auto length = delimiter == std::string::npos
            ? input.size() - offset
            : delimiter - offset;
        auto address = trimmed_mail_field(std::string_view{input}.substr(offset, length));
        if (!address.empty()) {
            recipients.push_back({.email_address = std::move(address)});
        }
        if (delimiter == std::string::npos) {
            break;
        }
        offset = delimiter + 1;
    }
    return recipients;
}

winrt::fire_and_forget OverlayContent::showCalendarEditor(bool reminder) {
    const auto lifetime = get_strong();
    (void)lifetime;
    const TransientUIHold hold;
    try {
        if (!XamlRoot()) {
            co_return;
        }

        using namespace Microsoft::UI::Xaml;
        using namespace Microsoft::UI::Xaml::Controls;

        const auto now_ms = now_unix_milliseconds();
        const auto local_now = CalendarService::localDateTime(now_ms);
        auto selected_date = calendar_snapshot_
            ? calendar_snapshot_->reference_date
            : local_now.date;
        if (calendar_snapshot_ && selected_calendar_day_ordinal_) {
            const auto selected = std::find_if(
                calendar_snapshot_->week_days.begin(),
                calendar_snapshot_->week_days.end(),
                [this](const auto& day) {
                    return day.day_ordinal == *selected_calendar_day_ordinal_;
                });
            if (selected != calendar_snapshot_->week_days.end()) {
                selected_date = selected->date;
            }
        }

        CalendarLocalDateTime start{
            .date = selected_date,
            .hour = 9,
            .minute = 0,
        };
        if (selected_date == local_now.date) {
            start = CalendarService::localDateTime(now_ms + 3'600'000);
            start.minute = 0;
        }
        const auto end = CalendarService::localDateTime(
            CalendarService::unixMilliseconds(start) + 3'600'000);

        TextBox title_box;
        title_box.Header(box_value(L"标题"));
        title_box.PlaceholderText(reminder ? L"待办事项" : L"日程标题");
        title_box.MaxLength(200);

        DatePicker start_date_picker;
        start_date_picker.Header(box_value(reminder ? L"截止日期" : L"开始日期"));
        start_date_picker.Date(calendar_picker_date(start.date));
        start_date_picker.HorizontalAlignment(HorizontalAlignment::Stretch);

        TimePicker start_time_picker;
        start_time_picker.Header(box_value(reminder ? L"截止时间" : L"开始时间"));
        start_time_picker.MinuteIncrement(5);
        set_calendar_picker_time(start_time_picker, start.hour, start.minute);
        start_time_picker.Width(150);

        CheckBox all_day_check;
        all_day_check.Content(box_value(L"全天"));
        all_day_check.IsChecked(box_value(false).as<
            Windows::Foundation::IReference<bool>>());

        DatePicker end_date_picker;
        TimePicker end_time_picker;
        if (!reminder) {
            end_date_picker.Header(box_value(L"结束日期"));
            end_date_picker.Date(calendar_picker_date(end.date));
            end_date_picker.HorizontalAlignment(HorizontalAlignment::Stretch);
            end_time_picker.Header(box_value(L"结束时间"));
            end_time_picker.MinuteIncrement(5);
            set_calendar_picker_time(end_time_picker, end.hour, end.minute);
            end_time_picker.Width(150);
        }

        const auto make_date_time_row = [](const DatePicker& date, const TimePicker& time) {
            Grid row;
            row.ColumnSpacing(8);
            ColumnDefinition date_column;
            date_column.Width(GridLength{1, GridUnitType::Star});
            row.ColumnDefinitions().Append(date_column);
            ColumnDefinition time_column;
            time_column.Width(GridLength{150, GridUnitType::Pixel});
            row.ColumnDefinitions().Append(time_column);
            row.Children().Append(date);
            Grid::SetColumn(time, 1);
            row.Children().Append(time);
            return row;
        };
        const auto start_row = make_date_time_row(
            start_date_picker,
            start_time_picker);
        Grid end_row;
        if (!reminder) {
            end_row = make_date_time_row(end_date_picker, end_time_picker);
        }

        const auto update_time_enabled = [=]() {
            const bool all_day = unbox_value_or<bool>(all_day_check.IsChecked(), false);
            start_time_picker.IsEnabled(!all_day);
            if (!reminder) {
                end_time_picker.IsEnabled(!all_day);
            }
        };
        all_day_check.Checked([update_time_enabled](auto&&, auto&&) {
            update_time_enabled();
        });
        all_day_check.Unchecked([update_time_enabled](auto&&, auto&&) {
            update_time_enabled();
        });
        update_time_enabled();

        TextBlock error_text;
        error_text.TextWrapping(TextWrapping::Wrap);
        error_text.Visibility(Visibility::Collapsed);
        Automation::AutomationProperties::SetName(error_text, L"日程输入错误");

        StackPanel panel;
        panel.Spacing(12);
        panel.MinWidth(360);
        panel.Children().Append(title_box);
        panel.Children().Append(all_day_check);
        panel.Children().Append(start_row);
        if (!reminder) {
            panel.Children().Append(end_row);
        }
        panel.Children().Append(error_text);

        ContentDialog dialog;
        dialog.XamlRoot(XamlRoot());
        dialog.Title(box_value(reminder ? L"新建待办" : L"新建日程"));
        dialog.Content(panel);
        dialog.PrimaryButtonText(L"创建");
        dialog.CloseButtonText(L"取消");
        dialog.DefaultButton(ContentDialogButton::Primary);

        dialog.PrimaryButtonClick([=](
            ContentDialog const&,
            ContentDialogButtonClickEventArgs const& args) {
            try {
                const auto title = zisla::core::CalendarEngine::normalized_title(
                    to_string(title_box.Text()));
                const bool all_day = unbox_value_or<bool>(
                    all_day_check.IsChecked(),
                    false);
                const auto start_date = calendar_picker_civil_date(start_date_picker);
                const auto [start_hour, start_minute] = all_day
                    ? std::pair{0, 0}
                    : calendar_picker_time(start_time_picker);

                if (reminder) {
                    (void)zisla::core::CalendarEngine::validated(
                        zisla::core::CalendarReminderDraft{
                            .title = title,
                            .due_unix_ms = CalendarService::unixMilliseconds({
                                .date = start_date,
                                .hour = start_hour,
                                .minute = start_minute,
                            }),
                            .is_all_day = all_day,
                        });
                    AppHost::instance().createCalendarReminder(
                        title,
                        start_date,
                        start_hour,
                        start_minute,
                        all_day);
                } else {
                    const auto end_date = calendar_picker_civil_date(end_date_picker);
                    const auto [end_hour, end_minute] = all_day
                        ? std::pair{0, 0}
                        : calendar_picker_time(end_time_picker);
                    const auto start_ms = CalendarService::unixMilliseconds({
                        .date = start_date,
                        .hour = start_hour,
                        .minute = start_minute,
                    });
                    const auto end_ms = CalendarService::unixMilliseconds({
                        .date = all_day
                            ? zisla::core::CalendarEngine::add_days(end_date, 1)
                            : end_date,
                        .hour = end_hour,
                        .minute = end_minute,
                    });
                    (void)zisla::core::CalendarEngine::validated(
                        zisla::core::CalendarEventDraft{
                            .title = title,
                            .start_unix_ms = start_ms,
                            .end_unix_ms = end_ms,
                            .is_all_day = all_day,
                        });
                    AppHost::instance().createCalendarEvent(
                        title,
                        start_date,
                        start_hour,
                        start_minute,
                        end_date,
                        end_hour,
                        end_minute,
                        all_day);
                }

                error_text.Visibility(Visibility::Collapsed);
            } catch (const winrt::hresult_error& error) {
                error_text.Text(error.message());
                error_text.Visibility(Visibility::Visible);
                args.Cancel(true);
            } catch (const std::exception& error) {
                error_text.Text(from_utf8(error.what()));
                error_text.Visibility(Visibility::Visible);
                args.Cancel(true);
            }
        });

        (void)co_await dialog.ShowAsync();
    } catch (const winrt::hresult_error& error) {
        AgendaStatusText().Text(error.message());
    } catch (const std::exception& error) {
        AgendaStatusText().Text(from_utf8(error.what()));
    }
}

}
