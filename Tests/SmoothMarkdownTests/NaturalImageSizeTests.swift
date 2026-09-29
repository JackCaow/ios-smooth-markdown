import CoreGraphics
import XCTest
@testable import SmoothMarkdown

final class NaturalImageSizeTests: XCTestCase {
    func testNaturalSizeIsUsedUntilContainerIsNarrower() {
        let natural = CGSize(width: 240, height: 120)
        XCTAssertEqual(NaturalImageLayout.resolvedSize(natural: natural, width: nil, height: nil,
                                                        availableWidth: 400), natural)
        XCTAssertEqual(NaturalImageLayout.resolvedSize(natural: natural, width: nil, height: nil,
                                                        availableWidth: 150), CGSize(width: 150, height: 75))
    }

    func testExplicitHTMLDimensionsPreserveTheirBoxAndCapProportionally() {
        let natural = CGSize(width: 200, height: 100)
        XCTAssertEqual(NaturalImageLayout.resolvedSize(natural: natural, width: 80, height: 60,
                                                        availableWidth: 400), CGSize(width: 80, height: 60))
        XCTAssertEqual(NaturalImageLayout.resolvedSize(natural: natural, width: 80, height: nil,
                                                        availableWidth: 400), CGSize(width: 80, height: 40))
        XCTAssertEqual(NaturalImageLayout.resolvedSize(natural: natural, width: nil, height: 60,
                                                        availableWidth: 100), CGSize(width: 100, height: 50))
    }
}
