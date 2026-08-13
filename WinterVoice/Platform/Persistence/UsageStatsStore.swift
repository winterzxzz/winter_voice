import Combine
import Foundation

@MainActor
final class UsageStatsStore: ObservableObject, UsageRecording {
    @Published private(set) var totals: UsageTotals

    private static let key = "usage.totals"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        totals = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(UsageTotals.self, from: $0) }
            ?? UsageTotals()
    }

    func recordSession(words: Int, speakingSeconds: Double) {
        totals.totalWords += max(0, words)
        totals.totalSpeakingSeconds += max(0, speakingSeconds)
        totals.sessionCount += 1
        persist()
    }

    func reset() {
        totals = UsageTotals()
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(totals), forKey: Self.key)
    }
}
