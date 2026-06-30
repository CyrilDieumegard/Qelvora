import Foundation

final class OllamaEngine: CorrectionEngine {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        session: URLSession = .shared,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = encoder
        self.decoder = decoder
    }

    func correct(text: String, model: String, mode: CorrectionMode = .correction) async throws -> String {
        try await generate(
            text: text,
            model: model,
            system: CorrectionPrompt.system(mode: mode),
            prompt: CorrectionPrompt.user(text: text, mode: mode),
            temperature: temperature(for: mode),
            validateAgainstOriginal: true
        )
    }

    func translate(text: String, model: String, targetLanguage: TranslationLanguage) async throws -> String {
        try await generate(
            text: text,
            model: model,
            system: CorrectionPrompt.translationSystem(targetLanguage: targetLanguage),
            prompt: CorrectionPrompt.translationUser(text: text, targetLanguage: targetLanguage),
            temperature: 0.1,
            validateAgainstOriginal: false
        )
    }

    private func generate(
        text: String,
        model: String,
        system: String,
        prompt: String,
        temperature: Double,
        validateAgainstOriginal: Bool
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CorrectionEngineError.emptyInput
        }

        let url = baseURL.appending(path: "api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try encoder.encode(
            OllamaGenerateRequest(
                model: model,
                think: shouldDisableThinking(for: model) ? false : nil,
                system: system,
                prompt: prompt,
                stream: false,
                options: OllamaOptions(
                    temperature: temperature,
                    topP: 0.85,
                    numPredict: maxPredictionTokens(for: text),
                    numCtx: 2_048
                ),
                keepAlive: "15m"
            )
        )

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CorrectionEngineError.ollamaUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CorrectionEngineError.invalidResponse
        }

        let decodedResponse = try? decoder.decode(OllamaGenerateResponse.self, from: data)

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let message = decodedResponse?.error {
                throw CorrectionEngineError.ollamaError(message)
            }
            throw CorrectionEngineError.invalidResponse
        }

        if let error = decodedResponse?.error {
            throw CorrectionEngineError.ollamaError(error)
        }

        guard let correctedText = decodedResponse?.response else {
            throw CorrectionEngineError.invalidResponse
        }

        let cleanedText = cleanedCorrection(correctedText)
        guard !validateAgainstOriginal || isPlausibleCorrection(cleanedText, for: text) else {
            throw CorrectionEngineError.implausibleCorrection
        }

        return cleanedText
    }

    private func maxPredictionTokens(for text: String) -> Int {
        min(max(256, text.count + 128), 4_096)
    }

    private func temperature(for mode: CorrectionMode) -> Double {
        switch mode {
        case .correction:
            return 0
        case .professional, .concise:
            return 0.15
        case .natural:
            return 0.25
        case .playful:
            return 0.35
        }
    }

    private func shouldDisableThinking(for model: String) -> Bool {
        model.lowercased().hasPrefix("gemma4")
    }

    private func cleanedCorrection(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let removablePrefixes = [
            "J’ai corrigé :",
            "J’ai corrigé:",
            "J'ai corrigé :",
            "J'ai corrigé:",
            "Voici le texte corrigé :",
            "Voici le texte corrigé:",
            "Texte corrigé :",
            "Texte corrigé:",
            "Correction :",
            "Correction:"
        ]

        for prefix in removablePrefixes where cleaned.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
            cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        if cleaned.count >= 2,
           let first = cleaned.first,
           let last = cleaned.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    private func isPlausibleCorrection(_ correctedText: String, for originalText: String) -> Bool {
        let originalCount = originalText.alphanumericCount
        let correctedCount = correctedText.alphanumericCount

        guard originalCount >= 24 else {
            return correctedCount > 0
        }

        return correctedCount >= max(3, originalCount / 3)
    }
}

private extension String {
    var alphanumericCount: Int {
        filter { $0.isLetter || $0.isNumber }.count
    }
}
