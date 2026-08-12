import AppKit

@MainActor
final class AppRouter: ObservableObject {
    @Published private(set) var selection: AppShellDestination = .overview

    func navigate(to destination: AppShellDestination) {
        selection = destination
    }

    func activateApplication() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func openSystemSettings(for permission: AppPermission) {
        let anchor: String
        switch permission {
        case .microphone: anchor = "Privacy_Microphone"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .accessibility: anchor = "Privacy_Accessibility"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
