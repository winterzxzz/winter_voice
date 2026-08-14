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
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Text(destination.title)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
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
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}

/// The full sidebar: brand mark beside the traffic lights, a flat navigation
/// list, and the words/account footer of the reference app.
struct WVSidebar: View {
    @ObservedObject var presenter: AppShellPresenter
    @ObservedObject private var dictationPresenter: DictationPresenter
    @ObservedObject private var usageStats: UsageStatsStore

    init(presenter: AppShellPresenter) {
        self.presenter = presenter
        _dictationPresenter = ObservedObject(wrappedValue: presenter.dictationPresenter)
        _usageStats = ObservedObject(wrappedValue: presenter.usageStats)
    }

    private let items: [AppShellDestination] = [
        .overview, .history, .dictionary, .hotkey, .settings,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title-bar row: the sidebar ignores the top safe area, so this
            // sits on the same line as the traffic lights, brand to their right.
            brand
                .padding(.leading, 76)
                .frame(height: 30, alignment: .leading)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items, id: \.self) { destination in
                        WVNavRow(
                            destination: destination,
                            isSelected: presenter.selection == destination,
                            action: { presenter.navigate(to: destination) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            footer
        }
        .frame(width: 208)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.separator).frame(width: 1)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private var brand: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Color(hex: 0x1D4ED8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text("WinterVoice")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var footer: some View {
        let listening = dictationPresenter.hotkeyHealth == .listening
        return VStack(alignment: .leading, spacing: 0) {
            WVDivider()

            HStack(spacing: 9) {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20)
                Text("Words")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Text(usageStats.totals.totalWords.formatted())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 9) {
                Circle()
                    .fill(Theme.surfaceElevated)
                    .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                    .overlay(
                        Text("WV")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    )
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("WinterVoice")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(listening ? Theme.success : Theme.warning)
                            .frame(width: 5, height: 5)
                        Text(presenter.providerStatus.title)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }
}
