import SwiftUI

struct ModelPickerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var customModelName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !appState.modelManager.isOllamaAvailable {
                ollamaSetupNotice
            }

            Picker("Active model", selection: modelSelection) {
                ForEach(appState.modelManager.availableModels) { model in
                    Text(model.displayName).tag(model.name)
                }
            }

            Text(appState.modelManager.hardwareSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Custom Ollama model, e.g. llama3.1:8b", text: $customModelName)
                    .textFieldStyle(.roundedBorder)

                Button("Use") {
                    appState.modelManager.addCustomModel(named: customModelName)
                    customModelName = ""
                }
                .disabled(customModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()

            ForEach(appState.modelManager.availableModels) { model in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName)
                            .font(.system(size: 13, weight: .medium))
                        Text(model.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if appState.modelManager.installedModelNames.contains(model.name) {
                        Label("Installed", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    } else if model.isDownloadable {
                        Button {
                            Task {
                                await appState.modelManager.download(model: model)
                            }
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                        .disabled(appState.modelManager.downloadingModelName != nil)
                    } else {
                        Text("Custom")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            if let statusMessage = appState.modelManager.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ollamaSetupNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ollama is required", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text("Install Ollama, launch it once, then refresh Qelvora. Model downloads use the local Ollama API on localhost:11434.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    appState.openOllamaDownloadPage()
                } label: {
                    Label("Download Ollama", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    appState.openOllamaOrDownloadPage()
                } label: {
                    Label("Open Ollama", systemImage: "play.circle")
                }

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
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { appState.modelManager.selectedModelName },
            set: { appState.modelManager.selectModel(named: $0) }
        )
    }
}
