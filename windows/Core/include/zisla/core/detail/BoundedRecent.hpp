#pragma once

#include <algorithm>
#include <cstddef>
#include <utility>
#include <vector>

namespace zisla::core::detail {

template <typename Value, typename Newer>
void retain_newest(
    std::vector<Value>& values,
    Value value,
    std::size_t capacity,
    Newer newer) {
    if (capacity == 0) {
        return;
    }
    if (values.size() < capacity) {
        values.push_back(std::move(value));
        return;
    }

    const auto oldest = std::max_element(values.begin(), values.end(), newer);
    if (newer(value, *oldest)) {
        *oldest = std::move(value);
    }
}

}  // namespace zisla::core::detail
