import SwiftUI
import ZislaCore
import ZislaKit

struct FirstLaunchOnboardingView: View {
    @ObservedObject var session: FirstLaunchOnboardingSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch session.page {
                        case .greeting: greeting
                        case .introduction: introduction
                        case .permissions: permissions
                        case .ready: ready
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(0, viewport.size.height - 64),
                        alignment: session.page == .greeting ? .center : .topLeading
                    )
                    .padding(32)
                }
            }
            Hairline()
            navigation
                .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: reduceMotion) { session.start(reduceMotion: reduceMotion) }
        .onChange(of: session.page) { _, page in
            if page == .greeting { session.start(reduceMotion: reduceMotion) }
        }
        .onDisappear { session.close() }
        .onExitCommand { session.end(completed: false) }
    }

    private var greeting: some View {
        VStack(spacing: 24) {
            FirstLaunchGreetingAnimation(
                timeline: session.greetingTimeline,
                startedAt: session.greetingStartedAt,
                preferredLanguage: session.preferredLanguage
            )
            .frame(height: 180)
            thanks
            Button {
                session.isMuted.toggle()
            } label: {
                Label(localized(session.isMuted ? "onboarding.unmute" : "onboarding.mute"),
                      systemImage: session.isMuted ? "speaker.slash" : "speaker.wave.2")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("onboarding.introduction.title", body: "onboarding.introduction.body")
            FirstLaunchFeatureIllustration()
            feature("island", symbol: "rectangle.topthird.inset.filled")
            feature("tools", symbol: "square.stack.3d.up")
            feature("ai", symbol: "waveform")
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("onboarding.permissions.title", body: "onboarding.permissions.body")
            FirstLaunchOnboardingPermissionsView(session: session, coordinator: session.permissions)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.zislaSuccess)
                .accessibilityHidden(true)
            heading("onboarding.ready.title", body: "onboarding.ready.body")
            thanks
        }
        .padding(.vertical, 40)
    }

    private var thanks: some View {
        Link(destination: URL(string: "https://github.com/wzz6423/zisla/issues")!) {
            AppLocalizedText("onboarding.thanks")
                .font(.body)
                .multilineTextAlignment(session.page == .greeting ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var navigation: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                secondaryActions
                Spacer(minLength: 16)
                continueButton
            }
            VStack(alignment: .trailing, spacing: 12) {
                continueButton
                HStack(spacing: 16) { secondaryActions }
            }
        }
    }

    @ViewBuilder
    private var secondaryActions: some View {
        if session.page != .greeting {
            Button(localized("onboarding.back")) { session.back() }
        }
        if session.page == .permissions {
            Button(localized("onboarding.skip_permission")) { session.advance() }
        } else if session.page != .ready {
            Button(localized("onboarding.skip_intro")) { session.skipIntroduction() }
        }
    }

    private var continueButton: some View {
        Button(localized(session.page == .ready ? "onboarding.finish" : "onboarding.continue")) {
            session.advance()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }

    private func heading(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppLocalizedText(title)
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            AppLocalizedText(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func feature(_ id: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                AppLocalizedText("onboarding.feature.\(id).title").font(.headline)
                AppLocalizedText("onboarding.feature.\(id).body")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.fillControl, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.strokeCard))
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: locale)
    }
}

private struct FirstLaunchOnboardingPermissionsView: View {
    let session: FirstLaunchOnboardingSession
    @ObservedObject var coordinator: OnboardingPermissionCoordinator
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(coordinator.permissions) { item in
                VStack(alignment: .leading, spacing: 10) {
                    AppLocalizedText(item.titleKey)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    AppLocalizedText(item.bodyKey)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack { status(item); Spacer(); action(item) }
                        VStack(alignment: .leading, spacing: 8) { status(item); action(item) }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fillControl, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func status(_ item: OnboardingPermissionItem) -> some View {
        HStack(spacing: 6) {
            if item.status == .requesting {
                ProgressView().controlSize(.small)
                    .accessibilityHidden(true)
            } else if item.status == .granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.zislaSuccess)
                    .accessibilityHidden(true)
            }
            AppLocalizedText(item.status.localizationKey)
        }
        .font(.callout)
    }

    @ViewBuilder
    private func action(_ item: OnboardingPermissionItem) -> some View {
        if item.status != .granted {
            Button(AppLocalization.string(item.actionKey, locale: locale)) {
                session.performPermissionAction(item)
            }
            .disabled(coordinator.requesting != nil)
            .accessibilityLabel(Text(
                AppLocalization.string(item.actionKey, locale: locale) + " · " +
                    AppLocalization.string(item.titleKey, locale: locale)
            ))
        }
    }
}
