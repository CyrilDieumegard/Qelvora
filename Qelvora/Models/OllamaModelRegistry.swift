import Foundation

final class OllamaModelRegistry {
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

    func installedModels() async throws -> [String] {
        let url = baseURL.appending(path: "api/tags")
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CorrectionEngineError.ollamaUnavailable
        }

        let decoded = try decoder.decode(OllamaTagsResponse.self, from: data)
        return decoded.models
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func pull(model: LocalModel) async throws {
        let url = baseURL.appending(path: "api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 1_800
        request.httpBody = try encoder.encode(OllamaPullRequest(name: model.name, stream: false))

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            if let decoded = try? decoder.decode(OllamaPullResponse.self, from: data),
               let error = decoded.error {
                throw CorrectionEngineError.ollamaError(error)
            }

            throw CorrectionEngineError.ollamaUnavailable
        }

        if let decoded = try? decoder.decode(OllamaPullResponse.self, from: data),
           let error = decoded.error {
            throw CorrectionEngineError.ollamaError(error)
        }
    }
}
