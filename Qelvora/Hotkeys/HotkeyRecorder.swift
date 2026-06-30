import AppKit
import SwiftUI

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey

    func makeNSView(context: Context) -> HotkeyRecorderControl {
        let control = HotkeyRecorderControl()
        control.hotkey = hotkey
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .vertical)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .vertical)
        control.onHotkeyChange = { newHotkey in
            hotkey = newHotkey
        }
        return control
    }

    func updateNSView(_ nsView: HotkeyRecorderControl, context: Context) {
        nsView.hotkey = hotkey
    }
}

final class HotkeyRecorderControl: NSControl {
    var hotkey: Hotkey = .default {
        didSet {
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }

    var onHotkeyChange: ((Hotkey) -> Void)?
    private var isRecording = false {
        didSet {
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 170, height: 36)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        guard let newHotkey = Hotkey.from(event: event) else {
            NSSound.beep()
            return
        }

        hotkey = newHotkey
        onHotkeyChange?(newHotkey)
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds.insetBy(dx: 1, dy: 1)
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        let background = isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.controlBackgroundColor
        background.setFill()
        path.fill()

        let stroke = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()

        let title = isRecording ? "Press shortcut" : hotkey.displayString
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]

        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        let titleRect = NSRect(
            x: bounds.minX + 8,
            y: bounds.midY - attributedTitle.size().height / 2,
            width: bounds.width - 16,
            height: attributedTitle.size().height
        )
        attributedTitle.draw(in: titleRect)
    }
}
