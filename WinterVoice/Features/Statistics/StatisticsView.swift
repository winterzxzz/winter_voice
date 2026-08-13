import SwiftUI

struct StatisticsView: View {
    @ObservedObject var store: UsageStatsStore

    var body: some View {
        WVPage(
            icon: "chart.bar.xaxis",
            title: "Statistics",
            subtitle: "Local usage totals for successful dictations. Nothing leaves this Mac."
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200), spacing: 14)],
                spacing: 14
            ) {
                statTile(title: "Words dictated", value: store.totals.totalWords.formatted(), icon: "text.word.spacing")
                statTile(title: "Speaking time", value: speakingTime, icon: "clock")
                statTile(title: "Dictations", value: store.totals.sessionCount.formatted(), icon: "mic")
                statTile(title: "Average pace", value: averagePace, icon: "speedometer")
            }

            if store.totals.sessionCount > 0 {
                Button("Reset Statistics", role: .destructive) { store.reset() }
                    .buttonStyle(.wvSecondary(role: .destructive))
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.wvCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
        }
    }
}
