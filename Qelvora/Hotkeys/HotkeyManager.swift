import Carbon
import Foundation

@MainActor
final class HotkeyManager: ObservableObject {
    @Published private(set) var hotkey: Hotkey
    @Published private(set) var registrationError: String?

    var onPressed: (() -> Void)?

    private let userDefaults: UserDefaults
    private let hotkeyDefaultsKey = "globalHotkey"
    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isStarted = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: hotkeyDefaultsKey),
           let decoded = try? JSONDecoder().decode(Hotkey.self, from: data) {
            self.hotkey = Self.migratedHotkey(from: decoded)
        } else {
            self.hotkey = .default
        }
    }

    deinit {
        if let eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        installEventHandlerIfNeeded()
        register()
    }

    func updateHotkey(_ newHotkey: Hotkey) {
        hotkey = newHotkey

        if let data = try? JSONEncoder().encode(newHotkey) {
            userDefaults.set(data, forKey: hotkeyDefaultsKey)
        }

        if isStarted {
            register()
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.onPressed?()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            registrationError = "Unable to install the shortcut handler."
        }
    }

    private func register() {
        unregisterHotkeyOnly()

        let hotKeyID = EventHotKeyID(signature: 0x5156484B, id: 1)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )

        if status == noErr {
            registrationError = nil
        } else {
            registrationError = "The shortcut \(hotkey.displayString) is already in use."
        }
    }

    private func unregisterHotkeyOnly() {
        if let eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
            self.eventHotKeyRef = nil
        }
    }

    private func unregister() {
        unregisterHotkeyOnly()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private static func migratedHotkey(from hotkey: Hotkey) -> Hotkey {
        if hotkey == .legacyDefault || hotkey == .legacyRightOption {
            return .default
        }

        return hotkey
    }
}
