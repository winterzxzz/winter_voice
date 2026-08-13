import SwiftUI

struct StatisticsView: View {
    @ObservedObject var store: UsageStatsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Statistics")
                        .font(.largeTitle)
                    Text("Local usage totals for successful dictations. Nothing leaves this Mac.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 16)],
                    spacing: 16
                ) {
                    statTile(
                        title: "Words dictated",
                        value: store.totals.totalWords.formatted(),
                        icon: "text.word.spacing"
                    )
                    statTile(
                        title: "Speaking time",
                        value: speakingTime,
                        icon: "clock"
                    )
                    statTile(
                        title: "Dictations",
                        value: store.totals.sessionCount.formatted(),
                        icon: "mic"
                    )
                    statTile(
                        title: "Average pace",
                        value: averagePace,
                        icon: "speedometer"
                    )
                }

                if store.totals.sessionCount > 0 {
                    Button("Reset Statistics", role: .destructive) {
                        store.reset()
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(32)
        }
        .navigationTitle("Statistics")
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
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
