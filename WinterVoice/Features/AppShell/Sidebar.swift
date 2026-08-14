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
                if !isSelected, isHovering {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.hoverFill)
                }
            }
            .modifier(NavPillSurface(isSelected: isSelected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .help(iconOnly ? destination.title : "")
    }
}

/// The selected row's pill surface — Liquid Glass tinted with the pill color
/// on macOS 26+, the classic solid pill otherwise. Unselected rows pass
/// through untouched so hover keeps its faint fill.
private struct NavPillSurface: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.wvSurface(
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous),
                fill: Theme.navPillFill,
                glassTint: Theme.navPillFill.opacity(0.9),
                interactive: true
            )
        } else {
            content
        }
    }
}

/// The navigation rail below the titlebar strip: a flat list of destinations,
/// then the words counter and account card of the reference app. The titlebar
/// toggle collapses it to an icon-only rail instead of hiding it.
struct WVSidebar: View {
    @ObservedObject var presenter: AppShellPresenter
    @ObservedObject private var dictationPresenter: DictationPresenter
    @ObservedObject private var usageStats: UsageStatsStore
    @ObservedObject private var updates: UpdateController

    /// Shared with the titlebar toggle button through UserDefaults.
    @AppStorage(SidebarVisibility.key) private var isExpanded = true

    init(presenter: AppShellPresenter) {
        self.presenter = presenter
        _dictationPresenter = ObservedObject(wrappedValue: presenter.dictationPresenter)
        _usageStats = ObservedObject(wrappedValue: presenter.usageStats)
        _updates = ObservedObject(wrappedValue: presenter.updates)
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

            if case .available(let update) = updates.state {
                if isExpanded {
                    updateBanner(update)
                } else {
                    collapsedUpdateBadge(update)
                }
            }

            if isExpanded {
                footer
            } else {
                collapsedFooter
            }
        }
        .frame(width: isExpanded ? SidebarVisibility.expandedWidth : SidebarVisibility.railWidth)
        .frame(maxHeight: .infinity)
        .background(WVRailBackground().ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.separator).frame(width: 1)
        }
    }

    private var listening: Bool { dictationPresenter.hotkeyHealth == .listening }

    /// Notification card for the launch-time update discovery: title, blurb,
    /// a direct Download action, and a dismiss that skips this version — no
    /// Settings visit needed.
    private func updateBanner(_ update: AvailableUpdate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                WVBrandMark(size: 20)
                Text("New version available")
                    .font(.wv(12.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Button { updates.skip(update) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Skip this version")
            }

            Text("Version \(update.version) is ready to download.")
                .font(.wv(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button { updates.download(update) } label: {
                HStack(spacing: 4) {
                    Text("Download")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.wv(11.5, .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.accent.opacity(0.14))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .padding(.top, 2)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.surfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    /// Collapsed-rail version of the update banner: just the accent glyph;
    /// clicking starts the download directly, same as the expanded card.
    private func collapsedUpdateBadge(_ update: AvailableUpdate) -> some View {
        Button { updates.download(update) } label: {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .padding(.bottom, 4)
        .help("Update available: version \(update.version)")
    }

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
        // Oversize the mark slightly so the artwork's rounded corners stay
        // outside the circle and the clip has no transparent notches.
        WVBrandMark(size: 38)
            .frame(width: 32, height: 32)
            .clipShape(Circle())
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
