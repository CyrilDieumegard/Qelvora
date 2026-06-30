import Foundation

struct OllamaGenerateRequest: Encodable {
    let model: String
    let think: Bool?
    let system: String
    let prompt: String
    let stream: Bool
    let options: OllamaOptions
    let keepAlive: String

    enum CodingKeys: String, CodingKey {
        case model
        case think
        case system
        case prompt
        case stream
        case options
        case keepAlive = "keep_alive"
    }
}

struct OllamaOptions: Encodable {
    let temperature: Double
    let topP: Double
    let numPredict: Int
    let numCtx: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case numPredict = "num_predict"
        case numCtx = "num_ctx"
    }
}

struct OllamaGenerateResponse: Decodable {
    let response: String?
    let done: Bool?
    let error: String?
}

struct OllamaTagsResponse: Decodable {
    let models: [OllamaTagModel]
}

struct OllamaTagModel: Decodable {
    let name: String
}

struct OllamaPullRequest: Encodable {
    let name: String
    let stream: Bool
}

struct OllamaPullResponse: Decodable {
    let status: String?
    let error: String?
}
