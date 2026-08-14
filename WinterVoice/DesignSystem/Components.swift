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

// MARK: - Brand mark

/// The app logo square: a blue gradient tile with the waveform glyph. Used in
/// the titlebar, the floating widget, and the widget style previews.
struct WVBrandMark: View {
    var size: CGFloat = 19

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Theme.accent, Color(hex: 0x1D4ED8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            )
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
                .font(.wvCaptionMedium)
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
                        .lineSpacing(2.5)
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

// MARK: - Toggle

/// The reference switch: an emphasis-filled track with a contrasting knob when
/// on, a muted track with a gray knob when off.
struct WVToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                Capsule()
                    .fill(configuration.isOn ? Theme.emphasis : Theme.toggleOffFill)
                    .frame(width: 38, height: 22)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? Theme.textOnEmphasis : Theme.toggleKnobOff)
                            .frame(width: 16, height: 16)
                            .padding(3)
                    }
                    .animation(.spring(response: 0.24, dampingFraction: 0.9), value: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .opacity(isEnabled ? 1 : 0.5)
    }
}

extension ToggleStyle where Self == WVToggleStyle {
    static var wv: WVToggleStyle { WVToggleStyle() }
}

// MARK: - Dashed empty state

/// The reference empty state: a dashed rounded border around a centered icon
/// square, a bold one-liner, and a gray hint.
struct WVDashedEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            WVIconBadge(systemImage: icon, tint: Theme.textPrimary, size: 34)
            Text(title)
                .font(.wv(13.5, .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.wvCaption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(
                    Theme.borderStrong,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
        )
    }
}

// MARK: - Chip picker

/// A row of pill "chips" acting as a segmented control; the selected chip is
/// filled white with dark text like the reference (`Local / Cloud`,
/// `Always / Recording / Hidden`).
struct WVChipPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String
    var icon: ((Option) -> String?)? = nil
    /// Wraps the chips in an inset, bordered capsule container — the reference
    /// `Local / Cloud` segmented treatment.
    var grouped = false

    var body: some View {
        let row = HStack(spacing: grouped ? 2 : 6) {
            ForEach(options, id: \.self) { option in
                chip(option)
            }
        }
        if grouped {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            row
                .padding(3)
                .background(Theme.inset, in: shape)
                .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
        } else {
            row
        }
    }

    private func chip(_ option: Option) -> some View {
        ChipButton(
            isSelected: option == selection,
            title: label(option),
            symbol: icon?(option) ?? nil,
            action: { selection = option }
        )
    }
}

/// A single chip: an elevated dark fill with a brighter border when selected,
/// plain gray text with a hover hint otherwise — the reference chip treatment
/// (`Custom`, `Always`).
private struct ChipButton: View {
    let isSelected: Bool
    let title: String
    var symbol: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(.wv(12.5, isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    shape.fill(Theme.chipSelected)
                } else if isHovering {
                    shape.fill(Theme.inset)
                }
            }
            .overlay {
                if isSelected {
                    shape.strokeBorder(Theme.chipSelectedBorder, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}

// MARK: - Icon button

/// A small bordered square holding a single icon, e.g. the refresh control
/// beside a search field.
struct WVIconButton: View {
    let systemImage: String
    var help: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(isHovering ? Theme.surfaceElevated : Theme.inset, in: shape)
                .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .help(help ?? "")
    }
}

// MARK: - Search field

/// The inset dark search input used by History and Dictionary.
struct WVSearchField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(.wv(13))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: width)
        .background(Theme.inset, in: shape)
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
    }
}

// MARK: - Disclosure card

/// A full-width collapsible row inside a bordered card: label on the left,
/// chevron on the right — the reference "All models" / "Advanced" /
/// "Troubleshooting" rows.
struct WVDisclosureCard<Content: View>: View {
    let label: String
    var chevronLeading = false
    @ViewBuilder var content: Content

    @State private var isExpanded = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if chevronLeading {
                        chevron
                        labelText
                        Spacer(minLength: 0)
                    } else {
                        labelText
                        Spacer(minLength: 0)
                        chevron
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                WVDivider().padding(.horizontal, 14)
                content
                    .padding(14)
            }
        }
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
    }

    private var labelText: some View {
        Text(label)
            .font(.wv(13))
            .foregroundStyle(Theme.textSecondary)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .rotationEffect(.degrees(chevronLeading ? (isExpanded ? 90 : 0) : (isExpanded ? -90 : 90)))
    }
}
