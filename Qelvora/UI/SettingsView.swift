import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: SettingsTab = .general
    @State private var serviceStatusMessage: String?
    @State private var serviceDiagnostic = UserServicesInstaller.diagnostics()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            tabBar
            Divider()
            tabContent
        }
        .frame(minWidth: 840, minHeight: 600, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            QelvoraLogoMark(size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("Qelvora")
                    .font(.system(size: 24, weight: .semibold))

                Text("Local settings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            QelvoraStatusBadge(
                title: appState.coordinator.status.menuTitle,
                systemImage: appState.coordinator.status.systemImageName,
                tint: statusTint
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    selectedTab = tab
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalTab
        case .capture:
            captureTab
        case .model:
            modelTab
        case .services:
            servicesTab
        case .history:
            historyTab
        }
    }

    private var generalTab: some View {
        settingsScroll {
            SettingsPageTitle(
                title: "General",
                subtitle: "Core actions, global shortcut, and output style."
            )

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    actionsCard
                    hotkeyCard
                }
                .frame(width: 330)

                VStack(alignment: .leading, spacing: 14) {
                    outputModeCard
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var captureTab: some View {
        settingsScroll {
            SettingsPageTitle(
                title: "Capture",
                subtitle: "Permissions and selection-reading strategy."
            )

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    accessCard
                    captureMethodCard
                }
                .frame(width: 360)

                captureReliabilityCard
            }
        }
    }

    private var modelTab: some View {
        settingsScroll {
            VStack(alignment: .leading, spacing: 14) {
                SettingsPageTitle(
                    title: "Local model",
                    subtitle: "Choose the correction engine used by Qelvora."
                )

                SettingsCard(title: "Ollama configuration", systemImage: "cpu") {
                    ModelPickerView()
                }
            }
        }
    }

    private var servicesTab: some View {
        settingsScroll {
            VStack(alignment: .leading, spacing: 14) {
                SettingsPageTitle(
                    title: "macOS right click",
                    subtitle: "Diagnostics and repair for the Qelvora Services menu entry."
                )

                HStack(alignment: .top, spacing: 14) {
                    serviceCard
                        .frame(width: 430)

                    serviceDiagnosticCard
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            refreshServiceDiagnostic()
        }
    }

    private var historyTab: some View {
        settingsScroll {
            VStack(alignment: .leading, spacing: 14) {
                historyHeader

                if appState.coordinator.historyItems.isEmpty {
                    emptyHistoryCard
                } else {
                    SettingsCard(title: "\(appState.coordinator.historyItems.count) corrections", systemImage: "clock.arrow.circlepath") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(appState.coordinator.historyItems) { item in
                                historyRow(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private var historyHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            SettingsPageTitle(
                title: "History",
                subtitle: "Recent corrections stored locally on this Mac."
            )

            Spacer()

            if !appState.coordinator.historyItems.isEmpty {
                Button(role: .destructive) {
                    appState.coordinator.clearHistory()
                } label: {
                    Label("Clear history", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var actionsCard: some View {
        SettingsCard(title: "Actions", systemImage: "bolt.fill") {
            HStack(spacing: 10) {
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
        }
    }

    private var hotkeyCard: some View {
        SettingsCard(title: "Shortcut", systemImage: "keyboard") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    HotkeyRecorder(hotkey: hotkeyBinding)
                        .frame(width: 170, height: 36)

                    Button {
                        appState.hotkeyManager.updateHotkey(.default)
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Spacer()
                }

                if let registrationError = appState.hotkeyManager.registrationError {
                    Label(registrationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Works everywhere, without relying on right click.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var accessCard: some View {
        SettingsCard(title: "macOS access", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 8) {
                permissionRow(
                    title: "Accessibility",
                    isGranted: appState.canControlComputer,
                    action: appState.requestAccessibilityPermission
                )

                permissionRow(
                    title: "Screen capture",
                    isGranted: appState.canCaptureScreen,
                    action: appState.requestScreenCapturePermission
                )
            }
        }
    }

    private var outputModeCard: some View {
        SettingsCard(title: "Output style", systemImage: "slider.horizontal.3") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(CorrectionMode.allCases) { mode in
                    SettingsModeButton(
                        mode: mode,
                        isSelected: appState.coordinator.selectedMode == mode
                    ) {
                        appState.coordinator.selectedMode = mode
                    }
                }
            }
        }
    }

    private var captureMethodCard: some View {
        SettingsCard(title: "Method", systemImage: "viewfinder") {
            VStack(alignment: .leading, spacing: 10) {
                diagnosticRow(
                    title: "Mode",
                    value: "Hybrid auto",
                    isHealthy: true
                )

                Text("Qelvora first tries native methods when they are reliable, then falls back to OCR near the pointer for apps that block selection access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var captureReliabilityCard: some View {
        SettingsCard(title: "OCR reliability", systemImage: "scope") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsInfoBlock(
                    systemImage: "cursorarrow.motionlines",
                    title: "Pointer priority",
                    description: "Selection near the pointer is prioritized to avoid reading an unrelated blue link nearby."
                )

                SettingsInfoBlock(
                    systemImage: "rectangle.dashed",
                    title: "Selected zone",
                    description: "If detected text looks wrong, the result panel's OCR diagnostic shows what was actually read."
                )

                SettingsInfoBlock(
                    systemImage: "keyboard.badge.eye",
                    title: "Transparent fallback",
                    description: "When macOS blocks automatic replacement, Qelvora shows a copyable correction instead of hiding the failure."
                )
            }
        }
    }

    private var serviceCard: some View {
        SettingsCard(title: "macOS right click", systemImage: "cursorarrow.click.2") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Qelvora Service")
                            .font(.system(size: 14, weight: .semibold))

                        Text("Reinstall the Services entry if macOS no longer shows it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button {
                        let report = UserServicesInstaller.installOrRefresh()
                        serviceDiagnostic = report.diagnostic
                        serviceStatusMessage = report.summary
                    } label: {
                        Label("Reinstall", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                if let serviceStatusMessage {
                    Label(serviceStatusMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var serviceDiagnosticCard: some View {
        SettingsCard(title: "Diagnostic", systemImage: "stethoscope") {
            VStack(alignment: .leading, spacing: 10) {
                diagnosticRow(
                    title: "Workflow",
                    value: serviceDiagnostic.workflowExists ? "Present" : "Missing",
                    isHealthy: serviceDiagnostic.workflowExists
                )

                diagnosticRow(
                    title: "Info.plist",
                    value: serviceDiagnostic.infoPlistIsValid ? "Valid" : "Needs repair",
                    isHealthy: serviceDiagnostic.infoPlistIsValid
                )

                diagnosticRow(
                    title: "Action Automator",
                    value: serviceDiagnostic.documentWorkflowExists ? "Present" : "Missing",
                    isHealthy: serviceDiagnostic.documentWorkflowExists
                )

                if let lastModified = serviceDiagnostic.lastModified {
                    diagnosticRow(
                        title: "Last written",
                        value: DateFormatter.localizedString(from: lastModified, dateStyle: .short, timeStyle: .short),
                        isHealthy: true
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Installed path")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(serviceDiagnostic.workflowPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                Text("After repair, macOS may require you to quit and reopen the target app before its Services menu updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyHistoryCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("No saved corrections")
                .font(.system(size: 16, weight: .semibold))

            Text("Corrections will appear here with their mode and quick actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }

    private func settingsScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(24)
            .frame(maxWidth: 1040, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func permissionRow(
        title: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background((isGranted ? Color.green : Color.orange).opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func diagnosticRow(title: String, value: String, isHealthy: Bool) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHealthy ? Color.green : Color.orange)

            Spacer()

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background((isHealthy ? Color.green : Color.orange).opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func historyRow(_ item: CorrectionHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label(item.mode.title, systemImage: item.mode.systemImage)
                    .font(.system(size: 12, weight: .semibold))

                Text("\(item.wordCount) \(item.wordCount == 1 ? "word" : "words")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if item.correctionCount > 0 {
                    Text("\(item.correctionCount) \(item.correctionCount == 1 ? "correction" : "corrections")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }

                Spacer()

                Button {
                    appState.coordinator.showComposer(initialText: item.sourceText)
                } label: {
                    Label("Resume", systemImage: "arrow.uturn.left")
                }
                .buttonStyle(.borderless)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.correctedText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }

            Text(item.correctedText)
                .font(.system(size: 13))
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
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

    private var hotkeyBinding: Binding<Hotkey> {
        Binding(
            get: { appState.hotkeyManager.hotkey },
            set: { appState.hotkeyManager.updateHotkey($0) }
        )
    }

    private func refreshServiceDiagnostic() {
        serviceDiagnostic = UserServicesInstaller.diagnostics()
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case capture
    case model
    case services
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .capture:
            return "Capture"
        case .model:
            return "Model"
        case .services:
            return "Right click"
        case .history:
            return "History"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "switch.2"
        case .capture:
            return "viewfinder"
        case .model:
            return "cpu"
        case .services:
            return "cursorarrow.click.2"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(tab.title, systemImage: tab.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 112)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color(nsColor: .windowBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.clear : Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }
}

private struct SettingsModeButton: View {
    let mode: CorrectionMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 14, weight: .semibold))

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Text(mode.title)
                    .font(.system(size: 14, weight: .semibold))

                Text(mode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.60) : Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsInfoBlock: View {
    let systemImage: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }
}

private struct SettingsPageTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
