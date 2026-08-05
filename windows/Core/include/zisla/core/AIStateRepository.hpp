#pragma once

#include "zisla/core/AIModels.hpp"

#include <cstddef>
#include <filesystem>
#include <stdexcept>
#include <span>
#include <string>
#include <vector>

namespace zisla::core {

struct AIStateStorageChangeToken {
    std::optional<std::filesystem::file_time_type> database_modification_time;
    std::optional<std::uintmax_t> database_size;
    std::optional<std::filesystem::file_time_type> wal_modification_time;
    std::optional<std::uintmax_t> wal_size;

    friend bool operator==(
        const AIStateStorageChangeToken&,
        const AIStateStorageChangeToken&) = default;
};

struct AIState {
    std::vector<AIProgressTask> tasks;
    std::vector<AIUsageSample> usage_samples;
    std::vector<IslandNotice> notices;

    friend bool operator==(const AIState&, const AIState&) = default;
};

enum class AIStateRepositoryErrorCode {
    corrupted_state,
    task_not_found,
    storage_failure,
};

class AIStateRepositoryError : public std::runtime_error {
public:
    AIStateRepositoryError(
        AIStateRepositoryErrorCode code,
        std::string message,
        std::string subject = {});

    [[nodiscard]] AIStateRepositoryErrorCode code() const noexcept;
    [[nodiscard]] const std::string& subject() const noexcept;

private:
    AIStateRepositoryErrorCode code_;
    std::string subject_;
};

class AIStateRepository {
public:
    explicit AIStateRepository(
        std::filesystem::path directory,
        std::size_t maximum_usage_samples = 20'000);

    [[nodiscard]] const std::filesystem::path& directory() const noexcept;
    [[nodiscard]] std::filesystem::path database_path() const;
    [[nodiscard]] AIStateStorageChangeToken storage_change_token() const noexcept;

    [[nodiscard]] AIState load(bool include_usage_samples = true) const;
    void upsert(const AIProgressTask& task) const;
    void finish(
        std::string_view id,
        bool failed,
        std::optional<std::string> detail,
        std::int64_t at_unix_ms) const;
    [[nodiscard]] bool remove(std::string_view id) const;
    void clear_tasks() const;
    bool record_usage(const AIUsageSample& sample) const;
    std::size_t record_usage(std::span<const AIUsageSample> samples) const;
    void enqueue_notice(const IslandNotice& notice) const;
    void enqueue_notices(std::span<const IslandNotice> notices) const;
    [[nodiscard]] std::vector<IslandNotice> take_notices() const;

private:
    std::filesystem::path directory_;
    std::size_t maximum_usage_samples_;
};

}  // namespace zisla::core
