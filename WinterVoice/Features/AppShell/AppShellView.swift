import SwiftUI

struct AppShellView: View {
    @ObservedObject var presenter: AppShellPresenter
    let onboardingPresenter: OnboardingPresenter
    @Environment(\.scenePhase) private var scenePhase

    private var selection: Binding<AppShellDestination?> {
        Binding(
            get: { presenter.selection },
            set: { destination in
                if let destination { presenter.navigate(to: destination) }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("WinterVoice") {
                    sidebarRow(.overview)
                    sidebarRow(.permissions)
                    sidebarRow(.transcription)
                    sidebarRow(.hotkey)
                    sidebarRow(.privacy)
                }

                Section("Data") {
                    sidebarRow(.history)
                    sidebarRow(.dictionary)
                }
            }
            .navigationTitle("WinterVoice")
            .navigationSplitViewColumnWidth(min: 210, ideal: 235)
        } detail: {
            destinationView(presenter.selection)
                .id(presenter.selection)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { presenter.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { presenter.refresh() }
        }
    }

    private func sidebarRow(_ destination: AppShellDestination) -> some View {
        Label {
            HStack {
                Text(destination.title)
                Spacer()
            }
        } icon: {
            Image(systemName: destination.icon)
        }
        .tag(destination)
        .accessibilityLabel(destination.title)
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
        }
    }
}

extension AppShellDestination {
    var title: String {
        switch self {
        case .overview: "Overview"
        case .permissions: "Permissions"
        case .transcription: "Transcription"
        case .hotkey: "Hotkey"
        case .privacy: "Privacy"
        case .history: "History"
        case .dictionary: "Dictionary"
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
        }
    }

}
