import AppKit
import CoreGraphics

enum ScreenCapturePermission {
    static var canCaptureScreen: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }

        return true
    }

    static func requestAndOpenSettings() {
        if #available(macOS 10.15, *) {
            _ = CGRequestScreenCaptureAccess()
        }

        openSettings()
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
