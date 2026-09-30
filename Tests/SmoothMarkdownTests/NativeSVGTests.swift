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

    func testArcPathEndsAtRequestedPointAndCurvesBeyondChord() {
        let path = SVGPathData.parse("M 0 50 A 50 50 0 0 1 100 50")
        guard let path else { XCTFail("Arc path should parse"); return }
        XCTAssertEqual(path.boundingRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(path.boundingRect.maxX, 100, accuracy: 0.001)
        XCTAssertGreaterThan(path.boundingRect.height, 40)
    }

    func testMissingBundleResourceReturnsNil() {
        XCTAssertNil(SVG(named: "missing.svg", in: .module))
    }
}

#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class NativeSVGPixelTests: XCTestCase {
    private func bitmap(_ source: String, width: Int = 100, height: Int = 100) -> NSBitmapImageRep? {
        guard let svg = SVG(data: Data(source.utf8)) else { return nil }
        let renderer = ImageRenderer(content: SVGView(svg: svg).frame(width: CGFloat(width), height: CGFloat(height)))
        renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
        guard let data = renderer.nsImage?.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: data)
    }

    func testBasicPathRendersPixels() {
        let image = bitmap("<svg width='100' height='100'><path d='M10 10 L90 10 L90 90 L10 90 Z' fill='#ff0000'/></svg>")
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.colorAt(x: 50, y: 50)?.alphaComponent ?? 0, 0.9)
        XCTAssertLessThan(image?.colorAt(x: 2, y: 2)?.alphaComponent ?? 1, 0.1)
    }

    func testUseReferenceRendersDefinition() {
        let image = bitmap("<svg width='100' height='100'><defs><rect id='tile' width='20' height='20' fill='blue'/></defs><use href='#tile' x='40' y='40'/></svg>")
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.colorAt(x: 50, y: 50)?.alphaComponent ?? 0, 0.9)
        XCTAssertLessThan(image?.colorAt(x: 10, y: 10)?.alphaComponent ?? 1, 0.1)
    }

    func testUserSpacePatternRepeats() {
        let source = "<svg width='100' height='100'><defs><pattern id='dots' patternUnits='userSpaceOnUse' width='20' height='20'><rect width='10' height='10' fill='red'/></pattern></defs><rect width='100' height='100' fill='url(#dots)'/></svg>"
        let image = bitmap(source)
        XCTAssertGreaterThan(image?.colorAt(x: 5, y: 5)?.alphaComponent ?? 0, 0.9)
        XCTAssertLessThan(image?.colorAt(x: 15, y: 15)?.alphaComponent ?? 1, 0.1)
        XCTAssertGreaterThan(image?.colorAt(x: 25, y: 25)?.alphaComponent ?? 0, 0.9)
    }

    func testGaussianBlurSoftensEdge() {
        let source = "<svg width='100' height='100'><defs><filter id='soft'><feGaussianBlur stdDeviation='8'/></filter></defs><rect x='40' y='40' width='20' height='20' fill='red' filter='url(#soft)'/></svg>"
        let image = bitmap(source)
        XCTAssertGreaterThan(image?.colorAt(x: 50, y: 50)?.alphaComponent ?? 0, 0.5)
        XCTAssertGreaterThan(image?.colorAt(x: 37, y: 50)?.alphaComponent ?? 0, 0.01)
        XCTAssertLessThan(image?.colorAt(x: 37, y: 50)?.alphaComponent ?? 1, 0.9)
    }

    func testSimpleClassStylesheetAndInlineOverride() {
        let source = "<svg width='100' height='100'><style>.mark { fill: red; }</style><rect class='mark' x='0' y='0' width='40' height='40'/><rect class='mark' style='fill: blue' x='60' y='0' width='40' height='40'/></svg>"
        let image = bitmap(source)
        let left = image?.colorAt(x: 20, y: 20)?.usingColorSpace(.deviceRGB)
        let right = image?.colorAt(x: 80, y: 20)?.usingColorSpace(.deviceRGB)
        XCTAssertGreaterThan(left?.redComponent ?? 0, left?.blueComponent ?? 1)
        XCTAssertGreaterThan(right?.blueComponent ?? 0, right?.redComponent ?? 1)
    }

    func testAlphaMaskLimitsPaintedArea() {
        let source = "<svg width='100' height='100'><defs><mask id='window'><circle cx='50' cy='50' r='20' fill='white'/></mask></defs><rect width='100' height='100' fill='red' mask='url(#window)'/></svg>"
        let image = bitmap(source)
        XCTAssertGreaterThan(image?.colorAt(x: 50, y: 50)?.alphaComponent ?? 0, 0.9)
        XCTAssertLessThan(image?.colorAt(x: 10, y: 10)?.alphaComponent ?? 1, 0.1)
    }

    func testClipPathLimitsPaintedArea() {
        let source = "<svg width='100' height='100'><defs><clipPath id='cut'><circle cx='50' cy='50' r='20'/></clipPath></defs><rect width='100' height='100' fill='red' clip-path='url(#cut)'/></svg>"
        let image = bitmap(source)
        XCTAssertGreaterThan(image?.colorAt(x: 50, y: 50)?.alphaComponent ?? 0, 0.9)
        XCTAssertLessThan(image?.colorAt(x: 10, y: 10)?.alphaComponent ?? 1, 0.1)
    }

    func testRadialGradientHasDistinctCenterAndEdge() {
        let source = "<svg width='100' height='100'><defs><radialGradient id='glow'><stop offset='0%' stop-color='red'/><stop offset='100%' stop-color='blue'/></radialGradient></defs><rect width='100' height='100' fill='url(#glow)'/></svg>"
        guard let image = bitmap(source),
              let center = image.colorAt(x: 50, y: 50)?.usingColorSpace(.deviceRGB),
              let edge = image.colorAt(x: 5, y: 50)?.usingColorSpace(.deviceRGB) else {
            XCTFail("Gradient should render"); return
        }
        XCTAssertGreaterThan(center.redComponent, edge.redComponent)
        XCTAssertGreaterThan(edge.blueComponent, center.blueComponent)
    }

    func testEmbeddedPNGAndTextRenderPixels() {
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")!
        let source = "<svg width='100' height='100'><image href='data:image/png;base64,\(data.base64EncodedString())' x='10' y='10' width='30' height='30'/><text x='50' y='80' font-size='24'>Hi</text></svg>"
        let image = bitmap(source)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.colorAt(x: 20, y: 20)?.alphaComponent ?? 0, 0.9)
        var textPixels = 0
        if let image {
            for y in 50..<90 { for x in 40..<90 {
                if (image.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { textPixels += 1 }
            } }
        }
        XCTAssertGreaterThan(textPixels, 10)
    }
}
#endif
