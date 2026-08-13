import SwiftUI

struct RecordingPanelView: View {
    @ObservedObject var presenter: DictationPresenter
    let levelMeter: AudioLevelMeter
    var onToggle: () -> Void = {}
    var onDragDelta: (CGSize) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    @State private var lastDragTranslation: CGSize = .zero

    var body: some View {
        content
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: presenter.state)
            .padding(24)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onToggle() }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - lastDragTranslation.width,
                            height: value.translation.height - lastDragTranslation.height
                        )
                        lastDragTranslation = value.translation
                        onDragDelta(delta)
                    }
                    .onEnded { _ in
                        lastDragTranslation = .zero
                        onDragEnded()
                    }
            )
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.state {
        case .idle:
            idlePill
        case .preparing:
            pill {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                statusText("Preparing…")
            }
        case .recording:
            pill {
                PulsingMicDot()
                WaveformBars(levelMeter: levelMeter)
                statusText(presenter.hotkeyBinding.selection.title)
                    .opacity(0.55)
            }
        case .processing:
            pill {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                statusText("Transcribing…")
            }
        case .inserting:
            pill {
                Image(systemName: "text.insert")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                statusText("Inserting…")
            }
        case .failed(let failure):
            failureCard(failure)
        }
    }

    /// BridgeVoice-style resting state: a small always-on-top pill.
    /// Double-click starts a dictation; drag moves the widget.
    private var idlePill: some View {
        HStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 30)
        .background(panelBackground(in: Capsule()))
        .opacity(0.92)
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
                Text(failure.message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(failure.recovery)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 400, alignment: .leading)
        .background(panelBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }

    private func panelBackground(in shape: some InsettableShape) -> some View {
        shape
            .fill(Color.black.opacity(0.78))
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
    }

    private func statusText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
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
                    let wobble = CGFloat(sin(time * 9 + Double(index) * 1.3)) * 0.2
                    let height = 4 + 18 * min(1, max(0, level * Self.weights[index] + wobble * level))
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
