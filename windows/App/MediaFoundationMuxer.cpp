#include "pch.h"
#include "MediaFoundationMuxer.h"

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string_view>
#include <utility>

namespace winrt::Zisla {
namespace {

using ::Microsoft::WRL::ComPtr;

class MediaFoundationRuntime {
public:
    MediaFoundationRuntime() {
        const auto com_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        if (FAILED(com_result)) {
            throw std::runtime_error("无法初始化媒体封装 COM 线程");
        }
        com_initialized_ = true;
        const auto media_result = MFStartup(MF_VERSION, MFSTARTUP_FULL);
        if (FAILED(media_result)) {
            CoUninitialize();
            com_initialized_ = false;
            throw std::runtime_error("无法启动 Windows Media Foundation");
        }
        media_foundation_started_ = true;
    }

    ~MediaFoundationRuntime() {
        if (media_foundation_started_) {
            (void)MFShutdown();
        }
        if (com_initialized_) {
            CoUninitialize();
        }
    }

    MediaFoundationRuntime(const MediaFoundationRuntime&) = delete;
    MediaFoundationRuntime& operator=(const MediaFoundationRuntime&) = delete;

private:
    bool com_initialized_{false};
    bool media_foundation_started_{false};
};

[[noreturn]] void throw_media_error(
    std::string_view operation,
    HRESULT result) {
    std::ostringstream message;
    message << operation << "（HRESULT 0x" << std::hex << std::uppercase
            << static_cast<std::uint32_t>(result) << '）';
    throw std::runtime_error(message.str());
}

void check_media(HRESULT result, std::string_view operation) {
    if (FAILED(result)) {
        throw_media_error(operation, result);
    }
}

struct SourceTrack {
    ComPtr<IMFSourceReader> reader;
    ComPtr<IMFMediaType> media_type;
    ComPtr<IMFSample> sample;
    DWORD source_stream{0};
    DWORD sink_stream{0};
    DWORD flags{0};
    LONGLONG timestamp{0};
    LONGLONG duration{0};
    bool end_of_stream{false};
};

LONGLONG source_duration(IMFSourceReader* reader) noexcept {
    PROPVARIANT value{};
    PropVariantInit(&value);
    const auto result = reader->GetPresentationAttribute(
        static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE),
        MF_PD_DURATION,
        &value);
    LONGLONG duration = 0;
    if (SUCCEEDED(result)) {
        if (value.vt == VT_UI8) {
            duration = value.uhVal.QuadPart
                    > static_cast<ULONGLONG>(std::numeric_limits<LONGLONG>::max())
                ? std::numeric_limits<LONGLONG>::max()
                : static_cast<LONGLONG>(value.uhVal.QuadPart);
        } else if (value.vt == VT_I8 && value.hVal.QuadPart > 0) {
            duration = value.hVal.QuadPart;
        }
    }
    (void)PropVariantClear(&value);
    return duration;
}

SourceTrack open_source_track(
    const std::filesystem::path& path,
    DWORD stream,
    const GUID& expected_major_type) {
    ComPtr<IMFAttributes> attributes;
    check_media(
        MFCreateAttributes(&attributes, 2),
        "无法创建媒体读取属性");
    check_media(
        attributes->SetUINT32(MF_READWRITE_DISABLE_CONVERTERS, TRUE),
        "无法禁用媒体读取转换器");

    SourceTrack track;
    track.source_stream = stream;
    check_media(
        MFCreateSourceReaderFromURL(
            path.c_str(),
            attributes.Get(),
            &track.reader),
        "无法打开下载媒体轨道");
    check_media(
        track.reader->SetStreamSelection(
            static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS),
            FALSE),
        "无法清除媒体轨道选择");
    check_media(
        track.reader->SetStreamSelection(stream, TRUE),
        "下载文件缺少所需媒体轨道");
    check_media(
        track.reader->GetNativeMediaType(stream, 0, &track.media_type),
        "无法读取媒体轨道格式");
    GUID major_type{};
    check_media(
        track.media_type->GetGUID(MF_MT_MAJOR_TYPE, &major_type),
        "媒体轨道缺少类型信息");
    if (major_type != expected_major_type) {
        throw std::runtime_error("下载文件的媒体轨道类型不匹配");
    }
    track.duration = source_duration(track.reader.Get());
    return track;
}

void ensure_supported_video_type(IMFMediaType* type) {
    GUID subtype{};
    check_media(
        type->GetGUID(MF_MT_SUBTYPE, &subtype),
        "视频轨缺少编码信息");
    if (subtype != MFVideoFormat_H264 && subtype != MFVideoFormat_H264_ES) {
        throw std::runtime_error("Windows 原生封装当前只支持 H.264/AVC 视频轨");
    }
}

void ensure_supported_audio_type(IMFMediaType* type) {
    GUID subtype{};
    check_media(
        type->GetGUID(MF_MT_SUBTYPE, &subtype),
        "音频轨缺少编码信息");
    if (subtype != MFAudioFormat_AAC) {
        throw std::runtime_error("Windows 原生封装当前只支持 AAC 音频轨");
    }
}

void read_next(SourceTrack& track, IMFSinkWriter* writer) {
    track.sample.Reset();
    while (!track.sample.Get() && !track.end_of_stream) {
        track.flags = 0;
        track.timestamp = 0;
        check_media(
            track.reader->ReadSample(
                track.source_stream,
                0,
                nullptr,
                &track.flags,
                &track.timestamp,
                &track.sample),
            "无法读取媒体压缩采样");
        if ((track.flags & (MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED
                | MF_SOURCE_READERF_NATIVEMEDIATYPECHANGED)) != 0) {
            throw std::runtime_error("媒体轨道在封装过程中改变了编码格式");
        }
        if ((track.flags & MF_SOURCE_READERF_STREAMTICK) != 0) {
            check_media(
                writer->SendStreamTick(track.sink_stream, track.timestamp),
                "无法写入媒体时间间隙");
        }
        if ((track.flags & MF_SOURCE_READERF_ENDOFSTREAM) != 0) {
            track.end_of_stream = true;
        }
    }
}

void mux_impl(
    const std::filesystem::path& video_path,
    const std::filesystem::path& audio_path,
    const std::filesystem::path& output_path,
    const MediaFoundationMuxer::CancellationCheck& cancellation_check) {
    MediaFoundationRuntime runtime;
    auto video = open_source_track(
        video_path,
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM),
        MFMediaType_Video);
    auto audio = open_source_track(
        audio_path,
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
        MFMediaType_Audio);
    ensure_supported_video_type(video.media_type.Get());
    ensure_supported_audio_type(audio.media_type.Get());

    ComPtr<IMFAttributes> writer_attributes;
    check_media(
        MFCreateAttributes(&writer_attributes, 3),
        "无法创建媒体写入属性");
    check_media(
        writer_attributes->SetUINT32(MF_READWRITE_DISABLE_CONVERTERS, TRUE),
        "无法禁用媒体写入转换器");
    check_media(
        writer_attributes->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, TRUE),
        "无法禁用媒体写入节流");
    check_media(
        writer_attributes->SetGUID(
            MF_TRANSCODE_CONTAINERTYPE,
            MFTranscodeContainerType_MPEG4),
        "无法指定 MP4 封装格式");

    ComPtr<IMFSinkWriter> writer;
    check_media(
        MFCreateSinkWriterFromURL(
            output_path.c_str(),
            nullptr,
            writer_attributes.Get(),
            &writer),
        "无法创建 MP4 输出文件");
    check_media(
        writer->AddStream(video.media_type.Get(), &video.sink_stream),
        "Windows MP4 封装器不接受当前视频轨");
    check_media(
        writer->AddStream(audio.media_type.Get(), &audio.sink_stream),
        "Windows MP4 封装器不接受当前音频轨");
    check_media(
        writer->SetInputMediaType(
            video.sink_stream,
            video.media_type.Get(),
            nullptr),
        "无法配置 MP4 视频输入轨");
    check_media(
        writer->SetInputMediaType(
            audio.sink_stream,
            audio.media_type.Get(),
            nullptr),
        "无法配置 MP4 音频输入轨");
    check_media(writer->BeginWriting(), "无法开始 MP4 原样封装");

    read_next(video, writer.Get());
    read_next(audio, writer.Get());
    if (!video.sample.Get() || !audio.sample.Get()) {
        throw std::runtime_error("下载组件中缺少可封装的视频轨或音频轨");
    }
    LONGLONG video_end = video.duration;
    while (!video.end_of_stream || !audio.end_of_stream
        || video.sample.Get() || audio.sample.Get()) {
        if (cancellation_check && cancellation_check()) {
            throw std::runtime_error("媒体封装已取消");
        }
        if (audio.sample.Get() && video_end > 0 && audio.timestamp >= video_end) {
            audio.sample.Reset();
            audio.end_of_stream = true;
        }

        SourceTrack* next = nullptr;
        if (video.sample.Get() && audio.sample.Get()) {
            next = video.timestamp <= audio.timestamp ? &video : &audio;
        } else if (video.sample.Get()) {
            next = &video;
        } else if (audio.sample.Get()) {
            next = &audio;
        } else {
            break;
        }

        check_media(
            writer->WriteSample(next->sink_stream, next->sample.Get()),
            "无法写入 MP4 压缩采样");
        if (next == &video && video.duration <= 0) {
            LONGLONG sample_duration = 0;
            if (SUCCEEDED(video.sample->GetSampleDuration(&sample_duration))) {
                video_end = std::max(
                    video_end,
                    video.timestamp + std::max<LONGLONG>(0, sample_duration));
            }
        }
        read_next(*next, writer.Get());
    }

    check_media(writer->Finalize(), "无法完成 MP4 原样封装");
}

}  // namespace

MediaFoundationMuxer::MediaFoundationMuxer(
    CancellationCheck cancellation_check)
    : cancellation_check_(std::move(cancellation_check)) {}

void MediaFoundationMuxer::mux(
    const std::filesystem::path& video,
    const std::filesystem::path& audio,
    const std::filesystem::path& output) const {
    if (video.empty() || audio.empty() || output.empty()
        || !video.is_absolute() || !audio.is_absolute() || !output.is_absolute()) {
        throw std::runtime_error("媒体封装路径无效");
    }
    std::error_code error;
    if (!std::filesystem::is_regular_file(video, error) || error
        || !std::filesystem::is_regular_file(audio, error) || error
        || std::filesystem::exists(output, error) || error) {
        throw std::runtime_error("媒体封装输入不存在或输出已被占用");
    }
    if (cancellation_requested()) {
        throw std::runtime_error("媒体封装已取消");
    }

    try {
        mux_impl(video, audio, output, cancellation_check_);
    } catch (...) {
        std::error_code ignored;
        std::filesystem::remove(output, ignored);
        throw;
    }
    if (cancellation_requested()) {
        std::error_code ignored;
        std::filesystem::remove(output, ignored);
        throw std::runtime_error("媒体封装已取消");
    }
}

bool MediaFoundationMuxer::cancellation_requested() const noexcept {
    try {
        return cancellation_check_ && cancellation_check_();
    } catch (...) {
        return true;
    }
}

}
