import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            actions
            if !appState.modelManager.isOllamaAvailable {
                ollamaSetupPanel
            }
            statusPanel
            modelPanel
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            QelvoraLogoMark(size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Qelvora")
                    .font(.system(size: 20, weight: .semibold))

                Text(appState.hotkeyManager.hotkey.displayString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            QelvoraStatusDot(tint: statusTint)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        await appState.coordinator.correctSelection()
                    }
                } label: {
                    Label("Correct", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(appState.coordinator.isProcessing)

                Button {
                    appState.coordinator.showComposer()
                } label: {
                    Label("Write", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                Task {
                    await appState.coordinator.correctScreenRegion()
                }
            } label: {
                Label("Select screen area", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(appState.coordinator.isProcessing)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            QelvoraStatusBadge(
                title: appState.coordinator.status.menuTitle,
                systemImage: appState.coordinator.status.systemImageName,
                tint: statusTint
            )

            permissionRow(
                title: "Accessibility",
                isGranted: appState.canControlComputer,
                action: appState.requestAccessibilityPermission
            )

            permissionRow(
                title: "Screen",
                isGranted: appState.canCaptureScreen,
                action: appState.requestScreenCapturePermission
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Model", selection: modelSelection) {
                ForEach(appState.modelManager.availableModels) { model in
                    Text(model.displayName)
                        .tag(model.name)
                }
            }

            HStack(spacing: 8) {
                if !appState.modelManager.missingModels.isEmpty {
                    Menu {
                        ForEach(appState.modelManager.missingModels) { model in
                            Button(model.displayName) {
                                Task {
                                    await appState.modelManager.download(model: model)
                                }
                            }
                            .disabled(appState.modelManager.downloadingModelName != nil)
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }

                Button {
                    Task {
                        await appState.modelManager.refreshInstalledModels()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.modelManager.isRefreshing)

                Spacer()
            }
            .font(.caption)

            if let statusMessage = appState.modelManager.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var ollamaSetupPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ollama required", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Install and launch Ollama before downloading models or correcting text.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    appState.openOllamaDownloadPage()
                } label: {
                    Label("Download Ollama", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await appState.modelManager.refreshInstalledModels()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.modelManager.isRefreshing)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                appState.checkForUpdates()
            } label: {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                appState.showSettingsWindow()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    private func permissionRow(
        title: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGranted ? Color.green : Color.orange)

            Spacer()

            if isGranted {
                Text("OK")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .font(.system(size: 13, weight: .medium))
    }

    private var statusTint: Color {
        switch appState.coordinator.status {
        case .idle, .completed:
            return .green
        case .capturing, .correcting, .pasting:
            return .accentColor
        case .noSelection:
            return .orange
        case .missingAccessibility, .failed:
            return .red
        }
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { appState.modelManager.selectedModelName },
            set: { appState.modelManager.selectModel(named: $0) }
        )
    }
}

private struct QelvoraStatusDot: View {
    let tint: Color

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 10, height: 10)
            .overlay {
                Circle().stroke(.white.opacity(0.5), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.35), radius: 6)
            .accessibilityHidden(true)
    }
}
