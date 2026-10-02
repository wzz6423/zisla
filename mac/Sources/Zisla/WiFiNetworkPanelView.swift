import SwiftUI
import ZislaCore
import ZislaKit

struct WiFiNetworkPanelView: View {
    @ObservedObject var controller: SystemWiFiPanelController
    @State private var showsOtherNetworks = true
    @State private var password = ""
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(AppLocalization.text("Wi-Fi"), isOn: Binding(
                get: { controller.snapshot?.powerOn == true },
                set: { controller.setPower($0) }
            ))
            .font(.headline)
            .toggleStyle(WiFiPowerToggleStyle())
            .disabled(!controller.canSetPower)

            Divider()
            if let network = controller.passwordNetwork {
                passwordEntry(for: network)
            } else {
                networkContent
            }
            if let failure = controller.failure {
                Text(AppLocalization.text(failure.messageKey))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if failure != .requiresSystemSettings, failure != .passwordRequired {
                    Button(AppLocalization.text("重试")) { controller.refresh() }
                        .disabled(controller.isBusy)
                }
            }
            if controller.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(AppLocalization.text(activityKey))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Button(AppLocalization.text("打开 Wi-Fi 设置")) {
                    _ = controller.openSettings(.wifi)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Button {
                    controller.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(AppLocalization.text("刷新"))
                .accessibilityLabel(AppLocalization.text("刷新"))
                .disabled(controller.isBusy)
            }
        }
        .padding(14)
        .frame(width: 292)
        .onChange(of: controller.passwordNetwork?.id) { _, selectedID in
            password = ""
            passwordFocused = selectedID != nil
        }
        .onDisappear { password = "" }
    }

    @ViewBuilder
    private var networkContent: some View {
        if controller.snapshot?.powerOn == false {
            Text(AppLocalization.text("Wi-Fi 已关闭"))
                .foregroundStyle(.secondary)
        } else if controller.authorization != .authorized {
            authorizationContent
        } else if let snapshot = controller.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !snapshot.personalHotspots.isEmpty {
                        Text(AppLocalization.text("个人热点"))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(snapshot.personalHotspots) { networkRow($0) }
                        Divider()
                    }
                    if !snapshot.knownNetworks.isEmpty {
                        Text(AppLocalization.text("已知网络"))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(snapshot.knownNetworks) { networkRow($0) }
                        Divider()
                    }
                    DisclosureGroup(AppLocalization.text("其他网络"), isExpanded: $showsOtherNetworks) {
                        VStack(spacing: 4) {
                            ForEach(snapshot.otherNetworks) { networkRow($0) }
                            if snapshot.otherNetworks.isEmpty, !controller.isBusy {
                                Text(AppLocalization.text("未找到附近的 Wi-Fi 网络"))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.callout.weight(.semibold))
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authorizationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.snapshot?.isConnected == true {
                Text(AppLocalization.text("已连接"))
                    .font(.callout.weight(.semibold))
            }
            Text(AppLocalization.text("需要定位权限才能显示附近的 Wi-Fi 网络。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if controller.authorization == .notDetermined {
                Button(AppLocalization.text("允许访问位置")) {
                    controller.requestLocationAuthorization()
                }
                .disabled(controller.isBusy)
            } else {
                Button(AppLocalization.text("打开定位设置")) {
                    _ = controller.openSettings(.location)
                }
            }
        }
    }

    private func networkRow(_ network: WiFiNetwork) -> some View {
        Button {
            controller.selectNetwork(network)
        } label: {
            HStack(spacing: 9) {
                Image(
                    systemName: network.isPersonalHotspot == true ? "personalhotspot" : "wifi",
                    variableValue: network.isPersonalHotspot == true ? nil : network.signalStrength
                )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(network.isConnected ? Color.white : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(network.isConnected ? Color.accentColor : Color.primary.opacity(0.07), in: Circle())
                Text(verbatim: network.name)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if network.isConnected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else if network.id.security != .open {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controller.isBusy)
        .accessibilityLabel(Text(verbatim: network.name))
        .accessibilityValue(AppLocalization.text(network.isConnected ? "已连接" : "未连接"))
    }

    private func passwordEntry(for network: WiFiNetwork) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: network.name)
                .font(.headline)
                .lineLimit(2)
            SecureField(AppLocalization.text("Wi-Fi 密码"), text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($passwordFocused)
                .onSubmit { submitPassword() }
            HStack {
                Button(AppLocalization.text("取消")) {
                    password = ""
                    controller.cancelPasswordEntry()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(AppLocalization.text("加入网络")) { submitPassword() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || controller.isBusy)
            }
        }
    }

    private func submitPassword() {
        controller.connect(password: password)
        password = ""
    }

    private var activityKey: String {
        switch controller.activity {
        case .idle, .scanning: "正在搜索 Wi-Fi 网络…"
        case .updatingPower: "正在更新 Wi-Fi…"
        case .connecting: "正在连接…"
        case .authorizing: "正在等待定位授权…"
        }
    }
}

private struct WiFiPowerToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 54, height: 24)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Capsule()
                            .fill(.white)
                            .frame(width: 32, height: 20)
                            .padding(2)
                    }
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}
