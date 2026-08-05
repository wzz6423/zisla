#pragma once

#include <cstdint>
#include <string>

namespace zisla::core {

enum class DesktopToolAction {
    none,
    refresh_recycle_bin,
    arrange_desktop,
    empty_recycle_bin,
    open_store_updates,
    trim_own_working_set,
};

struct RecycleBinMetrics {
    std::uint64_t item_count{0};
    std::uint64_t size_bytes{0};
    bool available{false};

    friend bool operator==(const RecycleBinMetrics&, const RecycleBinMetrics&) = default;
};

struct DesktopToolsSnapshot {
    RecycleBinMetrics recycle_bin;
    DesktopToolAction active_action{DesktopToolAction::none};
    DesktopToolAction last_action{DesktopToolAction::none};
    bool busy{false};
    std::string status;
    std::string error;
    std::uint64_t revision{0};

    friend bool operator==(const DesktopToolsSnapshot&, const DesktopToolsSnapshot&) = default;
};

class DesktopToolsState {
public:
    [[nodiscard]] bool begin(DesktopToolAction action) noexcept;
    void complete(RecycleBinMetrics recycle_bin, std::string status);
    void fail(std::string error);

    [[nodiscard]] const DesktopToolsSnapshot& snapshot() const noexcept;

private:
    DesktopToolsSnapshot snapshot_;
};

}  // namespace zisla::core
