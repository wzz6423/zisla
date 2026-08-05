#include "pch.h"
#include "AIAgentSkillsService.h"

#include <shlobj.h>

#include <algorithm>
#include <array>
#include <fstream>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string_view>
#include <system_error>
#include <utility>

namespace winrt::Zisla {
namespace {

namespace fs = std::filesystem;

constexpr wchar_t configuration_file_name[] = L"ai-agent-skills.conf";
constexpr std::size_t maximum_configuration_bytes = 1024U * 1024U;
constexpr std::size_t maximum_disabled_path_count = 4'096;

constexpr std::array destinations{
    AIAgentSkillDestination::codex,
    AIAgentSkillDestination::claude,
    AIAgentSkillDestination::agents,
};

std::optional<fs::path> profile_directory() noexcept {
    wchar_t* raw_path = nullptr;
    if (FAILED(SHGetKnownFolderPath(
            FOLDERID_Profile,
            KF_FLAG_DEFAULT,
            nullptr,
            &raw_path))) {
        return std::nullopt;
    }
    fs::path result{raw_path};
    CoTaskMemFree(raw_path);
    return result;
}

std::string path_as_utf8(const fs::path& path) {
    const auto encoded = path.generic_u8string();
    return {
        reinterpret_cast<const char*>(encoded.data()),
        encoded.size()};
}

std::optional<fs::path> path_from_utf8(std::string_view value) {
    if (value.empty() || value.find('\0') != std::string_view::npos) {
        return std::nullopt;
    }
    try {
        std::u8string encoded;
        encoded.reserve(value.size());
        for (const auto character : value) {
            encoded.push_back(static_cast<char8_t>(
                static_cast<unsigned char>(character)));
        }
        return fs::path{encoded}.lexically_normal();
    } catch (...) {
        return std::nullopt;
    }
}

std::string hex_encode(std::string_view value) {
    constexpr char digits[] = "0123456789abcdef";
    std::string result;
    result.reserve(value.size() * 2);
    for (const auto character : value) {
        const auto byte = static_cast<unsigned char>(character);
        result.push_back(digits[byte >> 4U]);
        result.push_back(digits[byte & 0x0FU]);
    }
    return result;
}

std::optional<unsigned char> hex_value(char character) noexcept {
    if (character >= '0' && character <= '9') {
        return static_cast<unsigned char>(character - '0');
    }
    if (character >= 'a' && character <= 'f') {
        return static_cast<unsigned char>(character - 'a' + 10);
    }
    return std::nullopt;
}

std::optional<std::string> hex_decode(std::string_view value) {
    if (value.empty() || value.size() % 2 != 0) {
        return std::nullopt;
    }
    std::string result;
    result.reserve(value.size() / 2);
    for (std::size_t index = 0; index < value.size(); index += 2) {
        const auto high = hex_value(value[index]);
        const auto low = hex_value(value[index + 1]);
        if (!high || !low) {
            return std::nullopt;
        }
        result.push_back(static_cast<char>((*high << 4U) | *low));
    }
    return result;
}

bool same_path(const fs::path& lhs, const fs::path& rhs) {
    return path_as_utf8(lhs.lexically_normal())
        == path_as_utf8(rhs.lexically_normal());
}

std::string destination_name(AIAgentSkillDestination destination) {
    switch (destination) {
    case AIAgentSkillDestination::codex:
        return "Codex";
    case AIAgentSkillDestination::claude:
        return "Claude Code";
    case AIAgentSkillDestination::agents:
        return "Agents";
    }
    return "Skills";
}

std::string mode_token(
    zisla::core::AgentSkillSynchronizationMode mode) {
    return mode == zisla::core::AgentSkillSynchronizationMode::symbolic_link
        ? "symbolic-link"
        : "file-copy";
}

std::optional<zisla::core::AgentSkillSynchronizationMode> mode_from_token(
    std::string_view value) noexcept {
    using zisla::core::AgentSkillSynchronizationMode;
    if (value == "symbolic-link") {
        return AgentSkillSynchronizationMode::symbolic_link;
    }
    if (value == "file-copy") {
        return AgentSkillSynchronizationMode::file_copy;
    }
    return std::nullopt;
}

std::optional<AIAgentSkillDestination> destination_from_token(
    std::string_view value) noexcept {
    if (value == "codex") {
        return AIAgentSkillDestination::codex;
    }
    if (value == "claude") {
        return AIAgentSkillDestination::claude;
    }
    if (value == "agents") {
        return AIAgentSkillDestination::agents;
    }
    return std::nullopt;
}

std::string destination_token(AIAgentSkillDestination destination) {
    switch (destination) {
    case AIAgentSkillDestination::codex:
        return "codex";
    case AIAgentSkillDestination::claude:
        return "claude";
    case AIAgentSkillDestination::agents:
        return "agents";
    }
    return "";
}

}  // namespace

AIAgentSkillsService::AIAgentSkillsService(fs::path state_directory)
    : state_directory_(std::move(state_directory)),
      managed_directory_(state_directory_ / L"skills"),
      home_directory_(profile_directory().value_or(fs::path{})),
      snapshot_(std::make_shared<const AIAgentSkillsServiceSnapshot>(
          AIAgentSkillsServiceSnapshot{
              .managed_directory = managed_directory_,
          })) {}

AIAgentSkillsService::~AIAgentSkillsService() {
    stop();
}

bool AIAgentSkillsService::start(HWND target, UINT changed_message) {
    std::lock_guard lock(mutex_);
    if (running_ || thread_.joinable() || !target || changed_message == 0
        || state_directory_.empty() || home_directory_.empty()) {
        return false;
    }

    skills_.clear();
    configuration_ = {};
    error_.clear();
    revision_ = 0;
    loading_ = true;
    synchronizing_ = false;
    target_ = target;
    changed_message_ = changed_message;
    running_ = true;
    snapshot_.store(
        std::make_shared<const AIAgentSkillsServiceSnapshot>(
            AIAgentSkillsServiceSnapshot{
                .managed_directory = managed_directory_,
                .loading = true,
            }),
        std::memory_order_release);
    try {
        thread_ = std::thread([this] { run(); });
    } catch (...) {
        running_ = false;
        target_ = nullptr;
        changed_message_ = 0;
        return false;
    }
    return true;
}

void AIAgentSkillsService::stop() noexcept {
    {
        std::lock_guard lock(mutex_);
        if (!running_ && !thread_.joinable()) {
            return;
        }
        running_ = false;
    }
    condition_.notify_one();
    if (thread_.joinable()) {
        thread_.join();
    }
    std::lock_guard lock(mutex_);
    commands_.clear();
    target_ = nullptr;
    changed_message_ = 0;
}

void AIAgentSkillsService::reload() {
    enqueue({.kind = CommandKind::reload});
}

void AIAgentSkillsService::setSkillEnabled(fs::path path, bool enabled) {
    if (!path.empty()) {
        enqueue({
            .kind = CommandKind::set_skill_enabled,
            .path = std::move(path),
            .enabled = enabled,
        });
    }
}

void AIAgentSkillsService::setSynchronizationMode(
    zisla::core::AgentSkillSynchronizationMode mode) {
    enqueue({
        .kind = CommandKind::set_synchronization_mode,
        .mode = mode,
    });
}

void AIAgentSkillsService::setDestinationEnabled(
    AIAgentSkillDestination destination,
    bool enabled) {
    enqueue({
        .kind = CommandKind::set_destination_enabled,
        .destination = destination,
        .enabled = enabled,
    });
}

void AIAgentSkillsService::synchronize() {
    enqueue({.kind = CommandKind::synchronize});
}

fs::path AIAgentSkillsService::managedDirectory() const {
    return managed_directory_;
}

std::shared_ptr<const AIAgentSkillsServiceSnapshot>
AIAgentSkillsService::snapshot() const noexcept {
    return snapshot_.load(std::memory_order_acquire);
}

void AIAgentSkillsService::enqueue(Command command) {
    {
        std::lock_guard lock(mutex_);
        if (!running_) {
            return;
        }
        if (command.kind == CommandKind::reload) {
            std::erase_if(commands_, [](const Command& pending) {
                return pending.kind == CommandKind::reload;
            });
        } else if (command.kind == CommandKind::set_skill_enabled) {
            std::erase_if(commands_, [&command](const Command& pending) {
                return pending.kind == CommandKind::set_skill_enabled
                    && same_path(pending.path, command.path);
            });
        } else if (command.kind == CommandKind::set_synchronization_mode) {
            std::erase_if(commands_, [](const Command& pending) {
                return pending.kind == CommandKind::set_synchronization_mode;
            });
        } else if (command.kind == CommandKind::set_destination_enabled) {
            std::erase_if(commands_, [&command](const Command& pending) {
                return pending.kind == CommandKind::set_destination_enabled
                    && pending.destination == command.destination;
            });
        } else if (command.kind == CommandKind::synchronize) {
            std::erase_if(commands_, [](const Command& pending) {
                return pending.kind == CommandKind::synchronize;
            });
        }
        commands_.push_back(std::move(command));
    }
    condition_.notify_one();
}

void AIAgentSkillsService::run() noexcept {
    try {
        loadConfiguration();
        reloadSkills();
        loading_ = false;
        publish();
    } catch (const std::exception& error) {
        publishError(error.what());
    } catch (...) {
        publishError("Skills 初始化失败");
    }

    while (true) {
        Command command;
        {
            std::unique_lock lock(mutex_);
            condition_.wait(lock, [this] {
                return !commands_.empty() || !running_;
            });
            if (commands_.empty() && !running_) {
                break;
            }
            command = std::move(commands_.front());
            commands_.pop_front();
        }

        try {
            execute(std::move(command));
            publish();
        } catch (const std::exception& error) {
            publishError(error.what());
        } catch (...) {
            publishError("Skills 操作失败");
        }
    }
}

void AIAgentSkillsService::execute(Command command) {
    switch (command.kind) {
    case CommandKind::reload:
        error_.clear();
        loading_ = true;
        publish();
        reloadSkills();
        loading_ = false;
        return;
    case CommandKind::set_skill_enabled:
        std::erase_if(configuration_.disabled_paths, [&command](const fs::path& path) {
            return same_path(path, command.path);
        });
        if (!command.enabled) {
            configuration_.disabled_paths.push_back(command.path.lexically_normal());
        }
        saveConfiguration();
        error_.clear();
        reloadSkills();
        return;
    case CommandKind::set_synchronization_mode:
        configuration_.mode = command.mode;
        saveConfiguration();
        synchronizing_ = true;
        publish();
        synchronizeConfiguredDestinations();
        synchronizing_ = false;
        return;
    case CommandKind::set_destination_enabled:
        setDestinationConfigurationEnabled(command.destination, command.enabled);
        saveConfiguration();
        synchronizing_ = true;
        publish();
        synchronizeConfiguredDestinations();
        synchronizing_ = false;
        return;
    case CommandKind::synchronize:
        synchronizing_ = true;
        publish();
        synchronizeConfiguredDestinations();
        synchronizing_ = false;
        return;
    }
}

void AIAgentSkillsService::loadConfiguration() {
    configuration_ = {};
    const auto path = state_directory_ / configuration_file_name;
    std::error_code error;
    if (!fs::exists(path, error)) {
        if (error) {
            throw std::runtime_error("无法读取 Skills 配置");
        }
        return;
    }
    const auto size = fs::file_size(path, error);
    if (error || size > maximum_configuration_bytes) {
        throw std::runtime_error("Skills 配置无效");
    }

    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("无法打开 Skills 配置");
    }
    std::string line;
    while (std::getline(input, line)) {
        const auto delimiter = line.find('=');
        if (delimiter == std::string::npos) {
            continue;
        }
        const std::string_view key{line.data(), delimiter};
        const std::string_view value{line.data() + delimiter + 1,
            line.size() - delimiter - 1};
        if (key == "mode") {
            if (const auto mode = mode_from_token(value)) {
                configuration_.mode = *mode;
            }
            continue;
        }
        if (key == "destination") {
            const auto separator = value.find(':');
            if (separator == std::string_view::npos) {
                continue;
            }
            const auto destination = destination_from_token(value.substr(0, separator));
            const auto enabled = value.substr(separator + 1);
            if (destination && (enabled == "0" || enabled == "1")) {
                setDestinationConfigurationEnabled(*destination, enabled == "1");
            }
            continue;
        }
        if (key == "disabled"
            && configuration_.disabled_paths.size() < maximum_disabled_path_count) {
            const auto decoded = hex_decode(value);
            const auto path_value = decoded ? path_from_utf8(*decoded) : std::nullopt;
            if (path_value
                && std::none_of(
                    configuration_.disabled_paths.begin(),
                    configuration_.disabled_paths.end(),
                    [&path_value](const fs::path& current) {
                        return same_path(current, *path_value);
                    })) {
                configuration_.disabled_paths.push_back(std::move(*path_value));
            }
        }
    }
    if (!input.eof()) {
        throw std::runtime_error("无法读取 Skills 配置");
    }
}

void AIAgentSkillsService::saveConfiguration() const {
    std::error_code error;
    fs::create_directories(state_directory_, error);
    if (error) {
        throw std::runtime_error("无法创建 Skills 配置目录");
    }

    const auto path = state_directory_ / configuration_file_name;
    auto temporary = path;
    temporary += L".tmp";
    {
        std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
        if (!output) {
            throw std::runtime_error("无法保存 Skills 配置");
        }
        output << "mode=" << mode_token(configuration_.mode) << '\n';
        for (const auto destination : destinations) {
            output << "destination=" << destination_token(destination) << ':'
                   << (isDestinationEnabled(destination) ? '1' : '0') << '\n';
        }
        for (const auto& disabled : configuration_.disabled_paths) {
            output << "disabled=" << hex_encode(path_as_utf8(disabled)) << '\n';
        }
        output.flush();
        if (!output) {
            output.close();
            (void)fs::remove(temporary, error);
            throw std::runtime_error("无法保存 Skills 配置");
        }
    }

    if (!MoveFileExW(
            temporary.c_str(),
            path.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        (void)fs::remove(temporary, error);
        throw std::runtime_error("无法替换 Skills 配置");
    }
}

void AIAgentSkillsService::reloadSkills() {
    synchronizer_.ensure_managed_directory(managed_directory_);
    auto roots = zisla::core::AgentSkillCatalog::default_roots(home_directory_);
    roots.push_back(managed_directory_);
    std::vector<fs::path> ignored;
    ignored.reserve(destinations.size());
    for (const auto destination : destinations) {
        ignored.push_back(destinationDirectory(destination));
    }
    skills_ = zisla::core::AgentSkillCatalog::scan(
        roots,
        configuration_.disabled_paths,
        ignored);
}

void AIAgentSkillsService::synchronizeConfiguredDestinations() {
    synchronizer_.ensure_managed_directory(managed_directory_);
    std::vector<std::string> failures;
    for (const auto destination : destinations) {
        const auto path = destinationDirectory(destination);
        try {
            if (isDestinationEnabled(destination)) {
                synchronizer_.synchronize(managed_directory_, path, configuration_.mode);
            } else {
                synchronizer_.disable(path, managed_directory_);
            }
        } catch (const zisla::core::AgentSkillSynchronizationError& error) {
            failures.push_back(destination_name(destination) + "：" + error.what());
        } catch (const std::exception& error) {
            failures.push_back(destination_name(destination) + "：" + error.what());
        }
    }
    reloadSkills();
    if (failures.empty()) {
        error_.clear();
        return;
    }
    std::ostringstream message;
    message << "Skills 同步失败";
    for (const auto& failure : failures) {
        message << '\n' << failure;
    }
    error_ = message.str();
}

void AIAgentSkillsService::publish() noexcept {
    try {
        auto next = std::make_shared<AIAgentSkillsServiceSnapshot>();
        next->skills = skills_;
        next->managed_directory = managed_directory_;
        next->mode = configuration_.mode;
        next->error = error_;
        next->loading = loading_;
        next->synchronizing = synchronizing_;
        next->revision = ++revision_;
        next->destinations.reserve(destinations.size());
        for (const auto destination : destinations) {
            next->destinations.push_back({
                .destination = destination,
                .path = destinationDirectory(destination),
                .enabled = isDestinationEnabled(destination),
            });
        }
        snapshot_.store(std::move(next), std::memory_order_release);
        notify();
    } catch (...) {
    }
}

void AIAgentSkillsService::publishError(std::string error) noexcept {
    error_ = std::move(error);
    loading_ = false;
    synchronizing_ = false;
    publish();
}

void AIAgentSkillsService::notify() noexcept {
    HWND target = nullptr;
    UINT message = 0;
    {
        std::lock_guard lock(mutex_);
        target = target_;
        message = changed_message_;
    }
    if (target && message != 0) {
        (void)PostMessageW(target, message, 0, 0);
    }
}

bool AIAgentSkillsService::isDestinationEnabled(
    AIAgentSkillDestination destination) const noexcept {
    switch (destination) {
    case AIAgentSkillDestination::codex:
        return configuration_.codex_enabled;
    case AIAgentSkillDestination::claude:
        return configuration_.claude_enabled;
    case AIAgentSkillDestination::agents:
        return configuration_.agents_enabled;
    }
    return false;
}

void AIAgentSkillsService::setDestinationConfigurationEnabled(
    AIAgentSkillDestination destination,
    bool enabled) noexcept {
    switch (destination) {
    case AIAgentSkillDestination::codex:
        configuration_.codex_enabled = enabled;
        return;
    case AIAgentSkillDestination::claude:
        configuration_.claude_enabled = enabled;
        return;
    case AIAgentSkillDestination::agents:
        configuration_.agents_enabled = enabled;
        return;
    }
}

fs::path AIAgentSkillsService::destinationDirectory(
    AIAgentSkillDestination destination) const {
    switch (destination) {
    case AIAgentSkillDestination::codex:
        return home_directory_ / L".codex" / L"skills" / L"zisla-managed";
    case AIAgentSkillDestination::claude:
        return home_directory_ / L".claude" / L"skills" / L"zisla-managed";
    case AIAgentSkillDestination::agents:
        return home_directory_ / L".agents" / L"skills" / L"zisla-managed";
    }
    return {};
}

}
