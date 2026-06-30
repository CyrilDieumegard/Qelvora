import AppKit

struct PasteboardSnapshot: Equatable {
    private let itemData: [[NSPasteboard.PasteboardType: Data]]

    var isEmpty: Bool {
        itemData.isEmpty
    }

    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems ?? []
        let capturedItems = items.map { item in
            var capturedItem: [NSPasteboard.PasteboardType: Data] = [:]

            item.types.forEach { type in
                if let data = item.data(forType: type) {
                    capturedItem[type] = data
                }
            }

            return capturedItem
        }

        return PasteboardSnapshot(itemData: capturedItems)
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()

        let restoredItems = itemData.map { capturedItem in
            let item = NSPasteboardItem()
            capturedItem.forEach { type, data in
                item.setData(data, forType: type)
            }
            return item
        }

        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
