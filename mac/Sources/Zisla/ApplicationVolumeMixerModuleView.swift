import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct ApplicationVolumeMixerModuleView: View {
    @ObservedObject var service: ApplicationVolumeMixerService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                AppLocalizedText("应用音量混音器")
                    .font(.system(size: 15, weight: .semibold))
                AppLocalizedText("分别调整正在播放声音的应用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !service.isSupported {
                ContentUnavailableView {
                    Label(AppLocalization.text("应用音量混音器"), systemImage: "speaker.slash")
                } description: {
                    AppLocalizedText("应用音量需要 macOS 14.4 或更高版本")
                }
            } else {
                if let errorMessage = service.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.zislaWarning)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .islandGlassSurface(.card, cornerRadius: 10)
                }

                if service.applications.isEmpty {
                    ContentUnavailableView {
                        Label(AppLocalization.text("暂无正在播放声音的应用"), systemImage: "speaker.wave.2")
                    } description: {
                        AppLocalizedText("播放音乐或视频后，应用会显示在这里。")
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(service.applications) { application in
                                applicationRow(application)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func applicationRow(_ application: ApplicationVolumeApplication) -> some View {
        HStack(spacing: 12) {
            Group {
                if let data = application.iconData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .padding(3)
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(application.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .help(application.name)
                if let statusKey = Self.controlStatus(for: application, errorMessage: service.errorMessage) {
                    AppLocalizedText(statusKey)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, alignment: .leading)

            Slider(
                value: Binding(
                    get: { application.volume },
                    set: { service.setVolume($0, for: application.id) }
                ),
                in: 0...1,
                step: 0.01
            )
            .accessibilityLabel(AppLocalization.text("%@ 的音量", application.name))
            .accessibilityValue(application.volume.formatted(.percent.precision(.fractionLength(0))))

            Text(application.volume, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
                .accessibilityHidden(true)

            Button {
                service.toggleMute(for: application.id)
            } label: {
                Image(systemName: application.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(application.isMuted ? Color.zislaWarning : .primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text(application.isMuted ? "取消静音" : "静音"))
            .accessibilityLabel(AppLocalization.text(
                application.isMuted ? "取消 %@ 的静音" : "将 %@ 静音", application.name
            ))
        }
        .padding(12)
        .islandGlassSurface(.card, cornerRadius: 12)
    }

    static func controlStatus(for application: ApplicationVolumeApplication, errorMessage: String?) -> String? {
        guard !application.isControlled, application.isMuted || application.volume != 1 else { return nil }
        return errorMessage == nil ? "等待应用音量控制生效" : "音量调整未生效"
    }
}
