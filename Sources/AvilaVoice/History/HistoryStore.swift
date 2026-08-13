import Foundation

struct DictationRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date = .now
    var rawTranscript: String
    var finalText: String
    var modeName: String
    var wasInserted: Bool
    var durationSeconds: Double
}

/// Keeps the last few dictations (raw + result), stored locally in UserDefaults.
@MainActor
final class HistoryStore: ObservableObject {
    static let maxEntries = 5
    private static let key = "history.records"

    @Published private(set) var records: [DictationRecord] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([DictationRecord].self, from: data) {
            records = decoded
        }
    }

    var last: DictationRecord? { records.first }

    func add(_ record: DictationRecord) {
        records.insert(record, at: 0)
        if records.count > Self.maxEntries {
            records = Array(records.prefix(Self.maxEntries))
        }
        persist()
    }

    func clear() {
        records = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
