import AppKit
import XCTest
@testable import Qelvora

final class SelectionHighlightDetectorTests: XCTestCase {
    func testIgnoresBlueLinkTextWithoutSelectionBackground() throws {
        let image = try makeImage { _ in
            drawText(
                "Qelvora-0.1.0.dmg",
                at: CGPoint(x: 42, y: 92),
                color: NSColor(calibratedRed: 0.35, green: 0.68, blue: 1.0, alpha: 1),
                fontSize: 24
            )
        }

        let region = SelectionHighlightDetector().selectionRegion(
            in: image,
            searchRects: [CGRect(x: 0, y: 0, width: image.width, height: image.height)],
            pointerPoints: [CGPoint(x: 120, y: 108)]
        )

        XCTAssertNil(region)
    }

    func testDetectsSolidSelectionHighlightBehindText() throws {
        let image = try makeImage { _ in
            NSColor(calibratedRed: 0.22, green: 0.39, blue: 0.61, alpha: 1).setFill()
            NSRect(x: 36, y: 100, width: 390, height: 34).fill()

            drawText(
                "Le warning Accessibilité venait d'un check macOS trop strict",
                at: CGPoint(x: 44, y: 104),
                color: .white,
                fontSize: 22
            )
        }

        let region = try XCTUnwrap(
            SelectionHighlightDetector().selectionRegion(
                in: image,
                searchRects: [CGRect(x: 0, y: 0, width: image.width, height: image.height)],
                pointerPoints: [CGPoint(x: 500, y: 220)]
            )
        )

        XCTAssertGreaterThan(region.rect.width, 300)
        XCTAssertGreaterThan(region.rect.height, 20)
    }

    func testIgnoresSelectionHighlightTooFarFromPointer() throws {
        let image = try makeImage { _ in
            NSColor(calibratedRed: 0.22, green: 0.39, blue: 0.61, alpha: 1).setFill()
            NSRect(x: 36, y: 44, width: 260, height: 30).fill()

            drawText(
                "Texte selectionne tres loin",
                at: CGPoint(x: 44, y: 48),
                color: .white,
                fontSize: 19
            )
        }

        let region = SelectionHighlightDetector().selectionRegion(
            in: image,
            searchRects: [CGRect(x: 0, y: 0, width: image.width, height: image.height)],
            pointerPoints: [CGPoint(x: CGFloat(image.width) - 8, y: CGFloat(image.height) - 8)]
        )

        XCTAssertNil(region)
    }

    private func makeImage(
        draw: (NSRect) -> Void
    ) throws -> CGImage {
        let size = NSSize(width: 620, height: 260)
        let image = NSImage(size: size)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: size)
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        bounds.fill()
        draw(bounds)

        image.unlockFocus()

        var proposedRect = bounds
        return try XCTUnwrap(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
    }

    private func drawText(
        _ text: String,
        at point: CGPoint,
        color: NSColor,
        fontSize: CGFloat
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular)
        ]

        (text as NSString).draw(at: point, withAttributes: attributes)
    }
}

final class QelvoraServicesTests: XCTestCase {
    func testCorrectionPanelServiceIsDeclaredForPlainTextInputWithoutContextRestriction() throws {
        let bundle = Bundle(for: QelvoraServiceProvider.self)
        let services = try XCTUnwrap(bundle.infoDictionary?["NSServices"] as? [[String: Any]])
        let correctionPanelService = try XCTUnwrap(
            services.first { service in
                service["NSMessage"] as? String == "showCorrectionPanel"
            }
        )

        XCTAssertEqual(correctionPanelService["NSPortName"] as? String, "Qelvora")
        XCTAssertEqual(
            (correctionPanelService["NSMenuItem"] as? [String: String])?["default"],
            "Correct with Qelvora"
        )
        XCTAssertNil(correctionPanelService["NSRequiredContext"])
        XCTAssertNil(correctionPanelService["NSRestricted"])
        XCTAssertNil(correctionPanelService["NSReturnTypes"])
        XCTAssertEqual(correctionPanelService["NSTimeout"] as? Int, 120000)

        let sendTypes = try XCTUnwrap(correctionPanelService["NSSendTypes"] as? [String])

        XCTAssertTrue(sendTypes.contains("NSStringPboardType"))
        XCTAssertTrue(sendTypes.contains("public.utf8-plain-text"))
        XCTAssertTrue(sendTypes.contains("public.plain-text"))
        XCTAssertTrue(sendTypes.contains("public.text"))
    }

    func testReplacementServiceIsDeclaredForEditableTextContexts() throws {
        let bundle = Bundle(for: QelvoraServiceProvider.self)
        let services = try XCTUnwrap(bundle.infoDictionary?["NSServices"] as? [[String: Any]])
        let replacementService = try XCTUnwrap(
            services.first { service in
                service["NSMessage"] as? String == "correctSelection"
            }
        )

        XCTAssertEqual(replacementService["NSPortName"] as? String, "Qelvora")
        XCTAssertEqual(
            (replacementService["NSMenuItem"] as? [String: String])?["default"],
            "Replace with Qelvora"
        )
        XCTAssertNil(replacementService["NSRequiredContext"])

        let sendTypes = try XCTUnwrap(replacementService["NSSendTypes"] as? [String])
        let returnTypes = try XCTUnwrap(replacementService["NSReturnTypes"] as? [String])

        XCTAssertTrue(sendTypes.contains("NSStringPboardType"))
        XCTAssertTrue(sendTypes.contains("public.text"))
        XCTAssertTrue(returnTypes.contains("NSStringPboardType"))
        XCTAssertTrue(returnTypes.contains("public.text"))
        XCTAssertEqual(replacementService["NSTimeout"] as? Int, 120000)
    }

    func testBundleVersionIsBumpedForServiceCacheRefresh() throws {
        let bundle = Bundle(for: QelvoraServiceProvider.self)

        XCTAssertEqual(bundle.infoDictionary?["CFBundleShortVersionString"] as? String, "0.1.25")
        XCTAssertEqual(bundle.infoDictionary?["CFBundleVersion"] as? String, "26")
    }

    func testQelvoraURLSchemeIsDeclaredForUserServiceWorkflow() throws {
        let bundle = Bundle(for: QelvoraServiceProvider.self)
        let urlTypes = try XCTUnwrap(bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        XCTAssertTrue(schemes.contains("qelvora"))
    }

    func testUserWorkflowServiceUsesAutomatorServiceContract() throws {
        let infoPlist = UserServicesInstaller.infoPlist()
        let services = try XCTUnwrap(infoPlist["NSServices"] as? [[String: Any]])
        let service = try XCTUnwrap(services.first)

        XCTAssertEqual(infoPlist["CFBundleIdentifier"] as? String, "io.qelvora.Qelvora.CorrectService")
        XCTAssertEqual(service["NSMessage"] as? String, "runWorkflowAsService")
        XCTAssertEqual((service["NSMenuItem"] as? [String: String])?["default"], "Correct with Qelvora")
        XCTAssertEqual(service["NSSendTypes"] as? [String], ["public.utf8-plain-text"])
    }

    func testDefaultHotkeyUsesReadableTextInsteadOfKeyboardGlyphs() {
        XCTAssertEqual(Hotkey.default.displayString, "Option + Space")
        XCTAssertFalse(Hotkey.default.displayString.contains("⌥"))
        XCTAssertFalse(Hotkey.default.displayString.contains("⌘"))
        XCTAssertFalse(Hotkey.default.displayString.contains("⇧"))
        XCTAssertFalse(Hotkey.default.displayString.contains("⌃"))
    }
}
