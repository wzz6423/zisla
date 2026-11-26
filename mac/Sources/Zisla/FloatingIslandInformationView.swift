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
    let countdowns: [Status]
    let countdownLength: CGFloat
    let primaryThickness: CGFloat
    let statusThickness: CGFloat
    let primaryLength: CGFloat
    let size: CGSize
    var rowCount: Int { (primaryLength > 0 ? 1 : 0) + countdowns.count + (secondary == nil ? 0 : 1) }

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
        let countdownPresentations = presentations.filter { $0.priority == .focusCountdown }
        guard !icons.isEmpty || !presentations.isEmpty else { return nil }
        let edge = settings.islandPlacement.edge
        let iconSize = IslandStatusIconLayout.size(icons: icons, edge: edge)
        let thickness = max(CompactPillStatusPresentation.minimumThickness,
                            edge.isVertical ? iconSize?.width ?? 0 : iconSize?.height ?? 0)
        let statusThickness = edge.isVertical ? CompactPillStatusPresentation.minimumThickness : thickness
        let media = presentations.first { $0.isMedia && settings.mediaCompactStyle == .detailed }
        var primary = presentations.filter { $0.priority == .aiActivity }
            + presentations.filter { $0.priority != .aiActivity && $0.priority != .focusCountdown && $0 != media }
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
            status(presentation, thickness: statusThickness,
                   leadingInset: icons.isEmpty && index == 0 ? CompactPillStatusPresentation.trailingInset : 0)
        }
        let secondaryStatus = secondary.map { status($0, thickness: CompactPillStatusPresentation.minimumThickness) }
        let countdowns = countdownPresentations.map { presentation in
            let name = presentation.notice.metadata?["timerName"] ?? ""
            let text = [name, presentation.text].filter { !$0.isEmpty }.joined(separator: " ")
            let textLength = presentation.countdownTextLength(thickness: CompactPillStatusPresentation.minimumThickness, edge: edge)
            return Status(presentation: presentation, text: text,
                          length: textLength + CompactPillStatusPresentation.pomodoroControlsLength + 6
                              + CompactPillStatusPresentation.trailingInset * 2,
                          leadingInset: CompactPillStatusPresentation.trailingInset)
        }
        let countdownLength = countdowns.map(\.length).max() ?? 0
        let countdownThickness = CGFloat(countdowns.count) * CompactPillStatusPresentation.minimumThickness
        let iconLength = edge.isVertical ? iconSize?.height ?? 0 : iconSize?.width ?? 0
        let primaryLength = primaryStatuses.reduce(iconLength) { $0 + $1.length }
        let length = min(ScreenLayoutConfiguration.quickActionRowWidth, max(primaryLength, countdownLength, secondaryStatus?.length ?? 0))
        let primaryThickness = primaryLength > 0 ? thickness : 0
        let totalThickness = primaryThickness + countdownThickness
            + (secondaryStatus == nil ? 0 : CompactPillStatusPresentation.minimumThickness)
        self.edge = edge
        self.icons = icons
        self.iconSize = iconSize
        self.primary = primaryStatuses
        self.secondary = secondaryStatus
        self.countdowns = countdowns
        self.countdownLength = countdownLength
        self.primaryThickness = primaryThickness
        self.statusThickness = statusThickness
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
    var animatesLogo = false
    var onJoinMeeting: (String) -> Void = { _ in }

    var body: some View {
        GeometryReader { geometry in
            let length = layout.edge.isVertical ? geometry.size.height : geometry.size.width
            let rows = layout.edge.isVertical
                ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            rows {
                if layout.primaryLength > 0 {
                    primaryRow
                        .scaleEffect(x: layout.edge.isVertical ? 1 : min(1, length / layout.primaryLength),
                                     y: layout.edge.isVertical ? min(1, length / layout.primaryLength) : 1)
                        .frame(width: layout.edge.isVertical ? layout.primaryThickness : min(length, layout.primaryLength),
                               height: layout.edge.isVertical ? min(length, layout.primaryLength) : layout.primaryThickness)
                        .frame(width: layout.edge.isVertical ? layout.primaryThickness : length,
                               height: layout.edge.isVertical ? length : layout.primaryThickness,
                               alignment: layout.edge.isVertical ? .top : .leading)
                }
                ForEach(layout.countdowns) { status in
                    FloatingCountdownRow(status: status, edge: layout.edge)
                        .frame(width: layout.edge.isVertical ? CompactPillStatusPresentation.minimumThickness : length,
                               height: layout.edge.isVertical ? length : CompactPillStatusPresentation.minimumThickness)
                }
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
                IslandStatusIconStrip(icons: layout.icons, edge: layout.edge, date: date, animatesLogo: animatesLogo)
                    .frame(width: size.width, height: size.height)
            }
            ForEach(layout.primary) { status in
                CompactPillStatusContent(presentation: status.presentation, text: status.text, edge: layout.edge,
                                         visualizationStyle: visualizationStyle, item: status.presentation.isMedia ? item : nil,
                                         date: date, leadingInset: status.leadingInset,
                                         controlRegionThickness: layout.primaryThickness, onJoinMeeting: onJoinMeeting)
                    .frame(width: layout.edge.isVertical ? layout.statusThickness : status.length,
                           height: layout.edge.isVertical ? status.length : layout.statusThickness)
            }
        }
        .frame(width: layout.edge.isVertical ? layout.primaryThickness : layout.primaryLength,
               height: layout.edge.isVertical ? layout.primaryLength : layout.primaryThickness)
    }

}

private struct FloatingCountdownRow: View {
    let status: FloatingIslandInformationLayout.Status
    let edge: IslandEdge

    var body: some View {
        GeometryReader { geometry in
            let thickness = CompactPillStatusPresentation.minimumThickness
            let textLength = (edge.isVertical ? geometry.size.height : geometry.size.width)
                - CompactPillStatusPresentation.trailingInset * 2 - CompactPillStatusPresentation.pomodoroControlsLength - 6
            let row = edge.isVertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
            row {
                CompactCountdownText(name: status.presentation.notice.metadata?["timerName"] ?? "",
                                     clock: status.presentation.text, edge: edge,
                                     length: textLength, thickness: thickness)
                CompactPomodoroControls(edge: edge, notice: status.presentation.notice)
                    .frame(width: edge.isVertical ? thickness : CompactPillStatusPresentation.pomodoroControlsLength,
                           height: edge.isVertical ? CompactPillStatusPresentation.pomodoroControlsLength : thickness)
            }
            .padding(edge.isVertical ? .vertical : .horizontal, CompactPillStatusPresentation.trailingInset)
        }
        .foregroundStyle(.white)
        .environment(\.layoutDirection, .leftToRight)
        .background { CompactPomodoroControlRegion() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(status.presentation.notice.title) \(status.presentation.text)")
        .accessibilityIdentifier("countdown.row.\(status.presentation.notice.metadata?["timerKey"] ?? status.id)")
        .help("\(status.presentation.notice.title) \(status.presentation.text)")
    }
}
