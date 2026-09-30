import XCTest
@testable import SmoothMarkdown

final class NativeSVGTests: XCTestCase {
    func testViewBoxProvidesNaturalSize() {
        let svg = SVG(data: Data("<svg xmlns='http://www.w3.org/2000/svg' viewBox='4 8 120 60'><rect width='120' height='60'/></svg>".utf8))
        XCTAssertEqual(svg?.size, CGSize(width: 120, height: 60))
    }

    func testExplicitSizesAndUnits() {
        let svg = SVG(data: Data("<svg width='72pt' height='1in'><path d='M0 0 L96 0 L96 96 Z'/></svg>".utf8))
        XCTAssertEqual(svg?.size, CGSize(width: 96, height: 96))
    }

    func testMalformedAndOversizedDocumentsAreRejected() {
        XCTAssertNil(SVG(data: Data("broken".utf8)))
        XCTAssertNil(SVG(data: Data("<svg width='10' height='10'><rect></svg>".utf8)))
        XCTAssertNil(SVG(data: Data("<svg width='0' height='20'/>".utf8)))
        XCTAssertNil(SVG(data: Data("<svg width='20000' height='20'/>".utf8)))
        XCTAssertNil(SVG(data: Data(count: 2 * 1024 * 1024 + 1)))
    }

    func testMissingBundleResourceReturnsNil() {
        XCTAssertNil(SVG(named: "missing.svg", in: .module))
    }
}
