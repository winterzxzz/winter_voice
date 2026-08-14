import SwiftUI

/// A single navigation entry in the sidebar. The selected row is a solid pill
/// (white in Black, gray in Light) with dark text — the reference app's
/// signature selection state; other rows are gray with a faint hover fill.
/// In the collapsed rail only the icon shows, centered inside the pill.
struct WVNavRow: View {
    let destination: AppShellDestination
    let isSelected: Bool
    var iconOnly = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: destination.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 19)
                if !iconOnly {
                    Text(destination.title)
                        .font(.wv(14, isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(isSelected ? Theme.navPillText : Theme.textSecondary)
            .padding(.horizontal, iconOnly ? 10 : 12)
            .padding(.vertical, 9)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                if isSelected {
                    shape.fill(Theme.navPillFill)
                } else if isHovering {
                    shape.fill(Theme.hoverFill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .help(iconOnly ? destination.title : "")
    }
}

/// The navigation rail below the titlebar strip: a flat list of destinations,
/// then the words counter and account card of the reference app. The titlebar
/// toggle collapses it to an icon-only rail instead of hiding it.
struct WVSidebar: View {
    @ObservedObject var presenter: AppShellPresenter
    @ObservedObject private var dictationPresenter: DictationPresenter
    @ObservedObject private var usageStats: UsageStatsStore

    /// Shared with the titlebar toggle button through UserDefaults.
    @AppStorage(SidebarVisibility.key) private var isExpanded = true

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
                            iconOnly: !isExpanded,
                            action: { presenter.navigate(to: destination) }
                        )
                        .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            if isExpanded {
                footer
            } else {
                collapsedFooter
            }
        }
        .frame(width: isExpanded ? SidebarVisibility.expandedWidth : SidebarVisibility.railWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.separator).frame(width: 1)
        }
    }

    private var listening: Bool { dictationPresenter.hotkeyHealth == .listening }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                avatar
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

    /// Icon-only rail footer: just the avatar, with the listener status as a
    /// small dot pinned to its corner so health stays visible.
    private var collapsedFooter: some View {
        VStack(spacing: 0) {
            WVDivider()
            avatar
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(listening ? Theme.success : Theme.warning)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Theme.sidebar, lineWidth: 1.5))
                        .offset(x: 1, y: 1)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .help(presenter.providerStatus.title)
        }
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.surfaceElevated)
            .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1))
            .overlay(
                Text("WV")
                    .font(.wv(10.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
            )
            .frame(width: 32, height: 32)
    }
}

// MARK: - Visibility

enum SidebarVisibility {
    /// Shared UserDefaults key: the titlebar toggle button lives in a separate
    /// AppKit-hosted view tree, so both sides observe this via `@AppStorage`.
    /// `true` = full sidebar, `false` = icon-only rail.
    static let key = "sidebar.visible"

    static let expandedWidth: CGFloat = 208
    static let railWidth: CGFloat = 64
}
