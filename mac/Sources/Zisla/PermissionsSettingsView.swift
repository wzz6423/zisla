import AppKit
import SwiftUI
import ZislaKit

struct PermissionsSettingsView: View {
    @StateObject private var coordinator: OnboardingPermissionCoordinator
    @State private var settingsOpenFailure: OnboardingPermissionID?

    init(coordinator: @autoclosure @escaping () -> OnboardingPermissionCoordinator = OnboardingPermissionCoordinator()) {
        _coordinator = StateObject(wrappedValue: coordinator())
    }

    var body: some View {
        PermissionListView(performAction: performAction, coordinator: coordinator, settingsOpenFailure: settingsOpenFailure)
            .onAppear { coordinator.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                coordinator.refresh()
            }
            .onDisappear { coordinator.cancelCurrentRequest() }
    }

    private func performAction(_ item: OnboardingPermissionItem) {
        switch item.status {
        case .granted, .requesting: break
        case .denied, .restricted, .manual:
            settingsOpenFailure = coordinator.openSettings(for: item.id) ? nil : item.id
        case .notDetermined, .unavailable:
            coordinator.request(item.id)
        }
    }
}
