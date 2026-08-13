import SwiftUI

// MARK: - Card

/// A rounded, hairline-bordered surface. The core building block of every
/// screen: content is grouped into cards rather than system `Form` sections.
struct WVCard<Content: View>: View {
    var padding: CGFloat = Theme.Space.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
    }
}

// MARK: - Icon badge

/// The small rounded square that precedes a row title (holds an SF Symbol).
struct WVIconBadge: View {
    let systemImage: String
    var tint: Color = Theme.textSecondary
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.icon, style: .continuous)
            .fill(Theme.inset)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.icon, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Section header

/// The header at the top of a screen: icon badge, title, subtitle, and an
/// optional trailing accessory (e.g. a Refresh button).
struct WVSectionHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            WVIconBadge(systemImage: icon, tint: Theme.textPrimary, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.wvTitle)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Theme.Space.md)
            trailing
        }
    }
}

extension WVSectionHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Keycap

/// A single key rendered as a chip, e.g. `Cmd`, `Shift`, `Space`, `Fn / Globe`.
struct WVKeycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.wvKeycap)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.surfaceElevated, in: shape)
            .overlay(shape.strokeBorder(Theme.borderStrong, lineWidth: 1))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
    }
}

/// A sequence of keycaps joined by `+`, e.g. ⌘ + ⇧ + Space.
struct WVKeycapChord: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 {
                    Text("+")
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textTertiary)
                }
                WVKeycap(label: key)
            }
        }
    }
}

// MARK: - Status pill

/// A small status indicator: a colored dot + label, optionally on a tinted pill.
struct WVStatusPill: View {
    let text: String
    var color: Color = Theme.success
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.wvCaption.weight(.medium))
                .foregroundStyle(filled ? color : Theme.textSecondary)
        }
        .padding(.horizontal, filled ? 9 : 0)
        .padding(.vertical, filled ? 4 : 0)
        .background {
            if filled {
                Capsule().fill(color.opacity(0.14))
            }
        }
    }
}

// MARK: - Settings row scaffold

/// A labeled row inside a card: leading icon badge, title + subtitle, and a
/// trailing control cluster. Used across Shortcuts/Settings-style screens.
struct WVRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            WVIconBadge(systemImage: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.wvRowTitle)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.md)
            trailing
        }
        .padding(.vertical, 4)
    }
}

/// A hairline divider matching the card border tone.
struct WVDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
    }
}
