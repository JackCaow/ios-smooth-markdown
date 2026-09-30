import Foundation
import XCTest
@testable import SmoothMarkdown

final class ReaderImageSelectionProjectionTests: XCTestCase {
    func testAttributedStyleUpdateRetainsUTF16SelectionOnlyForSameText() {
        let source = "Before 😀\n█\nAfter"
        let range = (source as NSString).range(of: "😀\n█\nAfter")
        XCTAssertEqual(ReaderImageSelectionProjection.retainedRange(range, oldText: source,
                                                                   newText: source), range)
        XCTAssertNil(ReaderImageSelectionProjection.retainedRange(range, oldText: source,
                                                                  newText: "Replaced text"))
        XCTAssertNil(ReaderImageSelectionProjection.retainedRange(
            NSRange(location: (source as NSString).length + 1, length: 1),
            oldText: source, newText: source))
    }

    func testCopyAcrossTwoImagesKeepsOnlySurroundingText() {
        let source = "Before 😀\n█\nMiddle\n█\nAfter"
        let text = source as NSString
        let first = text.range(of: "█").location
        let second = text.range(of: "█", options: [], range: NSRange(location: first + 1,
                                                                    length: text.length - first - 1)).location
        XCTAssertEqual(ReaderImageSelectionProjection.copiedText(
            source, selectionStart: 0, imageAnchors: [first, second]),
                       "Before 😀\nMiddle\nAfter")
        let partial = text.substring(from: text.range(of: "Middle").location)
        XCTAssertEqual(ReaderImageSelectionProjection.copiedText(
            partial, selectionStart: text.range(of: "Middle").location,
            imageAnchors: [first, second]), "Middle\nAfter")
    }

    func testDraggingEitherDirectionCrossesAnyImageAnchor() {
        XCTAssertTrue(ReaderImageSelectionProjection.crossesImage(from: 0, to: 15, imageAnchors: [4, 12]))
        XCTAssertTrue(ReaderImageSelectionProjection.crossesImage(from: 15, to: 0, imageAnchors: [4, 12]))
        XCTAssertFalse(ReaderImageSelectionProjection.crossesImage(from: 5, to: 10, imageAnchors: [4, 12]))
    }

    func testCopyRejectsMismatchedAnchorOffset() {
        XCTAssertNil(ReaderImageSelectionProjection.copiedText("text", selectionStart: 0,
                                                                 imageAnchors: [2]))
    }
}
