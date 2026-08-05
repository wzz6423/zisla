#pragma once

#include <cstddef>
#include <vector>

namespace zisla::core {

enum class DashboardItemKind {
    focus_countdown,
    ai_activity,
    native_download,
    browser_download,
    media,
};

struct DashboardAvailability {
    bool focus_countdown_active{false};
    bool ai_activity_active{false};
    bool native_download_active{false};
    std::size_t browser_download_count{0};
    bool media_active{false};
};

struct DashboardItem {
    DashboardItemKind kind{DashboardItemKind::ai_activity};
    std::size_t source_index{0};

    friend bool operator==(const DashboardItem&, const DashboardItem&) = default;
};

class DashboardPresentation {
public:
    [[nodiscard]] static std::vector<DashboardItem> items(
        const DashboardAvailability& availability);
};

}  // namespace zisla::core
