import SwiftUI

struct RecordingPanelView: View {
    @ObservedObject var presenter: DictationPresenter
    let levelMeter: AudioLevelMeter
    var style: WidgetStyle = .labeled
    var onToggle: () -> Void = {}
    var onDragMoved: () -> Void = {}
    var onDragEnded: () -> Void = {}

    var body: some View {
        content
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: presenter.state)
            .padding(8)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onToggle() }
            .gesture(
                // Translation values are window-relative, and the drag moves the
                // window itself — so the controller tracks the cursor in screen
                // coordinates instead of trusting the gesture's math.
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in onDragMoved() }
                    .onEnded { _ in onDragEnded() }
            )
    }

    /// Two visual modes only — the resting pill and the listening waveform.
    /// Preparing joins listening so holding the key gives instant feedback;
    /// processing/inserting keep the resting pill because flashing a
    /// different layout for each short phase made the widget feel noisy.
    @ViewBuilder
    private var content: some View {
        switch presenter.state {
        case .idle, .processing, .inserting:
            idlePill
        case .preparing, .recording:
            pill {
                PulsingMicDot()
                WaveformBars(levelMeter: levelMeter)
            }
        case .failed(let failure):
            failureCard(failure)
        }
    }

    /// BridgeVoice-style resting state: a small always-on-top pill whose look
    /// follows the Style picker in Settings.
    /// Double-click starts a dictation; drag moves the widget.
    @ViewBuilder
    private var idlePill: some View {
        Group {
            switch style {
            case .labeled:
                HStack(spacing: 7) {
                    WVBrandMark(size: 17)
                    Text("WinterVoice")
                        .font(.wv(12.5, .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 32)
                .background(panelBackground(in: Capsule()))
            case .icon:
                WVBrandMark(size: 17)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .frame(minHeight: 32)
                    .background(panelBackground(in: Capsule()))
            case .minimal:
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .frame(minHeight: 26)
                    .background(panelBackground(in: Capsule()))
            }
        }
        .opacity(0.95)
        .help("Double-click to start dictation. \(presenter.hotkeyInstruction).")
    }

    private func pill(@ViewBuilder body: () -> some View) -> some View {
        HStack(spacing: 10) { body() }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(panelBackground(in: Capsule()))
    }

    private func failureCard(_ failure: DictationFailure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                // The panel is sized from `fittingSize`, which measures at the
                // ideal width — for plain Text that is one unwrapped line, so
                // longer failures rendered as a single truncated "…" line.
                // Pinning the ideal width and letting the text take its full
                // wrapped height keeps every failure fully readable.
                Text(failure.message)
                    .font(.wv(13, .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(failure.recovery)
                    .font(.wv(11))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(idealWidth: 400, maxWidth: 400, alignment: .leading)
        .background(panelBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }

    /// On macOS 26+ the pill is true Liquid Glass refracting whatever is
    /// behind the panel; a dark tint keeps the fixed white text legible on
    /// any wallpaper. Older systems keep the black-over-material capsule.
    @ViewBuilder
    private func panelBackground(in shape: some InsettableShape) -> some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(.black.opacity(0.5)).interactive(), in: shape)
        } else {
            shape
                .fill(Color.black.opacity(0.78))
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
    }
}

private struct PulsingMicDot: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = sin(timeline.date.timeIntervalSinceReferenceDate * 4)
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.35))
                    .frame(width: 18, height: 18)
                    .scaleEffect(1 + 0.18 * phase)
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// Seven-band live waveform driven by the real microphone RMS level.
private struct WaveformBars: View {
    let levelMeter: AudioLevelMeter

    private static let weights: [CGFloat] = [0.5, 0.75, 1.0, 1.15, 1.0, 0.75, 0.5]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let level = CGFloat(levelMeter.level)
            HStack(spacing: 3) {
                ForEach(0..<Self.weights.count, id: \.self) { index in
                    // Each bar dances on its own phase and speed so voice
                    // energy reads as a wave, not seven bars in lockstep.
                    let phase = time * (7.5 + Double(index) * 0.9) + Double(index) * 1.7
                    let wave = (CGFloat(sin(phase)) + 1) / 2
                    let energy = min(1, level * Self.weights[index])
                    // A faint idle breath keeps the pill alive between words;
                    // the real excursion is driven by the mic level.
                    let target = 0.06 + 0.1 * wave + energy * (0.35 + 0.65 * wave)
                    let height = 4 + 18 * min(1, target)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: max(4, height))
                        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: height)
                }
            }
            .frame(height: 22)
        }
    }
}
