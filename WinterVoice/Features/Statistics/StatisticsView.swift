import SwiftUI

/// Local usage totals rendered as the reference stats strip — one bordered
/// container split into four cells by hairlines, shown on the Home screen.
struct UsageStatsSection: View {
    @ObservedObject var store: UsageStatsStore

    var body: some View {
        HStack(spacing: 0) {
            statCell(label: "Words", value: store.totals.totalWords.formatted(), icon: "bolt")
            cellDivider
            statCell(label: "Speaking time", value: speakingTime, icon: "clock")
            cellDivider
            statCell(label: "Recordings", value: store.totals.sessionCount.formatted(), icon: "mic")
            cellDivider
            statCell(label: "Avg pace", value: averagePace, icon: "waveform")
        }
        .wvSurface(in: shape, fill: Theme.surface, border: Theme.border)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
    }

    private var cellDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1)
            .padding(.vertical, 10)
    }

    private var speakingTime: String {
        let seconds = Int(store.totals.totalSpeakingSeconds.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(rest)s"
    }

    private var averagePace: String {
        let pace = store.totals.averageWordsPerMinute
        guard pace > 0 else { return "—" }
        return "\(Int(pace.rounded())) wpm"
    }

    private func statCell(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(label.uppercased())
                    .font(.wvOverline)
                    .tracking(0.7)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.wv(21, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
