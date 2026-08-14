import SwiftUI

struct AppShellView: View {
    @ObservedObject var presenter: AppShellPresenter
    let onboardingPresenter: OnboardingPresenter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 0) {
            WVSidebar(presenter: presenter)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.canvas)
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .wvWindowChrome()
        .onAppear { presenter.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { presenter.refresh() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        destinationView(presenter.selection)
            .id(presenter.selection)
    }

    @ViewBuilder
    private func destinationView(_ destination: AppShellDestination) -> some View {
        switch destination {
        case .overview:
            OverviewView(presenter: presenter)
        case .history:
            HistoryView(store: presenter.history)
        case .dictionary:
            DictionaryView(store: presenter.dictionary)
        case .hotkey:
            HotkeyView(
                presenter: presenter.dictationPresenter,
                binding: presenter.hotkeyBinding,
                captureSuspender: presenter.hotkeyCaptureSuspender
            )
        case .settings:
            AppSettingsView(
                presenter: presenter,
                reopenOnboarding: onboardingPresenter.restart
            )
        }
    }
}

/// Shared page scaffold: a scrollable, max-width content column with a header
/// (plus optional trailing accessory) and consistent padding. Every screen sits
/// inside one of these so the dark canvas, spacing, and header treatment stay
/// identical across the app.
struct WVPage<Content: View, Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var maxWidth: CGFloat = 1000
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        maxWidth: CGFloat = 1000,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.maxWidth = maxWidth
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                WVSectionHeader(icon: icon, title: title, subtitle: subtitle) {
                    trailing
                }
                content
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 44)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
    }
}

extension WVPage where Trailing == EmptyView {
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        maxWidth: CGFloat = 1000,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            icon: icon,
            title: title,
            subtitle: subtitle,
            maxWidth: maxWidth,
            content: content,
            trailing: { EmptyView() }
        )
    }
}

extension AppShellDestination {
    var title: String {
        switch self {
        case .overview: "Home"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .hotkey: "Shortcuts"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .overview: "house"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .hotkey: "keyboard"
        case .settings: "gearshape"
        }
    }
}
