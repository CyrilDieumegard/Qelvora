import AppKit
import Foundation

@MainActor
final class CorrectionCoordinator: ObservableObject {
    @Published private(set) var status: CorrectionStatus = .idle
    @Published private(set) var isProcessing = false
    @Published var selectedMode: CorrectionMode = .correction
    @Published private(set) var historyItems: [CorrectionHistoryItem]

    private let textCapture: TextCaptureServiceProtocol
    private let correctionEngine: CorrectionEngine
    private let modelManager: ModelManager
    private let historyStore: CorrectionHistoryStore
    private var completionResetTask: Task<Void, Never>?

    init(
        textCapture: TextCaptureServiceProtocol,
        correctionEngine: CorrectionEngine,
        modelManager: ModelManager,
        historyStore: CorrectionHistoryStore = CorrectionHistoryStore()
    ) {
        self.textCapture = textCapture
        self.correctionEngine = correctionEngine
        self.modelManager = modelManager
        self.historyStore = historyStore
        self.historyItems = historyStore.load()
    }

    func correctSelection() async {
        guard !isProcessing else {
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        var keepCorrectionPanelOnError = false

        do {
            CorrectionResultPanel.hide()
            FeedbackBanner.hide()
            try? await Task.sleep(nanoseconds: 120_000_000)

            status = .capturing
            let capturedText = try await textCapture.captureSelectedText()

            status = .correcting
            CorrectionResultPanel.showLoading(sourceText: capturedText.text)
            let correctedText = try await correctionEngine.correct(
                text: capturedText.text,
                model: modelManager.selectedModelName,
                mode: selectedMode
            )
            showResult(correctedText: correctedText, sourceText: capturedText.text)
            rememberCorrection(sourceText: capturedText.text, correctedText: correctedText, mode: selectedMode)
            keepCorrectionPanelOnError = true

            status = .pasting
            try await textCapture.replaceSelection(with: correctedText)

            markCompleted(feedback: "Text corrected")
        } catch TextCaptureError.noSelection {
            if !keepCorrectionPanelOnError {
                showComposer()
            }
            status = .noSelection
            FeedbackBanner.show("No selection: editor opened")
        } catch TextCaptureError.selectionNotDetected(let message) {
            if !keepCorrectionPanelOnError {
                showComposer()
            }
            status = .noSelection
            FeedbackBanner.show("\(message). Editor opened")
        } catch TextCaptureError.accessibilityPermissionMissing {
            if !keepCorrectionPanelOnError {
                CorrectionResultPanel.hide()
            }
            status = .missingAccessibility
            FeedbackBanner.show("Keyboard access denied by macOS")
            NSSound.beep()
        } catch TextCaptureError.screenCapturePermissionMissing {
            if !keepCorrectionPanelOnError {
                CorrectionResultPanel.hide()
            }
            status = .failed("Screen Recording permission required")
            FeedbackBanner.show("Allow Screen Recording for this app")
            NSSound.beep()
        } catch {
            if !keepCorrectionPanelOnError {
                CorrectionResultPanel.hide()
            }
            status = .failed(error.localizedDescription)
            FeedbackBanner.show(error.localizedDescription)
            NSSound.beep()
        }
    }

    func showComposer(initialText: String = "", message: String? = nil) {
        CorrectionResultPanel.showComposer(
            initialText: initialText,
            message: message,
            selectedMode: selectedMode,
            onModeChange: { [weak self] mode in
                self?.selectedMode = mode
            },
            onCorrect: { [weak self] text in
                Task { @MainActor in
                    await self?.correctTypedText(text)
                }
            }
        )
    }

    func correctTypedText(_ text: String) async {
        await correctTypedText(text, mode: selectedMode)
    }

    func correctTypedText(_ text: String, mode: CorrectionMode) async {
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sourceText.isEmpty else {
            showComposer(initialText: text, message: "Enter text to correct.")
            return
        }

        guard !isProcessing else {
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            status = .correcting
            CorrectionResultPanel.showLoading(sourceText: sourceText)

            let correctedText = try await correctionEngine.correct(
                text: sourceText,
                model: modelManager.selectedModelName,
                mode: mode
            )

            showResult(correctedText: correctedText, sourceText: sourceText)
            rememberCorrection(sourceText: sourceText, correctedText: correctedText, mode: mode)
            markCompleted(feedback: "Correction ready")
        } catch {
            status = .failed(error.localizedDescription)
            showComposer(initialText: text, message: error.localizedDescription)
            FeedbackBanner.show(error.localizedDescription)
            NSSound.beep()
        }
    }

    func clearHistory() {
        historyItems = []
        historyStore.clear()
    }

    private func rememberCorrection(sourceText: String, correctedText: String, mode: CorrectionMode) {
        let analysis = CorrectionAnalysis(sourceText: sourceText, correctedText: correctedText)
        let item = CorrectionHistoryItem(
            mode: mode,
            sourceText: sourceText,
            correctedText: correctedText,
            analysis: analysis
        )

        historyItems = Array(([item] + historyItems).prefix(20))
        historyStore.save(historyItems)
    }

    private func showResult(
        correctedText: String,
        sourceText: String,
        translatedFrom language: TranslationLanguage? = nil
    ) {
        CorrectionResultPanel.show(
            correctedText: correctedText,
            sourceText: sourceText,
            translatedFrom: language,
            onTranslate: { [weak self] text, language in
                Task { @MainActor in
                    await self?.translateDisplayedText(text, originalSourceText: sourceText, targetLanguage: language)
                }
            }
        )
    }

    private func translateDisplayedText(
        _ text: String,
        originalSourceText: String,
        targetLanguage: TranslationLanguage
    ) async {
        guard !isProcessing else {
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            status = .correcting
            let translatedText = try await correctionEngine.translate(
                text: text,
                model: modelManager.selectedModelName,
                targetLanguage: targetLanguage
            )
            showResult(
                correctedText: translatedText,
                sourceText: originalSourceText,
                translatedFrom: targetLanguage
            )
            markCompleted(feedback: "Translation ready")
        } catch {
            status = .failed(error.localizedDescription)
            FeedbackBanner.show(error.localizedDescription)
            NSSound.beep()
        }
    }

    private func markCompleted(feedback: String) {
        status = .completed
        FeedbackBanner.show(feedback)
        completionResetTask?.cancel()
        completionResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if self.status == .completed {
                self.status = .idle
            }
        }
    }
}

@MainActor
private enum FeedbackBanner {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String) {
        hideTask?.cancel()

        let width: CGFloat = 420
        let height: CGFloat = 56
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screenFrame.maxX - width - 24,
            y: screenFrame.maxY - height - 24
        )

        let contentView = NSVisualEffectView(frame: NSRect(origin: .zero, size: CGSize(width: width, height: height)))
        contentView.material = .hudWindow
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail

        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        let newPanel = NSPanel(
            contentRect: NSRect(origin: origin, size: CGSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.contentView = contentView
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.ignoresMouseEvents = true
        newPanel.level = .statusBar
        newPanel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        panel?.orderOut(nil)
        panel = newPanel
        newPanel.orderFrontRegardless()

        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                hide()
            }
        }
    }

    static func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }
}
