import ApplicationServices
import Foundation

struct SelectedTextReader {
    func selectedTextFromFocusedElement() -> String? {
        selectedText(processIdentifier: nil)
    }

    func replaceSelectionInFocusedElement(with text: String) -> Bool {
        replaceSelection(processIdentifier: nil, with: text)
    }

    func selectedText(processIdentifier: pid_t?) -> String? {
        for element in candidateTextElements(processIdentifier: processIdentifier) {
            if let selectedText = selectedText(in: element) {
                return selectedText
            }
        }

        return nil
    }

    func replaceSelection(processIdentifier: pid_t?, with text: String) -> Bool {
        for element in candidateTextElements(processIdentifier: processIdentifier) {
            if replaceSelection(in: element, with: text) {
                return true
            }
        }

        return false
    }

    func focusedTextValue(processIdentifier: pid_t?) -> String? {
        for element in focusedTextCandidates(processIdentifier: processIdentifier) {
            if let text = stringAttribute(kAXValueAttribute, from: element),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        return nil
    }

    func replaceFocusedTextValue(processIdentifier: pid_t?, with text: String) -> Bool {
        for element in focusedTextCandidates(processIdentifier: processIdentifier) {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXValueAttribute as CFString,
                text as CFTypeRef
            )

            if result == .success {
                return true
            }
        }

        return false
    }

    private func selectedText(in element: AXUIElement) -> String? {
        if let selectedText = stringAttribute(kAXSelectedTextAttribute, from: element),
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedText
        }

        guard let selectedRange = selectedTextRange(in: element),
              selectedRange.location != kCFNotFound,
              selectedRange.length > 0,
              let currentText = stringAttribute(kAXValueAttribute, from: element) else {
            return nil
        }

        let nsText = currentText as NSString
        let range = NSRange(location: selectedRange.location, length: selectedRange.length)
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= nsText.length else {
            return nil
        }

        let selectedText = nsText.substring(with: range)
        return selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : selectedText
    }

    private func replaceSelection(in element: AXUIElement, with text: String) -> Bool {
        let directSetResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if directSetResult == .success {
            return true
        }

        guard let selectedRange = selectedTextRange(in: element) else {
            return false
        }

        guard selectedRange.location != kCFNotFound, selectedRange.length > 0 else {
            return false
        }

        guard let currentText = stringAttribute(kAXValueAttribute, from: element) else {
            return false
        }

        let nsText = currentText as NSString
        let range = NSRange(location: selectedRange.location, length: selectedRange.length)
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= nsText.length else {
            return false
        }

        let updatedText = nsText.replacingCharacters(in: range, with: text)
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            updatedText as CFTypeRef
        )

        guard setResult == .success else {
            return false
        }

        var insertedRange = CFRange(location: selectedRange.location, length: (text as NSString).length)
        if let insertedRangeValue = AXValueCreate(.cfRange, &insertedRange) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                insertedRangeValue
            )
        }

        return true
    }

    private func candidateTextElements(processIdentifier: pid_t?) -> [AXUIElement] {
        if let processIdentifier {
            return candidateTextElements(in: AXUIElementCreateApplication(processIdentifier))
        }

        var candidates: [AXUIElement] = []

        if let focusedElement = focusedElement() {
            candidates.append(focusedElement)
            candidates.append(contentsOf: descendants(of: focusedElement, maxDepth: 3, limit: 80))
        }

        if let focusedApplication = focusedApplication() {
            if let focusedElement = elementAttribute(kAXFocusedUIElementAttribute, from: focusedApplication) {
                candidates.append(focusedElement)
                candidates.append(contentsOf: descendants(of: focusedElement, maxDepth: 3, limit: 80))
            }

            if let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: focusedApplication) {
                candidates.append(focusedWindow)
                candidates.append(contentsOf: descendants(of: focusedWindow, maxDepth: 6, limit: 180))
            }
        }

        return candidates
    }

    private func focusedTextCandidates(processIdentifier: pid_t?) -> [AXUIElement] {
        var candidates: [AXUIElement] = []

        if let processIdentifier {
            let application = AXUIElementCreateApplication(processIdentifier)

            if let focusedElement = elementAttribute(kAXFocusedUIElementAttribute, from: application) {
                candidates.append(focusedElement)
                candidates.append(contentsOf: descendants(of: focusedElement, maxDepth: 2, limit: 40))
            }

            return candidates
        }

        if let focusedElement = focusedElement() {
            candidates.append(focusedElement)
            candidates.append(contentsOf: descendants(of: focusedElement, maxDepth: 2, limit: 40))
        }

        return candidates
    }

    private func candidateTextElements(in application: AXUIElement) -> [AXUIElement] {
        var candidates: [AXUIElement] = []

        if let focusedElement = elementAttribute(kAXFocusedUIElementAttribute, from: application) {
            candidates.append(focusedElement)
            candidates.append(contentsOf: descendants(of: focusedElement, maxDepth: 4, limit: 100))
        }

        if let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: application) {
            candidates.append(focusedWindow)
            candidates.append(contentsOf: descendants(of: focusedWindow, maxDepth: 7, limit: 220))
        }

        if let windows = elementArrayAttribute(kAXWindowsAttribute, from: application) {
            for window in windows.prefix(3) {
                candidates.append(window)
                candidates.append(contentsOf: descendants(of: window, maxDepth: 6, limit: 140))
            }
        }

        return candidates
    }

    private func focusedApplication() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        return elementAttribute(kAXFocusedApplicationAttribute, from: systemWideElement)
    }

    private func focusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        return elementAttribute(kAXFocusedUIElementAttribute, from: systemWideElement)
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

    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        var children: [AXUIElement] = []

        for attributeName in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, kAXContentsAttribute] {
            if let elements = elementArrayAttribute(attributeName, from: element) {
                children.append(contentsOf: elements)
            }
        }

        return children
    }

    private func selectedTextRange(in element: AXUIElement) -> CFRange? {
        guard let rangeAttribute = attribute(kAXSelectedTextRangeAttribute, from: element),
              CFGetTypeID(rangeAttribute) == AXValueGetTypeID() else {
            return nil
        }

        let rangeValue = rangeAttribute as! AXValue
        var selectedRange = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &selectedRange) else {
            return nil
        }

        return selectedRange
    }

    private func elementAttribute(_ attributeName: String, from element: AXUIElement) -> AXUIElement? {
        var focusedElementValue: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            element,
            attributeName as CFString,
            &focusedElementValue
        )

        guard focusResult == .success, let focusedElement = focusedElementValue else {
            return nil
        }

        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return nil
        }

        return (focusedElement as! AXUIElement)
    }

    private func elementArrayAttribute(_ attributeName: String, from element: AXUIElement) -> [AXUIElement]? {
        guard let value = attribute(attributeName, from: element) else {
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
        attribute(attributeName, from: element) as? String
    }

    private func attribute(_ attributeName: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attributeName as CFString, &value)

        guard result == .success else {
            return nil
        }

        return value
    }
}
