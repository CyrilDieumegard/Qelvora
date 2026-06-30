import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let modelManager: ModelManager
    let coordinator: CorrectionCoordinator
    let hotkeyManager: HotkeyManager
    private let targetApplicationTracker: TargetApplicationTracker
    @Published private(set) var canControlComputer = AccessibilityPermission.canControlComputer
    @Published private(set) var canCaptureScreen = ScreenCapturePermission.canCaptureScreen
    @Published private(set) var runningAppPath = AccessibilityPermission.runningAppPath

    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var permissionTimer: Timer?

    var menuBarSystemImage: String {
        if coordinator.isProcessing {
            return "wand.and.stars"
        }

        if !canControlComputer || !canCaptureScreen {
            return "exclamationmark.triangle"
        }

        return "feather"
    }

    init() {
        let modelManager = ModelManager()
        let targetApplicationTracker = TargetApplicationTracker()
        let textCapture = TextCaptureService(
            targetApplicationProvider: {
                targetApplicationTracker.targetApplicationForCorrection()
            }
        )
        let correctionEngine = OllamaEngine()
        let coordinator = CorrectionCoordinator(
            textCapture: textCapture,
            correctionEngine: correctionEngine,
            modelManager: modelManager
        )
        let hotkeyManager = HotkeyManager()

        hotkeyManager.onPressed = { [weak coordinator] in
            Task { @MainActor in
                await coordinator?.correctSelection()
            }
        }
        hotkeyManager.start()

        self.modelManager = modelManager
        self.coordinator = coordinator
        self.hotkeyManager = hotkeyManager
        self.targetApplicationTracker = targetApplicationTracker

        bridgeNestedObjectChanges()
        startPermissionMonitoring()
        observeIncomingServiceURLs()

        Task {
            await modelManager.refreshInstalledModels()
        }
    }

    func requestAccessibilityPermission() {
        AccessibilityPermission.requestAndOpenSettings()
        refreshAccessibilityPermission()
    }

    func refreshAccessibilityPermission() {
        canControlComputer = AccessibilityPermission.canControlComputer
        canCaptureScreen = ScreenCapturePermission.canCaptureScreen
        runningAppPath = AccessibilityPermission.runningAppPath
    }

    func requestScreenCapturePermission() {
        ScreenCapturePermission.requestAndOpenSettings()
        refreshAccessibilityPermission()
    }

    func showSettingsWindow() {
        let contentSize = NSSize(width: 920, height: 660)
        let minimumSize = NSSize(width: 840, height: 600)

        if let settingsWindow {
            if settingsWindow.frame.width < minimumSize.width || settingsWindow.frame.height < minimumSize.height {
                settingsWindow.setContentSize(contentSize)
            }
            settingsWindow.minSize = minimumSize
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsView()
                .environmentObject(self)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Qelvora Settings"
        window.contentViewController = hostingController
        window.setContentSize(contentSize)
        window.minSize = minimumSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func checkForUpdates() {
        NotificationCenter.default.post(name: .qelvoraCheckForUpdates, object: nil)
    }

    private func observeIncomingServiceURLs() {
        NotificationCenter.default.publisher(for: .qelvoraOpenURL)
            .compactMap { $0.object as? URL }
            .sink { [weak self] url in
                Task { @MainActor in
                    await self?.handleIncomingServiceURL(url)
                }
            }
            .store(in: &cancellables)
    }

    private func handleIncomingServiceURL(_ url: URL) async {
        guard url.scheme == "qelvora",
              url.host == "correct-file",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value else {
            return
        }

        let fileURL = URL(fileURLWithPath: path)

        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            coordinator.showComposer(message: "Unable to read the text from the macOS service.")
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
        await coordinator.correctTypedText(text, mode: coordinator.selectedMode)
    }

    private func bridgeNestedObjectChanges() {
        modelManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        coordinator.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        hotkeyManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func startPermissionMonitoring() {
        refreshAccessibilityPermission()

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshAccessibilityPermission()
            }
            .store(in: &cancellables)

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityPermission()
            }
        }
    }

    deinit {
        permissionTimer?.invalidate()
    }
}

extension Notification.Name {
    static let qelvoraOpenURL = Notification.Name("io.qelvora.open-url")
    static let qelvoraCheckForUpdates = Notification.Name("io.qelvora.check-for-updates")
}

@MainActor
private final class TargetApplicationTracker {
    private var lastUserApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    init(
        workspace: NSWorkspace = .shared,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        rememberIfUserApplication(workspace.frontmostApplication)

        activationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.rememberIfUserApplication(application)
            }
        }
    }

    func targetApplicationForCorrection() -> NSRunningApplication? {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication

        if isUserApplication(frontmostApplication) {
            lastUserApplication = frontmostApplication
            return frontmostApplication
        }

        return lastUserApplication
    }

    private func rememberIfUserApplication(_ application: NSRunningApplication?) {
        guard isUserApplication(application) else {
            return
        }

        lastUserApplication = application
    }

    private func isUserApplication(_ application: NSRunningApplication?) -> Bool {
        guard let application else {
            return false
        }

        guard application.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return false
        }

        if let bundleIdentifier = application.bundleIdentifier,
           bundleIdentifier == Bundle.main.bundleIdentifier {
            return false
        }

        return true
    }
}
