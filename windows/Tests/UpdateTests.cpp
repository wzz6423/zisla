#include <zisla/core/Update.hpp>

#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

void semanticVersionsFollowReleasePrecedence() {
    const auto preview = SemanticVersion::parse("v0.1.2-preview.3+build.9");
    const auto release = SemanticVersion::parse("0.1.2");
    const auto next = SemanticVersion::parse("0.1.3");
    expect(preview && release && next, "valid release version text should parse");
    expect(*preview < *release && *release < *next,
        "prerelease and patch precedence should follow semantic version ordering");
    expect(!SemanticVersion::parse("0.1.2.3").has_value(),
        "versions with more than three numeric components should be rejected");
    expect(!SemanticVersion::parse("v1..2").has_value(),
        "versions with empty numeric components should be rejected");
}

void releaseResponsesAcceptSafeGiteeShape() {
    const auto release = ReleaseResponseParser::parse(
        R"({"tag_name":"v0.1.3","html_url":"https://gitee.com/wzz6423/zisla/releases/tag/v0.1.3"})");
    expect(release.tag_name == "v0.1.3" && !release.draft && !release.prerelease
            && release.assets.empty(),
        "Gitee releases without GitHub-only fields should remain usable");

    const auto github = ReleaseResponseParser::parse(
        R"({"tag_name":"v0.1.4","html_url":"https://github.com/wzz6423/zisla/releases/tag/v0.1.4","assets":[{"name":"Zisla.msix","browser_download_url":"https://example.com/Zisla.msix","size":42}]})");
    expect(github.assets.size() == 1 && github.assets.front().download_url
            == "https://example.com/Zisla.msix",
        "safe release assets should be retained for the installation hand-off");
}

void releaseSelectionMatchesMacOSSourceOrder() {
    const auto gitee = ReleaseResponseParser::parse(
        R"({"tag_name":"v0.1.3","html_url":"https://gitee.com/wzz6423/zisla/releases/tag/v0.1.3"})");
    const auto github = ReleaseResponseParser::parse(
        R"({"tag_name":"v0.1.4","html_url":"https://github.com/wzz6423/zisla/releases/tag/v0.1.4"})");
    const auto selected = UpdateSelector::select("0.1.2", gitee, github);
    expect(selected && selected->source == ReleaseSource::gitee
            && selected->release.tag_name == "v0.1.3",
        "a newer Gitee release should take priority before GitHub is queried");

    const auto preview = ReleaseResponseParser::parse(
        R"({"tag_name":"v0.1.4-preview.1","html_url":"https://gitee.com/wzz6423/zisla/releases/tag/v0.1.4-preview.1","prerelease":true})");
    const auto fallback = UpdateSelector::select("0.1.2", preview, github);
    expect(fallback && fallback->source == ReleaseSource::github,
        "draft and prerelease releases should fall through to the GitHub release channel");

    const auto preview_selected = UpdateSelector::select(
        "0.1.2",
        preview,
        github,
        UpdateChannel::preview);
    expect(preview_selected && preview_selected->source == ReleaseSource::gitee,
        "the preview channel should accept its prerelease feed");
}

void releaseEndpointsAreFixedPerChannelAndSource() {
    expect(
        release_endpoint(ReleaseSource::gitee, UpdateChannel::release)
            == "https://gitee.com/api/v5/repos/wzz6423/zisla/releases/latest",
        "release channel should use Gitee latest endpoint");
    expect(
        release_endpoint(ReleaseSource::github, UpdateChannel::preview)
            == "https://api.github.com/repos/wzz6423/zisla/releases/tags/preview",
        "preview channel should use GitHub preview tag endpoint");
}

void unsafeOrMalformedReleaseResponsesAreRejected() {
    try {
        (void)ReleaseResponseParser::parse(
            R"({"tag_name":"v0.1.3","html_url":"file:///tmp/Zisla.msix"})");
    } catch (const ReleaseResponseError& error) {
        expect(error.code() == ReleaseResponseErrorCode::invalid_value,
            "non-HTTPS release URLs should fail as invalid values");
        return;
    }
    throw std::runtime_error("non-HTTPS release URLs should be rejected");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"semantic versions follow release precedence", semanticVersionsFollowReleasePrecedence},
        {"release responses accept safe Gitee shape", releaseResponsesAcceptSafeGiteeShape},
        {"release selection matches macOS source order", releaseSelectionMatchesMacOSSourceOrder},
        {"release endpoints are fixed per channel and source", releaseEndpointsAreFixedPerChannelAndSource},
        {"unsafe or malformed release responses are rejected", unsafeOrMalformedReleaseResponsesAreRejected},
    };

    std::size_t passed = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            ++passed;
        } catch (const std::exception& error) {
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }
    std::cout << passed << '/' << std::size(tests) << " tests passed\n";
    return passed == std::size(tests) ? 0 : 1;
}
