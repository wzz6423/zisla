#pragma once

#include "zisla/core/FeatureSettings.hpp"

#include <array>
#include <cstddef>

namespace zisla::core {

enum class ModuleId {
    dashboard,
    shelf,
    clipboard,
    ai_monitor,
    ai_agent,
    download,
    agenda,
    mail,
    quick_notes,
    pdf,
    toolbox,
    system,
};

class ModuleCatalog {
public:
    static constexpr std::size_t module_count = 12;

    [[nodiscard]] static constexpr std::array<ModuleId, module_count> all_modules() noexcept {
        return {
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
    }

    [[nodiscard]] static bool is_enabled(ModuleId module,
                                          const FeatureSettings& settings) noexcept;
};

}  // namespace zisla::core
