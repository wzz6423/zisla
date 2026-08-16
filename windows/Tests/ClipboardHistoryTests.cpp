#include "zisla/core/ClipboardHistory.hpp"
#include "zisla/core/ClipboardLinkDetector.hpp"

#include <chrono>
#include <cstdint>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        const auto suffix = std::chrono::steady_clock::now()
            .time_since_epoch().count();
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-windows-clipboard-" + std::to_string(suffix));
        std::filesystem::create_directories(path_);
    }

    ~TemporaryDirectory() {
        std::error_code error;
        std::filesystem::remove_all(path_, error);
    }

    TemporaryDirectory(const TemporaryDirectory&) = delete;
    TemporaryDirectory& operator=(const TemporaryDirectory&) = delete;

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

    std::filesystem::path create_file(std::string_view name) const {
        const auto path = path_ / name;
        std::ofstream stream(path, std::ios::binary);
        stream << name;
        if (!stream) {
            throw std::runtime_error("unable to create test file");
        }
        return std::filesystem::weakly_canonical(path);
    }

private:
    std::filesystem::path path_;
};

void defaultsRejectUnstorableContent() {
    TemporaryDirectory temporary;
    ClipboardHistoryRepository repository(temporary.path() / "state");

    expect(repository.capacity() == 999, "default history capacity should be 999");
    expect(repository.max_image_bytes() == 10U * 1024U * 1024U,
        "default image limit should be 10 MiB");
    expect(!repository.record(ClipboardHistoryContent::make_text("  \n\t"), 1),
        "blank text should be rejected");
    expect(!repository.record(ClipboardHistoryContent::make_image({}), 2),
        "empty images should be rejected");
    expect(!repository.record(
            ClipboardHistoryContent::make_file(temporary.path() / "missing.txt"),
            3,
            true),
        "missing files should be rejected");
    expect(repository.load().empty(), "rejected content should not create history rows");
}

void pinnedItemsSurviveHistoryCapacityAndPersist() {
    TemporaryDirectory temporary;
    const auto state = temporary.path() / "state";
    ClipboardHistoryRepository repository(state, 2);

    expect(repository.record(ClipboardHistoryContent::make_text("常用信息"), 100),
        "initial text should be recorded");
    const auto initial = repository.load();
    expect(initial.size() == 1, "initial history should contain one row");
    expect(repository.set_pinned(initial.front().id, true, 110),
        "existing history should be pinnable");
    expect(repository.record(ClipboardHistoryContent::make_text("第一条历史"), 200),
        "first history row should be recorded");
    expect(repository.record(ClipboardHistoryContent::make_text("第二条历史"), 300),
        "second history row should be recorded");
    expect(repository.record(ClipboardHistoryContent::make_text("第三条历史"), 400),
        "third history row should be recorded");

    const ClipboardHistoryRepository reopened(state, 2);
    const auto items = reopened.load();
    expect(items.size() == 3, "pinned plus two history rows should persist");
    expect(items[0].pinned && items[0].content.text == "常用信息",
        "pinned text should remain first");
    expect(!items[1].pinned && items[1].content.text == "第三条历史",
        "latest history should remain after trimming");
    expect(!items[2].pinned && items[2].content.text == "第二条历史",
        "second latest history should remain after trimming");
}

void duplicateContentRefreshesWithoutLosingPin() {
    TemporaryDirectory temporary;
    ClipboardHistoryRepository repository(temporary.path() / "state");
    const auto content = ClipboardHistoryContent::make_text("重复内容");

    expect(repository.record(content, 100, true), "pinned text should be recorded");
    const auto before = repository.load();
    expect(repository.record(content, 250, false), "duplicate text should refresh");
    const auto after = repository.load();

    expect(after.size() == 1, "duplicate text should reuse one row");
    expect(after[0].id == before[0].id, "duplicate text should preserve identity");
    expect(after[0].pinned, "ordinary recapture should not unpin a favorite");
    expect(after[0].last_copied_at_unix_ms == 250,
        "duplicate text should refresh its timestamp");
}

void textImageAndFilePersistAndMissingFilesAreDropped() {
    TemporaryDirectory temporary;
    const auto state = temporary.path() / "state";
    const auto file = temporary.create_file("attachment.txt");
    ClipboardHistoryRepository repository(state);

    expect(repository.record(ClipboardHistoryContent::make_text("hello"), 100),
        "text should be recorded");
    expect(repository.record(ClipboardHistoryContent::make_image({0, 1, 2, 3}), 200),
        "image should be recorded");
    expect(repository.record(ClipboardHistoryContent::make_file(file), 300, true),
        "existing file should be recorded as a favorite");

    const auto restored = ClipboardHistoryRepository(state).load();
    expect(restored.size() == 3, "all three content kinds should persist");
    expect(restored[0].content.kind == ClipboardContentKind::file
            && restored[0].content.file_path == file,
        "file favorite should restore its normalized path");
    expect(restored[1].content.kind == ClipboardContentKind::image
            && restored[1].content.image == std::vector<std::uint8_t>({0, 1, 2, 3}),
        "image bytes should round trip");
    expect(restored[2].content.kind == ClipboardContentKind::text
            && restored[2].content.text == "hello",
        "text should round trip");

    std::filesystem::remove(file);
    const auto cleaned = ClipboardHistoryRepository(state).load();
    expect(cleaned.size() == 2, "missing file favorites should be removed on load");
    expect(ClipboardHistoryRepository(state).load().size() == 2,
        "removed stale file rows should not reappear");
}

void removeAndClearOperationsRespectPinnedItems() {
    TemporaryDirectory temporary;
    const auto state = temporary.path() / "state";
    ClipboardHistoryRepository repository(state);
    expect(repository.record(ClipboardHistoryContent::make_text("pinned"), 100, true),
        "favorite should be recorded");
    expect(repository.record(ClipboardHistoryContent::make_text("history"), 200),
        "history should be recorded");

    repository.clear_history();
    auto items = repository.load();
    expect(items.size() == 1 && items[0].pinned,
        "clearing history should retain favorites");
    expect(repository.remove(items[0].id), "single row removal should report success");
    expect(!repository.remove(items[0].id), "repeated row removal should report false");
    expect(repository.record(ClipboardHistoryContent::make_text("again"), 300),
        "history should remain usable after removals");
    repository.clear_all();
    expect(repository.load().empty(), "clear all should remove every row");
}

void filteringSupportsFavoritesHistoryAndTextSearch() {
    const std::vector items = {
        ClipboardHistoryItem{
            .id = 1,
            .content = ClipboardHistoryContent::make_text("Hello Windows"),
            .last_copied_at_unix_ms = 300,
            .pinned = true,
        },
        ClipboardHistoryItem{
            .id = 2,
            .content = ClipboardHistoryContent::make_text("中文搜索"),
            .last_copied_at_unix_ms = 200,
        },
        ClipboardHistoryItem{
            .id = 3,
            .content = ClipboardHistoryContent::make_image({1}),
            .last_copied_at_unix_ms = 100,
        },
    };

    expect(filter_clipboard_history(items, ClipboardHistoryFilter::pinned, {}).size() == 1,
        "favorites filter should return only pinned rows");
    expect(filter_clipboard_history(items, ClipboardHistoryFilter::history, {}).size() == 2,
        "history filter should return only ordinary rows");
    const auto ascii = filter_clipboard_history(items, ClipboardHistoryFilter::all, "windows");
    expect(ascii.size() == 1 && ascii[0].id == 1,
        "ASCII text search should be case insensitive");
    const auto unicode = filter_clipboard_history(items, ClipboardHistoryFilter::all, "中文");
    expect(unicode.size() == 1 && unicode[0].id == 2,
        "UTF-8 text search should preserve exact non-ASCII matching");
}

void matchingSupportsLightweightFilteredViews() {
    const ClipboardHistoryItem image{
        .id = 1,
        .content = ClipboardHistoryContent::make_image({1, 2, 3}),
        .last_copied_at_unix_ms = 100,
    };
    const ClipboardHistoryItem file{
        .id = 2,
        .content = ClipboardHistoryContent::make_file(
            std::filesystem::path{"/tmp/Quarterly Report.PDF"},
            "Quarterly Report.PDF"),
        .last_copied_at_unix_ms = 200,
        .pinned = true,
    };

    expect(clipboard_history_matches(image, ClipboardHistoryFilter::history, {}),
        "an image should match the ordinary-history view without a query");
    expect(!clipboard_history_matches(image, ClipboardHistoryFilter::all, "image"),
        "an image should not match a text query");
    expect(clipboard_history_matches(file, ClipboardHistoryFilter::pinned, "report.pdf"),
        "file display-name matching should be ASCII case insensitive");
    expect(!clipboard_history_matches(file, ClipboardHistoryFilter::history, {}),
        "a favorite should not match the ordinary-history view");
}

ClipboardUrlCandidate url(
    std::string absolute,
    std::string host,
    std::string extension = {},
    std::string scheme = "https") {
    return {
        .absolute = std::move(absolute),
        .scheme = std::move(scheme),
        .host = std::move(host),
        .path_extension = std::move(extension),
    };
}

void linkClassifierRecognizesSupportedHostsAndDirectMedia() {
    expect(DownloadUrlClassifier::is_likely_downloadable(
            url("https://www.youtube.com/watch?v=abc", "www.youtube.com")),
        "supported hosts should be accepted");
    expect(DownloadUrlClassifier::is_likely_downloadable(
            url("https://cdn.example.com/movie.MP4", "cdn.example.com", "MP4")),
        "direct media extensions should be case insensitive");
    expect(!DownloadUrlClassifier::is_likely_downloadable(
            url("https://example.com/article", "example.com")),
        "ordinary pages should be rejected");
    expect(!DownloadUrlClassifier::is_likely_downloadable(
            url("ftp://youtube.com/file.mp4", "youtube.com", "mp4", "ftp")),
        "non-HTTP schemes should be rejected");
}

void linkDetectorRequiresChangesAndDeduplicatesRecentLinks() {
    ClipboardLinkDetector detector(2);
    detector.begin(10);
    const auto first = url("https://youtu.be/first", "youtu.be");
    const auto second = url("https://youtu.be/second", "youtu.be");
    const auto third = url("https://youtu.be/third", "youtu.be");

    expect(!detector.detect(10, first), "the current sequence should not be detected");
    expect(detector.detect(11, first).value_or("") == first.absolute,
        "a new supported link should be detected");
    expect(!detector.detect(11, second), "one sequence should be processed once");
    expect(!detector.detect(12, first), "recent duplicate links should be suppressed");
    expect(detector.detect(13, second).value_or("") == second.absolute,
        "a different link should be detected");
    expect(detector.detect(14, third).value_or("") == third.absolute,
        "a third link should evict the oldest recent entry");
    expect(detector.detect(15, first).value_or("") == first.absolute,
        "evicted links should become detectable again");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"defaults reject unstorable content", defaultsRejectUnstorableContent},
        {"pinned items survive capacity and persist", pinnedItemsSurviveHistoryCapacityAndPersist},
        {"duplicates refresh without losing pin", duplicateContentRefreshesWithoutLosingPin},
        {"all content kinds persist and stale files drop", textImageAndFilePersistAndMissingFilesAreDropped},
        {"remove and clear respect pinned items", removeAndClearOperationsRespectPinnedItems},
        {"filters and search select expected rows", filteringSupportsFavoritesHistoryAndTextSearch},
        {"matching supports lightweight filtered views", matchingSupportsLightweightFilteredViews},
        {"link classifier recognizes downloadable URLs", linkClassifierRecognizesSupportedHostsAndDirectMedia},
        {"link detector tracks changes and recent links", linkDetectorRequiresChangesAndDeduplicatesRecentLinks},
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
