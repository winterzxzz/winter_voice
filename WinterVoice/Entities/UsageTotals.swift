import Foundation

struct UsageTotals: Codable, Equatable, Sendable {
    var totalWords: Int = 0
    var totalSpeakingSeconds: Double = 0
    var sessionCount: Int = 0

    var averageWordsPerMinute: Double {
        guard totalSpeakingSeconds > 0 else { return 0 }
        return Double(totalWords) / (totalSpeakingSeconds / 60)
    }
}
