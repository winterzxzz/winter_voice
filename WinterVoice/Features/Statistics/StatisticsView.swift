import SwiftUI

/// Local usage totals rendered as stat tiles — shown on the Home screen.
struct UsageStatsSection: View {
    @ObservedObject var store: UsageStatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("USAGE")
                    .font(.wvOverline)
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if store.totals.sessionCount > 0 {
                    Button("Reset") { store.reset() }
                        .buttonStyle(.wvGhost(role: .destructive))
                }
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                spacing: 12
            ) {
                statTile(title: "Words dictated", value: store.totals.totalWords.formatted(), icon: "text.word.spacing")
                statTile(title: "Speaking time", value: speakingTime, icon: "clock")
                statTile(title: "Dictations", value: store.totals.sessionCount.formatted(), icon: "mic")
                statTile(title: "Average pace", value: averagePace, icon: "speedometer")
            }
        }
    }

    private var speakingTime: String {
        let seconds = Int(store.totals.totalSpeakingSeconds.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(rest)s" }
        return "\(rest)s"
    }

    private var averagePace: String {
        let pace = store.totals.averageWordsPerMinute
        guard pace > 0 else { return "—" }
        return "\(Int(pace.rounded())) wpm"
    }

    private func statTile(title: String, value: String, icon: String) -> some View {
        WVCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(title)
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(value)
                    .font(.wv(26, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
        }
    }
}
