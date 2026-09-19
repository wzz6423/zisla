#include "zisla/core/DiskCleanup.hpp"

#include <algorithm>
#include <limits>
#include <string>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

namespace zisla::core {
namespace {

int kind_priority(DiskCleanupKind kind) noexcept {
    switch (kind) {
    case DiskCleanupKind::crash_report:
        return 90;
    case DiskCleanupKind::temporary_file:
        return 85;
    case DiskCleanupKind::package_cache:
        return 80;
    case DiskCleanupKind::developer_artifact:
        return 70;
    case DiskCleanupKind::application_cache:
        return 35;
    case DiskCleanupKind::cache:
        return 30;
    case DiskCleanupKind::log:
        return 20;
    case DiskCleanupKind::large_file:
        return 10;
    }
    return 0;
}

std::filesystem::path normalized(const std::filesystem::path& value) {
    return value.lexically_normal();
}

bool component_equal(
    const std::filesystem::path& left,
    const std::filesystem::path& right) noexcept {
#if defined(_WIN32)
    const auto& left_value = left.native();
    const auto& right_value = right.native();
    constexpr auto maximum_length = static_cast<std::size_t>(
        std::numeric_limits<int>::max());
    if (left_value.size() > maximum_length || right_value.size() > maximum_length) {
        return false;
    }
    return CompareStringOrdinal(
        left_value.data(),
        static_cast<int>(left_value.size()),
        right_value.data(),
        static_cast<int>(right_value.size()),
        TRUE) == CSTR_EQUAL;
#else
    return left == right;
#endif
}

bool path_equal(
    const std::filesystem::path& left,
    const std::filesystem::path& right) noexcept {
    auto left_iterator = left.begin();
    auto right_iterator = right.begin();
    while (left_iterator != left.end() && right_iterator != right.end()) {
        if (!component_equal(*left_iterator, *right_iterator)) {
            return false;
        }
        ++left_iterator;
        ++right_iterator;
    }
    return left_iterator == left.end() && right_iterator == right.end();
}

bool path_less(
    const std::filesystem::path& left,
    const std::filesystem::path& right) noexcept {
#if defined(_WIN32)
    const auto& left_value = left.native();
    const auto& right_value = right.native();
    constexpr auto maximum_length = static_cast<std::size_t>(
        std::numeric_limits<int>::max());
    if (left_value.size() <= maximum_length && right_value.size() <= maximum_length) {
        const auto result = CompareStringOrdinal(
            left_value.data(),
            static_cast<int>(left_value.size()),
            right_value.data(),
            static_cast<int>(right_value.size()),
            TRUE);
        if (result != 0 && result != CSTR_EQUAL) {
            return result == CSTR_LESS_THAN;
        }
    }
    return left_value < right_value;
#else
    return left.generic_string() < right.generic_string();
#endif
}

bool strict_descendant(
    const std::filesystem::path& candidate,
    const std::filesystem::path& root) noexcept {
    if (candidate.empty() || root.empty()) {
        return false;
    }

    const auto normalized_candidate = normalized(candidate);
    const auto normalized_root = normalized(root);
    if (normalized_candidate == normalized_root) {
        return false;
    }

    auto candidate_component = normalized_candidate.begin();
    for (const auto& root_component : normalized_root) {
        if (candidate_component == normalized_candidate.end()
            || !component_equal(*candidate_component, root_component)) {
            return false;
        }
        ++candidate_component;
    }

    if (candidate_component == normalized_candidate.end()) {
        return false;
    }
    for (; candidate_component != normalized_candidate.end(); ++candidate_component) {
        if (*candidate_component == ".." || *candidate_component == ".") {
            return false;
        }
    }
    return true;
}

}  // namespace

bool DiskCleanupPlanner::isDescendantOfAllowedRoot(
    const std::filesystem::path& candidate,
    std::span<const std::filesystem::path> roots) noexcept {
    for (const auto& root : roots) {
        if (strict_descendant(candidate, root)) {
            return true;
        }
    }
    return false;
}

bool DiskCleanupPlanner::isAllowedCandidate(
    const DiskCleanupCandidate& candidate,
    std::span<const std::filesystem::path> roots) noexcept {
    return isDescendantOfAllowedRoot(candidate.path, roots);
}

std::vector<DiskCleanupCandidate> DiskCleanupPlanner::deduplicate(
    std::span<const DiskCleanupCandidate> candidates) {
    std::vector<DiskCleanupCandidate> result;
    result.reserve(candidates.size());

    for (const auto& candidate : candidates) {
        auto normalized_candidate = candidate;
        normalized_candidate.path = normalized(candidate.path);
        const auto existing = std::find_if(
            result.begin(),
            result.end(),
            [&normalized_candidate](const auto& value) {
                return path_equal(value.path, normalized_candidate.path);
            });
        if (existing == result.end()) {
            result.push_back(std::move(normalized_candidate));
            continue;
        }

        const auto candidate_priority = kind_priority(normalized_candidate.kind);
        const auto existing_priority = kind_priority(existing->kind);
        if (candidate_priority > existing_priority
            || (candidate_priority == existing_priority
                && normalized_candidate.size_bytes > existing->size_bytes)) {
            *existing = std::move(normalized_candidate);
        }
    }

    std::sort(
        result.begin(),
        result.end(),
        [](const auto& left, const auto& right) {
            return path_less(left.path, right.path);
        });
    return result;
}

}  // namespace zisla::core
