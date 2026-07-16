import CoreGraphics
import XCTest
@testable import Qelvora

final class ScreenRegionSelectionTests: XCTestCase {
    func testMapsRetinaSelectionIntoImagePixelsAndFlipsYAxis() {
        let selection = ScreenRegionSelection(
            displayID: 1,
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            selectedRect: CGRect(x: 100, y: 100, width: 300, height: 200)
        )

        XCTAssertEqual(
            selection.imageCropRect(imageSize: CGSize(width: 2_880, height: 1_800)),
            CGRect(x: 200, y: 1_200, width: 600, height: 400)
        )
    }

    func testMapsSelectionOnDisplayWithNegativeOrigin() {
        let selection = ScreenRegionSelection(
            displayID: 2,
            screenFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            selectedRect: CGRect(x: -1_820, y: 80, width: 400, height: 200)
        )

        XCTAssertEqual(
            selection.imageCropRect(imageSize: CGSize(width: 1_920, height: 1_080)),
            CGRect(x: 100, y: 800, width: 400, height: 200)
        )
    }

    func testClipsSelectionToItsDisplay() {
        let selection = ScreenRegionSelection(
            displayID: 3,
            screenFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            selectedRect: CGRect(x: 900, y: 700, width: 200, height: 200)
        )

        XCTAssertEqual(
            selection.imageCropRect(imageSize: CGSize(width: 2_000, height: 1_600)),
            CGRect(x: 1_800, y: 0, width: 200, height: 200)
        )
    }

    func testScreenRegionCaptureNeverRequestsAutomaticReplacement() {
        let capturedText = CapturedText(text: "Visible text", source: .screenRegion)

        XCTAssertFalse(capturedText.shouldReplaceSelection)
    }
}
