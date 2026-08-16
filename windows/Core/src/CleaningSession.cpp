#include "zisla/core/CleaningSession.hpp"

namespace zisla::core {

CleaningMode CleaningSession::mode() const noexcept {
    return mode_;
}

bool CleaningSession::active() const noexcept {
    return mode_ != CleaningMode::idle;
}

bool CleaningSession::set_mode(CleaningMode mode) noexcept {
    if (mode_ == mode) {
        return false;
    }
    mode_ = mode;
    return true;
}

void CleaningSession::stop() noexcept {
    mode_ = CleaningMode::idle;
}

}  // namespace zisla::core
