import Foundation

struct StatsEntry: Codable {
    var date: Date
    var words: Int
    var speakingSeconds: Double
}

/// Tracks dictated words and speaking time; computes time saved vs. typing.
@MainActor
final class StatsStore: ObservableObject {
    private static let key = "stats.entries"

    @Published private(set) var entries: [StatsEntry] = []

    /// Assumed typing speed in words per minute (user-adjustable in settings).
    var typingWordsPerMinute: Double {
        get { max(UserDefaults.standard.double(forKey: "stats.typingWPM"), 1) }
        set { UserDefaults.standard.set(newValue, forKey: "stats.typingWPM") }
    }

    init() {
        if UserDefaults.standard.object(forKey: "stats.typingWPM") == nil {
            UserDefaults.standard.set(40.0, forKey: "stats.typingWPM")
        }
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([StatsEntry].self, from: data) {
            entries = decoded
        }
    }

    func record(words: Int, speakingSeconds: Double) {
        entries.append(StatsEntry(date: .now, words: words, speakingSeconds: speakingSeconds))
        persist()
    }

    struct Summary {
        var words: Int
        var speakingSeconds: Double
        var savedSeconds: Double
    }

    func summary(since cutoff: Date) -> Summary {
        let slice = entries.filter { $0.date >= cutoff }
        let words = slice.reduce(0) { $0 + $1.words }
        let speaking = slice.reduce(0.0) { $0 + $1.speakingSeconds }
        let typingSeconds = Double(words) / typingWordsPerMinute * 60.0
        return Summary(words: words,
                       speakingSeconds: speaking,
                       savedSeconds: max(typingSeconds - speaking, 0))
    }

    var today: Summary { summary(since: Calendar.current.startOfDay(for: .now)) }
    var thisWeek: Summary {
        summary(since: Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now)
    }
    var thisMonth: Summary {
        summary(since: Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
