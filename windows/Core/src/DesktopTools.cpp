#include "zisla/core/DesktopTools.hpp"

#include <utility>

namespace zisla::core {

bool DesktopToolsState::begin(DesktopToolAction action) noexcept {
    if (snapshot_.busy || action == DesktopToolAction::none) {
        return false;
    }
    snapshot_.busy = true;
    snapshot_.active_action = action;
    snapshot_.status.clear();
    snapshot_.error.clear();
    ++snapshot_.revision;
    return true;
}

void DesktopToolsState::complete(
    RecycleBinMetrics recycle_bin,
    std::string status) {
    snapshot_.recycle_bin = recycle_bin;
    snapshot_.last_action = snapshot_.active_action;
    snapshot_.busy = false;
    snapshot_.active_action = DesktopToolAction::none;
    snapshot_.status = std::move(status);
    snapshot_.error.clear();
    ++snapshot_.revision;
}

void DesktopToolsState::fail(std::string error) {
    snapshot_.last_action = snapshot_.active_action;
    snapshot_.busy = false;
    snapshot_.active_action = DesktopToolAction::none;
    snapshot_.status.clear();
    snapshot_.error = std::move(error);
    ++snapshot_.revision;
}

const DesktopToolsSnapshot& DesktopToolsState::snapshot() const noexcept {
    return snapshot_;
}

}  // namespace zisla::core
