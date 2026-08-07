#include "zisla/core/DiskCleanup.hpp"

#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void acceptsOnlyStrictDescendantsOfAllowedRoots() {
    const std::vector<std::filesystem::path> roots{
        "/Users/test/Library/Caches",
        "/Users/test/Library/Logs",
    };

    expect(DiskCleanupPlanner::isDescendantOfAllowedRoot(
               "/Users/test/Library/Caches/tool/cache.db",
               roots),
        "a nested cache item should be allowed");
    expect(!DiskCleanupPlanner::isDescendantOfAllowedRoot(
               "/Users/test/Library/Caches",
               roots),
        "a cleanup root itself must never be removable");
    expect(!DiskCleanupPlanner::isDescendantOfAllowedRoot(
               "/Users/test/Library/Other/file.log",
               roots),
        "a sibling directory must be rejected");
    expect(!DiskCleanupPlanner::isDescendantOfAllowedRoot(
               "/Users/test/Library/Caches/item/../../Secrets/key",
               roots),
        "lexical traversal outside an allowed root must be rejected");
}

void rejectsCandidatesWithNoAllowedRoot() {
    const DiskCleanupCandidate candidate{
        .path = "/Users/test/Downloads/archive.zip",
        .kind = DiskCleanupKind::large_file,
        .size_bytes = 4'096,
    };
    const std::vector<std::filesystem::path> roots{
        "/Users/test/Library/Caches",
    };

    expect(!DiskCleanupPlanner::isAllowedCandidate(candidate, roots),
        "a candidate outside every configured root must be rejected");
}

void deduplicatesByPathAndKeepsMostSpecificClassification() {
    const std::vector<DiskCleanupCandidate> candidates{
        {
            .path = "/Users/test/Library/Caches/tool/cache.db",
            .kind = DiskCleanupKind::cache,
            .size_bytes = 100,
        },
        {
            .path = "/Users/test/Library/Caches/tool/cache.db",
            .kind = DiskCleanupKind::crash_report,
            .size_bytes = 120,
        },
        {
            .path = "/Users/test/Library/Caches/other.db",
            .kind = DiskCleanupKind::cache,
            .size_bytes = 64,
        },
    };

    const auto result = DiskCleanupPlanner::deduplicate(candidates);
    expect(result.size() == 2, "duplicate paths should collapse to one candidate");
    expect(result[0].path == "/Users/test/Library/Caches/other.db",
        "deduplicated candidates should have deterministic path ordering");
    expect(result[1].kind == DiskCleanupKind::crash_report
            && result[1].size_bytes == 120,
        "the more specific classification and latest size should win");
}

void followsNativePathCaseSemantics() {
    const std::vector<std::filesystem::path> roots{
        "/Users/Test/Library/Caches",
    };
    const auto descendant = DiskCleanupPlanner::isDescendantOfAllowedRoot(
        "/users/test/library/caches/tool/cache.db",
        roots);
#if defined(_WIN32)
    expect(descendant, "Windows cleanup paths should compare case-insensitively");
#else
    expect(!descendant, "case-sensitive platforms must preserve native path semantics");
#endif
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"allowed descendants", acceptsOnlyStrictDescendantsOfAllowedRoots},
        {"root safety", rejectsCandidatesWithNoAllowedRoot},
        {"candidate deduplication", deduplicatesByPathAndKeepsMostSpecificClassification},
        {"native path case semantics", followsNativePathCaseSemantics},
    };

    int failures = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            std::cout << "PASS: " << name << '\n';
        } catch (const std::exception& error) {
            ++failures;
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }
    return failures == 0 ? 0 : 1;
}
