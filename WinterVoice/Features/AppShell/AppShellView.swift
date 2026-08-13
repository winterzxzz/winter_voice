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
        case .permissions:
            PermissionsView(
                presenter: presenter.dictationPresenter,
                reopenOnboarding: onboardingPresenter.restart
            )
        case .transcription:
            TranscriptionView(presenter: presenter)
        case .hotkey:
            HotkeyView(
                presenter: presenter.dictationPresenter,
                binding: presenter.hotkeyBinding,
                captureSuspender: presenter.hotkeyCaptureSuspender
            )
        case .privacy:
            PrivacyView(presenter: presenter)
        case .history:
            HistoryView(store: presenter.history)
        case .dictionary:
            DictionaryView(store: presenter.dictionary)
        case .statistics:
            StatisticsView(store: presenter.usageStats)
        }
    }
}

/// Shared page scaffold: a scrollable, max-width content column with a header
/// and consistent padding. Every screen sits inside one of these so the dark
/// canvas, spacing, and header treatment stay identical across the app.
struct WVPage<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var maxWidth: CGFloat = 760
    @ViewBuilder var content: Content

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        maxWidth: CGFloat = 760,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                WVSectionHeader(icon: icon, title: title, subtitle: subtitle)
                content
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 48)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
    }
}

extension AppShellDestination {
    var title: String {
        switch self {
        case .overview: "Home"
        case .permissions: "Permissions"
        case .transcription: "Transcription"
        case .hotkey: "Shortcuts"
        case .privacy: "Privacy"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .statistics: "Statistics"
        }
    }

    var icon: String {
        switch self {
        case .overview: "house"
        case .permissions: "checkmark.shield"
        case .transcription: "waveform"
        case .hotkey: "keyboard"
        case .privacy: "hand.raised"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .statistics: "chart.bar.xaxis"
        }
    }
}
