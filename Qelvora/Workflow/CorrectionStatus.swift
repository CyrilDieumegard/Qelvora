import Foundation

enum CorrectionStatus: Equatable {
    case idle
    case capturing
    case correcting
    case pasting
    case noSelection
    case missingAccessibility
    case completed
    case failed(String)

    var menuTitle: String {
        switch self {
        case .idle:
            return "Ready"
        case .capturing:
            return "Reading selection..."
        case .correcting:
            return "Correcting..."
        case .pasting:
            return "Replacing..."
        case .noSelection:
            return "No text selected"
        case .missingAccessibility:
            return "Accessibility permission required"
        case .completed:
            return "Ready"
        case .failed(let message):
            return message
        }
    }

    var systemImageName: String {
        switch self {
        case .idle, .completed:
            return "checkmark.circle"
        case .capturing:
            return "doc.on.clipboard"
        case .correcting:
            return "wand.and.stars"
        case .pasting:
            return "arrow.down.doc"
        case .noSelection:
            return "selection.pin.in.out"
        case .missingAccessibility, .failed:
            return "exclamationmark.triangle"
        }
    }
}
