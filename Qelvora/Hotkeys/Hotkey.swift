import AppKit
import Carbon

struct Hotkey: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: HotkeyModifiers

    static let legacyDefault = Hotkey(keyCode: 8, modifiers: [.command, .shift])
    static let legacyRightOption = Hotkey(keyCode: 61, modifiers: [])
    static let `default` = Hotkey(keyCode: 49, modifiers: [.option])

    var displayString: String {
        let parts = modifiers.displayNames + [Self.keyDisplayName(for: keyCode)]
        return parts.joined(separator: " + ")
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0

        if modifiers.contains(.command) {
            result |= UInt32(cmdKey)
        }

        if modifiers.contains(.shift) {
            result |= UInt32(shiftKey)
        }

        if modifiers.contains(.option) {
            result |= UInt32(optionKey)
        }

        if modifiers.contains(.control) {
            result |= UInt32(controlKey)
        }

        return result
    }

    static func from(event: NSEvent) -> Hotkey? {
        let modifiers = HotkeyModifiers(eventModifiers: event.modifierFlags)

        guard modifiers.hasGlobalModifier || functionKeyCodes.contains(UInt32(event.keyCode)) else {
            return nil
        }

        return Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    static func keyDisplayName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        31: "O",
        32: "U",
        34: "I",
        35: "P",
        37: "L",
        38: "J",
        40: "K",
        45: "N",
        46: "M",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        23: "5",
        22: "6",
        26: "7",
        28: "8",
        25: "9",
        29: "0",
        47: ".",
        49: "Space",
        61: "Right Option",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        105: "F13",
        107: "F14",
        113: "F15",
        106: "F16",
        64: "F17",
        79: "F18",
        80: "F19",
        90: "F20"
    ]

    private static let functionKeyCodes: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]
}

struct HotkeyModifiers: OptionSet, Codable, Equatable, Hashable {
    let rawValue: UInt32

    static let command = HotkeyModifiers(rawValue: 1 << 0)
    static let shift = HotkeyModifiers(rawValue: 1 << 1)
    static let option = HotkeyModifiers(rawValue: 1 << 2)
    static let control = HotkeyModifiers(rawValue: 1 << 3)

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(eventModifiers: NSEvent.ModifierFlags) {
        var value = HotkeyModifiers()

        if eventModifiers.contains(.command) {
            value.insert(.command)
        }

        if eventModifiers.contains(.shift) {
            value.insert(.shift)
        }

        if eventModifiers.contains(.option) {
            value.insert(.option)
        }

        if eventModifiers.contains(.control) {
            value.insert(.control)
        }

        self = value
    }

    var hasGlobalModifier: Bool {
        contains(.command) || contains(.option) || contains(.control)
    }

    var displayString: String {
        displayNames.joined(separator: " + ")
    }

    var displayNames: [String] {
        var parts: [String] = []

        if contains(.control) {
            parts.append("Ctrl")
        }

        if contains(.option) {
            parts.append("Option")
        }

        if contains(.shift) {
            parts.append("Shift")
        }

        if contains(.command) {
            parts.append("Cmd")
        }

        return parts
    }
}
