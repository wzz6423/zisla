#include "zisla/core/QuickNotes.hpp"

#include <chrono>
#include <exception>
#include <filesystem>
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

class TemporaryDirectory {
public:
    TemporaryDirectory() {
        const auto suffix = std::chrono::steady_clock::now()
            .time_since_epoch().count();
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-windows-quick-notes-" + std::to_string(suffix));
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

private:
    std::filesystem::path path_;
};

void titlesUseTheFirstNonemptyMarkdownLine() {
    expect(quick_note_title("\n  \n## 项目计划  \n正文") == "项目计划",
        "a Markdown heading should become the title");
    expect(quick_note_title("普通标题\n正文") == "普通标题",
        "plain first lines should remain unchanged");
    expect(quick_note_title("######\n") == "新随记",
        "an empty heading should use the fallback title");
    expect(quick_note_title("\r\n\t") == "新随记",
        "blank content should use the fallback title");
}

void createUpdateFindAndOrderingPersist() {
    TemporaryDirectory temporary;
    const auto state = temporary.path() / "state";
    QuickNoteRepository repository(state);
    const auto first = repository.create("# 第一条\n正文", 100);
    const auto second = repository.create("# 第二条", 200);
    expect(first && second, "valid notes should be created");

    auto notes = repository.load();
    expect(notes.size() == 2 && notes[0].id == *second && notes[1].id == *first,
        "notes should sort by latest modification time");
    expect(repository.update(*first, "# 已更新\n内容", 300),
        "an existing note should update");
    expect(!repository.update(999, "missing", 400),
        "an unknown note should not update");

    const QuickNoteRepository reopened(state);
    notes = reopened.load();
    expect(notes[0].id == *first && notes[0].title == "已更新",
        "updates should persist and change the sort order");
    const auto restored = reopened.find(*first);
    expect(restored && restored->markdown == "# 已更新\n内容"
            && restored->created_at_unix_ms == 100
            && restored->modified_at_unix_ms == 300,
        "find should restore content and timestamps");
}

void deleteAndWelcomeSeedArePersistent() {
    TemporaryDirectory temporary;
    const auto state = temporary.path() / "state";
    QuickNoteRepository repository(state);
    expect(repository.ensure_welcome_note("# 朋友，看这里。\n欢迎", 100),
        "the welcome note should be seeded once");
    expect(!repository.ensure_welcome_note("# 重复欢迎", 200),
        "the welcome note should not be seeded twice");
    const auto notes = repository.load();
    expect(notes.size() == 1 && notes[0].title == "朋友，看这里。",
        "the seeded welcome note should be a normal local note");
    expect(repository.remove(notes[0].id), "the welcome note should be deletable");
    expect(!repository.remove(notes[0].id), "repeated deletion should report false");

    const QuickNoteRepository reopened(state);
    expect(!reopened.ensure_welcome_note("# 再次欢迎", 300),
        "a deleted welcome note should stay deleted");
    expect(reopened.load().empty(), "deletion should persist");
}

void searchMatchesTitleAndBody() {
    TemporaryDirectory temporary;
    QuickNoteRepository repository(temporary.path() / "state");
    expect(repository.create("# Windows Plan\n性能预算", 100).has_value(),
        "the first searchable note should be created");
    expect(repository.create("# 购物\n牛奶", 200).has_value(),
        "the second searchable note should be created");

    const auto ascii = repository.search("windows");
    expect(ascii.size() == 1 && ascii[0].title == "Windows Plan",
        "ASCII search should be case insensitive");
    const auto unicode = repository.search("性能");
    expect(unicode.size() == 1 && unicode[0].markdown.find("性能预算") != std::string::npos,
        "UTF-8 body search should preserve exact matching");
    expect(repository.search("").size() == 2,
        "an empty query should return all notes");
}

void contentLimitRejectsOversizedWrites() {
    TemporaryDirectory temporary;
    QuickNoteRepository repository(temporary.path() / "state", 8);
    expect(repository.max_markdown_bytes() == 8,
        "the configured content limit should be exposed");
    const auto note = repository.create("12345678", 100);
    expect(note.has_value(), "content at the byte limit should be accepted");
    expect(!repository.create("123456789", 200),
        "content beyond the byte limit should be rejected");
    expect(!repository.update(*note, "123456789", 300),
        "oversized updates should be rejected");
    expect(repository.find(*note)->markdown == "12345678",
        "a rejected update should preserve the prior content");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"titles use first nonempty Markdown line", titlesUseTheFirstNonemptyMarkdownLine},
        {"CRUD ordering and persistence", createUpdateFindAndOrderingPersist},
        {"welcome seed and deletion persist", deleteAndWelcomeSeedArePersistent},
        {"search matches title and body", searchMatchesTitleAndBody},
        {"content limits reject oversized writes", contentLimitRejectsOversizedWrites},
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
