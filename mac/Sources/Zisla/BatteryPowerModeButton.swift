import SwiftUI
import ZislaCore
import ZislaKit

struct BatteryPowerModeButton: View {
    let isPluggedIn: Bool
    let isLowPowerMode: Bool

    @StateObject private var controller = BatteryPowerModeController()

    private var presentation: BatteryPowerModePresentation {
        BatteryPowerModePresentation(
            currentMode: controller.currentMode,
            powerSource: controller.powerSource,
            supportedModes: controller.supportedModes,
            isChanging: controller.isChanging,
            error: controller.error
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Self.modeButtons(
                currentMode: controller.currentMode,
                presentation: presentation
            ) { mode in
                Task { await controller.setMode(mode) }
            }
            if let messageKey = presentation.messageKey {
                HStack(spacing: 6) {
                    if presentation.isBusy {
                        ProgressView().controlSize(.mini)
                    }
                    Text(AppLocalization.text(messageKey))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if controller.error != nil {
                        Button(AppLocalization.text("重试")) {
                            Task { await controller.refresh() }
                        }
                        .controlSize(.mini)
                        .disabled(controller.isChanging)
                    }
                }
            }
        }
        .help(AppLocalization.text("电源模式"))
        .accessibilityLabel(AppLocalization.text("电源模式"))
        .accessibilityValue(AppLocalization.text(presentation.titleKey))
        .task(id: [isPluggedIn, isLowPowerMode]) {
            await controller.refresh()
        }
    }

    static func modeButtons(
        currentMode: BatteryPowerMode?,
        presentation: BatteryPowerModePresentation,
        select: @escaping (BatteryPowerMode) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(BatteryPowerMode.allCases, id: \.rawValue) { mode in
                Button {
                    select(mode)
                } label: {
                    AppLocalizedText(BatteryPowerModePresentation.titleKey(for: mode))
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(currentMode == mode ? Color.accentColor : Color.secondary)
                .disabled(!presentation.canSelect(mode))
                .accessibilityAddTraits(currentMode == mode ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct BatteryPowerModePresentation {
    let titleKey: String
    let messageKey: String?
    let isBusy: Bool
    let canSelect: Bool
    private let supportedModes: [BatteryPowerMode]

    init(
        currentMode: BatteryPowerMode?,
        powerSource: BatteryPowerSource?,
        supportedModes: [BatteryPowerMode],
        isChanging: Bool,
        error: BatteryPowerModeError?
    ) {
        self.supportedModes = supportedModes
        titleKey = currentMode.map(Self.titleKey) ?? "电源模式"
        isBusy = isChanging || (powerSource == nil && error == nil)
        canSelect = !isBusy && error == nil && !supportedModes.isEmpty
        if isChanging {
            messageKey = "正在切换电源模式…"
        } else if let error {
            messageKey = switch error {
            case .stateUnavailable: "无法读取电源模式，请重试。"
            case .unsupportedMode: "当前供电方式不支持切换电源模式。"
            case .authorizationCancelled: "电源模式授权已取消。"
            case .authorizationDenied: "未获得切换电源模式的授权。"
            case .changeFailed: "无法切换电源模式，请重试。"
            case .verificationFailed: "无法确认电源模式已更改，请重试。"
            case .timedOut: "电源模式操作超时，请重试。"
            }
        } else if powerSource == nil {
            messageKey = "正在读取电源模式…"
        } else if supportedModes.isEmpty {
            messageKey = "当前供电方式不支持切换电源模式。"
        } else {
            messageKey = nil
        }
    }

    func canSelect(_ mode: BatteryPowerMode) -> Bool {
        canSelect && supportedModes.contains(mode)
    }

    static func titleKey(for mode: BatteryPowerMode) -> String {
        switch mode {
        case .automatic: "自动"
        case .lowPower: "低能耗模式"
        case .highPower: "高能耗模式"
        }
    }
}
