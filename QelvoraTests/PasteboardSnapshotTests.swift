import AppKit
import XCTest
@testable import Qelvora

final class PasteboardSnapshotTests: XCTestCase {
    func testRestoresStringAndHTMLPasteboardItems() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("QelvoraTests.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString("bonjour", forType: .string)
        item.setString("<strong>bonjour</strong>", forType: .html)
        pasteboard.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("au revoir", forType: .string)

        snapshot.restore(to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "bonjour")
        XCTAssertEqual(pasteboard.string(forType: .html), "<strong>bonjour</strong>")
    }

    func testRestoresEmptyPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("QelvoraTests.\(UUID().uuidString)"))
        pasteboard.clearContents()

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.setString("temporary", forType: .string)

        snapshot.restore(to: pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string))
    }
}

