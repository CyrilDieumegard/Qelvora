import SwiftUI

struct AccessibilityStatusView: View {
    @EnvironmentObject private var appState: AppState
    var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            permissionRow(
                title: "Accessibility",
                isGranted: appState.canControlComputer,
                grantedIcon: "checkmark.shield",
                missingIcon: "exclamationmark.triangle",
                actionTitle: "Allow",
                action: appState.requestAccessibilityPermission
            )

            if showDetails {
                HStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                    Text(appState.runningAppPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                if !AccessibilityPermission.isRunningFromApplications {
                    Label("Launch from /Applications", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            permissionRow(
                title: "Screen",
                isGranted: appState.canCaptureScreen,
                grantedIcon: "checkmark.viewfinder",
                missingIcon: "viewfinder",
                actionTitle: "Allow",
                action: appState.requestScreenCapturePermission
            )
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        isGranted: Bool,
        grantedIcon: String,
        missingIcon: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: isGranted ? grantedIcon : missingIcon)
                .foregroundStyle(isGranted ? Color.green : Color.orange)

            Spacer()

            if isGranted {
                Text("OK")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button(actionTitle, action: action)
            }
        }
    }
}
