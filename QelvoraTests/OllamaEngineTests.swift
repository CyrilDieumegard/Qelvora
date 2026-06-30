import Foundation
import XCTest
@testable import Qelvora

final class OllamaEngineTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testCorrectSendsNonStreamingPromptToOllama() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/generate")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try Self.bodyData(for: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

            XCTAssertEqual(json?["model"] as? String, "qwen2.5:3b")
            XCTAssertNil(json?["think"])
            let prompt = try XCTUnwrap(json?["prompt"] as? String)
            XCTAssertTrue(prompt.contains("je sui ici"))
            XCTAssertTrue(prompt.contains("<text>"))
            XCTAssertTrue(prompt.contains("</text>"))
            XCTAssertEqual(json?["stream"] as? Bool, false)
            XCTAssertEqual(json?["keep_alive"] as? String, "15m")
            XCTAssertNotNil(json?["system"] as? String)

            let options = try XCTUnwrap(json?["options"] as? [String: Any])
            XCTAssertEqual(options["temperature"] as? Double, 0)
            XCTAssertNotNil(options["num_predict"] as? Int)
            XCTAssertEqual(options["num_ctx"] as? Int, 2_048)

            let data = #"{"response":"je suis ici","done":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let engine = OllamaEngine(baseURL: URL(string: "http://ollama.test")!, session: makeMockSession())
        let corrected = try await engine.correct(text: "je sui ici", model: "qwen2.5:3b")

        XCTAssertEqual(corrected, "je suis ici")
    }

    func testCorrectDisablesThinkingForGemma4() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = try Self.bodyData(for: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

            XCTAssertEqual(json?["model"] as? String, "gemma4:e4b")
            XCTAssertEqual(json?["think"] as? Bool, false)

            let data = #"{"response":"Bon, je vais écrire un texte.","done":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let engine = OllamaEngine(baseURL: URL(string: "http://ollama.test")!, session: makeMockSession())
        let corrected = try await engine.correct(text: "Bon je vais aycrir un text.", model: "gemma4:e4b")

        XCTAssertEqual(corrected, "Bon, je vais écrire un texte.")
    }

    func testCorrectSendsModeSpecificPrompt() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = try Self.bodyData(for: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

            let prompt = try XCTUnwrap(json?["prompt"] as? String)
            let system = try XCTUnwrap(json?["system"] as? String)
            let options = try XCTUnwrap(json?["options"] as? [String: Any])

            XCTAssertTrue(prompt.contains(#""More professional" mode"#))
            XCTAssertTrue(system.contains("More professional mode"))
            XCTAssertTrue(system.contains("professional"))
            XCTAssertEqual(options["temperature"] as? Double, 0.15)

            let data = #"{"response":"Je vous remercie pour votre retour.","done":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let engine = OllamaEngine(baseURL: URL(string: "http://ollama.test")!, session: makeMockSession())
        let corrected = try await engine.correct(
            text: "merci pour ton retour",
            model: "qwen2.5:3b",
            mode: .professional
        )

        XCTAssertEqual(corrected, "Je vous remercie pour votre retour.")
    }

    func testTranslateSendsTargetLanguagePrompt() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = try Self.bodyData(for: request)
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]

            let prompt = try XCTUnwrap(json?["prompt"] as? String)
            let system = try XCTUnwrap(json?["system"] as? String)
            let options = try XCTUnwrap(json?["options"] as? [String: Any])

            XCTAssertTrue(prompt.contains("Translate only the text"))
            XCTAssertTrue(prompt.contains("Japanese"))
            XCTAssertTrue(system.contains("Translate the provided text into Japanese"))
            XCTAssertTrue(system.contains("Preserve text structure exactly"))
            XCTAssertEqual(options["temperature"] as? Double, 0.1)

            let data = #"{"response":"こんにちは、チーム。","done":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let engine = OllamaEngine(baseURL: URL(string: "http://ollama.test")!, session: makeMockSession())
        let translated = try await engine.translate(
            text: "Bonjour l'équipe.",
            model: "gemma4:e4b",
            targetLanguage: .japanese
        )

        XCTAssertEqual(translated, "こんにちは、チーム。")
        XCTAssertEqual(TranslationLanguage.chinese.code, "ZH")
        XCTAssertEqual(TranslationLanguage.japanese.code, "JA")
    }

    func testCorrectRejectsImplausiblyShortCorrectionForLongInput() async throws {
        MockURLProtocol.requestHandler = { request in
            let data = #"{"response":"2","done":true}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let engine = OllamaEngine(baseURL: URL(string: "http://ollama.test")!, session: makeMockSession())

        do {
            _ = try await engine.correct(
                text: "Bon je vais aycrir un text pourri mochess avec pleins de faute et voir si mon outi arrive a ccorigger",
                model: "qwen2.5:3b"
            )
            XCTFail("Expected an implausible correction error")
        } catch let error as CorrectionEngineError {
            XCTAssertEqual(error, .implausibleCorrection)
        }
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func bodyData(for request: URLRequest) throws -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }

        guard let bodyStream = request.httpBodyStream else {
            return Data()
        }

        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)

        while bodyStream.hasBytesAvailable {
            let count = bodyStream.read(&buffer, maxLength: buffer.count)

            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        return data
    }
}

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            XCTFail("Request handler is missing")
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
