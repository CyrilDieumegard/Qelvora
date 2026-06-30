import Foundation

struct CorrectionHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let mode: CorrectionMode
    let sourceText: String
    let correctedText: String
    let wordCount: Int
    let correctionCount: Int

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        mode: CorrectionMode,
        sourceText: String,
        correctedText: String,
        analysis: CorrectionAnalysis
    ) {
        self.id = id
        self.date = date
        self.mode = mode
        self.sourceText = sourceText
        self.correctedText = correctedText
        self.wordCount = analysis.wordCount
        self.correctionCount = analysis.correctionCount
    }
}

final class CorrectionHistoryStore {
    private let userDefaults: UserDefaults
    private let key = "correctionHistoryItems"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let limit = 20

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> [CorrectionHistoryItem] {
        guard let data = userDefaults.data(forKey: key),
              let items = try? decoder.decode([CorrectionHistoryItem].self, from: data) else {
            return []
        }

        return items
    }

    func save(_ items: [CorrectionHistoryItem]) {
        let limitedItems = Array(items.prefix(limit))
        guard let data = try? encoder.encode(limitedItems) else {
            return
        }

        userDefaults.set(data, forKey: key)
    }

    func clear() {
        userDefaults.removeObject(forKey: key)
    }
}
