#pragma once

#include <winrt/Windows.Foundation.h>

namespace winrt::Zisla {

// 在系统 Picker 或对话框打开期间保持浮层，避免延迟轻量关闭抢走交互。
class TransientUIHold {
public:
    TransientUIHold();
    ~TransientUIHold() noexcept;

    TransientUIHold(const TransientUIHold&) = delete;
    TransientUIHold& operator=(const TransientUIHold&) = delete;
};

void initializePicker(Windows::Foundation::IInspectable const& picker);

}  // namespace winrt::Zisla
