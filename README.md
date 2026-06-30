# Qelvora

Qelvora is a native macOS menu bar app that corrects the spelling and grammar of selected text in any app. The proof of concept uses a local Ollama model, so selected text stays on the user's Mac.

The source code is fully open source. Ready-to-use signed and notarized DMG builds, support, and updates are distributed separately as the official paid convenience build.

## Distribution Model

- Source code: free and public on GitHub.
- Official DMG: paid convenience build for users who want a signed, notarized, ready-to-install app.
- Releases are built from this repository so the public code remains the source of truth.
- Local-first design: selected text is processed through the user's local Ollama instance.

The project is released under the MIT License.

## Requirements

- macOS 14 Sonoma or newer
- Xcode 15 or newer
- Ollama installed locally
- At least one Ollama model pulled locally
- Accessibility permission enabled for Qelvora
- Screen Recording permission enabled for OCR fallback in apps that do not expose selected text

The app is intentionally not sandboxed. It needs Accessibility access to simulate `Cmd+C` and `Cmd+V` across other applications.

## Local Setup

1. Install Ollama from <https://ollama.com>.
2. Pull a small model for the first test:

   ```sh
   ollama pull qwen2.5:3b
   ```

   Qelvora also detects installed Ollama models automatically. Recommended models are shown first, but any installed or custom Ollama model name can be selected in Settings.

3. Build a local DMG:

   ```sh
   ./scripts/build-dmg.sh
   ```

4. Open `dist/Qelvora-0.1.0.dmg`.
5. Drag Qelvora to Applications.
6. Launch Qelvora from Applications.
7. Grant Accessibility permission when macOS asks, or open:

   ```text
   System Settings > Privacy & Security > Accessibility
   ```

For development, you can also open `Qelvora.xcodeproj` in Xcode and run the `Qelvora` scheme, but the DMG path is the expected manual test flow.

## How To Test The POC

Start with TextEdit:

1. Open TextEdit and type a sentence with spelling or grammar mistakes.
2. Select the text.
3. Press the global hotkey, by default `Cmd+Shift+C`.
4. Qelvora copies the selection, sends it to Ollama on `localhost:11434`, pastes the corrected text, then restores the previous clipboard contents.

Then test an Electron app such as Discord or Slack:

1. Type text in a message field.
2. Select the text.
3. Press the hotkey.
4. The selected text should be replaced in place.

## Architecture

```text
Qelvora/
├─ App/                  App lifecycle and shared state
├─ UI/                   Menu bar UI and settings
├─ TextCapture/          Cmd+C / clipboard / Cmd+V workflow
├─ CorrectionEngine/     Abstract correction engine and Ollama implementation
├─ Models/               Recommended model catalog, custom models, Ollama registry
├─ Hotkeys/              Global configurable hotkey
├─ Workflow/             End-to-end correction coordinator
└─ Resources/            Info.plist and app resources
```

The correction backend sits behind this protocol:

```swift
protocol CorrectionEngine {
    func correct(text: String, model: String) async throws -> String
}
```

The current implementation is `OllamaEngine`. A future embedded `llama.cpp` implementation can conform to the same protocol.

## POC Limits

- Ollama must already be installed and running.
- Recommended model downloads are delegated to the local Ollama API.
- Custom models must be available in Ollama before they can produce corrections.
- The app relies on simulated copy/paste, which is broad and pragmatic but depends on the focused app accepting normal keyboard shortcuts.
- Very large selections may take longer depending on the selected local model.

## Next Steps

- Publish the public GitHub repository.
- Add richer model health checks and onboarding.
- Automate signed and notarized DMG packaging from GitHub releases.
- Add more compatibility tests for Electron apps, browsers, editors, and office suites.
