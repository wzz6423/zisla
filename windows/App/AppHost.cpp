#include "pch.h"
#include "AppHost.h"
#include "AppNotificationService.h"
#include "AppPersistenceService.h"
#include "AIAgentSkillsService.h"
#include "AIAgentWorkspaceService.h"
#include "AIStateMonitor.h"
#include "BrowserDownloadService.h"
#include "CameraMirrorService.h"
#include "CameraMirrorWindow.h"
#include "CalendarService.h"
#include "ClaudeActivityMonitor.h"
#include "CodexActivityMonitor.h"
#include "GeminiActivityMonitor.h"
#include "GrokActivityMonitor.h"
#include "HarnessActivityMonitor.h"
#include "KimiActivityMonitor.h"
#include "QwenActivityMonitor.h"
#include "TraeActivityMonitor.h"
#include "WorkBuddyActivityMonitor.h"
#include "ClipboardHistoryService.h"
#include "CleaningWindow.h"
#include "DisplayTopology.h"
#include "DesktopToolsService.h"
#include "DiskCleanupService.h"
#include "DownloadService.h"
#include "FileActivityMonitor.h"
#include "FileShelfService.h"
#include "MediaSessionMonitor.h"
#include "OverlayWindow.h"
#include "PetWindow.h"
#include "PowerRequestService.h"
#include "PDFProcessingService.hpp"
#include "QuickNotesService.h"
#include "SettingsWindow.h"
#include "SideNoticeWindow.h"
#include "SystemMonitorService.h"
#include "TaskbarWidgetWindow.h"
#include "TeleprompterWindow.h"
#include "WeatherLocationService.h"
#include "WeatherService.h"
#include "VoiceInputService.h"

#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <shlobj.h>
#include <shobjidl_core.h>

#include <zisla/core/AIActivityMerger.hpp>
#include <zisla/core/CopilotSessionScanner.hpp>
#include <zisla/core/DoubaoSessionScanner.hpp>
#include <zisla/core/OpenCodeSessionScanner.hpp>
#include <zisla/core/QoderSessionScanner.hpp>
#include <zisla/core/VoiceHotkey.hpp>

#include <algorithm>
#include <array>
#include <chrono>
#include <cctype>
#include <exception>
#include <fstream>
#include <iterator>
#include <limits>
#include <stdexcept>
#include <system_error>
#include <utility>
#include <vector>

#include <tlhelp32.h>

namespace winrt::Zisla {
namespace {

constexpr std::int64_t alarm_delivery_grace_ms = 5 * 60 * 1'000;
constexpr wchar_t message_window_class[] = L"Zisla.MessageWindow";
constexpr UINT menu_open = 1;
constexpr UINT menu_settings = 2;
constexpr UINT menu_top_edge = 3;
constexpr UINT menu_exit = 4;
constexpr std::string_view current_application_version = "0.1.2";

using PathList = std::vector<std::filesystem::path>;

bool ascii_ends_with_case_insensitive(
    std::string_view value,
    std::string_view suffix) noexcept {
    if (value.size() < suffix.size()) {
        return false;
    }
    const auto offset = value.size() - suffix.size();
    for (std::size_t index = 0; index < suffix.size(); ++index) {
        auto left = value[offset + index];
        auto right = suffix[index];
        if (left >= 'A' && left <= 'Z') {
            left = static_cast<char>(left - 'A' + 'a');
        }
        if (right >= 'A' && right <= 'Z') {
            right = static_cast<char>(right - 'A' + 'a');
        }
        if (left != right) {
            return false;
        }
    }
    return true;
}

std::string update_install_url(const zisla::core::AvailableUpdate& update) {
    const auto appinstaller = std::find_if(
        update.release.assets.begin(),
        update.release.assets.end(),
        [](const zisla::core::ReleaseAsset& asset) {
            return ascii_ends_with_case_insensitive(asset.name, ".appinstaller");
        });
    return appinstaller == update.release.assets.end()
        ? update.release.html_url
        : appinstaller->download_url;
}

void append_unique_path(PathList& paths, std::filesystem::path path) {
    if (path.empty()) {
        return;
    }
    path = path.lexically_normal();
    if (std::find(paths.begin(), paths.end(), path) == paths.end()) {
        paths.push_back(std::move(path));
    }
}

std::optional<std::filesystem::path> known_folder_path(
    REFKNOWNFOLDERID folder) noexcept {
    PWSTR raw = nullptr;
    if (FAILED(SHGetKnownFolderPath(folder, KF_FLAG_DEFAULT, nullptr, &raw))) {
        return std::nullopt;
    }
    try {
        auto result = std::filesystem::path{raw};
        CoTaskMemFree(raw);
        return result;
    } catch (...) {
        CoTaskMemFree(raw);
        return std::nullopt;
    }
}

std::optional<std::filesystem::path> environment_path(
    const wchar_t* name) noexcept {
    const auto required = GetEnvironmentVariableW(name, nullptr, 0);
    if (required == 0) {
        return std::nullopt;
    }
    try {
        std::wstring value(required, L'\0');
        const auto length = GetEnvironmentVariableW(
            name,
            value.data(),
            static_cast<DWORD>(value.size()));
        if (length == 0 || length >= value.size()) {
            return std::nullopt;
        }
        value.resize(length);
        const auto first = value.find_first_not_of(L" \t\r\n\f\v");
        if (first == std::wstring::npos) {
            return std::nullopt;
        }
        const auto last = value.find_last_not_of(L" \t\r\n\f\v");
        return std::filesystem::path{value.substr(first, last - first + 1)};
    } catch (...) {
        return std::nullopt;
    }
}

PathList default_copilot_workspace_storage_roots() noexcept {
    try {
        PathList roots;
        const auto roaming = known_folder_path(FOLDERID_RoamingAppData);
        if (!roaming) {
            return roots;
        }
        constexpr const wchar_t* application_names[]{
            L"Code",
            L"Code - Insiders",
            L"Cursor",
            L"VSCodium",
            L"Windsurf",
        };
        for (const auto* application_name : application_names) {
            append_unique_path(
                roots,
                *roaming / application_name / L"User" / L"workspaceStorage");
        }
        return roots;
    } catch (...) {
        return {};
    }
}

std::filesystem::path default_copilot_cli_session_state_directory() noexcept {
    try {
        const auto profile = known_folder_path(FOLDERID_Profile);
        return profile ? *profile / L".copilot" / L"session-state"
                       : std::filesystem::path{};
    } catch (...) {
        return {};
    }
}

PathList default_qoder_config_roots() noexcept {
    try {
        PathList roots;
        if (const auto profile = known_folder_path(FOLDERID_Profile)) {
            append_unique_path(roots, *profile / L".qoder");
        }
        if (const auto roaming = known_folder_path(FOLDERID_RoamingAppData)) {
            append_unique_path(roots, *roaming / L"Qoder");
        }
        if (const auto local = known_folder_path(FOLDERID_LocalAppData)) {
            append_unique_path(roots, *local / L"Qoder");
        }
        return roots;
    } catch (...) {
        return {};
    }
}

PathList default_qoder_text_log_roots(
    const PathList& config_roots) noexcept {
    try {
        PathList roots = config_roots;
        if (const auto roaming = known_folder_path(FOLDERID_RoamingAppData)) {
            append_unique_path(roots, *roaming / L"Qoder" / L"logs");
            append_unique_path(roots, *roaming / L"QoderWork" / L"logs");
        }
        if (const auto local = known_folder_path(FOLDERID_LocalAppData)) {
            append_unique_path(roots, *local / L"Qoder" / L"logs");
            append_unique_path(roots, *local / L"QoderWork" / L"logs");
        }
        return roots;
    } catch (...) {
        return {};
    }
}

PathList default_doubao_data_roots() noexcept {
    try {
        PathList roots;
        if (const auto roaming = known_folder_path(FOLDERID_RoamingAppData)) {
            append_unique_path(roots, *roaming / L"Doubao");
        }
        if (const auto local = known_folder_path(FOLDERID_LocalAppData)) {
            append_unique_path(roots, *local / L"Doubao");
        }
        return roots;
    } catch (...) {
        return {};
    }
}

bool doubao_process_is_running() noexcept {
    const auto raw_snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (raw_snapshot == INVALID_HANDLE_VALUE) {
        return false;
    }
    winrt::handle snapshot;
    snapshot.attach(raw_snapshot);

    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    if (!Process32FirstW(snapshot.get(), &entry)) {
        return false;
    }
    do {
        if (lstrcmpiW(entry.szExeFile, L"Doubao.exe") == 0
            || lstrcmpiW(entry.szExeFile, L"DoubaoDesktop.exe") == 0
            || lstrcmpiW(entry.szExeFile, L"DoubaoAI.exe") == 0) {
            return true;
        }
    } while (Process32NextW(snapshot.get(), &entry));
    return false;
}

PathList default_opencode_data_roots() noexcept {
    try {
        if (const auto xdg_data = environment_path(L"XDG_DATA_HOME")) {
            return {*xdg_data / L"opencode"};
        }
        if (const auto profile = known_folder_path(FOLDERID_Profile)) {
            return {*profile / L".local" / L"share" / L"opencode"};
        }
        return {};
    } catch (...) {
        return {};
    }
}

std::optional<std::filesystem::path> configured_opencode_database_path(
    const PathList& data_roots) noexcept {
    const auto configured = environment_path(L"OPENCODE_DB");
    if (!configured) {
        return std::nullopt;
    }
    if (configured->is_absolute() || data_roots.empty()) {
        return configured;
    }
    try {
        return data_roots.front() / *configured;
    } catch (...) {
        return std::nullopt;
    }
}

bool is_opencode_database_name(const std::filesystem::path& path) {
    const auto name = path.filename().wstring();
    return name == L"opencode.db"
        || (name.starts_with(L"opencode-") && name.ends_with(L".db"));
}

PathList opencode_database_paths(
    const PathList& data_roots,
    const std::optional<std::filesystem::path>& configured_database) {
    PathList paths;
    if (configured_database) {
        append_unique_path(paths, *configured_database);
    }
    for (const auto& root : data_roots) {
        append_unique_path(paths, root / L"opencode.db");

        std::error_code error;
        std::filesystem::directory_iterator iterator(
            root,
            std::filesystem::directory_options::skip_permission_denied,
            error);
        const std::filesystem::directory_iterator end;
        while (!error && iterator != end) {
            const auto entry = *iterator;
            std::error_code status_error;
            const auto status = entry.symlink_status(status_error);
            if (!status_error && std::filesystem::is_regular_file(status)
                && !std::filesystem::is_symlink(status)
                && is_opencode_database_name(entry.path())) {
                append_unique_path(paths, entry.path());
            }
            iterator.increment(error);
        }
    }
    return paths;
}

std::int64_t now_unix_milliseconds() noexcept {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

std::int64_t monotonic_milliseconds() noexcept {
    const auto value = GetTickCount64();
    const auto maximum = static_cast<ULONGLONG>(
        std::numeric_limits<std::int64_t>::max());
    return value > maximum
        ? std::numeric_limits<std::int64_t>::max()
        : static_cast<std::int64_t>(value);
}

std::string ai_task_key(const zisla::core::AIProgressTask& task) {
    std::string result{zisla::core::ai_provider_token(task.provider)};
    result.push_back(':');
    result.append(task.id);
    return result;
}

std::string active_ai_notice_id(const zisla::core::AIProgressTask& task) {
    std::string result{"ai-active-"};
    result.append(zisla::core::ai_provider_token(task.provider));
    result.push_back('-');
    result.append(task.id);
    return result;
}

std::string browser_download_display_name(
    const zisla::core::BrowserDownloadItem& item) {
    const auto& path = item.target_path.empty()
        ? item.current_path
        : item.target_path;
    const auto separator = path.find_last_of("\\/");
    return separator == std::string::npos
        ? path
        : path.substr(separator + 1);
}

zisla::core::NoticeSide notice_side(zisla::core::AIProvider provider) noexcept {
    using zisla::core::AIProvider;
    switch (provider) {
    case AIProvider::claude:
    case AIProvider::gemini:
    case AIProvider::qwen:
    case AIProvider::trae:
    case AIProvider::doubao:
        return zisla::core::NoticeSide::left;
    case AIProvider::codex:
    case AIProvider::grok:
    case AIProvider::gpt:
    case AIProvider::copilot:
    case AIProvider::kimi:
    case AIProvider::coder:
    case AIProvider::opencode:
    case AIProvider::harness:
        return zisla::core::NoticeSide::right;
    }
    return zisla::core::NoticeSide::right;
}

bool custom_notifications_allowed() noexcept {
    QUERY_USER_NOTIFICATION_STATE state{};
    return FAILED(SHQueryUserNotificationState(&state))
        || state == QUNS_ACCEPTS_NOTIFICATIONS;
}

Windows::Foundation::IAsyncOperation<
    Windows::Foundation::Collections::IVector<Windows::Storage::IStorageItem>>
resolve_storage_items(
    std::vector<std::filesystem::path> paths) {
    using namespace Windows::Storage;

    auto storage_items = single_threaded_vector<IStorageItem>();
    for (const auto& path : paths) {
        if (path.empty()) {
            continue;
        }
        try {
            storage_items.Append(
                co_await StorageFile::GetFileFromPathAsync(path.c_str()));
            continue;
        } catch (...) {
        }
        try {
            storage_items.Append(
                co_await StorageFolder::GetFolderFromPathAsync(path.c_str()));
        } catch (...) {
        }
    }
    co_return storage_items;
}

winrt::fire_and_forget copy_paths_to_clipboard(
    std::vector<std::filesystem::path> paths) {
    using namespace Windows::ApplicationModel::DataTransfer;

    try {
        const auto storage_items = co_await resolve_storage_items(std::move(paths));
        if (storage_items.Size() == 0) {
            co_return;
        }
        DataPackage package;
        package.RequestedOperation(DataPackageOperation::Copy);
        package.SetStorageItems(storage_items);
        Clipboard::SetContent(package);
        Clipboard::Flush();
        AppHost::instance().ignoreCurrentClipboardSequence();
    } catch (...) {
    }
}

bool contains(const zisla::core::PixelRect& bounds, POINT point) noexcept {
    return point.x >= bounds.x && point.x < bounds.right()
        && point.y >= bounds.y && point.y < bounds.bottom();
}

std::optional<std::filesystem::path> teleprompter_script_path() noexcept {
    try {
        const auto folder = Windows::Storage::ApplicationData::Current().LocalFolder();
        if (!folder || folder.Path().empty()) {
            return std::nullopt;
        }
        return std::filesystem::path{folder.Path().c_str()} / L"teleprompter.txt";
    } catch (...) {
        return std::nullopt;
    }
}

std::optional<std::filesystem::path> application_state_directory() noexcept {
    try {
        const auto folder = Windows::Storage::ApplicationData::Current().LocalFolder();
        if (!folder || folder.Path().empty()) {
            return std::nullopt;
        }
        return std::filesystem::path{folder.Path().c_str()};
    } catch (...) {
        return std::nullopt;
    }
}

std::optional<std::filesystem::path> application_temporary_directory() noexcept {
    try {
        const auto folder = Windows::Storage::ApplicationData::Current().TemporaryFolder();
        if (!folder || folder.Path().empty()) {
            return std::nullopt;
        }
        return std::filesystem::path{folder.Path().c_str()};
    } catch (...) {
        return std::nullopt;
    }
}

std::optional<std::filesystem::path> module_directory() noexcept {
    try {
        std::array<wchar_t, 32'768> buffer{};
        const auto length = GetModuleFileNameW(
            nullptr,
            buffer.data(),
            static_cast<DWORD>(buffer.size()));
        if (length == 0 || length >= buffer.size()) {
            return std::nullopt;
        }
        return std::filesystem::path{
            std::wstring{buffer.data(), static_cast<std::size_t>(length)}}.parent_path();
    } catch (...) {
        return std::nullopt;
    }
}

std::optional<std::filesystem::path> default_download_directory() noexcept {
    PWSTR value = nullptr;
    if (FAILED(SHGetKnownFolderPath(
            FOLDERID_Downloads,
            KF_FLAG_DEFAULT,
            nullptr,
            &value))) {
        return std::nullopt;
    }
    try {
        auto result = std::filesystem::path{value};
        CoTaskMemFree(value);
        return result;
    } catch (...) {
        CoTaskMemFree(value);
        return std::nullopt;
    }
}

zisla::core::AlarmLocalClock current_alarm_clock() noexcept {
    SYSTEMTIME local{};
    GetLocalTime(&local);
    return {
        .weekday = static_cast<std::uint8_t>(local.wDayOfWeek + 1),
        .hour = local.wHour,
        .minute = local.wMinute,
        .second = local.wSecond,
        .now_unix_ms = now_unix_milliseconds(),
    };
}

std::string new_alarm_id() noexcept {
    try {
        GUID value{};
        if (FAILED(CoCreateGuid(&value))) {
            return {};
        }
        std::array<wchar_t, 40> buffer{};
        if (StringFromGUID2(value, buffer.data(), static_cast<int>(buffer.size())) <= 0) {
            return {};
        }
        return to_string(hstring{buffer.data()});
    } catch (...) {
        return {};
    }
}

std::string load_teleprompter_script() {
    const auto path = teleprompter_script_path();
    if (!path) {
        return {};
    }
    std::error_code error;
    const auto size = std::filesystem::file_size(*path, error);
    if (error
        || size > AppPersistenceService::maximum_teleprompter_script_bytes) {
        return {};
    }
    std::ifstream stream(*path, std::ios::binary);
    if (!stream) {
        return {};
    }
    return {
        std::istreambuf_iterator<char>{stream},
        std::istreambuf_iterator<char>{},
    };
}

}

AppHost& AppHost::instance() {
    static AppHost host;
    return host;
}

void AppHost::loadSettings() {
    try {
        const auto local = winrt::Windows::Storage::ApplicationData::Current().LocalSettings();
        const auto values = local.Values();
        if (values.HasKey(L"TopEdgeEnabled")) {
            const auto value = values.Lookup(L"TopEdgeEnabled");
            instance().top_edge_enabled_ = winrt::unbox_value_or<bool>(value, true);
        }
        if (values.HasKey(L"TaskbarWidgetEnabled")) {
            const auto value = values.Lookup(L"TaskbarWidgetEnabled");
            instance().taskbar_widget_enabled_ =
                winrt::unbox_value_or<bool>(value, true);
        }
        if (values.HasKey(L"PetEnabled")) {
            const auto value = values.Lookup(L"PetEnabled");
            instance().settings_.pet_enabled =
                winrt::unbox_value_or<bool>(value, true);
        }
        if (values.HasKey(L"PetId")) {
            const auto value = winrt::unbox_value_or<hstring>(
                values.Lookup(L"PetId"),
                L"dog");
            const auto id = to_string(value);
            if (!id.empty() && id.size() <= 64) {
                instance().settings_.pet_id = id;
            }
        }
        if (values.HasKey(L"PetSide")) {
            const auto value = winrt::unbox_value_or<hstring>(
                values.Lookup(L"PetSide"),
                L"right");
            instance().settings_.pet_side = value == L"left"
                ? zisla::core::PetSide::left
                : zisla::core::PetSide::right;
        }
        if (values.HasKey(L"SideNoticesEnabled")) {
            const auto value = values.Lookup(L"SideNoticesEnabled");
            instance().settings_.side_notices_enabled =
                winrt::unbox_value_or<bool>(value, true);
        }
        if (values.HasKey(L"NotificationsMuted")) {
            const auto value = values.Lookup(L"NotificationsMuted");
            instance().settings_.notifications_muted =
                winrt::unbox_value_or<bool>(value, false);
        }
        if (values.HasKey(L"ClipboardHistoryEnabled")) {
            const auto value = values.Lookup(L"ClipboardHistoryEnabled");
            instance().settings_.clipboard_history_enabled =
                winrt::unbox_value_or<bool>(value, false);
        }
        if (values.HasKey(L"ClipboardDetectionEnabled")) {
            const auto value = values.Lookup(L"ClipboardDetectionEnabled");
            instance().settings_.clipboard_detection_enabled =
                winrt::unbox_value_or<bool>(value, false);
        }
        if (values.HasKey(L"WeatherEnabled")) {
            const auto value = values.Lookup(L"WeatherEnabled");
            instance().settings_.weather_enabled =
                winrt::unbox_value_or<bool>(value, true);
        }
        if (values.HasKey(L"BrowserDownloadStatusEnabled")) {
            const auto value = values.Lookup(L"BrowserDownloadStatusEnabled");
            instance().settings_.browser_download_status_enabled =
                winrt::unbox_value_or<bool>(value, true);
        }
        if (values.HasKey(L"VoiceInputEnabled")) {
            const auto value = values.Lookup(L"VoiceInputEnabled");
            instance().settings_.voice_input_enabled =
                winrt::unbox_value_or<bool>(value, false);
        }
        if (values.HasKey(L"VoiceHotkeyAction")) {
            const auto value = winrt::unbox_value_or<hstring>(
                values.Lookup(L"VoiceHotkeyAction"),
                L"toggle");
            const auto action = zisla::core::voice_hotkey_action_from_token(
                to_string(value));
            if (action) {
                instance().settings_.voice_hotkey_action = *action;
            }
        }
        if (values.HasKey(L"VoiceHotkeyPreset")) {
            const auto value = winrt::unbox_value_or<hstring>(
                values.Lookup(L"VoiceHotkeyPreset"),
                L"control-alt-v");
            const auto preset = zisla::core::voice_hotkey_preset_from_token(
                to_string(value));
            if (preset) {
                instance().settings_.voice_hotkey_preset = *preset;
            }
        }
        if (values.HasKey(L"PomodoroFocusDurationSeconds")) {
            const auto value = values.Lookup(L"PomodoroFocusDurationSeconds");
            const auto seconds = winrt::unbox_value_or<std::int64_t>(
                value,
                zisla::core::PomodoroEngine::default_focus_duration_seconds);
            instance().pomodoro_engine_.set_duration_seconds(
                zisla::core::PomodoroMode::focus,
                seconds);
        }
        if (values.HasKey(L"PomodoroRestDurationSeconds")) {
            const auto value = values.Lookup(L"PomodoroRestDurationSeconds");
            const auto seconds = winrt::unbox_value_or<std::int64_t>(
                value,
                zisla::core::PomodoroEngine::default_rest_duration_seconds);
            instance().pomodoro_engine_.set_duration_seconds(
                zisla::core::PomodoroMode::rest,
                seconds);
        }
        if (values.HasKey(L"TeleprompterScrollSpeed")) {
            const auto value = values.Lookup(L"TeleprompterScrollSpeed");
            instance().teleprompter_engine_.set_scroll_speed(
                winrt::unbox_value_or<double>(
                    value,
                    zisla::core::TeleprompterEngine::default_scroll_speed));
        }
        if (values.HasKey(L"DownloadDirectory")) {
            const auto value = winrt::unbox_value_or<hstring>(
                values.Lookup(L"DownloadDirectory"),
                L"");
            const std::filesystem::path path{value.c_str()};
            std::error_code error;
            if (path.is_absolute()
                && std::filesystem::is_directory(path, error)
                && !error) {
                instance().download_output_directory_ = path;
            }
        }
        if (values.HasKey(L"MailTenant")) {
            const auto tenant = to_string(winrt::unbox_value_or<hstring>(
                values.Lookup(L"MailTenant"),
                L"common"));
            if (!tenant.empty() && tenant.size() <= 128) {
                instance().mail_connection_settings_.tenant = tenant;
            }
        }
        if (values.HasKey(L"MailClientId")) {
            const auto client_id = to_string(winrt::unbox_value_or<hstring>(
                values.Lookup(L"MailClientId"),
                L""));
            if (client_id.size()
                <= zisla::core::GraphOAuthRequestBuilder::maximum_client_id_bytes) {
                instance().mail_connection_settings_.client_id = client_id;
            }
        }
        if (values.HasKey(L"MailAccountName")) {
            const auto account_name = to_string(winrt::unbox_value_or<hstring>(
                values.Lookup(L"MailAccountName"),
                L""));
            if (account_name.size() <= 256) {
                instance().mail_connection_settings_.account_name = account_name;
            }
        }
        if (values.HasKey(L"UpdateChannel")) {
            const auto channel = zisla::core::update_channel_from_token(to_string(
                winrt::unbox_value_or<hstring>(
                    values.Lookup(L"UpdateChannel"),
                    L"release")));
            if (channel) {
                instance().update_channel_ = *channel;
            }
        }
        instance().teleprompter_engine_.set_script(load_teleprompter_script());
    } catch (...) {
    }
}

void AppHost::saveSettings() {
    try {
        const auto local = winrt::Windows::Storage::ApplicationData::Current().LocalSettings();
        const auto values = local.Values();
        const bool replaced = values.Insert(
            L"TopEdgeEnabled",
            winrt::box_value(instance().top_edge_enabled_));
        (void)replaced;
        const bool taskbar_widget_replaced = values.Insert(
            L"TaskbarWidgetEnabled",
            winrt::box_value(instance().taskbar_widget_enabled_));
        (void)taskbar_widget_replaced;
        const bool pet_enabled_replaced = values.Insert(
            L"PetEnabled",
            winrt::box_value(instance().settings_.pet_enabled));
        (void)pet_enabled_replaced;
        const bool pet_id_replaced = values.Insert(
            L"PetId",
            winrt::box_value(to_hstring(instance().settings_.pet_id)));
        (void)pet_id_replaced;
        const bool pet_side_replaced = values.Insert(
            L"PetSide",
            winrt::box_value(hstring{
                instance().settings_.pet_side == zisla::core::PetSide::left
                    ? L"left"
                    : L"right"}));
        (void)pet_side_replaced;
        const bool side_notices_replaced = values.Insert(
            L"SideNoticesEnabled",
            winrt::box_value(instance().settings_.side_notices_enabled));
        (void)side_notices_replaced;
        const bool notifications_muted_replaced = values.Insert(
            L"NotificationsMuted",
            winrt::box_value(instance().settings_.notifications_muted));
        (void)notifications_muted_replaced;
        const bool clipboard_history_replaced = values.Insert(
            L"ClipboardHistoryEnabled",
            winrt::box_value(instance().settings_.clipboard_history_enabled));
        (void)clipboard_history_replaced;
        const bool clipboard_detection_replaced = values.Insert(
            L"ClipboardDetectionEnabled",
            winrt::box_value(instance().settings_.clipboard_detection_enabled));
        (void)clipboard_detection_replaced;
        const bool weather_replaced = values.Insert(
            L"WeatherEnabled",
            winrt::box_value(instance().settings_.weather_enabled));
        (void)weather_replaced;
        const bool browser_download_status_replaced = values.Insert(
            L"BrowserDownloadStatusEnabled",
            winrt::box_value(instance().settings_.browser_download_status_enabled));
        (void)browser_download_status_replaced;
        const bool voice_input_replaced = values.Insert(
            L"VoiceInputEnabled",
            winrt::box_value(instance().settings_.voice_input_enabled));
        (void)voice_input_replaced;
        const bool voice_hotkey_action_replaced = values.Insert(
            L"VoiceHotkeyAction",
            winrt::box_value(to_hstring(
                zisla::core::voice_hotkey_action_token(
                    instance().settings_.voice_hotkey_action))));
        (void)voice_hotkey_action_replaced;
        const bool voice_hotkey_preset_replaced = values.Insert(
            L"VoiceHotkeyPreset",
            winrt::box_value(to_hstring(
                zisla::core::voice_hotkey_preset_token(
                    instance().settings_.voice_hotkey_preset))));
        (void)voice_hotkey_preset_replaced;
        const bool pomodoro_focus_replaced = values.Insert(
            L"PomodoroFocusDurationSeconds",
            winrt::box_value(instance().pomodoro_engine_.duration_seconds(
                zisla::core::PomodoroMode::focus)));
        (void)pomodoro_focus_replaced;
        const bool pomodoro_rest_replaced = values.Insert(
            L"PomodoroRestDurationSeconds",
            winrt::box_value(instance().pomodoro_engine_.duration_seconds(
                zisla::core::PomodoroMode::rest)));
        (void)pomodoro_rest_replaced;
        const bool teleprompter_speed_replaced = values.Insert(
            L"TeleprompterScrollSpeed",
            winrt::box_value(instance().teleprompter_engine_.scroll_speed()));
        (void)teleprompter_speed_replaced;
        if (!instance().download_output_directory_.empty()) {
            const bool download_directory_replaced = values.Insert(
                L"DownloadDirectory",
                winrt::box_value(hstring{
                    instance().download_output_directory_.c_str()}));
            (void)download_directory_replaced;
        }
        const bool mail_tenant_replaced = values.Insert(
            L"MailTenant",
            winrt::box_value(to_hstring(instance().mail_connection_settings_.tenant)));
        (void)mail_tenant_replaced;
        const bool mail_client_id_replaced = values.Insert(
            L"MailClientId",
            winrt::box_value(to_hstring(instance().mail_connection_settings_.client_id)));
        (void)mail_client_id_replaced;
        const bool mail_account_name_replaced = values.Insert(
            L"MailAccountName",
            winrt::box_value(to_hstring(instance().mail_connection_settings_.account_name)));
        (void)mail_account_name_replaced;
        const bool update_channel_replaced = values.Insert(
            L"UpdateChannel",
            winrt::box_value(to_hstring(
                zisla::core::update_channel_token(instance().update_channel_))));
        (void)update_channel_replaced;
    } catch (...) {
    }
}

AppHost::~AppHost() {
    shutdown();
}

void AppHost::start() {
    if (started_) {
        return;
    }

    createMessageWindow();
    const auto executable_directory = module_directory();
    if (download_output_directory_.empty()) {
        if (const auto directory = default_download_directory()) {
            download_output_directory_ = *directory;
        }
    }
    power_request_service_ = std::make_unique<PowerRequestService>();
    power_request_controller_ = std::make_unique<zisla::core::PowerRequestController>(
        *power_request_service_);
    overlay_window_ = std::make_unique<OverlayWindow>();
    const auto pdf_message_window = message_window_;
    pdf_processing_service_ = std::make_unique<zisla::pdf::PDFProcessingService>(
        [pdf_message_window] {
            if (pdf_message_window) {
                (void)PostMessageW(
                    pdf_message_window,
                    AppHost::pdf_processing_changed_message,
                    0,
                    0);
            }
        });
    (void)pdf_processing_service_->start();
    refreshPDFProcessing();
    refreshVoiceInput();
    refreshVoiceHotkey();
    taskbar_widget_window_ = std::make_unique<TaskbarWidgetWindow>();
    if (executable_directory) {
        pet_entries_ = zisla::core::PetLibrary::entries(
            *executable_directory / L"Assets" / L"Pets");
        if (settings_.pet_enabled) {
            (void)loadSelectedPet();
        }
    }
    notification_service_ = std::make_unique<AppNotificationService>();
    launch_unix_ms_ = now_unix_milliseconds();
    started_ = true;
    loadAlarms();
    (void)notification_service_->start(
        message_window_,
        notification_activated_message,
        alarm_notifications_changed_message);
    reconcileAndRescheduleAlarms();
    refreshPomodoro();
    refreshAlarms();
    refreshPowerRequests();
    refreshCleaning();

    if (const auto state_directory = application_state_directory()) {
        weather_location_repository_ =
            std::make_unique<zisla::core::WeatherLocationRepository>(
                *state_directory / L"weather-locations.json");
        try {
            weather_locations_ = weather_location_repository_->load();
        } catch (const std::exception& error) {
            weather_locations_ = {zisla::core::WeatherLocation::current()};
            weather_storage_error_ = error.what();
        }
    } else {
        weather_locations_ = {zisla::core::WeatherLocation::current()};
        weather_storage_error_ = "无法访问天气地点存储";
    }
    if (settings_.weather_enabled) {
        startWeatherService();
    }
    refreshWeatherView();

    if (settings_.file_shelf_enabled) {
        if (const auto state_directory = AIStateMonitor::defaultStateDirectory()) {
            file_shelf_service_ = std::make_unique<FileShelfService>(*state_directory);
            if (!file_shelf_service_->start(
                    message_window_,
                    file_shelf_changed_message)) {
                file_shelf_service_.reset();
            }
        }
    }

    updateClipboardListener();

    if (const auto state_directory = application_state_directory()) {
        quick_notes_service_ = std::make_unique<QuickNotesService>(*state_directory);
        if (!quick_notes_service_->start(
                message_window_,
                quick_notes_changed_message)) {
            quick_notes_service_.reset();
        }
    }
    if (!quick_notes_service_) {
        overlay_window_->setQuickNotes(
            std::make_shared<const QuickNotesServiceSnapshot>(
                QuickNotesServiceSnapshot{
                    .error = "无法访问随记存储",
                    .loading = false,
                }));
    }

    if (const auto state_directory = application_state_directory()) {
        ai_agent_skills_service_ = std::make_unique<AIAgentSkillsService>(
            *state_directory);
        if (!ai_agent_skills_service_->start(
                message_window_,
                ai_agent_skills_changed_message)) {
            ai_agent_skills_service_.reset();
        }
    }
    if (!ai_agent_skills_service_) {
        overlay_window_->setAIAgentSkills(
            std::make_shared<const AIAgentSkillsServiceSnapshot>(
                AIAgentSkillsServiceSnapshot{
                    .error = "无法访问 Skills 存储",
                    .loading = false,
                }));
    } else {
        refreshAIAgentSkills();
    }

    if (const auto state_directory = application_state_directory()) {
        ai_agent_workspace_service_ = std::make_unique<AIAgentWorkspaceService>(
            *state_directory);
        if (!ai_agent_workspace_service_->start(
                message_window_,
                ai_agent_workspace_changed_message)) {
            ai_agent_workspace_service_.reset();
        }
    }
    if (!ai_agent_workspace_service_) {
        overlay_window_->setAIAgentWorkspace(
            std::make_shared<const AIAgentWorkspaceServiceSnapshot>(
                AIAgentWorkspaceServiceSnapshot{
                    .error = "无法访问 AI Agent 工作区",
                    .loading = false,
                }));
    } else {
        refreshAIAgentWorkspace();
    }

    if (const auto state_directory = application_state_directory()) {
        calendar_service_ = std::make_unique<CalendarService>(*state_directory);
        if (!calendar_service_->start(
                message_window_,
                calendar_changed_message)) {
            calendar_service_.reset();
        }
    }
    if (!calendar_service_) {
        overlay_window_->setCalendar(
            std::make_shared<const CalendarServiceSnapshot>(
                CalendarServiceSnapshot{
                    .error = "无法访问日历存储",
                    .loading = false,
                }));
    }

    if (settings_.mail_enabled) {
        (void)startMailService();
    }
    refreshMailView();

    update_service_ = std::make_unique<UpdateService>(
        std::string(current_application_version));
    if (!update_service_->start(message_window_, update_changed_message)) {
        update_service_.reset();
    } else {
        update_service_->check(update_channel_);
    }
    refreshUpdate();

    system_monitor_service_ = std::make_unique<SystemMonitorService>();
    if (!system_monitor_service_->start(
            message_window_,
            system_monitor_changed_message)) {
        system_monitor_service_.reset();
        auto unavailable = std::make_shared<SystemMonitorServiceSnapshot>();
        unavailable->error = "无法启动系统监控服务";
        overlay_window_->setSystemMonitor(std::move(unavailable));
    } else {
        refreshSystemMonitor();
    }

    desktop_tools_service_ = std::make_unique<DesktopToolsService>();
    if (!desktop_tools_service_->start(
            message_window_,
            desktop_tools_changed_message)) {
        desktop_tools_service_.reset();
        auto unavailable = std::make_shared<zisla::core::DesktopToolsSnapshot>();
        unavailable->error = "无法启动桌面工具服务";
        overlay_window_->setDesktopTools(std::move(unavailable));
    } else {
        refreshDesktopToolsView();
    }

    disk_cleanup_service_ = std::make_unique<DiskCleanupService>();
    if (!disk_cleanup_service_->start(
            message_window_,
            disk_cleanup_changed_message)) {
        disk_cleanup_service_.reset();
        auto unavailable = std::make_shared<DiskCleanupServiceSnapshot>();
        unavailable->error = "无法启动磁盘清理服务";
        overlay_window_->setDiskCleanup(std::move(unavailable));
    } else {
        refreshDiskCleanup();
    }

    const auto temporary_directory = application_temporary_directory();
    if (executable_directory && temporary_directory) {
        download_service_ = std::make_unique<DownloadService>(
            *executable_directory / L"Tools" / L"yt-dlp.exe",
            std::nullopt,
            *temporary_directory / L"Downloads");
        if (!download_service_->start(message_window_, download_changed_message)) {
            download_service_.reset();
            download_startup_error_ = "无法启动下载服务";
        }
    } else {
        download_startup_error_ = "无法访问下载组件或临时目录";
    }
    refreshDownload();

    if (settings_.browser_download_status_enabled) {
        browser_download_service_ = std::make_unique<BrowserDownloadService>();
        if (!browser_download_service_->start(
                message_window_,
                browser_download_changed_message)) {
            browser_download_service_.reset();
        }
    }
    refreshBrowserDownloads();

    const bool tray_available = tray_icon_.add(message_window_, tray_message);
    bool top_edge_available = false;
    if (top_edge_enabled_) {
        top_edge_available = top_edge_trigger_.start(
            message_window_,
            top_edge_entered_message,
            top_edge_exited_message);
        if (top_edge_available
            && SetTimer(
                message_window_,
                top_edge_timer_id,
                top_edge_poll_interval_ms,
                nullptr) == 0) {
            top_edge_trigger_.stop();
            top_edge_available = false;
        }
        if (!top_edge_available) {
            top_edge_enabled_ = false;
            saveSettings();
        }
    }
    refreshTaskbarWidget();
    if (!tray_available && !top_edge_available
        && (!taskbar_widget_window_ || !taskbar_widget_window_->visible())) {
        showSettings();
    }
    if (settings_.ai_progress_enabled) {
        if (const auto state_directory = AIStateMonitor::defaultStateDirectory()) {
            ai_state_monitor_ = std::make_unique<AIStateMonitor>(*state_directory);
            if (!ai_state_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                ai_state_monitor_.reset();
            }
        }
        if (const auto codex_root = CodexActivityMonitor::defaultCodexRoot()) {
            codex_activity_monitor_ = std::make_unique<CodexActivityMonitor>(
                *codex_root);
            if (!codex_activity_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                codex_activity_monitor_.reset();
            }
        }
        if (const auto projects_root = ClaudeActivityMonitor::defaultProjectsRoot()) {
            claude_activity_monitor_ = std::make_unique<ClaudeActivityMonitor>(
                *projects_root);
            if (!claude_activity_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                claude_activity_monitor_.reset();
            }
        }
        if (const auto sessions_root = GeminiActivityMonitor::defaultSessionsRoot()) {
            gemini_activity_monitor_ = std::make_unique<GeminiActivityMonitor>(
                *sessions_root);
            if (!gemini_activity_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                gemini_activity_monitor_.reset();
            }
        }
        if (const auto sessions_directory = GrokActivityMonitor::defaultSessionsDirectory()) {
            grok_activity_monitor_ = std::make_unique<GrokActivityMonitor>(
                *sessions_directory);
            if (!grok_activity_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                grok_activity_monitor_.reset();
            }
        }
        if (const auto data_directory = HarnessActivityMonitor::defaultDataDirectory()) {
            harness_activity_monitor_ = std::make_unique<HarnessActivityMonitor>(
                *data_directory);
            if (!harness_activity_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                harness_activity_monitor_.reset();
            }
        }
        if (const auto sessions_file = WorkBuddyActivityMonitor::defaultSessionsFile()) {
            workbuddy_activity_monitor_ = std::make_unique<WorkBuddyActivityMonitor>(
                *sessions_file);
            if (!workbuddy_activity_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                workbuddy_activity_monitor_.reset();
            }
        }
        const auto trae_logs_roots = TraeActivityMonitor::defaultLogsRoots();
        if (!trae_logs_roots.empty()) {
            trae_activity_monitor_ = std::make_unique<TraeActivityMonitor>(
                trae_logs_roots);
            if (!trae_activity_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                trae_activity_monitor_.reset();
            }
        }
        if (const auto home_directory = KimiActivityMonitor::defaultHomeDirectory()) {
            kimi_activity_monitor_ = std::make_unique<KimiActivityMonitor>(
                *home_directory);
            if (!kimi_activity_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                kimi_activity_monitor_.reset();
            }
        }
        if (const auto projects_directory = QwenActivityMonitor::defaultProjectsDirectory()) {
            qwen_activity_monitor_ = std::make_unique<QwenActivityMonitor>(
                *projects_directory);
            if (!qwen_activity_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                qwen_activity_monitor_.reset();
            }
        }

        auto copilot_workspace_storage_roots =
            default_copilot_workspace_storage_roots();
        const auto copilot_cli_session_state_directory =
            default_copilot_cli_session_state_directory();
        auto qoder_config_roots = default_qoder_config_roots();
        auto qoder_text_log_roots = default_qoder_text_log_roots(
            qoder_config_roots);
        auto doubao_data_roots = default_doubao_data_roots();
        auto opencode_data_roots = default_opencode_data_roots();
        const auto configured_opencode_database = configured_opencode_database_path(
            opencode_data_roots);

        PathList file_watch_roots;
        for (const auto& root : copilot_workspace_storage_roots) {
            append_unique_path(file_watch_roots, root);
        }
        append_unique_path(file_watch_roots, copilot_cli_session_state_directory);
        for (const auto& root : qoder_config_roots) {
            append_unique_path(file_watch_roots, root);
        }
        for (const auto& root : qoder_text_log_roots) {
            append_unique_path(file_watch_roots, root);
        }
        for (const auto& root : doubao_data_roots) {
            append_unique_path(file_watch_roots, root);
        }
        for (const auto& root : opencode_data_roots) {
            append_unique_path(file_watch_roots, root);
        }
        if (configured_opencode_database) {
            append_unique_path(file_watch_roots, *configured_opencode_database);
        }

        if (!file_watch_roots.empty()) {
            file_activity_monitor_ = std::make_unique<FileActivityMonitor>(
                std::move(file_watch_roots),
                [copilot_workspace_storage_roots =
                     std::move(copilot_workspace_storage_roots),
                    copilot_cli_session_state_directory,
                    qoder_config_roots = std::move(qoder_config_roots),
                    qoder_text_log_roots = std::move(qoder_text_log_roots),
                    doubao_data_roots = std::move(doubao_data_roots),
                    opencode_data_roots = std::move(opencode_data_roots),
                    configured_opencode_database] {
                    FileActivityMonitor::ActivityList activities;
                    const auto append = [&activities](auto next) {
                        activities.insert(
                            activities.end(),
                            std::make_move_iterator(next.begin()),
                            std::make_move_iterator(next.end()));
                    };

                    if (!copilot_workspace_storage_roots.empty()
                        || !copilot_cli_session_state_directory.empty()) {
                        const zisla::core::CopilotSessionScanner scanner({
                            .workspace_storage_roots = copilot_workspace_storage_roots,
                            .cli_session_state_directory =
                                copilot_cli_session_state_directory,
                            .max_transcript_files = 12,
                            .max_cli_sessions = 12,
                            .initial_tail_bytes = 1U * 1024U * 1024U,
                        });
                        append(scanner.active_tasks());
                    }
                    if (!qoder_config_roots.empty() || !qoder_text_log_roots.empty()) {
                        const zisla::core::QoderSessionScanner scanner({
                            .config_roots = qoder_config_roots,
                            .text_log_roots = qoder_text_log_roots,
                            .max_log_files = 16,
                            .initial_tail_bytes = 1U * 1024U * 1024U,
                        });
                        append(scanner.active_tasks());
                    }
                    if (!doubao_data_roots.empty()) {
                        const zisla::core::DoubaoSessionScanner scanner({
                            .data_roots = doubao_data_roots,
                            .max_files = 32,
                            .recency_threshold_ms = 10 * 60 * 1'000,
                            .application_running = doubao_process_is_running(),
                        });
                        append(scanner.active_tasks());
                    }
                    if (opencode_data_roots.empty()
                        && !configured_opencode_database) {
                        return activities;
                    }
                    const zisla::core::OpenCodeSessionScanner scanner({
                        .database_paths = opencode_database_paths(
                            opencode_data_roots,
                            configured_opencode_database),
                        .data_roots = opencode_data_roots,
                        .max_sessions = 10,
                        .max_storage_files = 64,
                        .maximum_json_bytes = 1U * 1024U * 1024U,
                        .recency_threshold_ms = 30 * 60 * 1'000,
                    });
                    append(scanner.active_tasks());
                    return activities;
                });
            if (!file_activity_monitor_->start(
                    message_window_,
                    ai_activity_changed_message)) {
                file_activity_monitor_.reset();
            }
        }
    }
    if (settings_.media_enabled) {
        media_session_monitor_ = std::make_unique<MediaSessionMonitor>();
        if (!media_session_monitor_->start(
                message_window_,
                media_session_changed_message)) {
            media_session_monitor_.reset();
        }
    }
    refreshAIActivities();
    if (external_activation_pending_.exchange(false, std::memory_order_acq_rel)) {
        (void)PostMessageW(message_window_, activate_message, 0, 0);
    }
}

void AppHost::shutdown() noexcept {
    if (!started_ && !message_window_) {
        return;
    }

    // 先阻止挂起的 UI 协程在服务释放后继续提交结果。
    started_ = false;
    cancelScheduledDismiss();
    ++weather_location_generation_;
    weather_location_pending_ = false;
    cancelSideNoticeExpiration();
    cancelVoiceFinalization();
    stopPomodoroTimer();
    stopAlarmTimer();
    stopTeleprompterTimer();
    if (message_window_) {
        KillTimer(message_window_, top_edge_timer_id);
    }
    hideSideNoticeWindows();
    cleaning_windows_.clear();
    cleaning_session_.stop();
    cleaning_power_state_.reset();
    teleprompter_engine_.pause();
    if (camera_mirror_window_) {
        camera_mirror_window_->detachPreview();
    }
    if (camera_mirror_service_) {
        camera_mirror_service_->stop();
    }
    if (voice_input_service_) {
        voice_input_service_->cancel();
    }
    voice_hotkey_service_.reset();
    pending_share_items_ = nullptr;
    share_requested_revoker_.revoke();
    share_manager_ = nullptr;
    if (clipboard_listener_registered_ && message_window_) {
        (void)RemoveClipboardFormatListener(message_window_);
        clipboard_listener_registered_ = false;
    }
    clipboard_history_service_.reset();
    pdf_processing_service_.reset();
    ai_agent_workspace_service_.reset();
    ai_agent_skills_service_.reset();
    calendar_service_.reset();
    mail_service_.reset();
    update_service_.reset();
    weather_service_.reset();
    weather_location_repository_.reset();
    weather_locations_.clear();
    weather_status_override_.clear();
    if (notification_service_) {
        notification_service_->stop();
    }
    notification_service_.reset();
    persistence_service_.reset();
    power_request_controller_.reset();
    power_request_service_.reset();
    file_shelf_service_.reset();
    media_session_monitor_.reset();
    ai_state_monitor_.reset();
    file_activity_monitor_.reset();
    qwen_activity_monitor_.reset();
    kimi_activity_monitor_.reset();
    trae_activity_monitor_.reset();
    workbuddy_activity_monitor_.reset();
    harness_activity_monitor_.reset();
    grok_activity_monitor_.reset();
    gemini_activity_monitor_.reset();
    claude_activity_monitor_.reset();
    codex_activity_monitor_.reset();
    top_edge_trigger_.stop();
    tray_icon_.remove();
    if (taskbar_widget_window_) {
        taskbar_widget_window_->hide();
    }
    if (pet_window_) {
        pet_window_->hide();
    }
    settings_window_.reset();
    left_notice_window_.reset();
    right_notice_window_.reset();
    system_monitor_service_.reset();
    desktop_tools_service_.reset();
    disk_cleanup_service_.reset();
    download_service_.reset();
    browser_download_service_.reset();
    taskbar_widget_window_.reset();
    pet_window_.reset();
    pet_entries_.clear();
    pet_activity_.reset();
    overlay_window_.reset();
    quick_notes_service_.reset();
    teleprompter_window_.reset();
    camera_mirror_window_.reset();
    camera_mirror_service_.reset();
    voice_input_service_.reset();
    voice_input_phase_ = zisla::core::VoiceInputPhase::idle;
    side_notice_queue_.clear();
    browser_completed_notice_ids_.clear();
    active_ai_notice_ids_.clear();
    shown_ai_notice_ids_.clear();
    ai_task_statuses_.clear();
    side_notice_monitor_ = nullptr;
    destroyMessageWindow();
}

void AppHost::requestExternalActivation() noexcept {
    const auto window = activation_window_.load(std::memory_order_acquire);
    if (window && PostMessageW(window, activate_message, 0, 0)) {
        return;
    }
    external_activation_pending_.store(true, std::memory_order_release);
}

void AppHost::createMessageWindow() {
    const auto instance = GetModuleHandleW(nullptr);
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = windowProcedure;
    window_class.hInstance = instance;
    window_class.lpszClassName = message_window_class;

    if (!RegisterClassExW(&window_class)
        && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        winrt::throw_last_error();
    }

    message_window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        message_window_class,
        L"Zisla",
        WS_POPUP,
        0,
        0,
        0,
        0,
        nullptr,
        nullptr,
        instance,
        this);
    winrt::check_pointer(message_window_);
    activation_window_.store(message_window_, std::memory_order_release);
    taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
}

void AppHost::destroyMessageWindow() noexcept {
    activation_window_.store(nullptr, std::memory_order_release);
    if (message_window_) {
        DestroyWindow(message_window_);
        message_window_ = nullptr;
    }
}

LRESULT CALLBACK AppHost::windowProcedure(
    HWND hwnd,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
    AppHost* host = nullptr;
    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
        host = static_cast<AppHost*>(create->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(host));
    } else {
        host = reinterpret_cast<AppHost*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    }

    if (host) {
        if (host->taskbar_created_message_ != 0
            && message == host->taskbar_created_message_) {
            const bool restored = host->tray_icon_.restore();
            (void)restored;
            host->refreshTaskbarWidget();
            return 0;
        }
        return host->handleMessage(message, wparam, lparam);
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT AppHost::handleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
    case tray_message:
        handleTrayEvent(LOWORD(lparam));
        return 0;
    case top_edge_entered_message:
        if (cleaning_session_.active()) {
            return 0;
        }
        if (DisplayTopology::foregroundWindowCoversMonitor(
                reinterpret_cast<HMONITOR>(wparam),
                overlay_window_ ? overlay_window_->hwnd() : nullptr,
                settings_window_ ? settings_window_->hwnd() : nullptr)) {
            return 0;
        }
        dispatchPresentationAction(
            zisla::core::PresentationAction::hoverEntered(
                zisla::core::OverlayAnchor::top_edge));
        return 0;
    case top_edge_exited_message:
        dispatchPresentationAction(zisla::core::PresentationAction::hoverExited());
        return 0;
    case activate_message:
        if (cleaning_session_.active()) {
            return 0;
        }
        dispatchPresentationAction(
            zisla::core::PresentationAction::interactionRequested(
                zisla::core::OverlayAnchor::tray));
        return 0;
    case ai_activity_changed_message:
        refreshAIActivities();
        return 0;
    case media_session_changed_message:
        refreshNowPlaying();
        return 0;
    case file_shelf_changed_message:
        refreshFileShelf();
        return 0;
    case clipboard_history_changed_message:
        refreshClipboardHistory();
        return 0;
    case clipboard_link_detected_message:
        consumeClipboardLink();
        return 0;
    case cleaning_exit_message:
        endCleaning();
        return 0;
    case camera_mirror_changed_message:
        refreshCameraMirror();
        return 0;
    case camera_mirror_failed_message:
        if (camera_mirror_window_) {
            camera_mirror_window_->detachPreview();
        }
        if (camera_mirror_service_) {
            camera_mirror_service_->handle_runtime_failure(
                static_cast<std::uint64_t>(wparam));
        }
        refreshCameraMirror();
        return 0;
    case notification_activated_message:
        if (!cleaning_session_.active()) {
            dispatchPresentationAction(
                zisla::core::PresentationAction::interactionRequested(
                    zisla::core::OverlayAnchor::tray));
            if (overlay_window_ && overlay_window_->visible()) {
                try {
                    switch (static_cast<AppNotificationAction>(wparam)) {
                    case AppNotificationAction::alarms:
                        overlay_window_->showAlarmEditor();
                        break;
                    case AppNotificationAction::pomodoro:
                        overlay_window_->showPomodoro();
                        break;
                    case AppNotificationAction::open:
                        break;
                    }
                } catch (...) {
                }
            }
        }
        return 0;
    case weather_changed_message:
        handleWeatherChanged();
        return 0;
    case quick_notes_changed_message:
        refreshQuickNotes();
        return 0;
    case calendar_changed_message:
        refreshCalendar();
        return 0;
    case mail_changed_message:
        refreshMailView();
        return 0;
    case update_changed_message:
        refreshUpdate();
        return 0;
    case app_persistence_changed_message:
        handleAppPersistenceChanged();
        return 0;
    case alarm_notifications_changed_message:
        updateAlarmNotificationStatus();
        return 0;
    case pdf_processing_changed_message:
        refreshPDFProcessing();
        return 0;
    case ai_agent_skills_changed_message:
        refreshAIAgentSkills();
        return 0;
    case ai_agent_workspace_changed_message:
        refreshAIAgentWorkspace();
        return 0;
    case voice_input_changed_message:
        if (voice_input_service_) {
            voice_input_service_->handle_pending_events();
        }
        refreshVoiceInput();
        return 0;
    case WM_HOTKEY:
        if (voice_hotkey_service_ && voice_hotkey_service_->handle_hotkey(static_cast<int>(wparam))) {
            applyVoiceHotkeyCommand(zisla::core::voice_hotkey_command(
                voice_hotkey_service_->action(),
                zisla::core::VoiceHotkeyEvent::pressed));
        }
        return 0;
    case WM_INPUT:
        if (voice_hotkey_service_) {
            const auto key_up = voice_hotkey_service_->handle_raw_input(lparam);
            if (key_up && *key_up) {
                applyVoiceHotkeyCommand(zisla::core::voice_hotkey_command(
                    voice_hotkey_service_->action(),
                    zisla::core::VoiceHotkeyEvent::released));
            }
        }
        return 0;
    case system_monitor_changed_message:
        refreshSystemMonitor();
        return 0;
    case desktop_tools_changed_message:
        refreshDesktopToolsView();
        return 0;
    case disk_cleanup_changed_message:
        refreshDiskCleanup();
        return 0;
    case download_changed_message:
        refreshDownload();
        return 0;
    case browser_download_changed_message:
        refreshBrowserDownloads();
        return 0;
    case WM_CLIPBOARDUPDATE:
        if (clipboard_history_service_) {
            clipboard_history_service_->capture(GetClipboardSequenceNumber());
        }
        return 0;
    case WM_TIMER:
        if (wparam == top_edge_timer_id) {
            top_edge_trigger_.poll();
            return 0;
        }
        if (wparam == dismiss_timer_id) {
            const auto generation = scheduled_dismiss_generation_;
            cancelScheduledDismiss();
            dispatchPresentationAction(
                zisla::core::PresentationAction::dismissDelayElapsed(generation));
            return 0;
        }
        if (wparam == side_notice_timer_id) {
            cancelSideNoticeExpiration();
            (void)side_notice_queue_.remove_expired(monotonic_milliseconds());
            updateSideNoticeWindows();
            return 0;
        }
        if (wparam == pomodoro_timer_id) {
            handlePomodoroTimer();
            return 0;
        }
        if (wparam == teleprompter_timer_id) {
            handleTeleprompterTimer();
            return 0;
        }
        if (wparam == alarm_timer_id) {
            reconcileAndRescheduleAlarms();
            return 0;
        }
        if (wparam == voice_finalization_timer_id) {
            cancelVoiceFinalization();
            if (voice_input_service_) {
                voice_input_service_->finish_finalization();
            }
            refreshVoiceInput();
            return 0;
        }
        break;
    case WM_TIMECHANGE:
        reconcileAndRescheduleAlarms();
        return 0;
    case WM_POWERBROADCAST:
        if (wparam == PBT_APMRESUMEAUTOMATIC) {
            reconcileAndRescheduleAlarms();
        }
        return TRUE;
    case WM_THEMECHANGED:
    case WM_DWMCOLORIZATIONCOLORCHANGED:
    case WM_DWMCOMPOSITIONCHANGED:
        refreshBackdrops();
        tray_icon_.refreshTheme();
        return 0;
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
        if (message == WM_SETTINGCHANGE) {
            refreshBackdrops();
            tray_icon_.refreshTheme();
            if (pet_window_) {
                pet_window_->refreshSystemPreferences();
            }
        }
        top_edge_trigger_.refresh();
        refreshTaskbarWidget();
        if (message == WM_DISPLAYCHANGE && cleaning_session_.active()) {
            rebuildCleaningWindows();
        }
        if (message == WM_DISPLAYCHANGE && teleprompter_window_
            && teleprompter_window_->visible()) {
            teleprompter_window_->show();
        }
        if (message == WM_DISPLAYCHANGE && camera_mirror_window_
            && camera_mirror_window_->visible()) {
            camera_mirror_window_->show();
        }
        if (presentation_engine_.state().visibility
            != zisla::core::OverlayVisibility::hidden) {
            (void)showOverlay(presentation_engine_.state().anchor);
        }
        updateSideNoticeWindows();
        return 0;
    case WM_DESTROY:
        SetWindowLongPtrW(message_window_, GWLP_USERDATA, 0);
        return 0;
    default:
        break;
    }
    return DefWindowProcW(message_window_, message, wparam, lparam);
}

void AppHost::handleTrayEvent(UINT event) {
    switch (event) {
    case NIN_POPUPOPEN:
        dispatchPresentationAction(
            zisla::core::PresentationAction::hoverEntered(
                zisla::core::OverlayAnchor::tray));
        break;
    case NIN_POPUPCLOSE:
        dispatchPresentationAction(zisla::core::PresentationAction::hoverExited());
        break;
    case NIN_SELECT:
    case NIN_KEYSELECT:
    case WM_LBUTTONUP:
        dispatchPresentationAction(
            zisla::core::PresentationAction::interactionRequested(
                zisla::core::OverlayAnchor::tray));
        break;
    case WM_CONTEXTMENU:
    case WM_RBUTTONUP:
        showTrayContextMenu();
        break;
    default:
        break;
    }
}

void AppHost::showTrayContextMenu() {
    POINT point{};
    if (!GetCursorPos(&point)) {
        return;
    }
    const auto menu = CreatePopupMenu();
    if (!menu) {
        return;
    }

    AppendMenuW(menu, MF_STRING, menu_open, L"打开 Zisla");
    AppendMenuW(menu, MF_STRING, menu_settings, L"设置");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(
        menu,
        MF_STRING | (top_edge_enabled_ ? MF_CHECKED : MF_UNCHECKED),
        menu_top_edge,
        L"顶部悬停入口");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, menu_exit, L"退出");

    SetForegroundWindow(message_window_);
    const auto command = TrackPopupMenuEx(
        menu,
        TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        point.x,
        point.y,
        message_window_,
        nullptr);
    DestroyMenu(menu);
    PostMessageW(message_window_, WM_NULL, 0, 0);

    switch (command) {
    case menu_open:
        dispatchPresentationAction(
            zisla::core::PresentationAction::interactionRequested(
                zisla::core::OverlayAnchor::tray));
        break;
    case menu_settings:
        showSettings();
        break;
    case menu_top_edge:
        setTopEdgeEnabled(!top_edge_enabled_);
        break;
    case menu_exit:
        exitApplication();
        break;
    default:
        break;
    }
}

void AppHost::dispatchPresentationAction(
    zisla::core::PresentationAction action) {
    const auto effects = presentation_engine_.dispatch(action);
    applyEffects(effects);
}

void AppHost::applyEffects(const zisla::core::EffectBatch& effects) {
    bool host_failed = false;
    for (std::size_t index = 0; index < effects.size(); ++index) {
        const auto& effect = effects[index];
        switch (effect.kind) {
        case zisla::core::PresentationEffectKind::cancel_scheduled_dismiss:
            cancelScheduledDismiss();
            break;
        case zisla::core::PresentationEffectKind::schedule_dismiss:
            scheduleDismiss(effect.dismiss_generation);
            break;
        case zisla::core::PresentationEffectKind::show_peek:
        case zisla::core::PresentationEffectKind::show_interactive:
            host_failed = !showOverlay(effect.anchor);
            break;
        case zisla::core::PresentationEffectKind::hide:
            hideOverlay();
            break;
        }
    }

    if (host_failed) {
        const auto cleanup = presentation_engine_.dispatch(
            zisla::core::PresentationAction::hostFailed());
        for (std::size_t index = 0; index < cleanup.size(); ++index) {
            if (cleanup[index].kind == zisla::core::PresentationEffectKind::hide) {
                hideOverlay();
            } else if (cleanup[index].kind
                == zisla::core::PresentationEffectKind::cancel_scheduled_dismiss) {
                cancelScheduledDismiss();
            }
        }
    }
}

bool AppHost::showOverlay(zisla::core::OverlayAnchor anchor) {
    if (!overlay_window_ || cleaning_session_.active()) {
        return false;
    }

    try {
        hideSideNoticeWindows();
        const auto surface = presentation_engine_.state().visibility
                == zisla::core::OverlayVisibility::peek
            ? zisla::core::OverlaySurfaceKind::peek
            : zisla::core::OverlaySurfaceKind::interactive;
        zisla::core::PixelRect bounds{};

        if (anchor == zisla::core::OverlayAnchor::tray) {
            if (const auto tray_bounds = tray_icon_.bounds()) {
                const RECT tray_rect{
                    tray_bounds->x,
                    tray_bounds->y,
                    tray_bounds->right(),
                    tray_bounds->bottom(),
                };
                const auto screen = DisplayTopology::screenForRect(tray_rect);
                bounds = placement_engine_.trayCard(screen, *tray_bounds, surface);
            } else {
                POINT cursor{};
                if (!GetCursorPos(&cursor)) {
                    return false;
                }
                const auto screen = DisplayTopology::screenForPoint(cursor);
                bounds = placement_engine_.trayCard(
                    screen,
                    {cursor.x, cursor.y, 1, 1},
                    surface);
            }
        } else if (anchor == zisla::core::OverlayAnchor::taskbar) {
            const auto taskbar = TaskbarPlacement::forTrayIcon(tray_icon_.bounds());
            if (!taskbar || !taskbar->valid()) {
                return false;
            }
            const auto widget = placement_engine_.taskbarWidget(
                taskbar->screen,
                taskbar->bounds,
                taskbar->edge,
                tray_icon_.bounds());
            bounds = placement_engine_.taskbarCard(
                taskbar->screen,
                taskbar->bounds,
                widget,
                taskbar->edge,
                surface);
        } else {
            POINT cursor{};
            if (!GetCursorPos(&cursor)) {
                return false;
            }
            const auto screen = DisplayTopology::screenForPoint(cursor);
            bounds = placement_engine_.topEdgeCard(screen, surface);
        }

        overlay_window_->show(bounds, surface, presentation_engine_.state().pinned);
        if (surface == zisla::core::OverlaySurfaceKind::interactive
            && settings_.weather_enabled
            && weatherIsStale()) {
            refreshWeatherAsync(true);
        }
        return true;
    } catch (...) {
        updateSideNoticeWindows();
        return false;
    }
}

void AppHost::hideOverlay() noexcept {
    if (overlay_window_) {
        overlay_window_->hide();
    }
    updateSideNoticeWindows();
}

void AppHost::scheduleDismiss(std::uint64_t generation) {
    cancelScheduledDismiss();
    scheduled_dismiss_generation_ = generation;
    SetTimer(message_window_, dismiss_timer_id, dismiss_delay_ms, nullptr);
}

void AppHost::cancelScheduledDismiss() noexcept {
    if (message_window_) {
        KillTimer(message_window_, dismiss_timer_id);
    }
    scheduled_dismiss_generation_ = 0;
}

void AppHost::refreshAIActivities() noexcept {
    if (!overlay_window_) {
        return;
    }
    try {
        const auto persisted = ai_state_monitor_
            ? ai_state_monitor_->snapshot()
            : std::make_shared<const AIStateMonitor::ActivityList>();
        const auto codex_detected = codex_activity_monitor_
            ? codex_activity_monitor_->snapshot()
            : std::make_shared<const CodexActivityMonitor::ActivityList>();
        const auto claude_detected = claude_activity_monitor_
            ? claude_activity_monitor_->snapshot()
            : std::make_shared<const ClaudeActivityMonitor::ActivityList>();
        const auto gemini_detected = gemini_activity_monitor_
            ? gemini_activity_monitor_->snapshot()
            : std::make_shared<const GeminiActivityMonitor::ActivityList>();
        const auto grok_detected = grok_activity_monitor_
            ? grok_activity_monitor_->snapshot()
            : std::make_shared<const GrokActivityMonitor::ActivityList>();
        const auto harness_detected = harness_activity_monitor_
            ? harness_activity_monitor_->snapshot()
            : std::make_shared<const HarnessActivityMonitor::ActivityList>();
        const auto workbuddy_detected = workbuddy_activity_monitor_
            ? workbuddy_activity_monitor_->snapshot()
            : std::make_shared<const WorkBuddyActivityMonitor::ActivityList>();
        const auto trae_detected = trae_activity_monitor_
            ? trae_activity_monitor_->snapshot()
            : std::make_shared<const TraeActivityMonitor::ActivityList>();
        const auto kimi_detected = kimi_activity_monitor_
            ? kimi_activity_monitor_->snapshot()
            : std::make_shared<const KimiActivityMonitor::ActivityList>();
        const auto qwen_detected = qwen_activity_monitor_
            ? qwen_activity_monitor_->snapshot()
            : std::make_shared<const QwenActivityMonitor::ActivityList>();
        const auto file_detected = file_activity_monitor_
            ? file_activity_monitor_->snapshot()
            : std::make_shared<const FileActivityMonitor::ActivityList>();

        std::vector<zisla::core::AIProgressTask> detected;
        detected.reserve(
            codex_detected->size() + claude_detected->size() + gemini_detected->size()
            + grok_detected->size() + harness_detected->size()
            + workbuddy_detected->size() + trae_detected->size()
            + kimi_detected->size() + qwen_detected->size()
            + file_detected->size());
        detected.insert(detected.end(), codex_detected->begin(), codex_detected->end());
        detected.insert(detected.end(), claude_detected->begin(), claude_detected->end());
        detected.insert(detected.end(), gemini_detected->begin(), gemini_detected->end());
        detected.insert(detected.end(), grok_detected->begin(), grok_detected->end());
        detected.insert(
            detected.end(),
            harness_detected->begin(),
            harness_detected->end());
        detected.insert(
            detected.end(),
            workbuddy_detected->begin(),
            workbuddy_detected->end());
        detected.insert(detected.end(), trae_detected->begin(), trae_detected->end());
        detected.insert(detected.end(), kimi_detected->begin(), kimi_detected->end());
        detected.insert(detected.end(), qwen_detected->begin(), qwen_detected->end());
        detected.insert(detected.end(), file_detected->begin(), file_detected->end());

        const auto now_unix_ms = now_unix_milliseconds();
        const auto activities = zisla::core::AIActivityMerger::merge(
            *persisted,
            detected,
            {.now_unix_ms = now_unix_ms});
        overlay_window_->setAIActivities(activities);
        const auto activity = zisla::core::pet_activity_for_ai(activities);
        pet_activity_ = activity == zisla::core::PetActivity::idle
            ? std::nullopt
            : std::optional<zisla::core::PetActivity>{activity};
        if (pet_window_) {
            pet_window_->setActivity(pet_activity_);
        }
        consumeExternalNotices(now_unix_ms);
        refreshAIActivityNotices(activities, now_unix_ms);
        updateSideNoticeWindows();
    } catch (...) {
    }
}

void AppHost::refreshNowPlaying() noexcept {
    if (!overlay_window_) {
        return;
    }
    try {
        const auto snapshot = media_session_monitor_
            ? media_session_monitor_->snapshot()
            : nullptr;
        overlay_window_->setNowPlaying(snapshot);
        refreshMediaNotice(snapshot);
        updateSideNoticeWindows();
    } catch (...) {
    }
}

void AppHost::refreshFileShelf() noexcept {
    if (!overlay_window_ || !file_shelf_service_) {
        return;
    }
    try {
        const auto snapshot = file_shelf_service_->snapshot();
        overlay_window_->setShelfItems(
            *snapshot,
            file_shelf_service_->capacity());
    } catch (...) {
    }
}

void AppHost::refreshClipboardHistory() noexcept {
    if (!overlay_window_ || !clipboard_history_service_) {
        return;
    }
    try {
        const auto snapshot = clipboard_history_service_->snapshot();
        overlay_window_->setClipboardItems(
            snapshot,
            clipboard_history_service_->capacity());
    } catch (...) {
    }
}

void AppHost::refreshQuickNotes() noexcept {
    if (!overlay_window_ || !quick_notes_service_) {
        return;
    }
    try {
        overlay_window_->setQuickNotes(quick_notes_service_->snapshot());
    } catch (...) {
    }
}

void AppHost::refreshPDFProcessing() noexcept {
    if (!overlay_window_ || !pdf_processing_service_) {
        return;
    }
    try {
        overlay_window_->setPDFProcessing(pdf_processing_service_->snapshot());
    } catch (...) {
    }
}

void AppHost::refreshAIAgentWorkspace() noexcept {
    if (!overlay_window_ || !ai_agent_workspace_service_) {
        return;
    }
    try {
        overlay_window_->setAIAgentWorkspace(ai_agent_workspace_service_->snapshot());
    } catch (...) {
    }
}

void AppHost::refreshAIAgentSkills() noexcept {
    if (!overlay_window_ || !ai_agent_skills_service_) {
        return;
    }
    try {
        overlay_window_->setAIAgentSkills(ai_agent_skills_service_->snapshot());
    } catch (...) {
    }
}

void AppHost::refreshCalendar() noexcept {
    if (!overlay_window_ || !calendar_service_) {
        return;
    }
    try {
        overlay_window_->setCalendar(calendar_service_->snapshot());
    } catch (...) {
    }
}

void AppHost::refreshMailView() noexcept {
    if (!overlay_window_ && !settings_window_) {
        return;
    }
    try {
        std::shared_ptr<const MailServiceSnapshot> snapshot;
        if (mail_service_) {
            snapshot = mail_service_->snapshot();
        } else {
            auto unavailable = std::make_shared<MailServiceSnapshot>();
            unavailable->phase = mail_connection_settings_.client_id.empty()
                ? MailServicePhase::not_configured
                : MailServicePhase::failed;
            unavailable->connection = mail_connection_settings_;
            unavailable->message = mail_connection_settings_.client_id.empty()
                ? "请在设置中连接 Microsoft Graph 邮箱"
                : "邮件服务不可用";
            snapshot = std::move(unavailable);
        }
        if (overlay_window_) {
            overlay_window_->setMail(snapshot);
        }
        if (settings_window_) {
            settings_window_->setMail(std::move(snapshot));
        }
    } catch (...) {
    }
}

bool AppHost::startMailService() noexcept {
    if (mail_service_) {
        return true;
    }
    try {
        auto service = std::make_unique<MailService>(mail_connection_settings_);
        if (!service->start(message_window_, mail_changed_message)) {
            return false;
        }
        mail_service_ = std::move(service);
        return true;
    } catch (...) {
        return false;
    }
}

void AppHost::refreshUpdate() noexcept {
    if (!overlay_window_ && !settings_window_) {
        return;
    }
    try {
        std::shared_ptr<const UpdateServiceSnapshot> snapshot;
        if (update_service_) {
            snapshot = update_service_->snapshot();
        } else {
            auto unavailable = std::make_shared<UpdateServiceSnapshot>();
            unavailable->phase = UpdateServicePhase::failed;
            unavailable->channel = update_channel_;
            unavailable->message = "更新服务不可用";
            snapshot = std::move(unavailable);
        }
        if (settings_window_) {
            settings_window_->setUpdate(std::move(snapshot));
        }
    } catch (...) {
    }
}

void AppHost::refreshSystemMonitor() noexcept {
    if (!overlay_window_ || !system_monitor_service_) {
        return;
    }
    try {
        overlay_window_->setSystemMonitor(system_monitor_service_->snapshot());
    } catch (...) {
    }
}

void AppHost::refreshDesktopToolsView() noexcept {
    if (!overlay_window_ || !desktop_tools_service_) {
        return;
    }
    try {
        overlay_window_->setDesktopTools(desktop_tools_service_->snapshot());
    } catch (...) {
    }
}

void AppHost::refreshDiskCleanup() noexcept {
    if (!overlay_window_ || !disk_cleanup_service_) {
        return;
    }
    try {
        overlay_window_->setDiskCleanup(disk_cleanup_service_->snapshot());
    } catch (...) {
    }
}

void AppHost::refreshDownload() noexcept {
    if (!overlay_window_) {
        return;
    }
    try {
        std::shared_ptr<const zisla::core::DownloadSnapshot> snapshot;
        if (download_service_) {
            snapshot = download_service_->snapshot();
        } else {
            auto unavailable = std::make_shared<zisla::core::DownloadSnapshot>();
            unavailable->request.output_directory = download_output_directory_;
            unavailable->phase = zisla::core::DownloadPhase::failed;
            unavailable->error = download_startup_error_.empty()
                ? "下载服务不可用"
                : download_startup_error_;
            unavailable->revision = 1;
            snapshot = std::move(unavailable);
        }
        overlay_window_->setDownload(snapshot, download_output_directory_);
        refreshDownloadNotice(snapshot);
        updateSideNoticeWindows();
    } catch (...) {
    }
}

void AppHost::refreshBrowserDownloads() noexcept {
    if (!overlay_window_) {
        return;
    }
    try {
        std::shared_ptr<const BrowserDownloadServiceSnapshot> snapshot;
        if (browser_download_service_) {
            snapshot = browser_download_service_->snapshot();
        } else {
            snapshot = std::make_shared<const BrowserDownloadServiceSnapshot>();
        }
        overlay_window_->setBrowserDownloads(snapshot);
        refreshBrowserDownloadNotice(snapshot);
        updateSideNoticeWindows();
    } catch (...) {
    }
}

void AppHost::refreshTaskbarWidget() noexcept {
    if (taskbar_widget_window_) {
        if (!taskbar_widget_enabled_ || cleaning_session_.active()) {
            taskbar_widget_window_->hide();
        } else {
            try {
                const auto taskbar = TaskbarPlacement::forTrayIcon(tray_icon_.bounds());
                if (!taskbar || !taskbar->valid()) {
                    taskbar_widget_window_->hide();
                } else {
                    const auto bounds = placement_engine_.taskbarWidget(
                        taskbar->screen,
                        taskbar->bounds,
                        taskbar->edge,
                        tray_icon_.bounds());
                    taskbar_widget_window_->show(bounds);
                }
            } catch (...) {
                taskbar_widget_window_->hide();
            }
        }
    }
    refreshPet();
}

void AppHost::refreshBackdrops() noexcept {
    if (overlay_window_) {
        overlay_window_->refreshBackdrop();
    }
    if (taskbar_widget_window_) {
        taskbar_widget_window_->refreshBackdrop();
    }
    if (settings_window_) {
        settings_window_->refreshBackdrop();
    }
    if (left_notice_window_) {
        left_notice_window_->refreshBackdrop();
    }
    if (right_notice_window_) {
        right_notice_window_->refreshBackdrop();
    }
}

void AppHost::refreshPet() noexcept {
    if (!settings_.pet_enabled || cleaning_session_.active()) {
        if (pet_window_) {
            pet_window_->hide();
        }
        return;
    }
    if (!pet_window_ && !loadSelectedPet()) {
        return;
    }

    try {
        const auto taskbar = TaskbarPlacement::forTrayIcon(tray_icon_.bounds());
        if (!taskbar || !taskbar->valid()) {
            pet_window_->hide();
            return;
        }
        const auto widget = placement_engine_.taskbarWidget(
            taskbar->screen,
            taskbar->bounds,
            taskbar->edge,
            tray_icon_.bounds());
        const auto bounds = placement_engine_.taskbarPet(
            taskbar->screen,
            widget,
            taskbar->edge,
            settings_.pet_side);
        if (bounds.width <= 0 || bounds.height <= 0) {
            pet_window_->hide();
            return;
        }
        pet_window_->show(bounds);
    } catch (...) {
        pet_window_->hide();
    }
}

bool AppHost::loadSelectedPet() noexcept {
    if (pet_entries_.empty()) {
        return false;
    }

    try {
        auto selected = std::find_if(
            pet_entries_.begin(),
            pet_entries_.end(),
            [this](const auto& entry) {
                return entry.manifest.id == settings_.pet_id;
            });
        if (selected == pet_entries_.end()) {
            selected = std::find_if(
                pet_entries_.begin(),
                pet_entries_.end(),
                [](const auto& entry) {
                    return entry.manifest.id == "dog";
                });
        }
        if (selected == pet_entries_.end()) {
            selected = pet_entries_.begin();
        }

        auto replacement = std::make_unique<PetWindow>();
        if (!replacement->load(*selected)) {
            return false;
        }
        replacement->refreshSystemPreferences();
        replacement->setActivity(pet_activity_);
        settings_.pet_id = selected->manifest.id;
        pet_window_ = std::move(replacement);
        return true;
    } catch (...) {
        return false;
    }
}

void AppHost::refreshDownloadNotice(
    const std::shared_ptr<const zisla::core::DownloadSnapshot>& snapshot) {
    constexpr std::string_view active_notice_id = "video-download-active-right";
    if (!snapshot) {
        (void)side_notice_queue_.remove(active_notice_id);
        return;
    }

    const bool notices_enabled = settings_.side_notices_enabled
        && settings_.video_download_status_enabled
        && !settings_.notifications_muted;
    if (!notices_enabled || !snapshot->active()) {
        (void)side_notice_queue_.remove(active_notice_id);
    }

    if (notices_enabled && snapshot->active()) {
        std::string detail;
        switch (snapshot->phase) {
        case zisla::core::DownloadPhase::preparing:
            detail = "正在准备下载";
            break;
        case zisla::core::DownloadPhase::downloading:
            detail = snapshot->speed;
            if (!snapshot->eta.empty()) {
                if (!detail.empty()) {
                    detail.append(" · ");
                }
                detail.append("ETA ");
                detail.append(snapshot->eta);
            }
            break;
        case zisla::core::DownloadPhase::cancelling:
            detail = "正在取消";
            break;
        default:
            break;
        }
        const zisla::core::IslandNotice notice{
            .id = std::string{active_notice_id},
            .title = snapshot->request.mode == zisla::core::DownloadMode::video
                ? "视频下载"
                : "音频下载",
            .detail = detail.empty()
                ? std::nullopt
                : std::optional<std::string>{std::move(detail)},
            .kind = zisla::core::NoticeKind::info,
            .side = zisla::core::NoticeSide::right,
            .created_at_unix_ms = now_unix_milliseconds(),
            .progress = snapshot->phase == zisla::core::DownloadPhase::downloading
                ? std::optional<double>{snapshot->fraction}
                : std::nullopt,
        };
        if (!side_notice_queue_.update_if_present(notice)) {
            side_notice_queue_.enqueue(
                notice,
                monotonic_milliseconds(),
                std::nullopt);
            anchorSideNoticesToPointer();
        }
        return;
    }

    const bool terminal = snapshot->phase == zisla::core::DownloadPhase::completed
        || snapshot->phase == zisla::core::DownloadPhase::failed;
    if (!terminal || snapshot->revision == download_terminal_notice_revision_) {
        return;
    }
    download_terminal_notice_revision_ = snapshot->revision;
    if (!notices_enabled) {
        return;
    }

    std::string title = snapshot->phase == zisla::core::DownloadPhase::completed
        ? "下载完成"
        : "下载失败";
    std::optional<std::string> detail;
    if (snapshot->phase == zisla::core::DownloadPhase::completed
        && snapshot->completed_file) {
        detail = to_string(hstring{snapshot->completed_file->filename().c_str()});
    } else if (!snapshot->error.empty()) {
        detail = snapshot->error;
    }
    side_notice_queue_.enqueue({
        .id = "video-download-result-" + std::to_string(snapshot->revision),
        .title = std::move(title),
        .detail = std::move(detail),
        .kind = snapshot->phase == zisla::core::DownloadPhase::completed
            ? zisla::core::NoticeKind::success
            : zisla::core::NoticeKind::error,
        .side = zisla::core::NoticeSide::right,
        .created_at_unix_ms = now_unix_milliseconds(),
    }, monotonic_milliseconds(), 3'000);
    anchorSideNoticesToPointer();
}

void AppHost::refreshBrowserDownloadNotice(
    const std::shared_ptr<const BrowserDownloadServiceSnapshot>& snapshot) {
    constexpr std::string_view active_notice_id =
        "browser-download-active-right";
    const bool notices_enabled = settings_.side_notices_enabled
        && settings_.browser_download_status_enabled
        && !settings_.notifications_muted;
    if (!snapshot || !notices_enabled) {
        (void)side_notice_queue_.remove(active_notice_id);
        browser_completed_notice_ids_.clear();
        return;
    }

    if (snapshot->summary.total_active_count == 0) {
        (void)side_notice_queue_.remove(active_notice_id);
    } else {
        std::string detail = std::to_string(
            snapshot->summary.total_active_count);
        detail.append(" 个进行中");
        if (snapshot->summary.combined_progress) {
            const auto percent = static_cast<long long>(std::llround(
                std::clamp(*snapshot->summary.combined_progress, 0.0, 1.0)
                    * 100.0));
            detail.append(" · ");
            detail.append(std::to_string(percent));
            detail.push_back('%');
        }
        const zisla::core::IslandNotice notice{
            .id = std::string{active_notice_id},
            .title = "浏览器下载",
            .detail = std::move(detail),
            .kind = zisla::core::NoticeKind::info,
            .side = zisla::core::NoticeSide::right,
            .created_at_unix_ms = now_unix_milliseconds(),
            .progress = snapshot->summary.combined_progress,
        };
        if (!side_notice_queue_.update_if_present(notice)) {
            side_notice_queue_.enqueue(
                notice,
                monotonic_milliseconds(),
                std::nullopt);
            anchorSideNoticesToPointer();
        }
    }

    std::unordered_set<std::string> current_ids;
    for (const auto& completion : snapshot->recently_completed) {
        std::string id = "browser-download-complete-";
        id.append(completion.identity);
        id.push_back('-');
        id.append(std::to_string(completion.item.start_time_unix_ms));
        id.push_back('-');
        id.append(std::to_string(completion.item.end_time_unix_ms));
        current_ids.insert(id);
        if (!browser_completed_notice_ids_.insert(id).second) {
            continue;
        }

        std::string detail = browser_download_display_name(completion.item);
        side_notice_queue_.enqueue({
            .id = std::move(id),
            .title = "浏览器下载完成",
            .detail = detail.empty()
                ? std::nullopt
                : std::optional<std::string>{std::move(detail)},
            .kind = zisla::core::NoticeKind::success,
            .side = zisla::core::NoticeSide::right,
            .created_at_unix_ms = now_unix_milliseconds(),
        }, monotonic_milliseconds(), 3'000);
        anchorSideNoticesToPointer();
    }
    for (auto iterator = browser_completed_notice_ids_.begin();
         iterator != browser_completed_notice_ids_.end();) {
        if (!current_ids.contains(*iterator)) {
            iterator = browser_completed_notice_ids_.erase(iterator);
        } else {
            ++iterator;
        }
    }
}

void AppHost::refreshPomodoro() noexcept {
    if (!overlay_window_) {
        return;
    }
    try {
        overlay_window_->setPomodoro(
            pomodoro_engine_.snapshot(now_unix_milliseconds()));
    } catch (...) {
    }
}

void AppHost::refreshAlarms() noexcept {
    if (!overlay_window_) {
        return;
    }
    try {
        std::string error = alarm_storage_error_;
        if (!alarm_notification_error_.empty()) {
            if (!error.empty()) {
                error.append("；");
            }
            error.append(alarm_notification_error_);
        }
        overlay_window_->setAlarms(
            alarm_book_.alarms(),
            alarm_book_.next_alarm(current_alarm_clock()),
            std::move(error));
    } catch (...) {
    }
}

void AppHost::refreshPowerRequests() noexcept {
    if (!overlay_window_) {
        return;
    }
    try {
        overlay_window_->setPowerRequests(power_request_controller_
            ? power_request_controller_->snapshot()
            : zisla::core::PowerRequestSnapshot{});
    } catch (...) {
    }
}

void AppHost::refreshCleaning() noexcept {
    if (!overlay_window_) {
        return;
    }
    try {
        overlay_window_->setCleaning(cleaning_session_.mode());
    } catch (...) {
    }
}

void AppHost::refreshTeleprompter() noexcept {
    if (!teleprompter_window_) {
        return;
    }
    try {
        teleprompter_window_->setSnapshot(teleprompter_engine_.snapshot());
    } catch (...) {
    }
}

void AppHost::refreshCameraMirror() noexcept {
    if (!camera_mirror_window_ || !camera_mirror_service_) {
        return;
    }
    try {
        camera_mirror_window_->setSnapshot(
            camera_mirror_service_->snapshot(),
            camera_mirror_service_->media_player());
    } catch (...) {
    }
}

void AppHost::refreshVoiceInput() noexcept {
    if (!overlay_window_) {
        return;
    }

    try {
        zisla::core::VoiceInputSnapshot snapshot;
        if (voice_input_service_) {
            snapshot = voice_input_service_->snapshot();
        }

        const auto previous_phase = voice_input_phase_;
        voice_input_phase_ = snapshot.phase;
        if (snapshot.phase == zisla::core::VoiceInputPhase::finalizing) {
            if (previous_phase != zisla::core::VoiceInputPhase::finalizing
                && message_window_) {
                SetTimer(
                    message_window_,
                    voice_finalization_timer_id,
                    static_cast<UINT>(
                        zisla::core::VoiceInputSession::finalization_timeout_seconds.count()
                        * 1'000),
                    nullptr);
            }
        } else {
            cancelVoiceFinalization();
        }

        overlay_window_->setVoiceInput(snapshot, settings_.voice_input_enabled);
        if (started_
            && previous_phase == zisla::core::VoiceInputPhase::finalizing
            && snapshot.phase == zisla::core::VoiceInputPhase::idle
            && !snapshot.final_text.empty()) {
            copyTextToClipboard(snapshot.final_text);
        }
    } catch (...) {
    }
}

void AppHost::cancelVoiceFinalization() noexcept {
    if (message_window_) {
        KillTimer(message_window_, voice_finalization_timer_id);
    }
}

void AppHost::refreshVoiceHotkey() noexcept {
    if (!message_window_) {
        return;
    }

    if (!settings_.voice_input_enabled) {
        voice_hotkey_service_.reset();
        return;
    }

    try {
        if (!voice_hotkey_service_) {
            voice_hotkey_service_ = std::make_unique<GlobalHotkeyService>();
        }

        if (!voice_hotkey_service_->register_hotkey(
                message_window_,
                settings_.voice_hotkey_action,
                settings_.voice_hotkey_preset)) {
            return;
        }
    } catch (...) {
        voice_hotkey_service_.reset();
    }
}

void AppHost::applyVoiceHotkeyCommand(
    zisla::core::VoiceHotkeyCommand command) noexcept {
    switch (command) {
    case zisla::core::VoiceHotkeyCommand::toggle_voice_input:
        toggleVoiceInput();
        return;
    case zisla::core::VoiceHotkeyCommand::start_voice_input:
        startVoiceInput();
        return;
    case zisla::core::VoiceHotkeyCommand::stop_voice_input:
        stopVoiceInput();
        return;
    case zisla::core::VoiceHotkeyCommand::none:
        return;
    }
}

void AppHost::startVoiceInput() noexcept {
    if (!settings_.voice_input_enabled || !message_window_) {
        return;
    }

    try {
        if (!voice_input_service_) {
            voice_input_service_ = std::make_shared<VoiceInputService>(
                message_window_,
                voice_input_changed_message);
        }

        const auto phase = voice_input_service_->snapshot().phase;
        if (phase == zisla::core::VoiceInputPhase::listening
            || phase == zisla::core::VoiceInputPhase::requesting_speech_permission
            || phase == zisla::core::VoiceInputPhase::requesting_microphone_permission
            || phase == zisla::core::VoiceInputPhase::starting) {
            return;
        }
        if (phase == zisla::core::VoiceInputPhase::finalizing) {
            cancelVoiceFinalization();
            voice_input_service_->finish_finalization();
        }
        voice_input_service_->start();
    } catch (...) {
        if (voice_input_service_) {
            voice_input_service_->cancel();
        }
    }
    refreshVoiceInput();
}

void AppHost::stopVoiceInput() noexcept {
    if (!voice_input_service_) {
        return;
    }

    try {
        const auto phase = voice_input_service_->snapshot().phase;
        if (phase == zisla::core::VoiceInputPhase::listening) {
            voice_input_service_->stop();
        } else if (phase == zisla::core::VoiceInputPhase::requesting_speech_permission
            || phase == zisla::core::VoiceInputPhase::requesting_microphone_permission
            || phase == zisla::core::VoiceInputPhase::starting) {
            voice_input_service_->cancel();
        }
    } catch (...) {
        voice_input_service_->cancel();
    }
    refreshVoiceInput();
}

void AppHost::startWeatherService() noexcept {
    if (weather_service_ || !message_window_ || !settings_.weather_enabled) {
        return;
    }
    try {
        auto service = std::make_unique<WeatherService>();
        if (!service->start(message_window_, weather_changed_message)) {
            weather_status_override_ = "无法启动天气服务";
            return;
        }
        weather_service_ = std::move(service);
    } catch (const std::exception& error) {
        weather_status_override_ = error.what();
    } catch (...) {
        weather_status_override_ = "无法启动天气服务";
    }
}

void AppHost::handleWeatherChanged() noexcept {
    if (!weather_service_) {
        return;
    }
    try {
        const auto snapshot = weather_service_->snapshot();
        if (snapshot
            && snapshot->operation == WeatherServiceOperation::search
            && snapshot->phase == WeatherServicePhase::ready
            && !snapshot->search_results.empty()
            && snapshot->generation > handled_weather_search_generation_) {
            handled_weather_search_generation_ = snapshot->generation;
            if (!weather_location_repository_) {
                weather_status_override_ = "无法保存天气地点";
                refreshWeatherView();
                return;
            }
            const auto& result = snapshot->search_results.front();
            weather_location_repository_->add_saved(
                result.display_name,
                result.coordinate);
            weather_locations_ = weather_location_repository_->load();
            weather_storage_error_.clear();
            refreshWeatherAsync(false);
            return;
        }
        refreshWeatherView();
    } catch (const std::exception& error) {
        weather_status_override_ = error.what();
        refreshWeatherView();
    } catch (...) {
        weather_status_override_ = "无法更新天气地点";
        refreshWeatherView();
    }
}

void AppHost::refreshWeatherView() noexcept {
    if (!overlay_window_) {
        return;
    }
    try {
        auto status = weather_status_override_;
        if (status.empty() && !weather_storage_error_.empty()) {
            status = weather_storage_error_;
        }
        overlay_window_->setWeather(
            weather_service_ ? weather_service_->snapshot() : nullptr,
            weather_locations_,
            settings_.weather_enabled,
            weather_location_pending_,
            std::move(status));
    } catch (...) {
    }
}

winrt::fire_and_forget AppHost::refreshWeatherAsync(
    bool request_current_location) {
    if (!started_ || !settings_.weather_enabled) {
        co_return;
    }
    if (request_current_location && weather_location_pending_) {
        co_return;
    }
    startWeatherService();
    if (!weather_service_) {
        refreshWeatherView();
        co_return;
    }

    const auto generation = ++weather_location_generation_;
    std::string first_error = weather_storage_error_;
    std::vector<zisla::core::WeatherLocation> locations = weather_locations_;
    if (weather_location_repository_) {
        try {
            locations = weather_location_repository_->load();
            weather_storage_error_.clear();
        } catch (const std::exception& error) {
            if (first_error.empty()) {
                first_error = error.what();
            }
        }
    }

    if (request_current_location) {
        weather_location_pending_ = true;
        weather_status_override_ = "正在获取当前位置";
        refreshWeatherView();
        try {
            const auto position = co_await WeatherLocationService::currentPosition();
            if (!started_ || generation != weather_location_generation_) {
                weather_location_pending_ = false;
                co_return;
            }
            const auto basic = position.Coordinate().Point().Position();
            const zisla::core::GeoCoordinate coordinate{
                basic.Latitude,
                basic.Longitude,
            };
            if (!coordinate.valid()) {
                throw std::runtime_error("Windows 返回了无效位置");
            }
            auto current_name = std::string{"当前位置"};
            if (const auto current = std::find_if(
                    locations.begin(),
                    locations.end(),
                    [](const auto& location) {
                        return location.kind
                            == zisla::core::WeatherLocationKind::current;
                    });
                current != locations.end()) {
                current_name = current->display_name;
            }
            if (weather_location_repository_) {
                weather_location_repository_->update_current(
                    current_name,
                    coordinate);
                locations = weather_location_repository_->load();
            } else {
                if (locations.empty()) {
                    locations.push_back(zisla::core::WeatherLocation::current());
                }
                locations.front() = zisla::core::WeatherLocation::current(
                    current_name,
                    coordinate);
            }
        } catch (const hresult_error& error) {
            const auto message = to_string(error.message());
            if (first_error.empty()) {
                first_error = message.empty()
                    ? "无法获取当前位置"
                    : message;
            }
        } catch (const std::exception& error) {
            if (first_error.empty()) {
                first_error = error.what();
            }
        } catch (...) {
            if (first_error.empty()) {
                first_error = "无法获取当前位置";
            }
        }
        weather_location_pending_ = false;
    }

    if (!started_ || generation != weather_location_generation_
        || !weather_service_) {
        co_return;
    }
    weather_locations_ = locations;
    weather_status_override_.clear();
    if (!weather_service_->requestRefresh(
            std::move(locations),
            std::move(first_error))) {
        weather_status_override_ = "天气服务不可用";
    }
    refreshWeatherView();
}

bool AppHost::weatherIsStale() const noexcept {
    if (!weather_service_) {
        return true;
    }
    const auto snapshot = weather_service_->snapshot();
    if (!snapshot) {
        return true;
    }
    if (snapshot->phase == WeatherServicePhase::loading) {
        return false;
    }
    if (snapshot->weather.empty()) {
        return true;
    }
    const auto now = now_unix_milliseconds();
    return std::any_of(
        snapshot->weather.begin(),
        snapshot->weather.end(),
        [now](const auto& weather) {
            return weather.fetched_at_unix_ms <= 0
                || now - weather.fetched_at_unix_ms >= 15 * 60 * 1'000;
        });
}

void AppHost::handlePomodoroTimer() noexcept {
    try {
        const auto now_unix_ms = now_unix_milliseconds();
        const auto completed_mode = pomodoro_engine_.mode();
        if (pomodoro_engine_.complete_if_needed(now_unix_ms)) {
            stopPomodoroTimer();
            const auto next = pomodoro_engine_.snapshot(now_unix_ms);
            if (!settings_.notifications_muted && notification_service_) {
                (void)notification_service_->show_pomodoro_completion(
                    completed_mode,
                    zisla::core::PomodoroEngine::format_clock(
                        next.remaining_seconds));
            }
            if (settings_.side_notices_enabled && !settings_.notifications_muted) {
                side_notice_queue_.enqueue({
                    .id = "pomodoro-" + std::to_string(now_unix_ms),
                    .title = completed_mode == zisla::core::PomodoroMode::focus
                        ? "专注结束"
                        : "休息结束",
                    .detail = completed_mode == zisla::core::PomodoroMode::focus
                        ? std::optional<std::string>{"开始休息 "
                            + zisla::core::PomodoroEngine::format_clock(
                                next.remaining_seconds)}
                        : std::optional<std::string>{"开始下一段专注"},
                    .kind = zisla::core::NoticeKind::info,
                    .side = zisla::core::NoticeSide::right,
                    .created_at_unix_ms = now_unix_ms,
                }, monotonic_milliseconds());
                anchorSideNoticesToPointer();
                updateSideNoticeWindows();
            }
        }
        refreshPomodoro();
    } catch (...) {
    }
}

void AppHost::stopPomodoroTimer() noexcept {
    if (message_window_) {
        KillTimer(message_window_, pomodoro_timer_id);
    }
}

void AppHost::loadAlarms() noexcept {
    alarm_book_ = zisla::core::AlarmBook{};
    persistence_service_.reset();
    alarm_persistence_revision_ = 0;
    alarm_storage_error_.clear();
    const auto directory = application_state_directory();
    if (!directory) {
        alarm_storage_error_ = "无法访问闹钟存储目录";
        return;
    }
    std::unique_ptr<AppPersistenceService> service;
    try {
        service = std::make_unique<AppPersistenceService>(*directory);
        alarm_book_ = zisla::core::AlarmBook(service->loadAlarms());
    } catch (const std::exception& error) {
        alarm_storage_error_ = "无法读取闹钟：";
        alarm_storage_error_.append(error.what());
    } catch (...) {
        alarm_storage_error_ = "无法读取闹钟";
    }
    bool service_started = false;
    try {
        service_started = service
            && service->start(message_window_, app_persistence_changed_message);
    } catch (...) {
    }
    if (!service_started) {
        if (alarm_storage_error_.empty()) {
            alarm_storage_error_ = "无法启动后台存储服务";
        }
        return;
    }
    persistence_service_ = std::move(service);
}

bool AppHost::commitAlarms(zisla::core::AlarmBook alarms) noexcept {
    if (!persistence_service_) {
        alarm_storage_error_ = "无法保存闹钟：存储不可用";
        refreshAlarms();
        return false;
    }
    const auto revision = persistence_service_->persistAlarms(alarms.alarms());
    if (revision == 0) {
        alarm_storage_error_ = "无法保存闹钟：存储不可用";
        refreshAlarms();
        return false;
    }
    alarm_persistence_revision_ = revision;
    alarm_book_ = std::move(alarms);
    alarm_storage_error_.clear();

    if (notification_service_
        && notification_service_->reschedule_alarms(alarm_book_.alarms())) {
        alarm_notification_error_.clear();
    } else {
        alarm_notification_error_ = "闹钟已保存，但 Windows 通知不可用";
        const auto error = notification_service_
            ? notification_service_->last_error()
            : std::string{};
        if (!error.empty()) {
            alarm_notification_error_.append("：");
            alarm_notification_error_.append(error);
        }
    }
    refreshAlarms();
    scheduleAlarmTimer();
    return true;
}

void AppHost::handleAppPersistenceChanged() noexcept {
    if (!persistence_service_) {
        return;
    }
    const auto snapshot = persistence_service_->snapshot();
    if (!snapshot || snapshot->alarm_revision == 0
        || snapshot->alarm_revision != alarm_persistence_revision_) {
        return;
    }
    if (snapshot->alarm_error.empty()) {
        alarm_storage_error_.clear();
    } else {
        alarm_storage_error_ = "无法保存闹钟：";
        alarm_storage_error_.append(snapshot->alarm_error);
    }
    refreshAlarms();
}

void AppHost::updateAlarmNotificationStatus() noexcept {
    const auto error = notification_service_
        ? notification_service_->last_error()
        : std::string{"Windows app notifications are unavailable"};
    if (error.empty()) {
        alarm_notification_error_.clear();
    } else {
        alarm_notification_error_ = "Windows 闹钟通知不可用：";
        alarm_notification_error_.append(error);
    }
    refreshAlarms();
}

void AppHost::reconcileAndRescheduleAlarms() noexcept {
    stopAlarmTimer();
    const auto now_unix_ms = now_unix_milliseconds();
    auto reconciled = alarm_book_;
    if (reconciled.reconcile(now_unix_ms, alarm_delivery_grace_ms)) {
        if (persistence_service_) {
            const auto revision = persistence_service_->persistAlarms(
                reconciled.alarms());
            if (revision != 0) {
                alarm_persistence_revision_ = revision;
                alarm_book_ = std::move(reconciled);
                alarm_storage_error_.clear();
            } else {
                alarm_storage_error_ = "无法更新已触发闹钟：存储不可用";
            }
        } else {
            alarm_storage_error_ = "无法更新已触发闹钟：存储不可用";
        }
    }

    const bool one_shot_in_delivery_window = std::any_of(
        alarm_book_.alarms().begin(), alarm_book_.alarms().end(),
        [now_unix_ms](const auto& alarm) {
            return alarm.enabled && !alarm.repeating()
                && alarm.one_shot_fire_unix_ms <= now_unix_ms
                && zisla::core::AlarmBook::delivery_deadline(
                       alarm.one_shot_fire_unix_ms,
                       alarm_delivery_grace_ms) > now_unix_ms;
        });
    if (one_shot_in_delivery_window) {
        alarm_notification_error_.clear();
    } else if (notification_service_
        && notification_service_->reschedule_alarms(alarm_book_.alarms())) {
        alarm_notification_error_.clear();
    } else {
        alarm_notification_error_ = "Windows 闹钟通知不可用";
        const auto error = notification_service_
            ? notification_service_->last_error()
            : std::string{};
        if (!error.empty()) {
            alarm_notification_error_.append("：");
            alarm_notification_error_.append(error);
        }
    }
    refreshAlarms();
    scheduleAlarmTimer();
}

void AppHost::scheduleAlarmTimer() noexcept {
    stopAlarmTimer();
    if (!message_window_) {
        return;
    }
    const auto now = current_alarm_clock();
    std::optional<std::int64_t> next_refresh;
    if (const auto next = alarm_book_.next_alarm(now)) {
        next_refresh = zisla::core::AlarmBook::delivery_deadline(
            next->fire_unix_ms,
            alarm_delivery_grace_ms);
    }
    for (const auto& alarm : alarm_book_.alarms()) {
        if (!alarm.enabled || alarm.repeating()
            || alarm.one_shot_fire_unix_ms > now.now_unix_ms) {
            continue;
        }
        const auto cleanup = zisla::core::AlarmBook::delivery_deadline(
            alarm.one_shot_fire_unix_ms,
            alarm_delivery_grace_ms);
        if (cleanup > now.now_unix_ms
            && (!next_refresh || cleanup < *next_refresh)) {
            next_refresh = cleanup;
        }
    }
    if (!next_refresh) {
        return;
    }
    UINT delay = 1;
    if (*next_refresh > now.now_unix_ms) {
        const auto remaining = static_cast<std::uint64_t>(*next_refresh)
            - static_cast<std::uint64_t>(now.now_unix_ms);
        constexpr auto timer_slack_ms = std::uint64_t{1'000};
        constexpr auto maximum_delay = static_cast<std::uint64_t>(
            USER_TIMER_MAXIMUM);
        delay = remaining >= maximum_delay - timer_slack_ms
            ? USER_TIMER_MAXIMUM
            : static_cast<UINT>(remaining + timer_slack_ms);
    }
    (void)SetTimer(message_window_, alarm_timer_id, delay, nullptr);
}

void AppHost::stopAlarmTimer() noexcept {
    if (message_window_) {
        KillTimer(message_window_, alarm_timer_id);
    }
}

void AppHost::handleTeleprompterTimer() noexcept {
    if (!teleprompter_window_ || !teleprompter_window_->visible()) {
        teleprompter_engine_.pause();
        stopTeleprompterTimer();
        return;
    }
    try {
        const auto now = monotonic_milliseconds();
        const auto elapsed = teleprompter_last_tick_ms_ == 0
            ? 0.0
            : static_cast<double>(now - teleprompter_last_tick_ms_) / 1'000.0;
        teleprompter_last_tick_ms_ = now;
        teleprompter_engine_.advance(
            elapsed,
            teleprompter_window_->scrollableHeight());
        if (!teleprompter_engine_.auto_scrolling()) {
            stopTeleprompterTimer();
        }
        refreshTeleprompter();
    } catch (...) {
        teleprompter_engine_.pause();
        stopTeleprompterTimer();
        refreshTeleprompter();
    }
}

void AppHost::stopTeleprompterTimer() noexcept {
    if (message_window_) {
        KillTimer(message_window_, teleprompter_timer_id);
    }
    teleprompter_last_tick_ms_ = 0;
}

void AppHost::consumeClipboardLink() noexcept {
    if (!clipboard_history_service_) {
        return;
    }
    try {
        const auto link = clipboard_history_service_->detected_link();
        if (!link) {
            return;
        }
        if (overlay_window_) {
            overlay_window_->setDetectedClipboardLink(link->url);
        }
        if (settings_.side_notices_enabled && !settings_.notifications_muted) {
            side_notice_queue_.enqueue({
                .id = "clipboard-link-" + (link->host.empty() ? std::string{"media"} : link->host),
                .title = "发现可下载链接",
                .detail = link->host.empty()
                    ? std::optional<std::string>{"媒体链接"}
                    : std::optional<std::string>{link->host},
                .kind = zisla::core::NoticeKind::info,
                .side = zisla::core::NoticeSide::left,
                .created_at_unix_ms = now_unix_milliseconds(),
            }, monotonic_milliseconds());
            anchorSideNoticesToPointer();
            updateSideNoticeWindows();
        }
    } catch (...) {
    }
}

void AppHost::updateClipboardListener() noexcept {
    const bool link_detection_enabled = settings_.downloader_enabled
        && settings_.clipboard_detection_enabled;
    const bool service_needed = settings_.clipboard_history_enabled
        || link_detection_enabled;
    if (service_needed && !clipboard_history_service_) {
        try {
            if (const auto state_directory = AIStateMonitor::defaultStateDirectory()) {
                auto service = std::make_unique<ClipboardHistoryService>(
                    *state_directory);
                if (service->start(
                        message_window_,
                        clipboard_history_changed_message,
                        clipboard_link_detected_message)) {
                    clipboard_history_service_ = std::move(service);
                }
            }
        } catch (...) {
            clipboard_history_service_.reset();
        }
    }
    if (clipboard_history_service_) {
        clipboard_history_service_->configure(
            settings_.clipboard_history_enabled,
            link_detection_enabled);
    }
    const bool should_listen = clipboard_history_service_ && service_needed;
    if (should_listen && !clipboard_listener_registered_ && message_window_) {
        clipboard_listener_registered_ =
            AddClipboardFormatListener(message_window_) != FALSE;
    } else if (!should_listen && clipboard_listener_registered_ && message_window_) {
        (void)RemoveClipboardFormatListener(message_window_);
        clipboard_listener_registered_ = false;
    }
    if (!service_needed) {
        clipboard_history_service_.reset();
    }
}

void AppHost::consumeExternalNotices(std::int64_t now_unix_ms) {
    if (!ai_state_monitor_) {
        return;
    }
    auto notices = ai_state_monitor_->takeNotices();
    if (notices.empty() || !settings_.side_notices_enabled
        || settings_.notifications_muted) {
        return;
    }

    const auto earliest = launch_unix_ms_ - 2'000;
    std::vector<zisla::core::IslandNotice> accepted;
    accepted.reserve(notices.size());
    for (auto& notice : notices) {
        if (notice.created_at_unix_ms >= earliest
            && notice.created_at_unix_ms <= now_unix_ms + 300'000) {
            accepted.push_back(std::move(notice));
        }
    }
    if (accepted.empty()) {
        return;
    }
    side_notice_queue_.enqueue_all(accepted, monotonic_milliseconds());
    anchorSideNoticesToPointer();
}

void AppHost::refreshAIActivityNotices(
    std::span<const zisla::core::AIProgressTask> activities,
    std::int64_t now_unix_ms) {
    if (!settings_.side_notices_enabled || settings_.notifications_muted) {
        for (const auto& id : active_ai_notice_ids_) {
            (void)side_notice_queue_.remove(id);
        }
        active_ai_notice_ids_.clear();
        shown_ai_notice_ids_.clear();
        ai_task_statuses_.clear();
        return;
    }

    std::unordered_map<std::string, zisla::core::AIProgressStatus> next_statuses;
    std::unordered_set<std::string> next_active_notice_ids;
    bool enqueued = false;

    for (const auto& task : activities) {
        const auto key = ai_task_key(task);
        const auto previous = ai_task_statuses_.find(key);
        const bool status_changed = previous != ai_task_statuses_.end()
            && previous->second != task.status;
        next_statuses.emplace(key, task.status);

        if (zisla::core::is_active(task.status)) {
            const auto notice_id = active_ai_notice_id(task);
            next_active_notice_ids.insert(notice_id);
            const zisla::core::IslandNotice notice{
                .id = notice_id,
                .title = task.title,
                .detail = task.detail,
                .kind = zisla::core::notice_kind_for(task.status),
                .side = notice_side(task.provider),
                .created_at_unix_ms = task.updated_at_unix_ms,
                .progress = task.progress,
            };
            if (!side_notice_queue_.update_if_present(notice)
                && (!shown_ai_notice_ids_.contains(notice_id) || status_changed)) {
                side_notice_queue_.enqueue(notice, monotonic_milliseconds());
                shown_ai_notice_ids_.insert(notice_id);
                enqueued = true;
            }
        }

        const bool terminal = task.status == zisla::core::AIProgressStatus::succeeded
            || task.status == zisla::core::AIProgressStatus::failed;
        if (status_changed && terminal) {
            side_notice_queue_.enqueue({
                .id = "task-" + key + "-" + std::to_string(task.updated_at_unix_ms),
                .title = task.title,
                .detail = task.status == zisla::core::AIProgressStatus::succeeded
                    ? std::optional<std::string>{"任务已完成"}
                    : std::optional<std::string>{"任务执行失败"},
                .kind = zisla::core::notice_kind_for(task.status),
                .side = task.status == zisla::core::AIProgressStatus::succeeded
                    ? zisla::core::NoticeSide::right
                    : zisla::core::NoticeSide::left,
                .created_at_unix_ms = now_unix_ms,
            }, monotonic_milliseconds());
            enqueued = true;
        }
    }

    for (const auto& id : active_ai_notice_ids_) {
        if (!next_active_notice_ids.contains(id)) {
            (void)side_notice_queue_.remove(id);
            shown_ai_notice_ids_.erase(id);
        }
    }
    active_ai_notice_ids_ = std::move(next_active_notice_ids);
    ai_task_statuses_ = std::move(next_statuses);
    if (enqueued) {
        anchorSideNoticesToPointer();
    }
}

void AppHost::refreshMediaNotice(
    std::shared_ptr<const zisla::core::NowPlayingSnapshot> snapshot) {
    constexpr std::string_view left_id = "media-active-left";
    constexpr std::string_view right_id = "media-active-right";
    if (!settings_.side_notices_enabled || settings_.notifications_muted
        || !snapshot || !snapshot->valid()
        || snapshot->playback_status != zisla::core::MediaPlaybackStatus::playing) {
        (void)side_notice_queue_.remove(left_id);
        (void)side_notice_queue_.remove(right_id);
        media_notice_presented_ = false;
        return;
    }

    const auto source = snapshot->source_application.empty()
        ? std::string{"媒体播放器"}
        : snapshot->source_application;
    std::string detail = snapshot->title;
    if (!snapshot->artist.empty()) {
        if (!detail.empty()) {
            detail.append(" \xC2\xB7 ");
        }
        detail.append(snapshot->artist);
    }
    const auto now = now_unix_milliseconds();
    const std::array notices{
        zisla::core::IslandNotice{
            .id = std::string{left_id},
            .title = source,
            .detail = snapshot->title,
            .kind = zisla::core::NoticeKind::info,
            .side = zisla::core::NoticeSide::left,
            .created_at_unix_ms = now,
        },
        zisla::core::IslandNotice{
            .id = std::string{right_id},
            .title = "正在播放",
            .detail = std::move(detail),
            .kind = zisla::core::NoticeKind::info,
            .side = zisla::core::NoticeSide::right,
            .created_at_unix_ms = now,
        },
    };

    const bool left_visible = side_notice_queue_.update_if_present(notices[0]);
    const bool right_visible = side_notice_queue_.update_if_present(notices[1]);
    if (left_visible || right_visible || media_notice_presented_) {
        return;
    }
    side_notice_queue_.enqueue_all(notices, monotonic_milliseconds());
    media_notice_presented_ = true;
    anchorSideNoticesToPointer();
}

void AppHost::updateSideNoticeWindows() noexcept {
    scheduleSideNoticeExpiration();
    if (!settings_.side_notices_enabled || settings_.notifications_muted
        || side_notice_queue_.empty()
        || cleaning_session_.active()
        || (teleprompter_window_ && teleprompter_window_->visible())
        || (camera_mirror_window_ && camera_mirror_window_->visible())
        || presentation_engine_.state().visibility
            != zisla::core::OverlayVisibility::hidden
        || (settings_window_ && IsWindowVisible(settings_window_->hwnd()))
        || !custom_notifications_allowed()) {
        hideSideNoticeWindows();
        return;
    }

    if (!side_notice_monitor_) {
        anchorSideNoticesToPointer();
    }
    auto screen = DisplayTopology::screenForMonitor(side_notice_monitor_);
    if (screen.work_area.width <= 0 || screen.work_area.height <= 0) {
        side_notice_monitor_ = nullptr;
        anchorSideNoticesToPointer();
        screen = DisplayTopology::screenForMonitor(side_notice_monitor_);
    }
    if (!side_notice_monitor_ || screen.work_area.width <= 0
        || screen.work_area.height <= 0
        || DisplayTopology::foregroundWindowCoversMonitor(
            side_notice_monitor_,
            overlay_window_ ? overlay_window_->hwnd() : nullptr,
            settings_window_ ? settings_window_->hwnd() : nullptr)) {
        hideSideNoticeWindows();
        return;
    }

    try {
        const auto left_state = side_notice_queue_.view_state(
            zisla::core::NoticeSide::left);
        const auto right_state = side_notice_queue_.view_state(
            zisla::core::NoticeSide::right);
        const auto left_rows = left_state.ordinary_notices.size()
            + static_cast<std::size_t>(left_state.compact_notice.has_value());
        const auto right_rows = right_state.ordinary_notices.size()
            + static_cast<std::size_t>(right_state.compact_notice.has_value());

        if (left_rows == 0) {
            if (left_notice_window_) {
                left_notice_window_->hide();
            }
        } else {
            if (!left_notice_window_) {
                left_notice_window_ = std::make_unique<SideNoticeWindow>(
                    zisla::core::NoticeSide::left);
            }
            left_notice_window_->show(
                placement_engine_.sideNoticePanel(
                    screen,
                    zisla::core::NoticeSide::left,
                    left_rows),
                left_state);
        }

        if (right_rows == 0) {
            if (right_notice_window_) {
                right_notice_window_->hide();
            }
        } else {
            if (!right_notice_window_) {
                right_notice_window_ = std::make_unique<SideNoticeWindow>(
                    zisla::core::NoticeSide::right);
            }
            right_notice_window_->show(
                placement_engine_.sideNoticePanel(
                    screen,
                    zisla::core::NoticeSide::right,
                    right_rows),
                right_state);
        }
    } catch (...) {
        hideSideNoticeWindows();
    }
}

void AppHost::hideSideNoticeWindows() noexcept {
    if (left_notice_window_) {
        left_notice_window_->hide();
    }
    if (right_notice_window_) {
        right_notice_window_->hide();
    }
}

void AppHost::scheduleSideNoticeExpiration() noexcept {
    cancelSideNoticeExpiration();
    if (!message_window_) {
        return;
    }
    const auto next = side_notice_queue_.next_expiration_ms();
    if (!next) {
        return;
    }
    const auto now = monotonic_milliseconds();
    const auto remaining = *next <= now ? std::int64_t{1} : *next - now;
    const auto delay = static_cast<UINT>(std::min<std::int64_t>(
        remaining,
        USER_TIMER_MAXIMUM));
    (void)SetTimer(message_window_, side_notice_timer_id, delay, nullptr);
}

void AppHost::cancelSideNoticeExpiration() noexcept {
    if (message_window_) {
        KillTimer(message_window_, side_notice_timer_id);
    }
}

void AppHost::anchorSideNoticesToPointer() noexcept {
    POINT cursor{};
    side_notice_monitor_ = GetCursorPos(&cursor)
        ? DisplayTopology::monitorForPoint(cursor)
        : MonitorFromWindow(message_window_, MONITOR_DEFAULTTOPRIMARY);
}

void AppHost::promoteOverlay() {
    if (presentation_engine_.state().visibility
        == zisla::core::OverlayVisibility::peek) {
        dispatchPresentationAction(
            zisla::core::PresentationAction::interactionRequested(
                presentation_engine_.state().anchor));
    }
}

void AppHost::dismissOverlay() {
    dispatchPresentationAction(zisla::core::PresentationAction::dismissRequested());
}

void AppHost::togglePin() {
    dispatchPresentationAction(zisla::core::PresentationAction::pinChanged(
        !presentation_engine_.state().pinned));
}

void AppHost::showSettings() {
    dismissOverlay();
    hideSideNoticeWindows();
    if (!settings_window_) {
        settings_window_ = std::make_unique<SettingsWindow>();
    }
    settings_window_->show();
}

void AppHost::openTaskbarWidget() {
    if (cleaning_session_.active()) {
        return;
    }
    dispatchPresentationAction(
        zisla::core::PresentationAction::interactionRequested(
            zisla::core::OverlayAnchor::taskbar));
}

void AppHost::setTaskbarWidgetEnabled(bool enabled) {
    if (taskbar_widget_enabled_ == enabled) {
        return;
    }
    taskbar_widget_enabled_ = enabled;
    if (!enabled && presentation_engine_.state().anchor
        == zisla::core::OverlayAnchor::taskbar) {
        dismissOverlay();
    }
    refreshTaskbarWidget();
    saveSettings();
}

void AppHost::setPetEnabled(bool enabled) {
    if (settings_.pet_enabled == enabled) {
        return;
    }
    settings_.pet_enabled = enabled;
    if (!enabled && pet_window_) {
        pet_window_->hide();
    } else if (enabled && !pet_window_) {
        (void)loadSelectedPet();
    }
    refreshPet();
    saveSettings();
}

void AppHost::setPetId(std::string id) {
    if (id.empty() || id == settings_.pet_id) {
        return;
    }
    const auto previous = settings_.pet_id;
    settings_.pet_id = std::move(id);
    if (!loadSelectedPet()) {
        settings_.pet_id = previous;
        return;
    }
    refreshPet();
    saveSettings();
}

void AppHost::setPetSide(zisla::core::PetSide side) {
    if (settings_.pet_side == side) {
        return;
    }
    settings_.pet_side = side;
    refreshPet();
    saveSettings();
}

void AppHost::setTopEdgeEnabled(bool enabled) {
    if (top_edge_enabled_ == enabled) {
        return;
    }
    top_edge_enabled_ = enabled;
    if (enabled) {
        const bool trigger_started = message_window_
            && top_edge_trigger_.start(
                message_window_,
                top_edge_entered_message,
                top_edge_exited_message);
        const bool timer_started = trigger_started
            && SetTimer(
                message_window_,
                top_edge_timer_id,
                top_edge_poll_interval_ms,
                nullptr) != 0;
        if (!timer_started) {
            if (message_window_) {
                KillTimer(message_window_, top_edge_timer_id);
            }
            top_edge_trigger_.stop();
            top_edge_enabled_ = false;
        }
    } else {
        if (message_window_) {
            KillTimer(message_window_, top_edge_timer_id);
        }
        top_edge_trigger_.stop();
        if (presentation_engine_.state().anchor
            == zisla::core::OverlayAnchor::top_edge) {
            dismissOverlay();
        }
    }
    saveSettings();
}

void AppHost::setSideNoticesEnabled(bool enabled) {
    if (settings_.side_notices_enabled == enabled) {
        return;
    }
    settings_.side_notices_enabled = enabled;
    if (!enabled) {
        side_notice_queue_.clear();
        active_ai_notice_ids_.clear();
        shown_ai_notice_ids_.clear();
        media_notice_presented_ = false;
        browser_completed_notice_ids_.clear();
        updateSideNoticeWindows();
    } else {
        refreshAIActivities();
        refreshNowPlaying();
        refreshBrowserDownloads();
    }
    saveSettings();
}

void AppHost::setClipboardHistoryEnabled(bool enabled) {
    if (settings_.clipboard_history_enabled == enabled) {
        return;
    }
    settings_.clipboard_history_enabled = enabled;
    updateClipboardListener();
    refreshClipboardHistory();
    saveSettings();
}

void AppHost::setClipboardDetectionEnabled(bool enabled) {
    if (settings_.clipboard_detection_enabled == enabled) {
        return;
    }
    settings_.clipboard_detection_enabled = enabled;
    updateClipboardListener();
    saveSettings();
}

void AppHost::setVoiceInputEnabled(bool enabled) {
    if (settings_.voice_input_enabled == enabled) {
        return;
    }

    settings_.voice_input_enabled = enabled;
    if (!enabled) {
        cancelVoiceFinalization();
        if (voice_input_service_) {
            voice_input_service_->cancel();
        }
        voice_input_service_.reset();
        voice_input_phase_ = zisla::core::VoiceInputPhase::idle;
    }
    refreshVoiceInput();
    refreshVoiceHotkey();
    saveSettings();
}

void AppHost::setVoiceHotkeyAction(zisla::core::VoiceHotkeyAction action) {
    if (settings_.voice_hotkey_action == action) {
        return;
    }
    settings_.voice_hotkey_action = action;
    refreshVoiceHotkey();
    saveSettings();
}

void AppHost::setVoiceHotkeyPreset(zisla::core::VoiceHotkeyPreset preset) {
    if (settings_.voice_hotkey_preset == preset) {
        return;
    }
    settings_.voice_hotkey_preset = preset;
    refreshVoiceHotkey();
    saveSettings();
}

void AppHost::toggleVoiceInput() {
    if (!settings_.voice_input_enabled || !message_window_) {
        return;
    }

    try {
        if (!voice_input_service_) {
            startVoiceInput();
            return;
        }

        const auto phase = voice_input_service_->snapshot().phase;
        if (phase == zisla::core::VoiceInputPhase::listening) {
            stopVoiceInput();
            return;
        } else if (phase == zisla::core::VoiceInputPhase::finalizing) {
            cancelVoiceFinalization();
            voice_input_service_->finish_finalization();
        } else if (phase == zisla::core::VoiceInputPhase::idle
            || phase == zisla::core::VoiceInputPhase::failed) {
            startVoiceInput();
            return;
        } else {
            voice_input_service_->cancel();
            refreshVoiceInput();
            return;
        }
        startVoiceInput();
    } catch (...) {
        if (voice_input_service_) {
            voice_input_service_->cancel();
        }
        refreshVoiceInput();
    }
}

void AppHost::setNotificationsMuted(bool muted) {
    if (settings_.notifications_muted == muted) {
        return;
    }
    settings_.notifications_muted = muted;
    if (muted) {
        side_notice_queue_.clear();
        active_ai_notice_ids_.clear();
        shown_ai_notice_ids_.clear();
        media_notice_presented_ = false;
        browser_completed_notice_ids_.clear();
        updateSideNoticeWindows();
    } else {
        refreshAIActivities();
        refreshNowPlaying();
        refreshBrowserDownloads();
    }
    saveSettings();
}

void AppHost::setWeatherEnabled(bool enabled) {
    if (settings_.weather_enabled == enabled) {
        return;
    }
    settings_.weather_enabled = enabled;
    ++weather_location_generation_;
    weather_location_pending_ = false;
    weather_status_override_.clear();
    if (enabled) {
        startWeatherService();
    } else {
        weather_service_.reset();
    }
    refreshWeatherView();
    saveSettings();
}

void AppHost::setBrowserDownloadStatusEnabled(bool enabled) {
    if (settings_.browser_download_status_enabled == enabled) {
        return;
    }
    settings_.browser_download_status_enabled = enabled;
    browser_completed_notice_ids_.clear();
    if (!enabled) {
        browser_download_service_.reset();
        (void)side_notice_queue_.remove("browser-download-active-right");
    } else if (started_ && message_window_) {
        browser_download_service_ = std::make_unique<BrowserDownloadService>();
        if (!browser_download_service_->start(
                message_window_,
                browser_download_changed_message)) {
            browser_download_service_.reset();
        }
    }
    refreshBrowserDownloads();
    saveSettings();
}

void AppHost::setSystemMonitorActive(bool active) noexcept {
    if (system_monitor_service_) {
        system_monitor_service_->set_active(active);
    }
}

void AppHost::refreshDesktopTools() {
    if (desktop_tools_service_) {
        desktop_tools_service_->refreshRecycleBin();
    }
}

void AppHost::arrangeDesktop() {
    if (desktop_tools_service_) {
        desktop_tools_service_->arrangeDesktop();
    }
}

void AppHost::emptyRecycleBin() {
    if (desktop_tools_service_) {
        desktop_tools_service_->emptyRecycleBin();
    }
}

void AppHost::openStoreUpdates() {
    if (desktop_tools_service_) {
        desktop_tools_service_->openStoreUpdates();
    }
}

void AppHost::checkForUpdates(zisla::core::UpdateChannel channel) {
    update_channel_ = channel;
    saveSettings();
    if (update_service_) {
        update_service_->check(channel);
    }
    refreshUpdate();
}

void AppHost::openAvailableUpdate() {
    if (!update_service_) {
        return;
    }
    const auto snapshot = update_service_->snapshot();
    if (!snapshot || !snapshot->update) {
        return;
    }
    const auto target = update_install_url(*snapshot->update);
    if (target.empty()) {
        return;
    }
    const auto uri = to_hstring(target);
    (void)ShellExecuteW(
        nullptr,
        L"open",
        uri.c_str(),
        nullptr,
        nullptr,
        SW_SHOWNORMAL);
}

void AppHost::configureMail(MailConnectionSettings settings) {
    if (settings.tenant.empty()) {
        settings.tenant = "common";
    }
    if (settings.tenant.size() > 128
        || settings.client_id.size()
            > zisla::core::GraphOAuthRequestBuilder::maximum_client_id_bytes
        || settings.account_name.size() > 256) {
        return;
    }
    mail_connection_settings_ = std::move(settings);
    saveSettings();
    const bool was_running = mail_service_ != nullptr;
    if (startMailService() && was_running) {
        mail_service_->configure(mail_connection_settings_);
    }
    refreshMailView();
}

void AppHost::beginMailAuthorization() {
    if (startMailService()) {
        mail_service_->begin_authorization();
    }
}

void AppHost::refreshMail() {
    if (startMailService()) {
        mail_service_->refresh();
    }
}

void AppHost::markMailRead(std::string message_id) {
    if (startMailService()) {
        mail_service_->mark_read(std::move(message_id));
    }
}

void AppHost::moveMailToJunk(std::string message_id) {
    if (startMailService()) {
        mail_service_->move_to_junk(std::move(message_id));
    }
}

void AppHost::deleteMail(std::string message_id) {
    if (startMailService()) {
        mail_service_->move_to_deleted(std::move(message_id));
    }
}

void AppHost::sendMail(
    std::vector<zisla::core::MailRecipient> recipients,
    std::string subject,
    std::string body) {
    if (startMailService()) {
        mail_service_->send(
            std::move(recipients),
            std::move(subject),
            std::move(body));
    }
}

void AppHost::replyMail(std::string message_id, std::string body) {
    if (startMailService()) {
        mail_service_->reply(std::move(message_id), std::move(body));
    }
}

void AppHost::trimOwnWorkingSet() {
    if (desktop_tools_service_) {
        desktop_tools_service_->trimOwnWorkingSet();
    }
}

void AppHost::scanDiskCleanup() {
    if (disk_cleanup_service_) {
        disk_cleanup_service_->scan();
    }
}

void AppHost::cleanDiskCleanup(std::vector<std::filesystem::path> paths) {
    if (disk_cleanup_service_ && !paths.empty()) {
        disk_cleanup_service_->clean(std::move(paths));
    }
}

void AppHost::refreshWeather() {
    if (!settings_.weather_enabled) {
        return;
    }
    refreshWeatherAsync(true);
}

void AppHost::searchWeatherLocation(std::string query) {
    if (!settings_.weather_enabled) {
        return;
    }
    startWeatherService();
    weather_status_override_.clear();
    if (!weather_service_ || !weather_service_->requestSearch(std::move(query))) {
        weather_status_override_ = "天气服务不可用";
        refreshWeatherView();
    }
}

void AppHost::removeWeatherLocation(std::string id) {
    if (!weather_location_repository_) {
        return;
    }
    try {
        if (!weather_location_repository_->remove(id)) {
            return;
        }
        weather_locations_ = weather_location_repository_->load();
        weather_storage_error_.clear();
        if (settings_.weather_enabled) {
            refreshWeatherAsync(false);
        } else {
            refreshWeatherView();
        }
    } catch (const std::exception& error) {
        weather_storage_error_ = error.what();
        refreshWeatherView();
    }
}

void AppHost::setSideNoticeHovered(std::string_view id, bool hovered) {
    if (side_notice_queue_.set_hovered(
            id,
            hovered,
            monotonic_milliseconds())) {
        scheduleSideNoticeExpiration();
    }
}

void AppHost::dismissSideNotice(std::string_view id) {
    if (side_notice_queue_.remove(id)) {
        updateSideNoticeWindows();
    }
}

void AppHost::settingsWindowHidden() noexcept {
    updateSideNoticeWindows();
}

void AppHost::toggleMediaPlayback() {
    if (media_session_monitor_) {
        if (const auto snapshot = media_session_monitor_->snapshot()) {
            (void)media_session_monitor_->request({
                .kind = MediaSessionCommandKind::toggle_play_pause,
                .session_id = snapshot->session_id,
            });
        }
    }
}

void AppHost::playPreviousMedia() {
    if (media_session_monitor_) {
        if (const auto snapshot = media_session_monitor_->snapshot()) {
            (void)media_session_monitor_->request({
                .kind = MediaSessionCommandKind::previous,
                .session_id = snapshot->session_id,
            });
        }
    }
}

void AppHost::playNextMedia() {
    if (media_session_monitor_) {
        if (const auto snapshot = media_session_monitor_->snapshot()) {
            (void)media_session_monitor_->request({
                .kind = MediaSessionCommandKind::next,
                .session_id = snapshot->session_id,
            });
        }
    }
}

void AppHost::seekMedia(double position_seconds) {
    if (media_session_monitor_) {
        if (const auto snapshot = media_session_monitor_->snapshot()) {
            (void)media_session_monitor_->request({
                .kind = MediaSessionCommandKind::seek,
                .session_id = snapshot->session_id,
                .position_seconds = position_seconds,
            });
        }
    }
}

void AppHost::togglePomodoro() {
    const auto now_unix_ms = now_unix_milliseconds();
    if (pomodoro_engine_.phase() == zisla::core::PomodoroPhase::running) {
        pomodoro_engine_.pause(now_unix_ms);
        stopPomodoroTimer();
    } else {
        pomodoro_engine_.start(now_unix_ms);
        if (!SetTimer(
                message_window_,
                pomodoro_timer_id,
                pomodoro_timer_interval_ms,
                nullptr)) {
            pomodoro_engine_.pause(now_unix_ms);
        }
    }
    refreshPomodoro();
}

void AppHost::resetPomodoro() {
    stopPomodoroTimer();
    pomodoro_engine_.reset();
    refreshPomodoro();
}

void AppHost::setPomodoroDuration(
    zisla::core::PomodoroMode mode,
    std::int64_t seconds) {
    if (seconds <= 0) {
        return;
    }
    if (pomodoro_engine_.mode() == mode) {
        stopPomodoroTimer();
    }
    pomodoro_engine_.set_duration_seconds(mode, seconds);
    saveSettings();
    refreshPomodoro();
}

bool AppHost::addAlarm(
    int hour,
    int minute,
    std::string label,
    zisla::core::AlarmWeekdayMask weekday_mask) {
    zisla::core::AlarmItem alarm{
        .id = new_alarm_id(),
        .hour = hour,
        .minute = minute,
        .label = std::move(label),
        .weekday_mask = weekday_mask,
    };
    if (alarm.id.empty()) {
        alarm_storage_error_ = "无法创建闹钟标识";
        refreshAlarms();
        return false;
    }
    if (!alarm.repeating()) {
        const auto fire_time = AppNotificationService::next_one_shot_fire_unix_ms(
            alarm.hour, alarm.minute);
        if (!fire_time) {
            alarm_storage_error_ = "无法计算闹钟触发时间";
            refreshAlarms();
            return false;
        }
        alarm.one_shot_fire_unix_ms = *fire_time;
    }

    auto next = alarm_book_;
    if (!next.add(std::move(alarm))) {
        alarm_storage_error_ = "无法添加闹钟，最多可保存 64 条";
        refreshAlarms();
        return false;
    }
    return commitAlarms(std::move(next));
}

bool AppHost::updateAlarm(
    std::string id,
    int hour,
    int minute,
    std::string label,
    zisla::core::AlarmWeekdayMask weekday_mask) {
    const auto existing = alarm_book_.find(id);
    if (!existing) {
        alarm_storage_error_ = "要编辑的闹钟已不存在";
        refreshAlarms();
        return false;
    }
    auto alarm = *existing;
    alarm.hour = hour;
    alarm.minute = minute;
    alarm.label = std::move(label);
    alarm.weekday_mask = weekday_mask;
    if (weekday_mask == 0) {
        const auto fire_time = AppNotificationService::next_one_shot_fire_unix_ms(
            hour, minute);
        if (!fire_time) {
            alarm_storage_error_ = "无法计算闹钟触发时间";
            refreshAlarms();
            return false;
        }
        alarm.one_shot_fire_unix_ms = *fire_time;
    } else {
        alarm.one_shot_fire_unix_ms = 0;
    }

    auto next = alarm_book_;
    if (!next.update(std::move(alarm))) {
        alarm_storage_error_ = "无法更新闹钟";
        refreshAlarms();
        return false;
    }
    return commitAlarms(std::move(next));
}

void AppHost::setAlarmEnabled(std::string id, bool enabled) {
    const auto existing = alarm_book_.find(id);
    if (!existing || existing->enabled == enabled) {
        return;
    }
    auto alarm = *existing;
    alarm.enabled = enabled;
    if (enabled && !alarm.repeating()) {
        const auto fire_time = AppNotificationService::next_one_shot_fire_unix_ms(
            alarm.hour, alarm.minute);
        if (!fire_time) {
            alarm_storage_error_ = "无法计算闹钟触发时间";
            refreshAlarms();
            return;
        }
        alarm.one_shot_fire_unix_ms = *fire_time;
    }
    auto next = alarm_book_;
    if (next.update(std::move(alarm))) {
        (void)commitAlarms(std::move(next));
    }
}

void AppHost::removeAlarm(std::string id) {
    auto next = alarm_book_;
    if (next.remove(id)) {
        (void)commitAlarms(std::move(next));
    }
}

void AppHost::openSystemClock() {
    const auto result = reinterpret_cast<INT_PTR>(ShellExecuteW(
        nullptr,
        L"open",
        L"ms-clock:",
        nullptr,
        nullptr,
        SW_SHOWNORMAL));
    if (result <= 32) {
        alarm_storage_error_ = "无法打开 Windows 时钟";
        refreshAlarms();
    }
}

void AppHost::setKeepDisplayAwake(bool enabled) {
    if (power_request_controller_) {
        (void)power_request_controller_->set_keep_display_awake(enabled);
    }
    refreshPowerRequests();
}

void AppHost::setPreventIdleSystemSleep(bool enabled) {
    if (power_request_controller_) {
        (void)power_request_controller_->set_prevent_idle_system_sleep(enabled);
    }
    refreshPowerRequests();
}

void AppHost::startScreenCleaning() {
    startCleaning(zisla::core::CleaningMode::screen);
}

void AppHost::startKeyboardCleaning() {
    startCleaning(zisla::core::CleaningMode::keyboard);
}

void AppHost::requestEndCleaning() noexcept {
    if (message_window_) {
        (void)PostMessageW(message_window_, cleaning_exit_message, 0, 0);
    }
}

void AppHost::showTeleprompter() {
    try {
        closeCameraMirror();
        dismissOverlay();
        hideSideNoticeWindows();
        if (!teleprompter_window_) {
            teleprompter_window_ = std::make_unique<TeleprompterWindow>();
        }
        refreshTeleprompter();
        teleprompter_window_->show();
    } catch (...) {
        teleprompter_window_.reset();
        teleprompter_engine_.pause();
        stopTeleprompterTimer();
    }
}

void AppHost::closeTeleprompter() noexcept {
    teleprompter_engine_.pause();
    stopTeleprompterTimer();
    if (teleprompter_window_) {
        teleprompter_window_->hide();
    }
    refreshTeleprompter();
    updateSideNoticeWindows();
}

void AppHost::toggleTeleprompterScrolling() {
    if (teleprompter_engine_.toggle_auto_scroll()) {
        teleprompter_last_tick_ms_ = monotonic_milliseconds();
        if (!SetTimer(
                message_window_,
                teleprompter_timer_id,
                teleprompter_timer_interval_ms,
                nullptr)) {
            teleprompter_engine_.pause();
            teleprompter_last_tick_ms_ = 0;
        }
    } else {
        stopTeleprompterTimer();
    }
    refreshTeleprompter();
}

void AppHost::resetTeleprompter() {
    teleprompter_engine_.reset();
    stopTeleprompterTimer();
    refreshTeleprompter();
}

void AppHost::setTeleprompterSpeed(double speed) {
    teleprompter_engine_.set_scroll_speed(speed);
    saveSettings();
    refreshTeleprompter();
}

void AppHost::setTeleprompterScript(std::string script) {
    if (script.size()
        > AppPersistenceService::maximum_teleprompter_script_bytes) {
        return;
    }
    teleprompter_engine_.set_script(script);
    stopTeleprompterTimer();
    if (persistence_service_) {
        persistence_service_->persistTeleprompter(std::move(script));
    }
    refreshTeleprompter();
}

void AppHost::showCameraMirror() {
    try {
        closeTeleprompter();
        dismissOverlay();
        hideSideNoticeWindows();
        if (!camera_mirror_window_) {
            camera_mirror_window_ = std::make_unique<CameraMirrorWindow>();
        }
        if (!camera_mirror_service_) {
            camera_mirror_service_ = std::make_shared<CameraMirrorService>(
                message_window_,
                camera_mirror_changed_message,
                camera_mirror_failed_message);
        }
        camera_mirror_window_->show();
        const auto phase = camera_mirror_service_->snapshot().phase;
        if (phase == zisla::core::CameraMirrorPhase::idle
            || phase == zisla::core::CameraMirrorPhase::failed) {
            camera_mirror_service_->start();
        }
        refreshCameraMirror();
    } catch (...) {
        if (camera_mirror_window_) {
            camera_mirror_window_->detachPreview();
        }
        if (camera_mirror_service_) {
            camera_mirror_service_->stop();
        }
        camera_mirror_window_.reset();
        camera_mirror_service_.reset();
    }
}

void AppHost::closeCameraMirror() noexcept {
    if (camera_mirror_window_) {
        camera_mirror_window_->detachPreview();
    }
    if (camera_mirror_service_) {
        camera_mirror_service_->stop();
    }
    refreshCameraMirror();
    if (camera_mirror_window_) {
        camera_mirror_window_->hide();
    }
    updateSideNoticeWindows();
}

void AppHost::retryCameraMirror() {
    if (!camera_mirror_window_ || !camera_mirror_window_->visible()
        || !camera_mirror_service_) {
        return;
    }
    camera_mirror_window_->detachPreview();
    camera_mirror_service_->start();
    refreshCameraMirror();
}

void AppHost::startCleaning(zisla::core::CleaningMode mode) noexcept {
    if (mode == zisla::core::CleaningMode::idle
        || (cleaning_session_.mode() == mode && !cleaning_windows_.empty())) {
        return;
    }

    try {
        if (!replaceCleaningWindows(mode)) {
            return;
        }
        const bool was_active = cleaning_session_.active();
        (void)cleaning_session_.set_mode(mode);
        if (!was_active) {
            holdPowerRequestsForCleaning();
        }
        refreshCleaning();
        refreshTaskbarWidget();
        dismissOverlay();
        hideSideNoticeWindows();
    } catch (...) {
    }
}

void AppHost::endCleaning() noexcept {
    if (!cleaning_session_.active()) {
        return;
    }
    cleaning_windows_.clear();
    cleaning_session_.stop();
    restorePowerRequestsAfterCleaning();
    refreshCleaning();
    refreshTaskbarWidget();
    updateSideNoticeWindows();
}

void AppHost::rebuildCleaningWindows() noexcept {
    try {
        (void)replaceCleaningWindows(cleaning_session_.mode());
    } catch (...) {
    }
}

bool AppHost::replaceCleaningWindows(zisla::core::CleaningMode mode) {
    if (mode == zisla::core::CleaningMode::idle) {
        return false;
    }

    POINT cursor{};
    (void)GetCursorPos(&cursor);
    std::vector<zisla::core::ScreenSnapshot> screens;
    if (mode == zisla::core::CleaningMode::keyboard) {
        screens.push_back(DisplayTopology::screenForPoint(cursor));
    } else {
        screens = DisplayTopology::screens();
    }
    std::erase_if(screens, [](const zisla::core::ScreenSnapshot& screen) {
        return screen.bounds.width <= 0 || screen.bounds.height <= 0;
    });
    if (screens.empty()) {
        const auto fallback = DisplayTopology::screenForPoint(cursor);
        if (fallback.bounds.width <= 0 || fallback.bounds.height <= 0) {
            return false;
        }
        screens.push_back(fallback);
    }

    std::size_t active_index = 0;
    for (std::size_t index = 0; index < screens.size(); ++index) {
        if (contains(screens[index].bounds, cursor)) {
            active_index = index;
            break;
        }
    }

    std::vector<std::unique_ptr<CleaningWindow>> windows;
    windows.reserve(screens.size());
    for (std::size_t index = 0; index < screens.size(); ++index) {
        auto window = std::make_unique<CleaningWindow>(mode);
        window->show(screens[index].bounds, index == active_index);
        windows.push_back(std::move(window));
    }
    cleaning_windows_.swap(windows);
    return true;
}

void AppHost::holdPowerRequestsForCleaning() noexcept {
    if (!power_request_controller_ || cleaning_power_state_) {
        return;
    }
    cleaning_power_state_ = power_request_controller_->snapshot();
    (void)power_request_controller_->set_keep_display_awake(true);
    (void)power_request_controller_->set_prevent_idle_system_sleep(true);
    refreshPowerRequests();
}

void AppHost::restorePowerRequestsAfterCleaning() noexcept {
    if (!power_request_controller_ || !cleaning_power_state_) {
        cleaning_power_state_.reset();
        return;
    }
    const auto desired = *cleaning_power_state_;
    cleaning_power_state_.reset();
    (void)power_request_controller_->set_keep_display_awake(
        desired.keep_display_awake);
    (void)power_request_controller_->set_prevent_idle_system_sleep(
        desired.prevent_idle_system_sleep);
    refreshPowerRequests();
}

void AppHost::addShelfPaths(std::vector<std::filesystem::path> paths) {
    if (file_shelf_service_) {
        file_shelf_service_->add(std::move(paths));
    }
}

void AppHost::removeShelfPath(std::filesystem::path path) {
    if (file_shelf_service_) {
        file_shelf_service_->remove(std::move(path));
    }
}

void AppHost::clearShelf() {
    if (file_shelf_service_) {
        file_shelf_service_->clear();
    }
}

void AppHost::copyShelfPath(std::filesystem::path path) {
    std::vector<std::filesystem::path> paths;
    paths.push_back(std::move(path));
    copy_paths_to_clipboard(std::move(paths));
}

void AppHost::copyAllShelfPaths() {
    if (!file_shelf_service_) {
        return;
    }
    std::vector<std::filesystem::path> paths;
    const auto snapshot = file_shelf_service_->snapshot();
    paths.reserve(snapshot->size());
    for (const auto& item : *snapshot) {
        paths.push_back(item.path);
    }
    copy_paths_to_clipboard(std::move(paths));
}

void AppHost::shareAllShelfPaths() {
    if (!file_shelf_service_) {
        return;
    }
    std::vector<std::filesystem::path> paths;
    const auto snapshot = file_shelf_service_->snapshot();
    paths.reserve(snapshot->size());
    for (const auto& item : *snapshot) {
        paths.push_back(item.path);
    }
    shareShelfPathsAsync(std::move(paths));
}

bool AppHost::ensureShareManager() {
    if (share_manager_) {
        return true;
    }
    if (!overlay_window_ || !overlay_window_->hwnd()) {
        return false;
    }

    const auto interop = get_activation_factory<
        Windows::ApplicationModel::DataTransfer::DataTransferManager,
        IDataTransferManagerInterop>();
    constexpr winrt::guid data_transfer_manager_iid{
        0xa5caee9b,
        0x8708,
        0x49d1,
        {0x8d, 0x36, 0x67, 0xd2, 0x5a, 0x8d, 0xa0, 0x0c},
    };
    check_hresult(interop->GetForWindow(
        overlay_window_->hwnd(),
        data_transfer_manager_iid,
        put_abi(share_manager_)));
    share_requested_revoker_ = share_manager_.DataRequested(
        auto_revoke,
        [this](
            Windows::ApplicationModel::DataTransfer::DataTransferManager const&,
            Windows::ApplicationModel::DataTransfer::DataRequestedEventArgs const& args) {
            const auto request = args.Request();
            if (!pending_share_items_ || pending_share_items_.Size() == 0) {
                request.FailWithDisplayText(L"没有可共享的文件");
                return;
            }
            const auto data = request.Data();
            data.Properties().Title(L"Zisla 文件中转");
            data.RequestedOperation(
                Windows::ApplicationModel::DataTransfer::DataPackageOperation::Copy);
            data.SetStorageItems(pending_share_items_);
        });
    return true;
}

winrt::fire_and_forget AppHost::shareShelfPathsAsync(
    std::vector<std::filesystem::path> paths) {
    try {
        const auto items = co_await resolve_storage_items(std::move(paths));
        if (!started_ || !overlay_window_ || !message_window_
            || items.Size() == 0 || !ensureShareManager()) {
            co_return;
        }
        pending_share_items_ = items;
        const auto interop = get_activation_factory<
            Windows::ApplicationModel::DataTransfer::DataTransferManager,
            IDataTransferManagerInterop>();
        check_hresult(interop->ShowShareUIForWindow(overlay_window_->hwnd()));
    } catch (...) {
    }
}

void AppHost::openShelfPath(const std::filesystem::path& path) {
    if (!path.empty()) {
        (void)ShellExecuteW(
            nullptr,
            L"open",
            path.c_str(),
            nullptr,
            nullptr,
            SW_SHOWNORMAL);
    }
}

void AppHost::revealShelfPath(const std::filesystem::path& path) {
    if (path.empty()) {
        return;
    }
    PIDLIST_ABSOLUTE item = nullptr;
    if (SUCCEEDED(SHParseDisplayName(
            path.c_str(),
            nullptr,
            &item,
            0,
            nullptr))) {
        (void)SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
        CoTaskMemFree(item);
    }
}

void AppHost::addPinnedClipboardContent(
    zisla::core::ClipboardHistoryContent content) {
    if (clipboard_history_service_) {
        clipboard_history_service_->record_pinned(std::move(content));
    }
}

void AppHost::setClipboardItemPinned(std::int64_t id, bool pinned) {
    if (clipboard_history_service_) {
        clipboard_history_service_->set_pinned(id, pinned);
    }
}

void AppHost::removeClipboardItem(std::int64_t id) {
    if (clipboard_history_service_) {
        clipboard_history_service_->remove(id);
    }
}

void AppHost::clearClipboardHistory() {
    if (clipboard_history_service_) {
        clipboard_history_service_->clear_history();
    }
}

void AppHost::clearAllClipboardItems() {
    if (clipboard_history_service_) {
        clipboard_history_service_->clear_all();
    }
}

void AppHost::copyClipboardItem(std::int64_t id) {
    if (!clipboard_history_service_) {
        return;
    }
    const auto snapshot = clipboard_history_service_->snapshot();
    const auto item = std::find_if(snapshot->begin(), snapshot->end(), [id](const auto& value) {
        return value.id == id;
    });
    if (item != snapshot->end()) {
        copyClipboardItemAsync(std::move(snapshot), id);
    }
}

void AppHost::copyTextToClipboard(std::string text) {
    using namespace Windows::ApplicationModel::DataTransfer;
    if (text.empty()) {
        return;
    }
    try {
        DataPackage package;
        package.RequestedOperation(DataPackageOperation::Copy);
        package.SetText(to_hstring(text));
        Clipboard::SetContent(package);
        Clipboard::Flush();
        ignoreCurrentClipboardSequence();
    } catch (...) {
    }
}

bool AppHost::startDownload(
    std::string url,
    zisla::core::DownloadMode mode,
    std::filesystem::path output_directory) {
    if (!download_service_) {
        return false;
    }
    zisla::core::DownloadRequest request{
        .url = std::move(url),
        .mode = mode,
        .output_directory = std::move(output_directory),
    };
    const bool started = download_service_->start_download(request);
    if (started) {
        download_output_directory_ = request.output_directory;
        saveSettings();
    }
    refreshDownload();
    return started;
}

void AppHost::cancelDownload() {
    if (download_service_) {
        download_service_->cancel();
    }
}

void AppHost::revealDownloadedFile() {
    if (!download_service_) {
        return;
    }
    const auto snapshot = download_service_->snapshot();
    if (snapshot && snapshot->phase == zisla::core::DownloadPhase::completed
        && snapshot->completed_file) {
        revealShelfPath(*snapshot->completed_file);
    }
}

void AppHost::reloadQuickNotes() {
    if (quick_notes_service_) {
        quick_notes_service_->reload();
    }
}

void AppHost::createQuickNote(std::string markdown) {
    if (quick_notes_service_) {
        quick_notes_service_->create(std::move(markdown));
    }
}

void AppHost::updateQuickNote(std::int64_t id, std::string markdown) {
    if (quick_notes_service_) {
        quick_notes_service_->update(id, std::move(markdown));
    }
}

void AppHost::removeQuickNote(std::int64_t id) {
    if (quick_notes_service_) {
        quick_notes_service_->remove(id);
    }
}

std::uint64_t AppHost::submitPDFProcessing(
    zisla::pdf::PDFProcessingRequest request) {
    if (!pdf_processing_service_) {
        return 0;
    }
    try {
        return pdf_processing_service_->submit(std::move(request));
    } catch (...) {
        return 0;
    }
}

void AppHost::reloadAIAgentSkills() {
    if (ai_agent_skills_service_) {
        ai_agent_skills_service_->reload();
    }
}

void AppHost::reloadAIAgentWorkspace() {
    if (ai_agent_workspace_service_) {
        ai_agent_workspace_service_->reload();
    }
}

void AppHost::createAIAgentThread() {
    if (ai_agent_workspace_service_) {
        ai_agent_workspace_service_->createThread();
    }
}

void AppHost::removeAIAgentThread(std::string thread_id) {
    if (ai_agent_workspace_service_) {
        ai_agent_workspace_service_->removeThread(std::move(thread_id));
    }
}

void AppHost::submitAIAgentMessage(
    std::string thread_id,
    std::string content,
    std::optional<zisla::core::AgentCLIKind> cli_kind,
    std::optional<std::string> channel_id) {
    if (!ai_agent_workspace_service_) {
        return;
    }
    std::vector<zisla::core::AgentSkill> skills;
    if (ai_agent_skills_service_) {
        if (const auto snapshot = ai_agent_skills_service_->snapshot()) {
            skills = snapshot->skills;
        }
    }
    ai_agent_workspace_service_->submitMessage(
        std::move(thread_id),
        std::move(content),
        std::move(skills),
        cli_kind,
        std::move(channel_id));
}

void AppHost::cancelAIAgentRequest() noexcept {
    if (ai_agent_workspace_service_) {
        ai_agent_workspace_service_->cancelActiveRequest();
    }
}

void AppHost::configureAIAgentConnection(
    std::optional<std::string> channel_id,
    zisla::core::AgentChannelProtocol protocol,
    std::string name,
    std::string base_url,
    std::string model,
    std::string endpoint_priority,
    std::string api_key,
    std::optional<zisla::core::AgentBalanceProbe> balance_probe) {
    if (ai_agent_workspace_service_) {
        ai_agent_workspace_service_->configureAPIConnection(
            std::move(channel_id),
            protocol,
            std::move(name),
            std::move(base_url),
            std::move(model),
            std::move(endpoint_priority),
            std::move(api_key),
            std::move(balance_probe));
    }
}

void AppHost::removeAIAgentConnection(std::string channel_id) {
    if (ai_agent_workspace_service_) {
        ai_agent_workspace_service_->removeAPIConnection(std::move(channel_id));
    }
}

void AppHost::refreshAIAgentAccountBalance(std::string account_id) {
    if (ai_agent_workspace_service_) {
        ai_agent_workspace_service_->refreshAccountBalance(std::move(account_id));
    }
}

void AppHost::refreshAIAgentChannelModels(std::string channel_id) {
    if (ai_agent_workspace_service_) {
        ai_agent_workspace_service_->refreshChannelModels(std::move(channel_id));
    }
}

void AppHost::setAIAgentSkillEnabled(
    std::filesystem::path path,
    bool enabled) {
    if (ai_agent_skills_service_) {
        ai_agent_skills_service_->setSkillEnabled(std::move(path), enabled);
    }
}

void AppHost::setAIAgentSkillsSynchronizationMode(
    zisla::core::AgentSkillSynchronizationMode mode) {
    if (ai_agent_skills_service_) {
        ai_agent_skills_service_->setSynchronizationMode(mode);
    }
}

void AppHost::setAIAgentSkillsDestinationEnabled(
    AIAgentSkillDestination destination,
    bool enabled) {
    if (ai_agent_skills_service_) {
        ai_agent_skills_service_->setDestinationEnabled(destination, enabled);
    }
}

void AppHost::synchronizeAIAgentSkills() {
    if (ai_agent_skills_service_) {
        ai_agent_skills_service_->synchronize();
    }
}

void AppHost::openAIAgentSkillsLibrary() {
    if (!ai_agent_skills_service_) {
        return;
    }
    const auto directory = ai_agent_skills_service_->managedDirectory();
    if (directory.empty()) {
        return;
    }
    try {
        zisla::core::AgentSkillSynchronizer synchronizer;
        synchronizer.ensure_managed_directory(directory);
        if (reinterpret_cast<INT_PTR>(ShellExecuteW(
                nullptr,
                L"open",
                directory.c_str(),
                nullptr,
                nullptr,
                SW_SHOWNORMAL)) > 32) {
            ai_agent_skills_service_->reload();
        }
    } catch (...) {
    }
}

void AppHost::showCurrentCalendarWeek() {
    if (calendar_service_) {
        calendar_service_->showCurrentWeek();
    }
}

void AppHost::setCalendarReferenceDate(zisla::core::CalendarCivilDate date) {
    if (calendar_service_) {
        calendar_service_->setReferenceDate(date);
    }
}

void AppHost::createCalendarEvent(
    std::string title,
    zisla::core::CalendarCivilDate start_date,
    int start_hour,
    int start_minute,
    zisla::core::CalendarCivilDate end_date,
    int end_hour,
    int end_minute,
    bool all_day) {
    if (calendar_service_) {
        calendar_service_->createEvent(
            std::move(title),
            {
                .date = start_date,
                .hour = start_hour,
                .minute = start_minute,
            },
            {
                .date = end_date,
                .hour = end_hour,
                .minute = end_minute,
            },
            all_day);
    }
}

void AppHost::createCalendarReminder(
    std::string title,
    zisla::core::CalendarCivilDate due_date,
    int due_hour,
    int due_minute,
    bool all_day) {
    if (calendar_service_) {
        calendar_service_->createReminder(
            std::move(title),
            {
                .date = due_date,
                .hour = due_hour,
                .minute = due_minute,
            },
            all_day);
    }
}

void AppHost::setCalendarReminderCompleted(
    std::int64_t id,
    bool completed) {
    if (calendar_service_) {
        calendar_service_->setReminderCompleted(id, completed);
    }
}

void AppHost::removeCalendarItem(std::int64_t id) {
    if (calendar_service_) {
        calendar_service_->remove(id);
    }
}

winrt::fire_and_forget AppHost::copyClipboardItemAsync(
    std::shared_ptr<const std::vector<zisla::core::ClipboardHistoryItem>> snapshot,
    std::int64_t id) {
    using namespace Windows::ApplicationModel::DataTransfer;
    try {
        if (!snapshot) {
            co_return;
        }
        const auto found = std::find_if(
            snapshot->begin(),
            snapshot->end(),
            [id](const auto& value) { return value.id == id; });
        if (found == snapshot->end()) {
            co_return;
        }
        const auto& item = *found;
        DataPackage package;
        package.RequestedOperation(DataPackageOperation::Copy);
        switch (item.content.kind) {
        case zisla::core::ClipboardContentKind::text:
            package.SetText(to_hstring(item.content.text));
            break;
        case zisla::core::ClipboardContentKind::image: {
            Windows::Storage::Streams::InMemoryRandomAccessStream stream;
            Windows::Storage::Streams::DataWriter writer{stream};
            writer.WriteBytes(item.content.image);
            const auto stored = co_await writer.StoreAsync();
            if (stored != item.content.image.size()) {
                co_return;
            }
            (void)writer.DetachStream();
            stream.Seek(0);
            package.SetBitmap(
                Windows::Storage::Streams::RandomAccessStreamReference::CreateFromStream(stream));
            break;
        }
        case zisla::core::ClipboardContentKind::file: {
            std::vector<std::filesystem::path> paths{item.content.file_path};
            const auto storage_items = co_await resolve_storage_items(std::move(paths));
            if (storage_items.Size() == 0) {
                co_return;
            }
            package.SetStorageItems(storage_items);
            break;
        }
        }
        if (!started_) {
            co_return;
        }
        Clipboard::SetContent(package);
        Clipboard::Flush();
        ignoreCurrentClipboardSequence();
    } catch (...) {
    }
}

void AppHost::ignoreCurrentClipboardSequence() noexcept {
    if (clipboard_history_service_) {
        clipboard_history_service_->ignore_sequence(GetClipboardSequenceNumber());
    }
}

void AppHost::exitApplication() {
    shutdown();
    Microsoft::UI::Xaml::Application::Current().Exit();
}

zisla::core::OverlayAnchor AppHost::currentAnchor() const noexcept {
    return presentation_engine_.state().anchor;
}

bool AppHost::isTopEdgeEnabled() const noexcept {
    return top_edge_enabled_;
}

bool AppHost::areSideNoticesEnabled() const noexcept {
    return settings_.side_notices_enabled;
}

bool AppHost::isClipboardHistoryEnabled() const noexcept {
    return settings_.clipboard_history_enabled;
}

bool AppHost::isClipboardDetectionEnabled() const noexcept {
    return settings_.clipboard_detection_enabled;
}

bool AppHost::isVoiceInputEnabled() const noexcept {
    return settings_.voice_input_enabled;
}

zisla::core::VoiceHotkeyAction AppHost::voiceHotkeyAction() const noexcept {
    return settings_.voice_hotkey_action;
}

zisla::core::VoiceHotkeyPreset AppHost::voiceHotkeyPreset() const noexcept {
    return settings_.voice_hotkey_preset;
}

std::string AppHost::voiceHotkeyStatus() const {
    if (!voice_hotkey_service_) {
        return "未初始化";
    }
    return voice_hotkey_service_->status_message();
}

bool AppHost::areNotificationsMuted() const noexcept {
    return settings_.notifications_muted;
}

bool AppHost::isWeatherEnabled() const noexcept {
    return settings_.weather_enabled;
}

bool AppHost::isBrowserDownloadStatusEnabled() const noexcept {
    return settings_.browser_download_status_enabled;
}

bool AppHost::isTaskbarWidgetEnabled() const noexcept {
    return taskbar_widget_enabled_;
}

bool AppHost::isPetEnabled() const noexcept {
    return settings_.pet_enabled;
}

const std::string& AppHost::petId() const noexcept {
    return settings_.pet_id;
}

zisla::core::PetSide AppHost::petSide() const noexcept {
    return settings_.pet_side;
}

const MailConnectionSettings& AppHost::mailConnectionSettings() const noexcept {
    return mail_connection_settings_;
}

zisla::core::UpdateChannel AppHost::updateChannel() const noexcept {
    return update_channel_;
}

std::shared_ptr<const MailServiceSnapshot> AppHost::mailSnapshot() const noexcept {
    return mail_service_ ? mail_service_->snapshot() : nullptr;
}

std::shared_ptr<const UpdateServiceSnapshot> AppHost::updateSnapshot() const noexcept {
    return update_service_ ? update_service_->snapshot() : nullptr;
}

std::vector<zisla::core::PetManifest> AppHost::availablePets() const {
    std::vector<zisla::core::PetManifest> result;
    result.reserve(pet_entries_.size());
    for (const auto& entry : pet_entries_) {
        result.push_back(entry.manifest);
    }
    return result;
}

std::size_t AppHost::clipboardImageLimit() const noexcept {
    return clipboard_history_service_
        ? clipboard_history_service_->max_image_bytes()
        : 10U * 1024U * 1024U;
}

HWND AppHost::overlayWindowHandle() const noexcept {
    return overlay_window_ ? overlay_window_->hwnd() : nullptr;
}

}
