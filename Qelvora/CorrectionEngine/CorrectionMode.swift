import Foundation

enum CorrectionMode: String, CaseIterable, Identifiable, Codable {
    case correction
    case professional
    case natural
    case concise
    case playful

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .correction:
            return "Correct"
        case .professional:
            return "More professional"
        case .natural:
            return "More natural"
        case .concise:
            return "Shorter"
        case .playful:
            return "More playful"
        }
    }

    var systemImage: String {
        switch self {
        case .correction:
            return "wand.and.stars"
        case .professional:
            return "briefcase"
        case .natural:
            return "text.bubble"
        case .concise:
            return "scissors"
        case .playful:
            return "sparkles"
        }
    }

    var description: String {
        switch self {
        case .correction:
            return "Fix spelling and grammar without changing the tone."
        case .professional:
            return "Clearer, calmer, and better suited for work."
        case .natural:
            return "Fluid, human, and close to real conversation."
        case .concise:
            return "Shorten the text without losing meaning."
        case .playful:
            return "More lively, light, and energetic."
        }
    }
}
