import SwiftUI

struct LaunchGateView: View {
    @ObservedObject var onboardingPresenter: OnboardingPresenter
    let shellPresenter: AppShellPresenter
    @State private var isShowingSplash = true
    /// Observed here — the window root — so a theme switch re-evaluates the
    /// color scheme below. Theme tokens are appearance-dynamic colors, so the
    /// appearance flip alone recolors every view in place; nothing is torn
    /// down and scroll/disclosure state survives.
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        ZStack {
            gate
                .opacity(isShowingSplash ? 0 : 1)

            if isShowingSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        isShowingSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .preferredColorScheme(theme.mode.colorScheme)
    }

    @ViewBuilder
    private var gate: some View {
        if onboardingPresenter.isPresented {
            OnboardingView(presenter: onboardingPresenter)
        } else {
            AppShellView(
                presenter: shellPresenter,
                onboardingPresenter: onboardingPresenter
            )
        }
    }
}

// MARK: - Splash

/// Branded launch intro: the logo mark blooms in over a soft accent glow, the
/// wordmark and tagline follow, a live waveform pulses, then the whole thing
/// crossfades into the app.
private struct SplashView: View {
    var onFinished: () -> Void

    @State private var showMark = false
    @State private var showTitle = false
    @State private var showBars = false

    var body: some View {
        ZStack {
            Theme.canvas

            // Soft glow behind the mark so the black canvas has depth.
            RadialGradient(
                colors: [Theme.accent.opacity(0.16), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 340
            )
            .offset(y: -40)

            VStack(spacing: 26) {
                logoMark
                    .scaleEffect(showMark ? 1 : 0.8)
                    .opacity(showMark ? 1 : 0)

                VStack(spacing: 8) {
                    Text("WinterVoice")
                        .font(.wv(30, .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Speak anywhere. It types for you.")
                        .font(.wv(13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 10)

                SplashWave()
                    .opacity(showBars ? 1 : 0)
                    .padding(.top, 2)
            }
            .offset(y: -16)
        }
        .ignoresSafeArea()
        .task { await run() }
    }

    private var logoMark: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Theme.accent, Color(hex: 0x1D4ED8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 76, height: 76)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Theme.accent.opacity(0.5), radius: 30, y: 10)
    }

    private func run() async {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
            showMark = true
        }
        try? await Task.sleep(nanoseconds: 280_000_000)
        withAnimation(.easeOut(duration: 0.45)) {
            showTitle = true
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        withAnimation(.easeOut(duration: 0.4)) {
            showBars = true
        }
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        onFinished()
    }
}

/// Five accent capsules pulsing in a gentle sine wave — the app's dictation
/// pill motif, used as the splash's sign of life.
private struct SplashWave: View {
    private static let weights: [CGFloat] = [0.45, 0.8, 1.0, 0.8, 0.45]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<Self.weights.count, id: \.self) { index in
                    let phase = sin(time * 3.4 + Double(index) * 0.9)
                    let height = 8 + 16 * Self.weights[index] * CGFloat(0.55 + 0.45 * phase)
                    Capsule()
                        .fill(Theme.accent.opacity(0.85))
                        .frame(width: 4, height: max(6, height))
                }
            }
            .frame(height: 26)
        }
    }
}
