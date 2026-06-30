import Foundation

protocol CorrectionEngine {
    func correct(text: String, model: String, mode: CorrectionMode) async throws -> String
    func translate(text: String, model: String, targetLanguage: TranslationLanguage) async throws -> String
}

enum CorrectionEngineError: LocalizedError, Equatable {
    case emptyInput
    case invalidResponse
    case implausibleCorrection
    case ollamaUnavailable
    case ollamaError(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "The text to correct is empty."
        case .invalidResponse:
            return "Ollama returned an invalid response."
        case .implausibleCorrection:
            return "Correction ignored: the model response was inconsistent."
        case .ollamaUnavailable:
            return "Ollama is not responding on localhost:11434."
        case .ollamaError(let message):
            return message
        }
    }
}
