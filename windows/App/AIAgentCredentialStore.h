#pragma once

#include <windows.h>
#include <wincred.h>

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>

namespace winrt::Zisla {

enum class CredentialNamespace {
    ai_agent,
    mail,
};

/// Stores short secrets in Windows Credential Manager; files use a separate protected store.
class CredentialStore {
public:
    static constexpr std::size_t maximum_secret_bytes = CRED_MAX_CREDENTIAL_BLOB_SIZE;

    explicit CredentialStore(CredentialNamespace credential_namespace = CredentialNamespace::ai_agent);

    [[nodiscard]] std::optional<std::string> read(std::string_view reference);
    [[nodiscard]] bool write(std::string_view reference, std::string_view secret);
    [[nodiscard]] bool erase(std::string_view reference);
    [[nodiscard]] const std::string& last_error() const noexcept;
    [[nodiscard]] static bool is_valid_reference(std::string_view reference) noexcept;

private:
    [[nodiscard]] std::optional<std::wstring> target_name(
        std::string_view reference);
    void set_error(DWORD error, std::string_view fallback);

    std::string last_error_;
    std::wstring target_prefix_;
};

using AIAgentCredentialStore = CredentialStore;

}
