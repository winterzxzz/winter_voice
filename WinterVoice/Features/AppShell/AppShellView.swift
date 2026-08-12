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

                Section("Coming Later") {
                    sidebarRow(.models)
                    sidebarRow(.remoteProviders)
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
                if destination.availability == .planned {
                    Text("Planned")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: destination.icon)
        }
        .tag(destination)
        .accessibilityLabel(destination.availability == .planned
            ? "\(destination.title), planned"
            : destination.title)
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
            TranscriptionView(capability: presenter.transcription)
        case .hotkey:
            HotkeyView(presenter: presenter.dictationPresenter)
        case .privacy:
            PrivacyView()
        case .models, .remoteProviders, .history, .dictionary:
            PlannedFeatureView(destination: destination)
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
        case .models: "Models"
        case .remoteProviders: "Remote Providers"
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
        case .models: "shippingbox"
        case .remoteProviders: "network"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        }
    }

    var plannedDescription: String {
        switch self {
        case .models: "Downloadable model management is not available in this MVP. WinterVoice currently uses Apple Speech built into macOS."
        case .remoteProviders: "Network transcription providers are not available. WinterVoice has no remote transcription fallback."
        case .history: "WinterVoice does not save transcripts. A local history surface is planned for a later release."
        case .dictionary: "Custom words and replacements are not available in this MVP."
        default: ""
        }
    }
}
