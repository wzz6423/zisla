#include "zisla/core/Download.hpp"

#include <algorithm>
#include <chrono>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

using namespace zisla::core;

void expect(bool condition, std::string_view message) {
    if (!condition) {
        throw std::runtime_error(std::string(message));
    }
}

class TestDirectory {
public:
    TestDirectory() {
        path_ = std::filesystem::temp_directory_path()
            / ("zisla-download-tests-"
                + std::to_string(std::chrono::steady_clock::now()
                    .time_since_epoch().count()));
        std::filesystem::create_directories(path_);
    }

    ~TestDirectory() {
        std::error_code ignored;
        std::filesystem::remove_all(path_, ignored);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_;
};

bool has_adjacent_arguments(
    const std::vector<std::string>& arguments,
    std::string_view first,
    std::string_view second) {
    for (std::size_t index = 1; index < arguments.size(); ++index) {
        if (arguments[index - 1] == first && arguments[index] == second) {
            return true;
        }
    }
    return false;
}

void validatesAndNormalizesDownloadRequests() {
    const auto normalized = DownloadRequestValidator::normalized_url(
        "  HTTPS://www.youtube.com/watch?v=abc  ");
    expect(normalized
            && *normalized == "https://www.youtube.com/watch?v=abc",
        "HTTP URLs should be trimmed and their scheme normalized");
    expect(!DownloadRequestValidator::normalized_url("ftp://example.com/file"),
        "non-HTTP schemes must be rejected");
    expect(!DownloadRequestValidator::normalized_url("https://"),
        "a URL without a host must be rejected");
    expect(!DownloadRequestValidator::normalized_url("https://user@"),
        "userinfo without a host must be rejected");
    expect(!DownloadRequestValidator::normalized_url("https://:443/path"),
        "a port without a host must be rejected");
    expect(!DownloadRequestValidator::normalized_url(
               "https://example.com/a b"),
        "whitespace inside a URL must be rejected");

    const DownloadRequest valid{
        .url = "https://youtu.be/example",
        .mode = DownloadMode::video,
        .output_directory = std::filesystem::temp_directory_path(),
    };
    expect(DownloadRequestValidator::validate(valid)
            == DownloadRequestValidation::valid,
        "an HTTP URL and absolute output directory should be valid");
    auto invalid_directory = valid;
    invalid_directory.output_directory = "relative";
    expect(DownloadRequestValidator::validate(invalid_directory)
            == DownloadRequestValidation::invalid_output_directory,
        "relative output directories must be rejected");
    invalid_directory.output_directory = std::filesystem::temp_directory_path()
        / "zisla-download-missing-output-directory";
    expect(DownloadRequestValidator::validate(invalid_directory)
            == DownloadRequestValidation::invalid_output_directory,
        "missing output directories must be rejected");
    TestDirectory temporary;
    const auto file = temporary.path() / "not-a-directory";
    std::ofstream(file).put('x');
    invalid_directory.output_directory = file;
    expect(DownloadRequestValidator::validate(invalid_directory)
            == DownloadRequestValidation::invalid_output_directory,
        "output paths that are files must be rejected");
}

void buildsHardenedYTDLPArguments() {
    const DownloadRequest request{
        .url = "https://example.com/watch?v=a&next=b",
        .mode = DownloadMode::video,
        .output_directory = std::filesystem::temp_directory_path() / "Downloads",
    };
    const auto temporary = std::filesystem::temp_directory_path() / "Zisla Task";
    const auto arguments = YTDLPArgumentBuilder::arguments(
        request,
        {.has_ffmpeg = true},
        temporary,
        std::filesystem::path{"C:/Tools/ffmpeg.exe"});

    expect(YTDLPArgumentBuilder::strategy(request, {.has_ffmpeg = true})
            == DownloadExecutionStrategy::direct,
        "video downloads with FFmpeg should finish directly");
    expect(has_adjacent_arguments(arguments, "--ignore-config", "--no-plugin-dirs"),
        "user configuration and plugin loading must be disabled");
    expect(std::find(arguments.begin(), arguments.end(), "--no-exec")
            != arguments.end(),
        "yt-dlp exec hooks must be disabled");
    expect(has_adjacent_arguments(arguments, "--merge-output-format", "mp4"),
        "video output should be merged as MP4 when FFmpeg is available");
    expect(arguments.size() >= 2
            && arguments[arguments.size() - 2] == "--"
            && arguments.back() == request.url,
        "the unmodified URL must be the final argv value after --");
}

void choosesNativePackagingWithoutFFmpeg() {
    const DownloadRequest video{
        .url = "https://youtu.be/example",
        .mode = DownloadMode::video,
        .output_directory = std::filesystem::temp_directory_path(),
    };
    expect(YTDLPArgumentBuilder::strategy(video, {.has_ffmpeg = false})
            == DownloadExecutionStrategy::native_packaging,
        "video without FFmpeg should use native packaging");
    const auto video_arguments = YTDLPArgumentBuilder::arguments(
        video,
        {.has_ffmpeg = false},
        std::filesystem::temp_directory_path() / "task");
    expect(std::any_of(video_arguments.begin(), video_arguments.end(), [](const auto& value) {
            return value.find("\"event\":\"component\"") != std::string::npos;
        }),
        "native packaging should request component events");

    auto audio = video;
    audio.mode = DownloadMode::audio;
    expect(YTDLPArgumentBuilder::strategy(audio, {.has_ffmpeg = false})
            == DownloadExecutionStrategy::direct,
        "M4A audio can finish directly without FFmpeg");
}

void parsesStructuredYTDLPEvents() {
    const auto progress = YTDLPOutputParser::parse(
        "__ZISLA_YTDLP_JSON__{\"event\":\"progress\",\"percent\":\" 52.5%\",\"speed\":\"2 MiB/s\",\"eta\":\"00:12\"}");
    expect(progress
            && progress->kind == YTDLPEventKind::progress
            && progress->fraction == 0.525
            && progress->speed == "2 MiB/s"
            && progress->eta == "00:12",
        "progress events should parse and normalize percentages");

    const auto completed = YTDLPOutputParser::parse(
        "__ZISLA_YTDLP_JSON__{\"event\":\"completed\",\"filepath\":\"/tmp/video.mp4\"}");
    expect(completed
            && completed->kind == YTDLPEventKind::completed_file
            && completed->path.filename() == "video.mp4",
        "completed file events should retain their path");

    const auto component = YTDLPOutputParser::parse(
        "__ZISLA_YTDLP_JSON__{\"event\":\"component\",\"filepath\":\"/tmp/video.137.mp4\",\"format_id\":\"137\",\"vcodec\":\"avc1\",\"acodec\":\"none\"}");
    expect(component
            && component->kind == YTDLPEventKind::completed_component
            && component->component
            && component->component->kind == DownloadedMediaKind::video,
        "component events should classify their media tracks");
    expect(!YTDLPOutputParser::parse("normal yt-dlp output"),
        "unstructured process output must not mutate download state");
    expect(!YTDLPOutputParser::parse(
               "__ZISLA_YTDLP_JSON__{not-json}"),
        "malformed structured output must be ignored");
}

void protectsAndBuildsOutputPaths() {
    TestDirectory temporary;
    const auto output = temporary.path() / "Downloads";
    const auto outside = temporary.path() / "Outside";
    std::filesystem::create_directories(output);
    std::filesystem::create_directories(outside);
    const auto inside_file = output / "video.mp4";
    const auto outside_file = outside / "video.mp4";
    std::ofstream(inside_file).put('x');
    std::ofstream(outside_file).put('x');

    expect(DownloadOutputPathValidator::normalized_file(inside_file, output)
            .has_value(),
        "an existing file inside the output directory should be accepted");
    expect(!DownloadOutputPathValidator::normalized_file(outside_file, output),
        "a sibling file must not escape the output directory");
    expect(!DownloadOutputPathValidator::normalized_file(output, output),
        "the output directory itself is not a completed file");
    const auto nested_directory = output / "folder";
    std::filesystem::create_directories(nested_directory);
    expect(!DownloadOutputPathValidator::normalized_file(nested_directory, output),
        "a directory inside the output directory is not a completed file");
    expect(!DownloadOutputPathValidator::normalized_file(
               output / "missing.mp4",
               output),
        "a missing output path is not a completed file");

    const DownloadedMediaComponent component{
        .path = temporary.path() / "Sample [id].137.mp4",
        .format_id = "137",
        .kind = DownloadedMediaKind::video,
    };
    expect(DownloadOutputPathBuilder::destination(component, output, "mp4")
            == output / "Sample [id].mp4",
        "native packaging should remove the format-id suffix");

    const auto desired = output / "Sample [id].mp4";
    std::ofstream(desired).put('x');
    std::ofstream(output / "Sample [id] (1).mp4").put('x');
    expect(DownloadOutputPathBuilder::available_destination(desired)
            == output / "Sample [id] (2).mp4",
        "a completed file must choose the first available numbered name");
}

void explainsBilibiliFallbackConditions() {
    expect(DownloadFailureDiagnostics::is_bilibili_url(
               "https://www.bilibili.com/video/BV1xx"),
        "Bilibili subdomains should be recognized");
    expect(DownloadFailureDiagnostics::should_use_bilibili_fallback(
               "ERROR: HTTP Error 412: Precondition Failed",
               "https://b23.tv/example"),
        "Bilibili HTTP 412 should request the native fallback");
    expect(!DownloadFailureDiagnostics::should_use_bilibili_fallback(
               "HTTP Error 412",
               "https://youtube.com/watch?v=x"),
        "HTTP 412 on another host must not use the Bilibili fallback");
    expect(DownloadFailureDiagnostics::actionable_message(
               "HTTP Error 412",
               "https://bilibili.com/video/x").find("风控") != std::string::npos,
        "Bilibili HTTP 412 should produce an actionable Chinese message");
}

void plansBilibiliNativeDownloads() {
    const auto bvid = BilibiliDownloadPlanner::extract_bvid(
        "https://www.bilibili.com/video/BV1d2N16KEh6?p=1");
    expect(bvid && *bvid == "BV1d2N16KEh6",
        "a direct Bilibili video URL should expose its BV identifier");
    expect(!BilibiliDownloadPlanner::extract_bvid(
               "https://example.com/video/BV1d2N16KEh6"),
        "a BV-looking path on another host must be rejected");

    const auto view = BilibiliDownloadPlanner::parse_view_response(
        *bvid,
        R"({"code":0,"data":{"title":"Sample: Video","cid":123456}})");
    expect(view.bvid == *bvid && view.title == "Sample: Video"
            && view.cid == 123456,
        "the view response should retain the title, cid, and requested BV identifier");

    const auto selection = BilibiliDownloadPlanner::parse_play_response(R"({
        "code": 0,
        "data": {
            "dash": {
                "video": [
                    {
                        "id": 120,
                        "baseUrl": "https://cdn.example/hevc.mp4",
                        "bandwidth": 6000000,
                        "codecs": "hev1.1.6.L120",
                        "mimeType": "video/mp4",
                        "width": 3840,
                        "height": 2160
                    },
                    {
                        "id": 80,
                        "base_url": "http://insecure.example/avc.mp4",
                        "backup_url": [
                            "https://cdn.example/avc.mp4",
                            "https://cdn.example/avc.mp4"
                        ],
                        "bandwidth": 3000000,
                        "codecs": "avc1.640028",
                        "mimeType": "video/mp4",
                        "width": 1920,
                        "height": 1080
                    }
                ],
                "audio": [
                    {
                        "id": 30216,
                        "baseUrl": "https://cdn.example/audio-low.m4a",
                        "bandwidth": 64000,
                        "codecs": "mp4a.40.2",
                        "mimeType": "audio/mp4"
                    },
                    {
                        "id": 30280,
                        "baseUrl": "https://cdn.example/audio-high.m4a",
                        "bandwidth": 192000,
                        "codecs": "mp4a.40.2",
                        "mimeType": "audio/mp4"
                    }
                ]
            }
        }
    })");
    expect(selection.video.id == 80
            && selection.video.urls
                == std::vector<std::string>{"https://cdn.example/avc.mp4"},
        "native packaging should prefer AVC MP4 and retain unique HTTPS URLs");
    expect(selection.audio.id == 30280
            && selection.audio.urls.front()
                == "https://cdn.example/audio-high.m4a",
        "native packaging should select the highest-bandwidth downloadable audio track");
}

void rejectsInvalidBilibiliResponses() {
    bool api_error = false;
    try {
        (void)BilibiliDownloadPlanner::parse_view_response(
            "BV1d2N16KEh6",
            R"({"code":-404,"message":"not found"})");
    } catch (const BilibiliResponseError& error) {
        api_error = std::string_view{error.what()}.find("not found")
            != std::string_view::npos;
    }
    expect(api_error,
        "Bilibili API failures should preserve the server's actionable message");

    bool missing_tracks = false;
    try {
        (void)BilibiliDownloadPlanner::parse_play_response(
            R"({"code":0,"data":{"dash":{"video":[],"audio":[]}}})");
    } catch (const BilibiliResponseError& error) {
        missing_tracks = std::string_view{error.what()}.find("DASH")
            != std::string_view::npos;
    }
    expect(missing_tracks,
        "a response without downloadable DASH tracks should explain the missing capability");
}

void downloadStateRejectsOverlapAndTracksCancellation() {
    DownloadState state;
    const DownloadRequest request{
        .url = "https://youtu.be/example",
        .mode = DownloadMode::video,
        .output_directory = std::filesystem::temp_directory_path(),
    };
    expect(state.begin(request), "the first download should begin");
    expect(!state.begin(request), "a second download must not overlap");
    state.update_progress(1.5, "3 MiB/s", "00:01");
    expect(state.snapshot().phase == DownloadPhase::downloading
            && state.snapshot().fraction == 1.0,
        "progress should be clamped and transition to downloading");
    expect(state.request_cancel(), "an active download should accept cancellation");
    expect(!state.request_cancel(), "cancellation should be idempotent");
    state.complete(std::filesystem::temp_directory_path() / "late.mp4");
    expect(state.snapshot().phase == DownloadPhase::cancelling,
        "a late completion must not override cancellation");
    state.fail("late failure");
    expect(state.snapshot().phase == DownloadPhase::cancelling,
        "a late failure must not override cancellation");
    state.cancel();
    expect(state.snapshot().phase == DownloadPhase::cancelled
            && !state.snapshot().active(),
        "process termination should settle as cancelled");
}

void quotesWindowsArgumentsForCreateProcess() {
    expect(WindowsCommandLine::quote_argument(L"plain") == L"plain",
        "plain arguments should not gain quotes");
    expect(WindowsCommandLine::quote_argument(L"two words") == L"\"two words\"",
        "arguments with spaces should be quoted");
    expect(WindowsCommandLine::quote_argument(L"a\"b") == L"\"a\\\"b\"",
        "embedded quotes must be escaped for CommandLineToArgvW semantics");
    expect(WindowsCommandLine::quote_argument(L"C:\\Program Files\\")
            == L"\"C:\\Program Files\\\\\"",
        "trailing backslashes in quoted arguments must be doubled");

    const std::vector<std::wstring> arguments{
        L"C:\\Program Files\\yt-dlp.exe",
        L"--",
        L"https://example.com/watch?v=a&b=c",
    };
    expect(WindowsCommandLine::build(arguments)
            == L"\"C:\\Program Files\\yt-dlp.exe\" -- https://example.com/watch?v=a&b=c",
        "CreateProcess command lines should preserve each argv boundary");
}

void boundsAndFramesProcessOutput() {
    DownloadProcessOutputBuffer output;
    expect(output.append("first").empty(),
        "an incomplete process line should stay buffered");
    const auto completed = output.append(" line\r\nsecond\n");
    expect(completed == std::vector<std::string>{"first line", "second"},
        "process output should frame lines across chunks and remove CRLF");

    std::string oversized(
        DownloadProcessOutputBuffer::maximum_line_bytes + 1,
        'x');
    oversized.append("\nrecovered\n");
    const auto recovered = output.append(oversized);
    expect(recovered == std::vector<std::string>{"recovered"},
        "an oversized line should be discarded without losing the next line");

    std::string diagnostic(
        DownloadProcessOutputBuffer::maximum_diagnostic_bytes + 64,
        'd');
    (void)output.append(diagnostic);
    expect(output.diagnostic().size()
            == DownloadProcessOutputBuffer::maximum_diagnostic_bytes,
        "diagnostic output should retain only its bounded tail");
    const auto final_line = output.finish();
    expect(!final_line,
        "an oversized unterminated line should remain discarded at EOF");
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string_view, std::function<void()>>> tests{
        {"request validation", validatesAndNormalizesDownloadRequests},
        {"hardened yt-dlp arguments", buildsHardenedYTDLPArguments},
        {"native packaging strategy", choosesNativePackagingWithoutFFmpeg},
        {"structured output parser", parsesStructuredYTDLPEvents},
        {"output path protection", protectsAndBuildsOutputPaths},
        {"Bilibili diagnostics", explainsBilibiliFallbackConditions},
        {"Bilibili native plan", plansBilibiliNativeDownloads},
        {"Bilibili response errors", rejectsInvalidBilibiliResponses},
        {"download state", downloadStateRejectsOverlapAndTracksCancellation},
        {"Windows command line quoting", quotesWindowsArgumentsForCreateProcess},
        {"bounded process output", boundsAndFramesProcessOutput},
    };

    int failures = 0;
    for (const auto& [name, test] : tests) {
        try {
            test();
            std::cout << "PASS: " << name << '\n';
        } catch (const std::exception& error) {
            ++failures;
            std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
        }
    }
    return failures == 0 ? 0 : 1;
}
