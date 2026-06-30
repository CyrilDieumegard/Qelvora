import AppKit
import SwiftUI

@MainActor
enum CorrectionResultPanel {
    private static var panel: NSPanel?

    static func showLoading(sourceText: String) {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        show(state: .loading(sourceText: text))
    }

    static func show(
        correctedText: String,
        sourceText: String? = nil,
        translatedFrom language: TranslationLanguage? = nil,
        onTranslate: ((String, TranslationLanguage) -> Void)? = nil
    ) {
        let text = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        show(
            state: .ready(
                correctedText: text,
                sourceText: sourceText?.trimmingCharacters(in: .whitespacesAndNewlines),
                analysis: CorrectionAnalysis(sourceText: sourceText, correctedText: text),
                translatedFrom: language,
                onTranslate: onTranslate
            )
        )
    }

    static func showComposer(
        initialText: String = "",
        message: String? = nil,
        selectedMode: CorrectionMode = .correction,
        onModeChange: @escaping (CorrectionMode) -> Void = { _ in },
        onCorrect: @escaping (String) -> Void
    ) {
        show(
            state: .composing(
                initialText: initialText,
                message: message,
                selectedMode: selectedMode,
                onModeChange: onModeChange,
                onCorrect: onCorrect
            )
        )
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private static func show(state: CorrectionResultPanelState) {
        let width: CGFloat = 640
        let height = state.height
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height - 16
        )

        let contentView = NSHostingView(
            rootView: CorrectionResultPanelView(
                state: state,
                onClose: {
                    hide()
                }
            )
            .frame(width: width, height: height)
        )
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.masksToBounds = true

        let styleMask: NSWindow.StyleMask = state.needsKeyboardInput
            ? [.borderless]
            : [.borderless, .nonactivatingPanel]
        let newPanel = ClickablePanel(
            contentRect: NSRect(origin: origin, size: CGSize(width: width, height: height)),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        newPanel.contentView = contentView
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.level = .statusBar
        newPanel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        newPanel.isReleasedWhenClosed = false

        panel?.orderOut(nil)
        panel = newPanel

        if state.needsKeyboardInput {
            NSApp.activate(ignoringOtherApps: true)
            newPanel.makeKeyAndOrderFront(nil)
        } else {
            newPanel.orderFrontRegardless()
        }
    }
}

private enum CorrectionResultPanelState {
    case composing(
        initialText: String,
        message: String?,
        selectedMode: CorrectionMode,
        onModeChange: (CorrectionMode) -> Void,
        onCorrect: (String) -> Void
    )
    case loading(sourceText: String)
    case ready(
        correctedText: String,
        sourceText: String?,
        analysis: CorrectionAnalysis,
        translatedFrom: TranslationLanguage?,
        onTranslate: ((String, TranslationLanguage) -> Void)?
    )

    var height: CGFloat {
        switch self {
        case .composing:
            return 360
        case .loading:
            return 260
        case .ready(_, _, let analysis, _, _):
            return analysis.hasHighlightedErrors ? 360 : 300
        }
    }

    var needsKeyboardInput: Bool {
        if case .composing = self {
            return true
        }

        return false
    }
}

private final class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private struct CorrectionResultPanelView: View {
    let state: CorrectionResultPanelState
    let onClose: () -> Void
    @State private var didCopy = false
    @State private var draftText = ""
    @State private var selectedMode: CorrectionMode = .correction
    @State private var showsDetectedText = false
    @State private var translatingLanguage: TranslationLanguage?
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch state {
            case .composing(let initialText, let message, let initialMode, let onModeChange, let onCorrect):
                VStack(alignment: .leading, spacing: 12) {
                    modePicker(onModeChange: onModeChange)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $draftText)
                            .font(.system(size: 14))
                            .scrollContentBackground(.hidden)
                            .focused($isDraftFocused)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.48))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            }

                        if draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Text to correct")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .padding(.top, 18)
                                .padding(.leading, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxHeight: .infinity)

                    if let message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack {
                        let trimmedDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                        Text("\(CorrectionAnalysis.wordCount(in: trimmedDraft)) words · \(trimmedDraft.count) characters")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            onCorrect(draftText)
                        } label: {
                            Label(selectedMode.title, systemImage: selectedMode.systemImage)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear {
                    draftText = initialText
                    selectedMode = initialMode
                    DispatchQueue.main.async {
                        isDraftFocused = true
                    }
                }

            case .loading(let sourceText):
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Detected text")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(sourceText.isEmpty ? "Correcting..." : sourceText)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !sourceText.isEmpty {
                            Text("\(CorrectionAnalysis.wordCount(in: sourceText)) words detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)

            case .ready(let correctedText, let sourceText, let analysis, let translatedFrom, let onTranslate):
                readyContent(
                    correctedText: correctedText,
                    sourceText: sourceText,
                    analysis: analysis,
                    translatedFrom: translatedFrom,
                    onTranslate: onTranslate
                )
            }
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 22, y: 12)
    }

    private func modePicker(onModeChange: @escaping (CorrectionMode) -> Void) -> some View {
        Picker("Mode", selection: $selectedMode) {
            ForEach(CorrectionMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: selectedMode) { _, newMode in
            onModeChange(newMode)
        }
    }

    @ViewBuilder
    private func readyContent(
        correctedText: String,
        sourceText: String?,
        analysis: CorrectionAnalysis,
        translatedFrom: TranslationLanguage?,
        onTranslate: ((String, TranslationLanguage) -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let correctnessPercentage = analysis.correctnessPercentage {
                    metricBadge(
                        "\(correctnessPercentage)% correct",
                        systemImage: "percent",
                        tint: correctnessTint(for: correctnessPercentage)
                    )
                }

                metricBadge(
                    "\(analysis.wordCount) \(analysis.wordCount == 1 ? "word" : "words")",
                    systemImage: "text.word.spacing",
                    tint: .secondary
                )

                metricBadge(
                    analysis.correctionCount > 0
                        ? "\(analysis.correctionCount) \(analysis.correctionCount > 1 ? "corrections" : "correction")"
                        : "No errors",
                    systemImage: analysis.correctionCount > 0 ? "text.badge.checkmark" : "checkmark.circle",
                    tint: analysis.correctionCount > 0 ? .red : .green
                )

                Spacer()
            }

            if let onTranslate {
                translationBar(
                    correctedText: correctedText,
                    translatedFrom: translatedFrom,
                    onTranslate: onTranslate
                )
            }

            ScrollView {
                Text(correctedText)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            .frame(maxHeight: analysis.hasHighlightedErrors ? 112 : 156)

            if analysis.hasHighlightedErrors {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Issues found", systemImage: "text.badge.xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    highlightedSourceText(from: analysis.highlightedSourceRuns)
                        .font(.system(size: 12))
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.red.opacity(0.16), lineWidth: 1)
                        }
                }
            }

            if let sourceText, !sourceText.isEmpty {
                Divider()

                DisclosureGroup(isExpanded: $showsDetectedText) {
                    Text(sourceText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Label("OCR diagnostic", systemImage: "viewfinder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func translationBar(
        correctedText: String,
        translatedFrom: TranslationLanguage?,
        onTranslate: @escaping (String, TranslationLanguage) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text("Translate")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(TranslationLanguage.allCases) { language in
                Button {
                    translatingLanguage = language
                    onTranslate(correctedText, language)
                } label: {
                    HStack(spacing: 4) {
                        if translatingLanguage == language {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.62)
                                .frame(width: 12, height: 12)
                        } else {
                            Text(language.flag)
                        }

                        Text(language.code)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(minWidth: 44)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(translatingLanguage != nil)
                .help("Translate to \(language.promptName)")
            }

            if let translatedFrom {
                Text("Now \(translatedFrom.code)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
    }

    private func metricBadge(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func correctnessTint(for percentage: Int) -> Color {
        if percentage >= 90 {
            return .green
        }

        if percentage >= 70 {
            return .orange
        }

        return .red
    }

    private func highlightedSourceText(from runs: [CorrectionHighlightRun]) -> Text {
        runs.reduce(Text("")) { partialText, run in
            var segment = Text(run.text)

            if run.isError {
                segment = segment
                    .foregroundColor(.red)
                    .underline(true, color: .red)
            }

            return partialText + segment
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            QelvoraLogoMark(size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 16, weight: .semibold))

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if case .ready = state {
                Button {
                    copyCorrection()
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
    }

    private var headerTitle: String {
        switch state {
        case .composing:
            return "Write"
        case .loading:
            return "Correction"
        case .ready(_, _, _, let translatedFrom, _):
            return translatedFrom == nil ? "Correction ready" : "Translation ready"
        }
    }

    private var headerSubtitle: String {
        switch state {
        case .composing:
            return "Text editor"
        case .loading:
            return "Local analysis"
        case .ready:
            return "Local result"
        }
    }

    private func copyCorrection() {
        guard case .ready(let correctedText, _, _, _, _) = state else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(correctedText, forType: .string)
        didCopy = true
    }
}
