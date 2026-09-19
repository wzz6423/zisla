#include "zisla/core/DashboardPresentation.hpp"

namespace zisla::core {

std::vector<DashboardItem> DashboardPresentation::items(
    const DashboardAvailability& availability) {
    std::vector<DashboardItem> result;
    if (availability.focus_countdown_active) {
        result.push_back({DashboardItemKind::focus_countdown});
    }
    if (availability.ai_activity_active) {
        result.push_back({DashboardItemKind::ai_activity});
    }
    if (availability.native_download_active) {
        result.push_back({DashboardItemKind::native_download});
    }
    for (std::size_t index = 0;
         index < availability.browser_download_count;
         ++index) {
        result.push_back({DashboardItemKind::browser_download, index});
    }
    if (availability.media_active) {
        result.push_back({DashboardItemKind::media});
    }
    return result;
}

}  // namespace zisla::core
