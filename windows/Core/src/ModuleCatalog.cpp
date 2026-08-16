#include "zisla/core/ModuleCatalog.hpp"

namespace zisla::core {

bool ModuleCatalog::is_enabled(ModuleId module,
                                const FeatureSettings& settings) noexcept {
    switch (module) {
    case ModuleId::dashboard:
        return true;
    case ModuleId::shelf:
        return settings.file_shelf_enabled;
    case ModuleId::clipboard:
        return settings.clipboard_history_enabled;
    case ModuleId::ai_monitor:
        return settings.ai_progress_enabled;
    case ModuleId::ai_agent:
        return settings.ai_agent_enabled;
    case ModuleId::download:
        return settings.downloader_enabled;
    case ModuleId::agenda:
        return settings.calendar_enabled || settings.weather_enabled;
    case ModuleId::mail:
        return settings.mail_enabled;
    case ModuleId::quick_notes:
        return settings.quick_notes_enabled;
    case ModuleId::pdf:
        return settings.pdf_tools_enabled;
    case ModuleId::toolbox:
        return settings.toolbox_enabled;
    case ModuleId::system:
        return settings.system_monitor_enabled;
    }
    return false;
}

}  // namespace zisla::core
