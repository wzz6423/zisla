#pragma once

#include <filesystem>
#include <stdexcept>
#include <string>
#include <vector>

namespace zisla::pdf {

enum class LocalOfficeAdapterErrorCode {
    invalid_input,
    converter_not_installed,
    output_validation,
    cannot_prepare_directory,
    launch_failed,
    conversion_failed,
    missing_output,
    unsupported_platform,
};

class LocalOfficeAdapterError : public std::runtime_error {
public:
    LocalOfficeAdapterError(LocalOfficeAdapterErrorCode code, std::string message);

    [[nodiscard]] LocalOfficeAdapterErrorCode code() const noexcept;

private:
    LocalOfficeAdapterErrorCode code_;
};

// 只调用用户已经安装的 LibreOffice，不把办公套件作为应用依赖打包或运行时下载。
class LocalOfficeAdapter {
public:
    LocalOfficeAdapter();
    explicit LocalOfficeAdapter(std::vector<std::filesystem::path> executable_candidates);

    [[nodiscard]] static bool supports(const std::filesystem::path& input);
    [[nodiscard]] static std::vector<std::filesystem::path> default_executable_candidates();
    [[nodiscard]] static std::vector<std::string> conversion_arguments(
        const std::filesystem::path& input,
        const std::filesystem::path& output_directory,
        const std::filesystem::path& profile_directory);

    void convert_to_pdf(
        const std::filesystem::path& input,
        const std::filesystem::path& output) const;

private:
    std::vector<std::filesystem::path> executable_candidates_;
};

}  // namespace zisla::pdf
