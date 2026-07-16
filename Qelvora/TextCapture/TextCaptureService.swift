import AppKit

struct CapturedText: Equatable {
    enum Source: Equatable {
        case selectedText
        case screenRegion
    }

    let text: String
    let sourceProcessIdentifier: pid_t?
    let source: Source

    init(
        text: String,
        sourceProcessIdentifier: pid_t? = nil,
        source: Source = .selectedText
    ) {
        self.text = text
        self.sourceProcessIdentifier = sourceProcessIdentifier
        self.source = source
    }

    var shouldReplaceSelection: Bool {
        source == .selectedText
    }
}

enum TextCaptureError: LocalizedError, Equatable {
    case accessibilityPermissionMissing
    case noSelection
    case selectionNotDetected(String)
    case copyTimedOut
    case pasteFailed
    case screenCapturePermissionMissing
    case regionSelectionCancelled
    case noTextInRegion

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "Qelvora needs Accessibility permission to simulate Cmd+C and Cmd+V."
        case .noSelection:
            return "No text selected."
        case .selectionNotDetected(let message):
            return message
        case .copyTimedOut:
            return "Unable to read the selection."
        case .pasteFailed:
            return "Unable to paste the corrected text."
        case .screenCapturePermissionMissing:
            return "Qelvora needs Screen Recording permission to read a screen area in apps like Discord."
        case .regionSelectionCancelled:
            return "Screen area selection canceled."
        case .noTextInRegion:
            return "No readable text found in that screen area."
        }
    }
}

protocol TextCaptureServiceProtocol {
    func captureSelectedText() async throws -> CapturedText
    func captureTextFromScreenRegion() async throws -> CapturedText
    func replaceSelection(with text: String) async throws
}

@MainActor
final class TextCaptureService: TextCaptureServiceProtocol {
    private enum ReplacementMode {
        case selection
        case mouseContextSelection
        case screenOCRSelection
        case screenRegion
        case focusedTextValue
    }

    private let keyboardSimulator: KeyboardSimulator
    private var selectedTextReader: SelectedTextReader
    private let screenTextReader: ScreenTextReader
    private let screenRegionSelector: ScreenRegionSelector
    private let pasteboard: NSPasteboard
    private let targetApplicationProvider: @MainActor () -> NSRunningApplication?
    private let copyTimeoutNanoseconds: UInt64 = 700_000_000
    private let pollIntervalNanoseconds: UInt64 = 30_000_000
    private let hotkeyReleaseDelayNanoseconds: UInt64 = 90_000_000
    private var activeTargetProcessIdentifier: pid_t?
    private var lastExternalTargetProcessIdentifier: pid_t?
    private var replacementMode: ReplacementMode = .selection
    private var mouseContextLocation: CGPoint?

    init(
        keyboardSimulator: KeyboardSimulator = KeyboardSimulator(),
        selectedTextReader: SelectedTextReader = SelectedTextReader(),
        screenTextReader: ScreenTextReader = ScreenTextReader(),
        screenRegionSelector: ScreenRegionSelector? = nil,
        pasteboard: NSPasteboard = .general,
        targetApplicationProvider: @escaping @MainActor () -> NSRunningApplication? = {
            NSWorkspace.shared.frontmostApplication
        }
    ) {
        self.keyboardSimulator = keyboardSimulator
        self.selectedTextReader = selectedTextReader
        self.screenTextReader = screenTextReader
        self.screenRegionSelector = screenRegionSelector ?? ScreenRegionSelector()
        self.pasteboard = pasteboard
        self.targetApplicationProvider = targetApplicationProvider
    }

    func captureSelectedText() async throws -> CapturedText {
        let targetApplication = targetApplicationForCapture()
        activeTargetProcessIdentifier = targetApplication?.processIdentifier
        replacementMode = .selection
        mouseContextLocation = nil

        try? await Task.sleep(nanoseconds: hotkeyReleaseDelayNanoseconds)

        let prefersScreenOCR = shouldPreferScreenOCR(for: targetApplication)

        if prefersScreenOCR {
            return try await captureTextFromScreenRegion(targetApplication: targetApplication)
        }

        if let selectedText = nonEmptyText(
            selectedTextReader.selectedText(processIdentifier: activeTargetProcessIdentifier)
        ) {
            replacementMode = .selection
            return CapturedText(
                text: selectedText,
                sourceProcessIdentifier: activeTargetProcessIdentifier
            )
        }

        if let copiedText = try? await copiedSelectedTextViaKeyboard(from: targetApplication) {
            replacementMode = .selection
            return CapturedText(
                text: copiedText,
                sourceProcessIdentifier: activeTargetProcessIdentifier
            )
        }

        if let focusedText = nonEmptyText(
            selectedTextReader.focusedTextValue(processIdentifier: activeTargetProcessIdentifier)
        ) {
            replacementMode = .focusedTextValue
            return CapturedText(
                text: focusedText,
                sourceProcessIdentifier: activeTargetProcessIdentifier
            )
        }

        return try await captureTextFromScreenRegion(targetApplication: targetApplication)
    }

    func captureTextFromScreenRegion() async throws -> CapturedText {
        try await captureTextFromScreenRegion(targetApplication: targetApplicationForCapture())
    }

    private func captureTextFromScreenRegion(
        targetApplication: NSRunningApplication?
    ) async throws -> CapturedText {
        guard ScreenCapturePermission.canCaptureScreen else {
            ScreenCapturePermission.requestAndOpenSettings()
            throw TextCaptureError.screenCapturePermissionMissing
        }

        activeTargetProcessIdentifier = targetApplication?.processIdentifier
        replacementMode = .screenRegion
        mouseContextLocation = nil

        guard let selection = await screenRegionSelector.selectRegion() else {
            throw TextCaptureError.regionSelectionCancelled
        }

        try? await Task.sleep(nanoseconds: 120_000_000)

        let recognizedText: String?
        do {
            recognizedText = try await screenTextReader.text(in: selection)
        } catch ScreenTextReaderError.screenCapturePermissionMissing {
            throw TextCaptureError.screenCapturePermissionMissing
        }

        guard let recognizedText,
              let text = nonEmptyText(recognizedText) else {
            throw TextCaptureError.noTextInRegion
        }

        return CapturedText(
            text: text,
            sourceProcessIdentifier: activeTargetProcessIdentifier,
            source: .screenRegion
        )
    }

    func replaceSelection(with text: String) async throws {
        guard replacementMode != .screenRegion else {
            throw TextCaptureError.pasteFailed
        }

        let targetApplication = application(with: activeTargetProcessIdentifier) ?? targetApplicationProvider()
        await activateTargetApplicationForKeyboard(targetApplication)
        let targetProcessIdentifier = targetApplication?.processIdentifier ?? activeTargetProcessIdentifier

        let pasteboardBeforePaste = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        let didWrite = pasteboard.setString(text, forType: .string)

        guard didWrite else {
            pasteboardBeforePaste.restore(to: pasteboard)
            throw TextCaptureError.pasteFailed
        }

        if replacementMode == .focusedTextValue {
            if !keyboardSimulator.selectAllViaMenu(processIdentifier: targetProcessIdentifier) {
                keyboardSimulator.selectAll(processIdentifier: targetProcessIdentifier)
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        if replacementMode == .screenOCRSelection {
            keyboardSimulator.paste(processIdentifier: targetProcessIdentifier)
        } else if replacementMode == .mouseContextSelection,
           keyboardSimulator.pasteViaContextMenu(
               processIdentifier: targetProcessIdentifier,
               at: mouseContextLocation
           ) {
            try? await Task.sleep(nanoseconds: 120_000_000)
        } else if !keyboardSimulator.pasteViaMenu(processIdentifier: targetProcessIdentifier) {
            keyboardSimulator.paste(processIdentifier: targetProcessIdentifier)
        }

        try? await Task.sleep(nanoseconds: 350_000_000)

        if replacementMode == .focusedTextValue {
            _ = selectedTextReader.replaceFocusedTextValue(processIdentifier: targetProcessIdentifier, with: text)
        }

        pasteboardBeforePaste.restore(to: pasteboard)

        if targetProcessIdentifier == nil,
           !selectedTextReader.replaceSelection(processIdentifier: targetProcessIdentifier, with: text) {
            throw TextCaptureError.pasteFailed
        }
    }

    private func activateTargetApplicationForKeyboard(_ application: NSRunningApplication?) async {
        guard let application, application.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return
        }

        if #available(macOS 14.0, *) {
            application.activate()
        } else {
            application.activate(options: [.activateIgnoringOtherApps])
        }
        await waitUntilFrontmost(application)
    }

    private func application(with processIdentifier: pid_t?) -> NSRunningApplication? {
        guard let processIdentifier else {
            return nil
        }

        return NSRunningApplication(processIdentifier: processIdentifier)
    }

    private func targetApplicationForCapture() -> NSRunningApplication? {
        let currentApplicationIdentifier = NSRunningApplication.current.processIdentifier
        let frontmostApplication = targetApplicationProvider()

        if let frontmostApplication,
           frontmostApplication.processIdentifier != currentApplicationIdentifier {
            lastExternalTargetProcessIdentifier = frontmostApplication.processIdentifier
            return frontmostApplication
        }

        if let lastExternalTargetProcessIdentifier,
           let previousApplication = application(with: lastExternalTargetProcessIdentifier),
           !previousApplication.isTerminated {
            return previousApplication
        }

        return frontmostApplication
    }

    private func shouldPreferScreenOCR(for application: NSRunningApplication?) -> Bool {
        let applicationHints = [
            application?.bundleIdentifier,
            application?.localizedName
        ]
            .compactMap { $0?.lowercased() }

        return applicationHints.contains { hint in
            hint.contains("discord")
        }
    }

    private func copiedSelectedTextViaKeyboard(from application: NSRunningApplication?) async throws -> String {
        let originalPasteboard = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()

        do {
            let selectedText = try await copySelectedTextViaKeyboard(from: application)
            originalPasteboard.restore(to: pasteboard)

            guard let selectedText = nonEmptyText(selectedText) else {
                throw TextCaptureError.noSelection
            }

            return selectedText
        } catch {
            originalPasteboard.restore(to: pasteboard)
            throw error
        }
    }

    private func nonEmptyText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : text
    }

    private func copySelectedTextViaKeyboard(from application: NSRunningApplication?) async throws -> String {
        var lastError: Error = TextCaptureError.noSelection

        if let application {
            activeTargetProcessIdentifier = application.processIdentifier
            await activateTargetApplicationForKeyboard(application)
        }

        for copyAction in [
            { self.keyboardSimulator.copyViaMenu(processIdentifier: self.activeTargetProcessIdentifier) },
            { self.keyboardSimulator.copy(processIdentifier: self.activeTargetProcessIdentifier); return true },
            { self.keyboardSimulator.copy(); return true }
        ] {
            pasteboard.clearContents()
            let initialChangeCount = pasteboard.changeCount

            if copyAction() {
                do {
                    return try await waitForCopiedText(after: initialChangeCount)
                } catch {
                    lastError = error
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
            }
        }

        throw lastError
    }

    private func waitUntilFrontmost(_ application: NSRunningApplication) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + 550_000_000

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                try? await Task.sleep(nanoseconds: 60_000_000)
                return
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func targetApplicationName(_ application: NSRunningApplication?) -> String {
        application?.localizedName ?? application?.bundleIdentifier ?? "inconnue"
    }

    private func waitForCopiedText(after initialChangeCount: Int) async throws -> String {
        let deadline = DispatchTime.now().uptimeNanoseconds + copyTimeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            let copiedText = pasteboard.string(forType: .string) ?? ""

            if !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return copiedText
            }

            if pasteboard.changeCount != initialChangeCount, !copiedText.isEmpty {
                return copiedText
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        throw TextCaptureError.noSelection
    }
}
