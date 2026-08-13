import SwiftUI

/// A single navigation entry in the sidebar: icon + label, with a filled
/// selection state and a hover highlight — the reference app's sidebar row.
struct WVNavRow: View {
    let destination: AppShellDestination
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: destination.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Text(destination.title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                if isSelected {
                    shape.fill(Theme.selectionFill)
                } else if isHovering {
                    shape.fill(Color.white.opacity(0.035))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The full sidebar: brand header, grouped navigation, and a live status footer
/// that stands in for the reference app's account/credits area.
struct WVSidebar: View {
    @ObservedObject var presenter: AppShellPresenter
    @ObservedObject private var dictationPresenter: DictationPresenter

    init(presenter: AppShellPresenter) {
        self.presenter = presenter
        _dictationPresenter = ObservedObject(wrappedValue: presenter.dictationPresenter)
    }

    private let primary: [AppShellDestination] = [.overview, .permissions, .transcription, .hotkey, .privacy]
    private let data: [AppShellDestination] = [.history, .dictionary, .statistics]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.top, 34)  // clear the traffic lights
                .padding(.horizontal, 14)
                .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    group(title: "WinterVoice", items: primary)
                    group(title: "Data", items: data)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            WVDivider().padding(.horizontal, 14)
            footer
                .padding(14)
        }
        .frame(width: 232)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.separator).frame(width: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Color(hex: 0x1D4ED8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text("WinterVoice")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func group(title: String, items: [AppShellDestination]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            ForEach(items, id: \.self) { destination in
                WVNavRow(
                    destination: destination,
                    isSelected: presenter.selection == destination,
                    action: { presenter.navigate(to: destination) }
                )
            }
        }
    }

    private var footer: some View {
        let listening = dictationPresenter.hotkeyHealth == .listening
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                WVIconBadge(
                    systemImage: listening ? "keyboard" : "exclamationmark.triangle.fill",
                    tint: listening ? Theme.success : Theme.warning,
                    size: 30
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(presenter.providerStatus.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(listening ? "Hotkey listening" : "Hotkey needs attention")
                        .font(.system(size: 11))
                        .foregroundStyle(listening ? Theme.success : Theme.warning)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
