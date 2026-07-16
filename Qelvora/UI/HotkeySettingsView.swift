import SwiftUI

struct HotkeySettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HotkeyRecorder(hotkey: hotkeyBinding)
                    .frame(width: 180, height: 38)

                Button {
                    appState.hotkeyManager.updateHotkey(.default)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }

                Spacer()
            }

            if let registrationError = appState.hotkeyManager.registrationError {
                Label(registrationError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The shortcut opens the rectangular screen-area selector. Use Correct selection for highlighted editable text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hotkeyBinding: Binding<Hotkey> {
        Binding(
            get: { appState.hotkeyManager.hotkey },
            set: { appState.hotkeyManager.updateHotkey($0) }
        )
    }
}
