import SwiftUI
import ZislaCore
import ZislaKit

struct BatteryChargeToFullButton: View {
    @ObservedObject var batteryMonitor: BatteryMonitor
    @StateObject private var controller: BatteryChargingController
    @Environment(\.locale) private var locale
    private let debugShowsButton: Bool

    init(
        batteryMonitor: BatteryMonitor,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = LegacyAppDataMigration.isDebugBuild,
        controller: BatteryChargingController? = nil
    ) {
        self.batteryMonitor = batteryMonitor
        _controller = StateObject(wrappedValue: controller ?? BatteryChargingController())
        debugShowsButton = isDebugBuild && environment["ZISLA_DEBUG_SHOW_CHARGE_TO_FULL"] == "1"
    }

    var body: some View {
        HStack(spacing: 0) {
            if debugShowsButton || controller.canChargeToFull || controller.canRetry || controller.isRequesting {
                Self.chargeButton(isRequesting: controller.isRequesting, locale: locale) {
                    Task {
                        await controller.chargeToFull(recheckEligibility: debugShowsButton) { batteryMonitor.snapshot }
                        batteryMonitor.refresh()
                    }
                }
            }
        }
        .task(id: batteryMonitor.snapshot) {
            await controller.refresh(for: batteryMonitor.snapshot)
        }
        .alert(BatteryLocalization.string("无法立即充至100%，请重试。", locale: locale),
               isPresented: $controller.requestFailed) {
            Button(BatteryLocalization.string("好", locale: locale), role: .cancel) {}
        }
    }

    static func chargeButton(
        isRequesting: Bool,
        locale: Locale,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(BatteryLocalization.string("立即充至100%", locale: locale))
                .font(.system(size: 10, weight: .medium))
                .fitsSingleLine()
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .keepsIntrinsicWidth()
        .disabled(isRequesting)
    }
}
