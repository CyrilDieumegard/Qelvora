import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var canPostEvents: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightPostEventAccess()
        }

        return isTrusted
    }

    static var canReadUIElements: Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedApplication: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApplication
        )

        return result == .success
    }

    static var canControlComputer: Bool {
        isTrusted || canPostEvents || canReadUIElements
    }

    static var runningAppPath: String {
        Bundle.main.bundleURL.path(percentEncoded: false)
    }

    static var isRunningFromApplications: Bool {
        runningAppPath.hasPrefix("/Applications/")
    }

    static func requestAndOpenSettings() {
        if !isTrusted && !canReadUIElements {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        if #available(macOS 10.15, *) {
            if !canPostEvents {
                _ = CGRequestPostEventAccess()
            }
        }

        openSettings()
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
