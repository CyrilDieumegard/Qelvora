import Foundation

enum TranslationLanguage: String, CaseIterable, Identifiable, Codable {
    case english
    case french
    case spanish
    case german
    case italian
    case chinese
    case japanese

    var id: String {
        rawValue
    }

    var flag: String {
        switch self {
        case .english:
            return "🇬🇧"
        case .french:
            return "🇫🇷"
        case .spanish:
            return "🇪🇸"
        case .german:
            return "🇩🇪"
        case .italian:
            return "🇮🇹"
        case .chinese:
            return "🇨🇳"
        case .japanese:
            return "🇯🇵"
        }
    }

    var code: String {
        switch self {
        case .english:
            return "EN"
        case .french:
            return "FR"
        case .spanish:
            return "ES"
        case .german:
            return "DE"
        case .italian:
            return "IT"
        case .chinese:
            return "ZH"
        case .japanese:
            return "JA"
        }
    }

    var promptName: String {
        switch self {
        case .english:
            return "English"
        case .french:
            return "French"
        case .spanish:
            return "Spanish"
        case .german:
            return "German"
        case .italian:
            return "Italian"
        case .chinese:
            return "Chinese"
        case .japanese:
            return "Japanese"
        }
    }
}
