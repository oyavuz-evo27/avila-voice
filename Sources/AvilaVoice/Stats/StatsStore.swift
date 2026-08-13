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
    /// An undecodable history blob is parked here instead of being overwritten.
    private static let backupKey = "stats.entries.backup"
    /// Keep ~13 months — enough for every summary view.
    static let retentionDays = 400

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
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { return }
        if let decoded = try? JSONDecoder().decode([StatsEntry].self, from: data) {
            // Pruned in memory only — the next record() persists the trimmed state,
            // so app launch never pays an extra encode + write.
            entries = Self.pruned(decoded)
        } else {
            // Never let the next save overwrite a possibly repairable blob.
            UserDefaults.standard.set(data, forKey: Self.backupKey)
            NSLog("AvilaVoice: stats history was undecodable — parked under \(Self.backupKey)")
        }
    }

    func record(words: Int, speakingSeconds: Double) {
        entries.append(StatsEntry(date: .now, words: words, speakingSeconds: speakingSeconds))
        entries = Self.pruned(entries)
        persist()
    }

    /// Drops entries older than `retentionDays`, measured from the NEWEST entry rather
    /// than the wall clock — a wrongly future-set system clock can therefore never
    /// wipe real history.
    private static func pruned(_ entries: [StatsEntry]) -> [StatsEntry] {
        guard let newest = entries.map(\.date).max(),
              let cutoff = Calendar.current.date(byAdding: .day,
                                                 value: -retentionDays,
                                                 to: newest) else { return entries }
        return entries.filter { $0.date >= cutoff }
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
        } else {
            NSLog("AvilaVoice: could not encode stats entries — keeping previous data on disk")
        }
    }
}
