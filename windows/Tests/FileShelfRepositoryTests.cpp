#include "zisla/core/FileShelfRepository.hpp"

#include <chrono>
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
            / ("zisla-windows-file-shelf-" + std::to_string(suffix));
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

void addIgnoresMissingAndNormalizedDuplicates() {
    TemporaryDirectory temporary;
    const auto file = temporary.create_file("first.txt");
    const auto duplicate = file.parent_path() / "." / file.filename();
    const auto missing = temporary.path() / "missing.txt";
    FileShelfRepository repository(temporary.path() / "state");
    const std::vector paths = {file, duplicate, missing};

    expect(repository.add(paths, 1'000) == 1,
        "only one existing normalized path should be added");
    const auto items = repository.load();
    expect(items.size() == 1 && items[0].path == file,
        "the shelf should retain the normalized existing path");
}

void capacityKeepsLatestNinetyNineItems() {
    TemporaryDirectory temporary;
    FileShelfRepository repository(temporary.path() / "state");
    std::vector<std::filesystem::path> files;
    for (int index = 0; index < 100; ++index) {
        files.push_back(temporary.create_file(
            "file-" + std::to_string(index) + ".txt"));
    }

    expect(repository.capacity() == 99, "the default capacity should be 99");
    expect(repository.add(files, 2'000) == 100,
        "all unique files should be accepted before FIFO trimming");
    const auto items = repository.load();
    expect(items.size() == 99, "the shelf should retain its configured capacity");
    expect(items.front().path == files[1] && items.back().path == files[99],
        "FIFO trimming should evict only the oldest item");
}

void recordsPersistAcrossRepositoryInstances() {
    TemporaryDirectory temporary;
    const auto first = temporary.create_file("first.txt");
    const auto second = temporary.create_file("second.txt");
    const auto state = temporary.path() / "state";
    {
        FileShelfRepository repository(state);
        const std::vector paths = {first, second};
        expect(repository.add(paths, 3'000) == 2,
            "the first repository should persist both paths");
    }

    const FileShelfRepository reopened(state);
    const auto items = reopened.load();
    expect(items.size() == 2, "a reopened repository should restore both paths");
    expect(items[0].path == first && items[1].path == second,
        "reopened items should keep insertion order");
    expect(items[0].added_at_unix_ms == 3'000,
        "reopened items should preserve their added timestamp");
}

void loadRemovesFilesThatNoLongerExist() {
    TemporaryDirectory temporary;
    const auto first = temporary.create_file("first.txt");
    const auto second = temporary.create_file("second.txt");
    FileShelfRepository repository(temporary.path() / "state");
    const std::vector paths = {first, second};
    expect(repository.add(paths, 4'000) == 2, "both files should be added");
    std::filesystem::remove(first);

    const auto items = repository.load();
    expect(items.size() == 1 && items[0].path == second,
        "loading should omit and delete missing files");
    temporary.create_file("first.txt");
    expect(repository.load().size() == 1,
        "a stale record should not reappear when its path is recreated");
}

void removeClearAndMinimumCapacityArePersistent() {
    TemporaryDirectory temporary;
    const auto first = temporary.create_file("first.txt");
    const auto second = temporary.create_file("second.txt");
    FileShelfRepository repository(temporary.path() / "state", 0);
    const std::vector paths = {first, second};

    expect(repository.capacity() == 1, "capacity should clamp to one");
    expect(repository.add(paths, 5'000) == 2, "both files should be accepted");
    expect(repository.load().size() == 1 && repository.load()[0].path == second,
        "minimum capacity should keep the latest file");
    expect(repository.remove(second), "remove should delete the stored path");
    expect(!repository.remove(second), "removing the same path twice should be false");
    expect(repository.add(std::span{paths}.first(1), 6'000) == 1,
        "a removed path should be addable again");
    repository.clear();
    expect(repository.load().empty(), "clear should persist an empty shelf");
}

}  // namespace

int main() {
    const std::pair<std::string_view, std::function<void()>> tests[] = {
        {"add ignores missing and duplicate paths", addIgnoresMissingAndNormalizedDuplicates},
        {"capacity keeps latest 99 items", capacityKeepsLatestNinetyNineItems},
        {"records persist across instances", recordsPersistAcrossRepositoryInstances},
        {"load removes missing files", loadRemovesFilesThatNoLongerExist},
        {"remove clear and minimum capacity persist", removeClearAndMinimumCapacityArePersistent},
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
