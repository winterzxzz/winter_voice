import SwiftUI

/// A single navigation entry in the sidebar. The selected row is a solid white
/// pill with dark text — the reference app's signature selection state; other
/// rows are gray with a faint hover fill.
struct WVNavRow: View {
    let destination: AppShellDestination
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: destination.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 19)
                Text(destination.title)
                    .font(.wv(14, isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Theme.textOnWhite : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                if isSelected {
                    shape.fill(Color.white)
                } else if isHovering {
                    shape.fill(Theme.hoverFill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}

/// The navigation rail below the titlebar strip: a flat list of destinations,
/// then the words counter and account card of the reference app.
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
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(items, id: \.self) { destination in
                        WVNavRow(
                            destination: destination,
                            isSelected: presenter.selection == destination,
                            action: { presenter.navigate(to: destination) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            footer
        }
        .frame(width: 208)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.separator).frame(width: 1)
        }
    }

    private var footer: some View {
        let listening = dictationPresenter.hotkeyHealth == .listening
        return VStack(alignment: .leading, spacing: 0) {
            WVDivider()

            HStack(spacing: 10) {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 19)
                Text("Words")
                    .font(.wv(13.5, .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Text(usageStats.totals.totalWords.formatted())
                    .font(.wv(13, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.surfaceElevated)
                    .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
                    .overlay(
                        Text("WV")
                            .font(.wv(10.5, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    )
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("WinterVoice")
                        .font(.wv(13, .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(listening ? Theme.success : Theme.warning)
                            .frame(width: 5, height: 5)
                        Text(presenter.providerStatus.title)
                            .font(.wv(11.5))
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
