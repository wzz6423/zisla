#include "zisla/core/ClipboardLinkDetector.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <string_view>

namespace zisla::core {
namespace {

constexpr std::array supported_hosts = {
    "youtube.com",
    "youtu.be",
    "bilibili.com",
    "b23.tv",
    "vimeo.com",
    "x.com",
    "twitter.com",
    "instagram.com",
    "tiktok.com",
    "facebook.com",
    "soundcloud.com",
    "spotify.com",
    "twitch.tv",
    "dailymotion.com",
    "v.qq.com",
    "video.qq.com",
    "weixin.qq.com",
    "mp.weixin.qq.com",
    "channels.weixin.qq.com",
    "youku.com",
    "mgtv.com",
    "iqiyi.com",
    "music.apple.com",
    "itunes.apple.com",
    "y.qq.com",
    "music.163.com",
    "kugou.com",
    "kuwo.cn",
};

constexpr std::array media_extensions = {
    "mp4", "mkv", "webm", "mov", "m4v", "avi", "flv",
    "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus",
};

std::string lower_ascii(std::string_view value) {
    std::string result(value);
    std::transform(result.begin(), result.end(), result.begin(), [](char character) {
        return static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
    });
    return result;
}

bool host_matches(std::string_view host, std::string_view supported) noexcept {
    if (host == supported) {
        return true;
    }
    return host.size() > supported.size()
        && host.ends_with(supported)
        && host[host.size() - supported.size() - 1] == '.';
}

}  // namespace

bool DownloadUrlClassifier::is_likely_downloadable(
    const ClipboardUrlCandidate& candidate) noexcept {
    try {
        const auto scheme = lower_ascii(candidate.scheme);
        if (scheme != "http" && scheme != "https") {
            return false;
        }
        auto host = lower_ascii(candidate.host);
        if (host.starts_with("www.")) {
            host.erase(0, 4);
        }
        if (host.empty() || candidate.absolute.empty()) {
            return false;
        }
        if (std::any_of(supported_hosts.begin(), supported_hosts.end(),
                [&host](std::string_view supported) {
                    return host_matches(host, supported);
                })) {
            return true;
        }
        const auto extension = lower_ascii(candidate.path_extension);
        return std::find(media_extensions.begin(), media_extensions.end(), extension)
            != media_extensions.end();
    } catch (...) {
        return false;
    }
}

ClipboardLinkDetector::ClipboardLinkDetector(std::size_t recent_capacity)
    : recent_capacity_(std::max<std::size_t>(1, recent_capacity)) {}

void ClipboardLinkDetector::begin(std::uint64_t sequence) noexcept {
    last_sequence_ = sequence;
}

std::optional<std::string> ClipboardLinkDetector::detect(
    std::uint64_t sequence,
    const ClipboardUrlCandidate& candidate) {
    if (last_sequence_ && sequence == *last_sequence_) {
        return std::nullopt;
    }
    last_sequence_ = sequence;
    if (!DownloadUrlClassifier::is_likely_downloadable(candidate)) {
        return std::nullopt;
    }
    if (!recent_link_set_.insert(candidate.absolute).second) {
        return std::nullopt;
    }
    recent_links_.push_back(candidate.absolute);
    if (recent_links_.size() > recent_capacity_) {
        recent_link_set_.erase(recent_links_.front());
        recent_links_.erase(recent_links_.begin());
    }
    return candidate.absolute;
}

}  // namespace zisla::core
