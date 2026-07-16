import AppKit
import CoreGraphics

struct ScreenRegionSelection: Equatable {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let selectedRect: CGRect

    func imageCropRect(imageSize: CGSize) -> CGRect {
        let selectedRect = selectedRect.intersection(screenFrame)
        guard !selectedRect.isNull,
              selectedRect.width > 0,
              selectedRect.height > 0,
              screenFrame.width > 0,
              screenFrame.height > 0,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return .null
        }

        let scaleX = imageSize.width / screenFrame.width
        let scaleY = imageSize.height / screenFrame.height
        let localMinX = selectedRect.minX - screenFrame.minX
        let localMinY = selectedRect.minY - screenFrame.minY

        return CGRect(
            x: localMinX * scaleX,
            y: imageSize.height - ((localMinY + selectedRect.height) * scaleY),
            width: selectedRect.width * scaleX,
            height: selectedRect.height * scaleY
        )
        .intersection(CGRect(origin: .zero, size: imageSize))
        .integral
    }
}

@MainActor
final class ScreenRegionSelector {
    private var activeSession: ScreenRegionSelectionSession?

    func selectRegion() async -> ScreenRegionSelection? {
        guard activeSession == nil else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let session = ScreenRegionSelectionSession { [weak self] selection in
                self?.activeSession = nil
                continuation.resume(returning: selection)
            }

            activeSession = session
            session.start()
        }
    }
}

@MainActor
private final class ScreenRegionSelectionSession {
    private let completion: (ScreenRegionSelection?) -> Void
    private var panels: [NSPanel] = []
    private var keyMonitor: Any?
    private var isFinished = false
    private var didPushCursor = false

    init(completion: @escaping (ScreenRegionSelection?) -> Void) {
        self.completion = completion
    }

    func start() {
        let screens = NSScreen.screens

        guard !screens.isEmpty else {
            finish(with: nil)
            return
        }

        for screen in screens {
            guard let displayID = Self.displayID(for: screen) else {
                continue
            }

            let panel = ScreenRegionSelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            let selectionView = ScreenRegionSelectionView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                screenFrame: screen.frame,
                displayID: displayID,
                onSelection: { [weak self] selection in
                    self?.finish(with: selection)
                }
            )

            panel.contentView = selectionView
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            panels.append(panel)
        }

        guard !panels.isEmpty else {
            finish(with: nil)
            return
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else {
                return event
            }

            self?.finish(with: nil)
            return nil
        }

        NSApp.activate(ignoringOtherApps: true)
        panels.forEach { $0.orderFrontRegardless() }

        let pointer = NSEvent.mouseLocation
        let activePanel = panels.first { $0.frame.contains(pointer) } ?? panels[0]
        activePanel.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
        didPushCursor = true
    }

    private func finish(with selection: ScreenRegionSelection?) {
        guard !isFinished else {
            return
        }

        isFinished = true

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }

        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        if didPushCursor {
            NSCursor.pop()
        }
        completion(selection)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}

private final class ScreenRegionSelectionPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class ScreenRegionSelectionView: NSView {
    private let screenFrame: CGRect
    private let displayID: CGDirectDisplayID
    private let onSelection: (ScreenRegionSelection) -> Void
    private var dragOrigin: CGPoint?
    private var selectionRect = CGRect.zero

    init(
        frame frameRect: NSRect,
        screenFrame: CGRect,
        displayID: CGDirectDisplayID,
        onSelection: @escaping (ScreenRegionSelection) -> Void
    ) {
        self.screenFrame = screenFrame
        self.displayID = displayID
        self.onSelection = onSelection
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        selectionRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else {
            return
        }

        selectionRect = normalizedRect(from: dragOrigin, to: convert(event.locationInWindow, from: nil))
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragOrigin else {
            return
        }

        let finalRect = normalizedRect(from: dragOrigin, to: convert(event.locationInWindow, from: nil))
            .intersection(bounds)
        self.dragOrigin = nil

        guard finalRect.width >= 12, finalRect.height >= 12, let window else {
            selectionRect = .zero
            needsDisplay = true
            return
        }

        let screenRect = window.convertToScreen(finalRect)
        onSelection(
            ScreenRegionSelection(
                displayID: displayID,
                screenFrame: screenFrame,
                selectedRect: screenRect
            )
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let shade = NSBezierPath(rect: bounds)
        if !selectionRect.isEmpty {
            shade.appendRect(selectionRect)
        }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.32).setFill()
        shade.fill()

        if !selectionRect.isEmpty {
            NSColor.white.withAlphaComponent(0.96).setStroke()
            let outerStroke = NSBezierPath(roundedRect: selectionRect.insetBy(dx: -1, dy: -1), xRadius: 7, yRadius: 7)
            outerStroke.lineWidth = 4
            outerStroke.stroke()

            NSColor(calibratedRed: 0.12, green: 0.48, blue: 1.0, alpha: 1).setStroke()
            let accentStroke = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
            accentStroke.lineWidth = 2
            accentStroke.stroke()
        }

        drawInstructions()
    }

    private func drawInstructions() {
        let text = "Drag around the text to read  ·  Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let labelRect = CGRect(
            x: bounds.midX - (size.width + 32) / 2,
            y: bounds.maxY - size.height - 40,
            width: size.width + 32,
            height: size.height + 18
        )

        NSColor(calibratedWhite: 0.08, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 10, yRadius: 10).fill()
        (text as NSString).draw(
            at: CGPoint(x: labelRect.minX + 16, y: labelRect.minY + 9),
            withAttributes: attributes
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
