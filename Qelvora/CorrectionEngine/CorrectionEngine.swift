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
    case ollamaModelMissing(String)
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
            return "Ollama is required. Install and launch Ollama, then try again."
        case .ollamaModelMissing(let modelName):
            return "\(modelName) is not installed in Ollama. Download the model from Qelvora settings first."
        case .ollamaError(let message):
            return message
        }
    }
}
