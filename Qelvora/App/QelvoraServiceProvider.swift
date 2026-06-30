import AppKit
import Foundation

@objc final class QelvoraServiceProvider: NSObject {
    private let correctionEngine: CorrectionEngine
    private let userDefaults: UserDefaults
    private let selectedModelKey = "selectedModelName"

    init(
        correctionEngine: CorrectionEngine = OllamaEngine(),
        userDefaults: UserDefaults = .standard
    ) {
        self.correctionEngine = correctionEngine
        self.userDefaults = userDefaults
    }

    @objc(showCorrectionPanel:userData:error:)
    func showCorrectionPanel(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let selectedText = selectedText(from: pasteboard) else {
            error.pointee = "No text selected." as NSString
            return
        }

        startVisibleCorrection(for: selectedText)
    }

    @objc(correctSelection:userData:error:)
    func correctSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let selectedText = selectedText(from: pasteboard) else {
            error.pointee = "No text selected." as NSString
            return
        }

        do {
            let correctedText = try correctSynchronously(text: selectedText)
            pasteboard.clearContents()
            pasteboard.setString(correctedText, forType: .string)
        } catch let correctionError {
            error.pointee = correctionError.localizedDescription as NSString
        }
    }

    private func startVisibleCorrection(for text: String) {
        let modelName = selectedModelName

        Task { @MainActor in
            await correctAndShow(text: text, modelName: modelName)
        }
    }

    @MainActor
    private func correctAndShow(text: String, modelName: String) async {
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sourceText.isEmpty else {
            return
        }

        CorrectionResultPanel.showLoading(sourceText: sourceText)

        do {
            let correctedText = try await correctionEngine.correct(
                text: sourceText,
                model: modelName,
                mode: .correction
            )
            showResult(correctedText: correctedText, sourceText: sourceText, modelName: modelName)
        } catch {
            CorrectionResultPanel.showComposer(
                initialText: sourceText,
                message: error.localizedDescription,
                onCorrect: { [weak self] newText in
                    self?.startVisibleCorrection(for: newText)
                }
            )
            NSSound.beep()
        }
    }

    @MainActor
    private func showResult(
        correctedText: String,
        sourceText: String,
        modelName: String,
        translatedFrom language: TranslationLanguage? = nil
    ) {
        CorrectionResultPanel.show(
            correctedText: correctedText,
            sourceText: sourceText,
            translatedFrom: language,
            onTranslate: { [weak self] text, language in
                Task { @MainActor in
                    await self?.translateAndShow(
                        text: text,
                        sourceText: sourceText,
                        modelName: modelName,
                        targetLanguage: language
                    )
                }
            }
        )
    }

    @MainActor
    private func translateAndShow(
        text: String,
        sourceText: String,
        modelName: String,
        targetLanguage: TranslationLanguage
    ) async {
        do {
            let translatedText = try await correctionEngine.translate(
                text: text,
                model: modelName,
                targetLanguage: targetLanguage
            )
            showResult(
                correctedText: translatedText,
                sourceText: sourceText,
                modelName: modelName,
                translatedFrom: targetLanguage
            )
        } catch {
            CorrectionResultPanel.showComposer(
                initialText: text,
                message: error.localizedDescription,
                onCorrect: { [weak self] newText in
                    self?.startVisibleCorrection(for: newText)
                }
            )
            NSSound.beep()
        }
    }

    private func selectedText(from pasteboard: NSPasteboard) -> String? {
        let stringTypes: [NSPasteboard.PasteboardType] = [
            .string,
            NSPasteboard.PasteboardType("NSStringPboardType"),
            NSPasteboard.PasteboardType("public.utf8-plain-text"),
            NSPasteboard.PasteboardType("public.plain-text"),
            NSPasteboard.PasteboardType("public.text")
        ]

        for type in stringTypes {
            guard let text = pasteboard.string(forType: type),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            return text
        }

        return nil
    }

    private func correctSynchronously(text: String) throws -> String {
        let semaphore = DispatchSemaphore(value: 0)
        let resultQueue = DispatchQueue(label: "io.qelvora.service-provider.result")
        var result: Result<String, Error>?
        let modelName = selectedModelName

        Task.detached { [correctionEngine] in
            let correctionResult: Result<String, Error>

            do {
                let correctedText = try await correctionEngine.correct(
                    text: text,
                    model: modelName,
                    mode: .correction
                )
                correctionResult = .success(correctedText)
            } catch {
                correctionResult = .failure(error)
            }

            resultQueue.sync {
                result = correctionResult
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 115) == .timedOut {
            throw ServiceError.timeout
        }

        let correctionResult = resultQueue.sync {
            result
        }

        guard let correctionResult else {
            throw ServiceError.noResult
        }

        return try correctionResult.get()
    }

    private var selectedModelName: String {
        if let storedModel = userDefaults.string(forKey: selectedModelKey),
           !storedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storedModel
        }

        return ModelManager.preferredModelName(for: .current)
            ?? ModelManager.models(for: .current).first?.name
            ?? "qwen2.5:3b"
    }
}

private enum ServiceError: LocalizedError {
    case timeout
    case noResult

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Qelvora took too long to correct the text."
        case .noResult:
            return "Qelvora did not return a correction."
        }
    }
}
