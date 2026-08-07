#include "pch.h"
#include "AIAgentCredentialStore.h"

#include <algorithm>
#include <iterator>
#include <memory>
#include <system_error>

namespace winrt::Zisla {
namespace {

constexpr wchar_t ai_agent_target_prefix[] = L"Zisla.AIAgent.";
constexpr wchar_t mail_target_prefix[] = L"Zisla.Mail.";
constexpr std::size_t maximum_target_prefix_length =
    std::size(ai_agent_target_prefix) - 1;

bool is_reference_character(char value) noexcept {
    return (value >= 'A' && value <= 'Z')
        || (value >= 'a' && value <= 'z')
        || (value >= '0' && value <= '9')
        || value == '.'
        || value == '_'
        || value == '-';
}

}

CredentialStore::CredentialStore(CredentialNamespace credential_namespace)
    : target_prefix_(credential_namespace == CredentialNamespace::mail
        ? mail_target_prefix
        : ai_agent_target_prefix) {}

std::optional<std::string> CredentialStore::read(std::string_view reference) {
    last_error_.clear();
    const auto target = target_name(reference);
    if (!target) {
        last_error_ = "凭据标识无效";
        return std::nullopt;
    }

    PCREDENTIALW raw_credential = nullptr;
    if (!CredReadW(target->c_str(), CRED_TYPE_GENERIC, 0, &raw_credential)) {
        const auto error = GetLastError();
        if (error != ERROR_NOT_FOUND) {
            set_error(error, "无法读取凭据");
        }
        return std::nullopt;
    }
    const std::unique_ptr<CREDENTIALW, decltype(&CredFree)> credential(
        raw_credential,
        CredFree);
    if (!credential->CredentialBlob
        || credential->CredentialBlobSize == 0
        || credential->CredentialBlobSize > maximum_secret_bytes) {
        last_error_ = "凭据内容无效";
        return std::nullopt;
    }
    return std::string(
        reinterpret_cast<const char*>(credential->CredentialBlob),
        credential->CredentialBlobSize);
}

bool CredentialStore::write(
    std::string_view reference,
    std::string_view secret) {
    last_error_.clear();
    const auto target = target_name(reference);
    if (!target) {
        last_error_ = "凭据标识无效";
        return false;
    }
    if (secret.empty() || secret.size() > maximum_secret_bytes) {
        last_error_ = "凭据超过大小限制";
        return false;
    }

    CREDENTIALW credential{};
    credential.Type = CRED_TYPE_GENERIC;
    credential.TargetName = const_cast<wchar_t*>(target->c_str());
    credential.CredentialBlobSize = static_cast<DWORD>(secret.size());
    credential.CredentialBlob = reinterpret_cast<LPBYTE>(
        const_cast<char*>(secret.data()));
    credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
    credential.UserName = const_cast<wchar_t*>(L"Zisla");
    if (!CredWriteW(&credential, 0)) {
        set_error(GetLastError(), "无法保存凭据");
        return false;
    }
    return true;
}

bool CredentialStore::erase(std::string_view reference) {
    last_error_.clear();
    const auto target = target_name(reference);
    if (!target) {
        last_error_ = "凭据标识无效";
        return false;
    }
    if (CredDeleteW(target->c_str(), CRED_TYPE_GENERIC, 0)) {
        return true;
    }
    const auto error = GetLastError();
    if (error == ERROR_NOT_FOUND) {
        return true;
    }
    set_error(error, "无法删除凭据");
    return false;
}

const std::string& CredentialStore::last_error() const noexcept {
    return last_error_;
}

bool CredentialStore::is_valid_reference(std::string_view reference) noexcept {
    return !reference.empty()
        && reference.size() + maximum_target_prefix_length <= CRED_MAX_STRING_LENGTH
        && std::all_of(
            reference.begin(), reference.end(), [](char value) {
                return is_reference_character(value);
            });
}

std::optional<std::wstring> CredentialStore::target_name(
    std::string_view reference) {
    if (!is_valid_reference(reference)) {
        return std::nullopt;
    }
    std::wstring target(target_prefix_);
    target.reserve(target_prefix_.size() + reference.size());
    for (const auto value : reference) {
        target.push_back(static_cast<wchar_t>(value));
    }
    return target;
}

void CredentialStore::set_error(DWORD error, std::string_view fallback) {
    try {
        const auto message = std::system_category().message(static_cast<int>(error));
        last_error_ = message.empty() ? std::string(fallback) : message;
    } catch (...) {
        last_error_ = fallback;
    }
}

}
