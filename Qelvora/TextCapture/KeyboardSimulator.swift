import ApplicationServices
import Foundation

struct KeyboardSimulator {
    private enum KeyCode {
        static let a: CGKeyCode = 0
        static let c: CGKeyCode = 8
        static let v: CGKeyCode = 9
        static let command: CGKeyCode = 55
        static let escape: CGKeyCode = 53
        static let shift: CGKeyCode = 56
        static let capsLock: CGKeyCode = 57
        static let option: CGKeyCode = 58
        static let control: CGKeyCode = 59
        static let rightShift: CGKeyCode = 60
        static let rightOption: CGKeyCode = 61
        static let rightControl: CGKeyCode = 62
        static let rightCommand: CGKeyCode = 54
    }

    func copy() {
        simulateCommandShortcut(keyCode: KeyCode.c)
    }

    func copy(processIdentifier: pid_t?) {
        simulateCommandShortcut(keyCode: KeyCode.c, processIdentifier: processIdentifier)
    }

    func copyViaMenu(processIdentifier: pid_t?) -> Bool {
        performMenuCommand(
            processIdentifier: processIdentifier,
            titles: ["Copy", "Copier"],
            commandCharacter: "C"
        )
    }

    func currentPointerLocation() -> CGPoint {
        currentMouseLocation()
    }

    func copyViaContextMenu(processIdentifier: pid_t?, at location: CGPoint? = nil) -> Bool {
        performContextMenuCommand(
            processIdentifier: processIdentifier,
            titles: ["Copy", "Copier"],
            commandCharacter: "C",
            location: location,
            allowsShortcutFallback: true
        )
    }

    func selectAll() {
        simulateCommandShortcut(keyCode: KeyCode.a)
    }

    func selectAll(processIdentifier: pid_t?) {
        simulateCommandShortcut(keyCode: KeyCode.a, processIdentifier: processIdentifier)
    }

    func selectAllViaMenu(processIdentifier: pid_t?) -> Bool {
        performMenuCommand(
            processIdentifier: processIdentifier,
            titles: ["Select All", "Tout sélectionner", "Tout selectionner"],
            commandCharacter: "A"
        )
    }

    func paste() {
        simulateCommandShortcut(keyCode: KeyCode.v)
    }

    func paste(processIdentifier: pid_t?) {
        simulateCommandShortcut(keyCode: KeyCode.v, processIdentifier: processIdentifier)
    }

    func pasteViaMenu(processIdentifier: pid_t?) -> Bool {
        performMenuCommand(
            processIdentifier: processIdentifier,
            titles: ["Paste", "Coller"],
            commandCharacter: "V"
        )
    }

    func pasteViaContextMenu(processIdentifier: pid_t?, at location: CGPoint? = nil) -> Bool {
        performContextMenuCommand(
            processIdentifier: processIdentifier,
            titles: ["Paste", "Coller"],
            commandCharacter: "V",
            location: location,
            allowsShortcutFallback: false
        )
    }

    private func simulateCommandShortcut(keyCode: CGKeyCode, processIdentifier: pid_t? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        releaseModifiers(source: source, processIdentifier: processIdentifier)
        usleep(25_000)

        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.command, keyDown: true)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.command, keyDown: false)

        commandDown?.flags = .maskCommand
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        commandUp?.flags = []

        post(commandDown, processIdentifier: processIdentifier)
        usleep(20_000)
        post(keyDown, processIdentifier: processIdentifier)
        usleep(35_000)
        post(keyUp, processIdentifier: processIdentifier)
        usleep(20_000)
        post(commandUp, processIdentifier: processIdentifier)
    }

    private func simulatePlainKey(keyCode: CGKeyCode, processIdentifier: pid_t? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = []
        keyUp?.flags = []

        post(keyDown, processIdentifier: processIdentifier)
        usleep(20_000)
        post(keyUp, processIdentifier: processIdentifier)
    }

    private func releaseModifiers(source: CGEventSource?, processIdentifier: pid_t?) {
        [
            KeyCode.command,
            KeyCode.rightCommand,
            KeyCode.shift,
            KeyCode.rightShift,
            KeyCode.option,
            KeyCode.rightOption,
            KeyCode.control,
            KeyCode.rightControl,
            KeyCode.capsLock
        ].forEach { keyCode in
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            event?.flags = []
            post(event, processIdentifier: processIdentifier)
        }
    }

    private func post(_ event: CGEvent?, processIdentifier: pid_t?) {
        guard let event else {
            return
        }

        if let processIdentifier {
            event.postToPid(processIdentifier)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    private func performMenuCommand(
        processIdentifier: pid_t?,
        titles: [String],
        commandCharacter: String
    ) -> Bool {
        guard let processIdentifier else {
            return false
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, from: application) else {
            return false
        }

        if pressMenuItem(
            in: menuBar,
            titles: titles,
            commandCharacter: commandCharacter,
            allowsCommandCharacterFallback: false
        ) {
            return true
        }

        if let editMenu = editMenuItem(in: menuBar) {
            _ = AXUIElementPerformAction(editMenu, kAXPressAction as CFString)
            usleep(120_000)

            if pressMenuItem(
                in: editMenu,
                titles: titles,
                commandCharacter: commandCharacter,
                allowsCommandCharacterFallback: true
            ) {
                return true
            }

            if pressMenuItem(
                in: menuBar,
                titles: titles,
                commandCharacter: commandCharacter,
                allowsCommandCharacterFallback: false
            ) {
                return true
            }
        }

        return false
    }

    private func performContextMenuCommand(
        processIdentifier: pid_t?,
        titles: [String],
        commandCharacter: String,
        location: CGPoint?,
        allowsShortcutFallback: Bool
    ) -> Bool {
        let mouseLocation = location ?? currentMouseLocation()
        rightClick(at: mouseLocation)
        usleep(220_000)

        let roots = contextMenuSearchRoots(processIdentifier: processIdentifier)

        for root in roots {
            if pressMenuItem(
                in: root,
                titles: titles,
                commandCharacter: commandCharacter,
                allowsCommandCharacterFallback: false,
                maxDepth: 12,
                limit: 1_400
            ) {
                return true
            }
        }

        if allowsShortcutFallback, let keyCode = keyCode(forCommandCharacter: commandCharacter) {
            simulateCommandShortcut(keyCode: keyCode, processIdentifier: processIdentifier)
            usleep(140_000)
            return true
        }

        // If the menu is open but no usable item was found, close it so the next
        // fallback does not operate with a context menu still covering the app.
        simulatePlainKey(keyCode: KeyCode.escape, processIdentifier: processIdentifier)
        return false
    }

    private func keyCode(forCommandCharacter commandCharacter: String) -> CGKeyCode? {
        switch commandCharacter.uppercased() {
        case "A":
            return KeyCode.a
        case "C":
            return KeyCode.c
        case "V":
            return KeyCode.v
        default:
            return nil
        }
    }

    private func editMenuItem(in menuBar: AXUIElement) -> AXUIElement? {
        let editTitles = ["Edit", "Édition", "Edition", "Modifier"]

        return descendants(of: menuBar, maxDepth: 3, limit: 80).first { element in
            guard let title = stringAttribute(kAXTitleAttribute, from: element) else {
                return false
            }

            return editTitles.contains { title.caseInsensitiveCompare($0) == .orderedSame }
        }
    }

    private func pressMenuItem(
        in root: AXUIElement,
        titles: [String],
        commandCharacter: String,
        allowsCommandCharacterFallback: Bool,
        maxDepth: Int = 8,
        limit: Int = 600
    ) -> Bool {
        let commandCharacter = commandCharacter.uppercased()
        let candidates = descendants(of: root, maxDepth: maxDepth, limit: limit)

        for element in candidates where menuItemMatches(
            element,
            titles: titles,
            commandCharacter: commandCharacter,
            allowsCommandCharacterFallback: allowsCommandCharacterFallback
        ) {
            if let isEnabled = boolAttribute(kAXEnabledAttribute, from: element), !isEnabled {
                continue
            }

            if pressElement(element) {
                return true
            }
        }

        return false
    }

    private func pressElement(_ element: AXUIElement) -> Bool {
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            usleep(120_000)
            return true
        }

        guard let frame = frame(of: element) else {
            return false
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        leftClick(at: center)
        usleep(120_000)
        return true
    }

    private func menuItemMatches(
        _ element: AXUIElement,
        titles: [String],
        commandCharacter: String,
        allowsCommandCharacterFallback: Bool
    ) -> Bool {
        if let title = stringAttribute(kAXTitleAttribute, from: element),
           titles.contains(where: { title.caseInsensitiveCompare($0) == .orderedSame }) {
            return true
        }

        guard allowsCommandCharacterFallback else {
            return false
        }

        if let command = stringAttribute(kAXMenuItemCmdCharAttribute, from: element) {
            return command.uppercased() == commandCharacter
        }

        return false
    }

    private func descendants(of element: AXUIElement, maxDepth: Int, limit: Int) -> [AXUIElement] {
        guard maxDepth > 0, limit > 0 else {
            return []
        }

        let children = childElements(of: element)
        var result = Array(children.prefix(limit))

        for child in children where result.count < limit {
            let remainingLimit = limit - result.count
            result.append(contentsOf: descendants(of: child, maxDepth: maxDepth - 1, limit: remainingLimit))
        }

        return result
    }

    private func contextMenuSearchRoots(processIdentifier: pid_t?) -> [AXUIElement] {
        var roots: [AXUIElement] = []

        if let elementAtMouse = elementAtCurrentMouseLocation() {
            roots.append(elementAtMouse)
            roots.append(contentsOf: ancestors(of: elementAtMouse, limit: 8))
        }

        if let processIdentifier {
            let application = AXUIElementCreateApplication(processIdentifier)
            roots.append(application)

            if let focusedElement = elementAttribute(kAXFocusedUIElementAttribute, from: application) {
                roots.append(focusedElement)
                roots.append(contentsOf: ancestors(of: focusedElement, limit: 5))
            }

            if let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: application) {
                roots.append(focusedWindow)
            }
        }

        return roots
    }

    private func ancestors(of element: AXUIElement, limit: Int) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var current = element

        for _ in 0..<limit {
            guard let parent = elementAttribute(kAXParentAttribute, from: current) else {
                break
            }

            result.append(parent)
            current = parent
        }

        return result
    }

    private func elementAtCurrentMouseLocation() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        let location = currentMouseLocation()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(location.x),
            Float(location.y),
            &element
        )

        guard result == .success else {
            return nil
        }

        return element
    }

    private func currentMouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func rightClick(at location: CGPoint) {
        mouseClick(at: location, button: .right, downType: .rightMouseDown, upType: .rightMouseUp)
    }

    private func leftClick(at location: CGPoint) {
        mouseClick(at: location, button: .left, downType: .leftMouseDown, upType: .leftMouseUp)
    }

    private func mouseClick(
        at location: CGPoint,
        button: CGMouseButton,
        downType: CGEventType,
        upType: CGEventType
    ) {
        let source = CGEventSource(stateID: .hidSystemState)
        let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: location,
            mouseButton: button
        )
        let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: location,
            mouseButton: button
        )

        mouseDown?.post(tap: .cghidEventTap)
        usleep(45_000)
        mouseUp?.post(tap: .cghidEventTap)
    }

    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        var children: [AXUIElement] = []

        for attributeName in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, kAXMenuBarAttribute] {
            if let elements = elementArrayAttribute(attributeName, from: element) {
                children.append(contentsOf: elements)
            }
        }

        return children
    }

    private func elementAttribute(_ attributeName: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)

        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func elementArrayAttribute(_ attributeName: String, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)

        guard result == .success, let value else {
            return nil
        }

        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [(value as! AXUIElement)]
        }

        guard let values = value as? [CFTypeRef] else {
            return nil
        }

        return values.compactMap { value in
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return nil
            }

            return (value as! AXUIElement)
        }
    }

    private func stringAttribute(_ attributeName: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)

        guard result == .success else {
            return nil
        }

        return value as? String
    }

    private func boolAttribute(_ attributeName: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)

        guard result == .success else {
            return nil
        }

        return value as? Bool
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute, from: element),
              let size = sizeAttribute(kAXSizeAttribute, from: element) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func pointAttribute(_ attributeName: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeAttribute(_ attributeName: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)

        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }
}
