import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

@MainActor
struct FloatingIslandInformationLayout {
    struct Status: Identifiable {
        let presentation: CompactPillStatusPresentation
        let text: String
        let length: CGFloat
        let leadingInset: CGFloat
        var id: String { presentation.notice.id }
    }

    let edge: IslandEdge
    let icons: [IslandStatusIcon]
    let iconSize: CGSize?
    let primary: [Status]
    let secondary: Status?
    let primaryThickness: CGFloat
    let primaryLength: CGFloat
    let size: CGSize

    init?(notices: [IslandNotice], icons: [IslandStatusIcon], settings: FeatureSettings,
          item: NowPlayingSnapshot?, at date: Date) {
        guard settings.supportsStatusIconsInIsland, settings.islandShowMoreInformation else { return nil }
        let notices = settings.sideNoticesEnabled ? notices : []
        guard !notices.contains(where: {
            $0.id.hasPrefix("voice-processing-") || $0.id.hasPrefix("screen-recording-operation-")
        }) else { return nil }
        let icons = settings.effectiveStatusIconDestination == .island
            ? icons.filter { !$0.isSystemMonitor || settings.systemMonitorEnabled } : []
        let presentations = SideNoticeLayoutEngine().compactPillPresentations(for: notices, settings: settings)
        guard !icons.isEmpty || !presentations.isEmpty else { return nil }
        let edge = settings.islandPlacement.edge
        let iconSize = IslandStatusIconLayout.size(icons: icons, edge: edge)
        let thickness = max(CompactPillStatusPresentation.minimumThickness,
                            edge.isVertical ? iconSize?.width ?? 0 : iconSize?.height ?? 0)
        let media = presentations.first { $0.isMedia && settings.mediaCompactStyle == .detailed }
        var primary = presentations.filter { $0.priority == .aiActivity }
            + presentations.filter { $0.priority != .aiActivity && $0 != media }
        var secondary = media
        if primary.isEmpty && icons.isEmpty, let media {
            primary = [media]
            secondary = nil
        }
        func status(_ presentation: CompactPillStatusPresentation, thickness: CGFloat,
                    leadingInset: CGFloat = CompactPillStatusPresentation.trailingInset) -> Status {
            let text = CompactPillStatusContent.displayText(for: presentation, settings: settings, item: item, at: date)
            return Status(presentation: presentation, text: text,
                length: presentation.length(thickness: thickness, edge: edge, text: text, item: item,
                    leadingInset: leadingInset), leadingInset: leadingInset)
        }
        let primaryStatuses = primary.enumerated().map { index, presentation in
            status(presentation, thickness: thickness,
                leadingInset: icons.isEmpty && index == 0 ? CompactPillStatusPresentation.trailingInset : 0)
        }
        let secondaryStatus = secondary.map { status($0, thickness: CompactPillStatusPresentation.minimumThickness) }
        let iconLength = edge.isVertical ? iconSize?.height ?? 0 : iconSize?.width ?? 0
        let primaryLength = primaryStatuses.reduce(iconLength) { $0 + $1.length }
        let length = min(ScreenLayoutConfiguration.quickActionRowWidth, max(primaryLength, secondaryStatus?.length ?? 0))
        let totalThickness = thickness + (secondaryStatus == nil ? 0 : CompactPillStatusPresentation.minimumThickness)
        self.edge = edge
        self.icons = icons
        self.iconSize = iconSize
        self.primary = primaryStatuses
        self.secondary = secondaryStatus
        self.primaryThickness = thickness
        self.primaryLength = primaryLength
        self.size = edge.isVertical ? CGSize(width: totalThickness, height: length)
            : CGSize(width: length, height: totalThickness)
    }
}

struct FloatingIslandInformationView: View {
    let layout: FloatingIslandInformationLayout
    let visualizationStyle: MediaVisualizationStyle
    let item: NowPlayingSnapshot?
    let date: Date

    var body: some View {
        GeometryReader { geometry in
            let length = layout.edge.isVertical ? geometry.size.height : geometry.size.width
            let rows = layout.edge.isVertical
                ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            rows {
                primaryRow
                    .scaleEffect(x: layout.edge.isVertical ? 1 : min(1, length / layout.primaryLength),
                                 y: layout.edge.isVertical ? min(1, length / layout.primaryLength) : 1)
                    .frame(width: layout.edge.isVertical ? layout.primaryThickness : min(length, layout.primaryLength),
                           height: layout.edge.isVertical ? min(length, layout.primaryLength) : layout.primaryThickness)
                    .frame(width: layout.edge.isVertical ? layout.primaryThickness : length,
                           height: layout.edge.isVertical ? length : layout.primaryThickness,
                           alignment: layout.edge.isVertical ? .top : .leading)
                if let secondary = layout.secondary {
                    CompactPillStatusContent(presentation: secondary.presentation, text: secondary.text,
                        edge: layout.edge, visualizationStyle: visualizationStyle, item: item, date: date)
                        .frame(width: layout.edge.isVertical ? CompactPillStatusPresentation.minimumThickness : min(length, secondary.length),
                               height: layout.edge.isVertical ? min(length, secondary.length) : CompactPillStatusPresentation.minimumThickness)
                        .frame(width: layout.edge.isVertical ? CompactPillStatusPresentation.minimumThickness : length,
                               height: layout.edge.isVertical ? length : CompactPillStatusPresentation.minimumThickness,
                               alignment: layout.edge.isVertical ? .top : .leading)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var primaryRow: some View {
        let row = layout.edge.isVertical
            ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return row {
            if let size = layout.iconSize {
                IslandStatusIconStrip(icons: layout.icons, edge: layout.edge, date: date)
                    .frame(width: size.width, height: size.height)
            }
            ForEach(layout.primary) { status in
                CompactPillStatusContent(presentation: status.presentation, text: status.text, edge: layout.edge,
                    visualizationStyle: visualizationStyle, item: status.presentation.isMedia ? item : nil,
                    date: date, leadingInset: status.leadingInset)
                    .frame(width: layout.edge.isVertical ? layout.primaryThickness : status.length,
                           height: layout.edge.isVertical ? status.length : layout.primaryThickness)
            }
        }
        .frame(width: layout.edge.isVertical ? layout.primaryThickness : layout.primaryLength,
               height: layout.edge.isVertical ? layout.primaryLength : layout.primaryThickness)
    }
}
