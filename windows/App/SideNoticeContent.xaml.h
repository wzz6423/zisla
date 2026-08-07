#pragma once

#include "SideNoticeContent.g.h"

#include <zisla/core/SideNoticeQueue.hpp>

namespace winrt::Zisla::implementation {

struct SideNoticeContent : SideNoticeContentT<SideNoticeContent> {
    SideNoticeContent();

    void setOpaqueSurface(bool opaque);

    void setState(
        zisla::core::NoticeSide side,
        const zisla::core::SideNoticeViewState& state);

private:
    [[nodiscard]] Microsoft::UI::Xaml::Controls::Grid makeRow(
        const zisla::core::IslandNotice& notice,
        std::size_t compact_count);
};

}

namespace winrt::Zisla::factory_implementation {

struct SideNoticeContent : SideNoticeContentT<
    SideNoticeContent,
    implementation::SideNoticeContent> {};

}
