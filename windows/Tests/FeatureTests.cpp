#include "zisla/core/AIModels.hpp"
#include "zisla/core/AIActivityMerger.hpp"
#include "zisla/core/CompactStatusSelector.hpp"
#include "zisla/core/DashboardPresentation.hpp"
#include "zisla/core/FeatureSettings.hpp"
#include "zisla/core/ModuleCatalog.hpp"

#include <array>
#include <cstdint>
#include <exception>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string_view>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void defaultModulesFollowWindowsConvention() {
    const FeatureSettings settings{};

    expect(ModuleCatalog::is_enabled(ModuleId::dashboard, settings),
        "dashboard should always be enabled on Windows");
    expect(ModuleCatalog::is_enabled(ModuleId::shelf, settings),
        "shelf should be enabled by default");
    expect(!ModuleCatalog::is_enabled(ModuleId::clipboard, settings),
        "clipboard should be disabled by default (privacy-sensitive)");
    expect(ModuleCatalog::is_enabled(ModuleId::ai_monitor, settings),
        "ai_monitor should be enabled by default");
    expect(ModuleCatalog::is_enabled(ModuleId::ai_agent, settings),
        "ai_agent should be enabled by default");
    expect(ModuleCatalog::is_enabled(ModuleId::download, settings),
        "download should be enabled by default");
    expect(ModuleCatalog::is_enabled(ModuleId::agenda, settings),
        "agenda should be enabled when calendar or weather is on");
    expect(!ModuleCatalog::is_enabled(ModuleId::mail, settings),
        "mail should be disabled by default (privacy-sensitive)");
    expect(ModuleCatalog::is_enabled(ModuleId::quick_notes, settings),
        "quick_notes should be enabled by default");
    expect(ModuleCatalog::is_enabled(ModuleId::pdf, settings),
        "pdf should be enabled by default");
    expect(ModuleCatalog::is_enabled(ModuleId::toolbox, settings),
        "toolbox should be enabled by default");
    expect(ModuleCatalog::is_enabled(ModuleId::system, settings),
        "system should be enabled by default");
}

void moduleCatalogHasStableWindowsOrder() {
    constexpr std::array expected = {
        ModuleId::dashboard,
        ModuleId::shelf,
        ModuleId::clipboard,
        ModuleId::ai_monitor,
        ModuleId::ai_agent,
        ModuleId::download,
        ModuleId::agenda,
        ModuleId::mail,
        ModuleId::quick_notes,
        ModuleId::pdf,
        ModuleId::toolbox,
        ModuleId::system,
    };

    expect(ModuleCatalog::all_modules() == expected,
        "Windows module order should remain stable and exclude unsupported lock-screen UI");
}

void everyIndependentModuleToggleIsRespected() {
    struct ToggleCase {
        ModuleId module;
        bool FeatureSettings::* setting;
    };
    constexpr ToggleCase cases[] = {
        {ModuleId::shelf, &FeatureSettings::file_shelf_enabled},
        {ModuleId::clipboard, &FeatureSettings::clipboard_history_enabled},
        {ModuleId::ai_monitor, &FeatureSettings::ai_progress_enabled},
        {ModuleId::ai_agent, &FeatureSettings::ai_agent_enabled},
        {ModuleId::download, &FeatureSettings::downloader_enabled},
        {ModuleId::mail, &FeatureSettings::mail_enabled},
        {ModuleId::quick_notes, &FeatureSettings::quick_notes_enabled},
        {ModuleId::pdf, &FeatureSettings::pdf_tools_enabled},
        {ModuleId::toolbox, &FeatureSettings::toolbox_enabled},
        {ModuleId::system, &FeatureSettings::system_monitor_enabled},
    };

    for (const auto& toggle : cases) {
        FeatureSettings settings{};
        settings.*(toggle.setting) = !(settings.*(toggle.setting));
        expect(ModuleCatalog::is_enabled(toggle.module, settings)
                == settings.*(toggle.setting),
            "module should follow its independent feature toggle");
    }
}

void agendaFollowsCalendarOrWeatherRule() {
    FeatureSettings both_off{};
    both_off.calendar_enabled = false;
    both_off.weather_enabled = false;
    expect(!ModuleCatalog::is_enabled(ModuleId::agenda, both_off),
        "agenda should be disabled when both calendar and weather are off");

    FeatureSettings calendar_only{};
    calendar_only.calendar_enabled = true;
    calendar_only.weather_enabled = false;
    expect(ModuleCatalog::is_enabled(ModuleId::agenda, calendar_only),
        "agenda should be enabled when calendar is on");

    FeatureSettings weather_only{};
    weather_only.calendar_enabled = false;
    weather_only.weather_enabled = true;
    expect(ModuleCatalog::is_enabled(ModuleId::agenda, weather_only),
        "agenda should be enabled when weather is on");

    FeatureSettings both_on{};
    both_on.calendar_enabled = true;
    both_on.weather_enabled = true;
    expect(ModuleCatalog::is_enabled(ModuleId::agenda, both_on),
        "agenda should be enabled when both are on");
}

void dashboardIsEmptyWithoutActiveSources() {
    expect(DashboardPresentation::items({}).empty(),
        "dashboard should not render inactive sources");
}

void dashboardUsesStableCrossFeatureOrder() {
    const auto items = DashboardPresentation::items({
        .focus_countdown_active = true,
        .ai_activity_active = true,
        .native_download_active = true,
        .browser_download_count = 2,
        .media_active = true,
    });
    const std::vector expected = {
        DashboardItem{DashboardItemKind::focus_countdown},
        DashboardItem{DashboardItemKind::ai_activity},
        DashboardItem{DashboardItemKind::native_download},
        DashboardItem{DashboardItemKind::browser_download, 0},
        DashboardItem{DashboardItemKind::browser_download, 1},
        DashboardItem{DashboardItemKind::media},
    };

    expect(items == expected,
        "dashboard should preserve the macOS activity order before Windows media");
}

void dashboardKeepsBrowserDownloadSourceIndexes() {
    const auto items = DashboardPresentation::items({
        .browser_download_count = 3,
    });

    expect(items.size() == 3,
        "each browser download should receive a dashboard item");
    for (std::size_t index = 0; index < items.size(); ++index) {
        expect(items[index] == DashboardItem{
                DashboardItemKind::browser_download,
                index,
            },
            "browser download items should retain their source index");
    }
}

void dashboardIncludesOnlyAvailableSingleSource() {
    const auto items = DashboardPresentation::items({
        .media_active = true,
    });

    expect(items == std::vector{DashboardItem{DashboardItemKind::media}},
        "a single active source should produce one dashboard item");
}

void supportedFeatureDefaultsMatchTheWindowsProductContract() {
    const FeatureSettings settings{};

    expect(!settings.clipboard_detection_enabled,
        "clipboard link detection should remain opt-in");
    expect(settings.side_notices_enabled,
        "side activity notices should be enabled by default");
    expect(settings.focus_countdown_status_enabled,
        "focus countdown should be eligible for compact status by default");
    expect(settings.browser_download_status_enabled,
        "browser download status should be enabled by default");
    expect(settings.video_download_status_enabled,
        "native downloader status should be enabled by default");
    expect(!settings.toolbox_reminder_enabled,
        "toolbox reminders should require explicit configuration");
    expect(settings.update_checks_enabled && settings.automatic_updates_enabled,
        "signed application updates should be enabled by default");
    expect(settings.top_edge_enabled,
        "the top-edge entry should follow the accepted Windows default");
    expect(settings.pet_enabled,
        "the desktop pet should retain the macOS product default");
    expect(settings.pet_id == "dog",
        "the desktop pet should default to the bundled dog");
    expect(settings.pet_side == PetSide::right,
        "the desktop pet should default to the right companion side");
    expect(settings.media_show_lyrics_and_info,
        "media details should be available by default");
    expect(!settings.voice_input_enabled,
        "voice input should remain opt-in because it needs permissions");
    expect(!settings.notifications_muted,
        "application notifications should not start muted");
}

void compactStatusPriorityDefaultOrderMatchesMacOS() {
    const auto order = CompactStatusSelector::default_order();

    expect(order.size() == 8, "should have 8 priority levels");
    expect(order[0] == CompactStatusPriority::transient,
        "transient should be first");
    expect(order[1] == CompactStatusPriority::video_download,
        "video_download should be second");
    expect(order[2] == CompactStatusPriority::browser_download,
        "browser_download should be third");
    expect(order[3] == CompactStatusPriority::focus_countdown,
        "focus_countdown should be fourth");
    expect(order[4] == CompactStatusPriority::toolbox_reminder,
        "toolbox_reminder should be fifth");
    expect(order[5] == CompactStatusPriority::ai_activity,
        "ai_activity should be sixth");
    expect(order[6] == CompactStatusPriority::media,
        "media should be seventh");
    expect(order[7] == CompactStatusPriority::focus_mode,
        "focus_mode should be eighth");
}

void normalizedDeduplicatesAndAppendsDefaults() {
    const std::array input = {
        CompactStatusPriority::media,
        CompactStatusPriority::transient,
        CompactStatusPriority::media,
    };

    const auto result = CompactStatusSelector::normalized(input);

    expect(result.size() == 8, "normalized should produce 8 items");
    expect(result[0] == CompactStatusPriority::media,
        "first unique item should be media");
    expect(result[1] == CompactStatusPriority::transient,
        "second unique item should be transient");
    expect(result[2] == CompactStatusPriority::video_download,
        "missing defaults should be appended in order");
    expect(result[3] == CompactStatusPriority::browser_download,
        "browser_download should follow");
}

void normalizedPreservesUserOrderBeforeDefaults() {
    const std::array input = {
        CompactStatusPriority::focus_mode,
        CompactStatusPriority::ai_activity,
        CompactStatusPriority::transient,
    };

    const auto result = CompactStatusSelector::normalized(input);

    expect(result[0] == CompactStatusPriority::focus_mode,
        "user order should be preserved");
    expect(result[1] == CompactStatusPriority::ai_activity,
        "user order should be preserved");
    expect(result[2] == CompactStatusPriority::transient,
        "user order should be preserved");
    expect(result[3] == CompactStatusPriority::video_download,
        "remaining defaults should follow");
}

void emptyInputProducesDefaultOrder() {
    const std::array<CompactStatusPriority, 0> input{};

    const auto result = CompactStatusSelector::normalized(input);
    const auto defaults = CompactStatusSelector::default_order();

    for (std::size_t i = 0; i < defaults.size(); ++i) {
        expect(result[i] == defaults[i],
            "empty input should produce default order");
    }
}

void selectorReturnsHighestAvailablePriority() {
    const std::array priorities = {
        CompactStatusPriority::media,
        CompactStatusPriority::ai_activity,
    };
    const std::array available = {
        CompactStatusPriority::focus_mode,
        CompactStatusPriority::ai_activity,
        CompactStatusPriority::transient,
    };

    expect(CompactStatusSelector::select(priorities, available)
            == CompactStatusPriority::ai_activity,
        "selector should return the first available status in normalized user order");
}

void selectorReturnsEmptyWhenNoStatusIsAvailable() {
    const auto priorities = CompactStatusSelector::default_order();
    const std::array<CompactStatusPriority, 0> available{};

    expect(!CompactStatusSelector::select(priorities, available).has_value(),
        "selector should return no status when none are available");
}

void normalizationIsIdempotentAndRejectsInvalidValues() {
    const std::array input = {
        static_cast<CompactStatusPriority>(255),
        CompactStatusPriority::media,
        CompactStatusPriority::media,
    };

    const auto once = CompactStatusSelector::normalized(input);
    const auto twice = CompactStatusSelector::normalized(once);

    expect(once == twice,
        "normalizing an already normalized priority list should be idempotent");
    expect(once[0] == CompactStatusPriority::media
            && once[1] == CompactStatusPriority::transient,
        "invalid values should be ignored before missing defaults are appended");
}

void aiProviderTokensAndAliasesMatchMacOSPersistence() {
    constexpr std::array providers = {
        AIProvider::claude,
        AIProvider::codex,
        AIProvider::gemini,
        AIProvider::grok,
        AIProvider::gpt,
        AIProvider::copilot,
        AIProvider::kimi,
        AIProvider::qwen,
        AIProvider::coder,
        AIProvider::trae,
        AIProvider::opencode,
        AIProvider::harness,
        AIProvider::doubao,
    };
    for (const auto provider : providers) {
        expect(parse_ai_provider(ai_provider_token(provider)) == provider,
            "every canonical AI provider token should round-trip");
    }

    expect(parse_ai_provider("CLAUDE-DESKTOP") == AIProvider::claude,
        "provider aliases should be ASCII case-insensitive");
    expect(parse_ai_provider("openai") == AIProvider::gpt,
        "OpenAI should preserve the ChatGPT-compatible provider mapping");
    expect(parse_ai_provider("github.copilot-chat") == AIProvider::copilot,
        "GitHub Copilot extension aliases should be recognized");
    expect(parse_ai_provider("qoderwork cn") == AIProvider::coder,
        "Qoder desktop aliases should retain the persisted coder identifier");
    expect(parse_ai_provider("open_code") == AIProvider::opencode,
        "OpenCode aliases should normalize to the stable provider");
    expect(parse_ai_provider("\xE8\xB1\x86\xE5\x8C\x85") == AIProvider::doubao,
        "the localized Doubao alias should remain compatible");
    expect(!parse_ai_provider("unknown-provider").has_value(),
        "unknown provider tokens should be rejected");
}

void aiProgressStatusesRetainActivityAndNoticeSemantics() {
    expect(is_active(AIProgressStatus::queued), "queued tasks should remain active");
    expect(is_active(AIProgressStatus::running), "running tasks should remain active");
    expect(is_active(AIProgressStatus::blocked), "blocked tasks should remain active");
    expect(is_active(AIProgressStatus::error), "recoverable error tasks should remain active");
    expect(!is_active(AIProgressStatus::succeeded), "succeeded tasks should be inactive");
    expect(!is_active(AIProgressStatus::failed), "failed tasks should be inactive");

    expect(notice_kind_for(AIProgressStatus::running) == NoticeKind::info,
        "running tasks should produce informational notices");
    expect(notice_kind_for(AIProgressStatus::blocked) == NoticeKind::warning,
        "blocked tasks should produce warning notices");
    expect(notice_kind_for(AIProgressStatus::error) == NoticeKind::error,
        "errored tasks should produce error notices");
    expect(notice_kind_for(AIProgressStatus::succeeded) == NoticeKind::success,
        "succeeded tasks should produce success notices");
}

void aiUsageTotalsSaturateInsteadOfOverflowing() {
    AIUsageSample ordinary{
        .input_tokens = 12'400,
        .output_tokens = 2'100,
    };
    expect(ordinary.total_tokens() == 14'500,
        "ordinary token totals should be added exactly");

    AIUsageSample extreme{
        .input_tokens = std::numeric_limits<std::uint64_t>::max() - 4,
        .output_tokens = 10,
    };
    expect(extreme.total_tokens() == std::numeric_limits<std::uint64_t>::max(),
        "token totals should saturate rather than overflow");
}

void detectedAITasksOverridePersistedTasksAndKeepStableOrder() {
    const std::vector<AIProgressTask> persisted = {
        {
            .id = "claude:one",
            .provider = AIProvider::claude,
            .title = "Old title",
            .status = AIProgressStatus::running,
            .updated_at_unix_ms = 1'000,
        },
        {
            .id = "codex:two",
            .provider = AIProvider::codex,
            .title = "Codex",
            .status = AIProgressStatus::succeeded,
            .updated_at_unix_ms = 500,
        },
    };
    const std::vector<AIProgressTask> detected = {
        {
            .id = "claude:one",
            .provider = AIProvider::claude,
            .title = "Current title",
            .status = AIProgressStatus::blocked,
            .updated_at_unix_ms = 1'900,
        },
        {
            .id = "gemini:three",
            .provider = AIProvider::gemini,
            .title = "Gemini",
            .status = AIProgressStatus::running,
            .updated_at_unix_ms = 1'800,
        },
    };

    const auto merged = AIActivityMerger::merge(
        persisted,
        detected,
        {.now_unix_ms = 2'000, .active_task_ttl_ms = 5'000});

    expect(merged.size() == 3, "detected tasks should merge without duplication");
    expect(merged[0].id == "claude:one"
            && merged[0].title == "Current title"
            && merged[0].status == AIProgressStatus::blocked,
        "a detector should replace persisted state for the same task id");
    expect(merged[1].id == "codex:two" && merged[2].id == "gemini:three",
        "existing order should stay stable and newly detected tasks should append");
}

void AIActivityMergeExpiresOnlyStaleActiveTasks() {
    const std::vector<AIProgressTask> persisted = {
        {
            .id = "stale-running",
            .status = AIProgressStatus::running,
            .updated_at_unix_ms = 1'000,
        },
        {
            .id = "boundary-running",
            .status = AIProgressStatus::running,
            .updated_at_unix_ms = 5'000,
        },
        {
            .id = "completed-history",
            .status = AIProgressStatus::succeeded,
            .updated_at_unix_ms = 1'000,
        },
        {
            .id = "future-clock",
            .status = AIProgressStatus::queued,
            .updated_at_unix_ms = 11'000,
        },
    };

    const auto merged = AIActivityMerger::merge(
        persisted,
        {},
        {.now_unix_ms = 10'000, .active_task_ttl_ms = 5'000});

    expect(merged.size() == 3, "only one stale active task should expire");
    expect(merged[0].id == "boundary-running",
        "a task exactly on the TTL boundary should remain active");
    expect(merged[1].id == "completed-history",
        "completed history should not be removed by the active-task TTL");
    expect(merged[2].id == "future-clock",
        "clock skew should not expire a task dated in the future");
}

void repeatedDetectorUpdatesKeepOneTaskAndUseTheLatestValue() {
    const std::vector<AIProgressTask> detected = {
        {
            .id = "codex:turn",
            .provider = AIProvider::codex,
            .title = "Running",
            .status = AIProgressStatus::running,
            .updated_at_unix_ms = 1'000,
        },
        {
            .id = "codex:turn",
            .provider = AIProvider::codex,
            .title = "Needs input",
            .status = AIProgressStatus::blocked,
            .updated_at_unix_ms = 1'500,
        },
    };

    const auto merged = AIActivityMerger::merge(
        {},
        detected,
        {.now_unix_ms = 2'000, .active_task_ttl_ms = 5'000});

    expect(merged.size() == 1, "duplicate detector updates should keep one task");
    expect(merged[0].title == "Needs input"
            && merged[0].status == AIProgressStatus::blocked,
        "the last detector update should win for a repeated task id");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"default modules follow Windows convention", defaultModulesFollowWindowsConvention},
        {"module catalog has stable Windows order", moduleCatalogHasStableWindowsOrder},
        {"every independent toggle is respected", everyIndependentModuleToggleIsRespected},
        {"agenda follows calendar-or-weather rule", agendaFollowsCalendarOrWeatherRule},
        {"dashboard hides inactive sources", dashboardIsEmptyWithoutActiveSources},
        {"dashboard uses stable activity order", dashboardUsesStableCrossFeatureOrder},
        {"dashboard keeps browser indexes", dashboardKeepsBrowserDownloadSourceIndexes},
        {"dashboard renders one active source", dashboardIncludesOnlyAvailableSingleSource},
        {"supported feature defaults match Windows", supportedFeatureDefaultsMatchTheWindowsProductContract},
        {"priority default order matches macOS", compactStatusPriorityDefaultOrderMatchesMacOS},
        {"normalized deduplicates and appends", normalizedDeduplicatesAndAppendsDefaults},
        {"normalized preserves user order", normalizedPreservesUserOrderBeforeDefaults},
        {"empty input produces default order", emptyInputProducesDefaultOrder},
        {"selector returns highest available priority", selectorReturnsHighestAvailablePriority},
        {"selector handles no available status", selectorReturnsEmptyWhenNoStatusIsAvailable},
        {"normalization is robust and idempotent", normalizationIsIdempotentAndRejectsInvalidValues},
        {"AI provider aliases match persistence", aiProviderTokensAndAliasesMatchMacOSPersistence},
        {"AI progress status semantics match", aiProgressStatusesRetainActivityAndNoticeSemantics},
        {"AI usage totals do not overflow", aiUsageTotalsSaturateInsteadOfOverflowing},
        {"detected AI tasks override persisted state", detectedAITasksOverridePersistedTasksAndKeepStableOrder},
        {"AI activity TTL only expires active tasks", AIActivityMergeExpiresOnlyStaleActiveTasks},
        {"repeated AI detector updates use latest", repeatedDetectorUpdatesKeepOneTaskAndUseTheLatestValue},
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
