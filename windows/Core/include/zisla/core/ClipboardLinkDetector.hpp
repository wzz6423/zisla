#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <unordered_set>
#include <vector>

namespace zisla::core {

struct ClipboardUrlCandidate {
    std::string absolute;
    std::string scheme;
    std::string host;
    std::string path_extension;

    friend bool operator==(const ClipboardUrlCandidate&, const ClipboardUrlCandidate&) = default;
};

class DownloadUrlClassifier {
public:
    [[nodiscard]] static bool is_likely_downloadable(
        const ClipboardUrlCandidate& candidate) noexcept;
};

class ClipboardLinkDetector {
public:
    explicit ClipboardLinkDetector(std::size_t recent_capacity = 32);

    void begin(std::uint64_t sequence) noexcept;
    [[nodiscard]] std::optional<std::string> detect(
        std::uint64_t sequence,
        const ClipboardUrlCandidate& candidate);

private:
    std::size_t recent_capacity_;
    std::optional<std::uint64_t> last_sequence_;
    std::vector<std::string> recent_links_;
    std::unordered_set<std::string> recent_link_set_;
};

}  // namespace zisla::core
