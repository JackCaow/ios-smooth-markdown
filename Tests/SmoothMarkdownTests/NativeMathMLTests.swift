import XCTest
import SwiftUI
@testable import SmoothMarkdown

final class NativeMathMLTests: XCTestCase {
    func testMathMLStructureAndEscaping() {
        let source = "\\left(\\frac{x_i}{2}\\right)+\\sqrt[3]{y}"
        let html = NativeMathML.html(source, display: true)
        XCTAssertTrue(html.contains("<mfrac>"))
        XCTAssertTrue(html.contains("<msub>"))
        XCTAssertTrue(html.contains("<mroot>"))
        XCTAssertTrue(html.contains("stretchy=\"true\""))
        XCTAssertTrue(NativeMathML.html("f(x)+F(b)", display: true)
            .contains("<mo stretchy=\"false\">(</mo>"))
        XCTAssertTrue(NativeMathML.html("a<b", display: false).contains("&lt;"))
    }

    func testMathMLMatrixColorAndLimits() {
        let html = NativeMathML.html("\\sum_{i=1}^{n}+\\textcolor{#aa0000}{\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}}", display: true)
        XCTAssertTrue(html.contains("<munderover>"))
        XCTAssertTrue(html.contains("mathcolor=\"#aa0000\""))
        XCTAssertTrue(html.contains("<mtable>"))
    }

    func testMathWhitespaceAndExplicitTextSpacing() {
        let math = NativeMathML.html("\\frac{\\partial}{\\partial t}", display: true)
        XCTAssertFalse(math.contains("<mspace"))
        XCTAssertTrue(math.contains("<mi>𝜕</mi><mi>t</mi>"))
        XCTAssertTrue(NativeMathML.html("\\text{with space}", display: false).contains("<mspace"))
        XCTAssertTrue(NativeMathML.html("a\\,b", display: false).contains("width=\"0.16666666666666666em\""))
        XCTAssertTrue(NativeMathML.html("a\\!b", display: false).contains("margin-left:-0.16666666666666666em"))
    }

    func testMathMLStylesAndColumnAlignment() {
        let html = NativeMathML.html("\\tfrac12+\\begin{array}{rl}x&=y\\end{array}", display: true)
        XCTAssertTrue(html.contains("displaystyle=\"false\""))
        XCTAssertTrue(html.contains("columnalign=\"right left\""))
        XCTAssertTrue(NativeMathML.html("\\scriptstyle{x}", display: true).contains("scriptlevel=\"1\""))
        XCTAssertTrue(NativeMathML.html("\\lim_{x\\to0}", display: true).contains("largeop=\"false\""))
    }

    func testThemeColorResolvesIntoSnapshotKeyColor() {
        XCTAssertEqual(NativeMathColorHex.resolve(Color(red: 1, green: 0, blue: 0), scheme: .light), "#FF0000")
        XCTAssertNotEqual(NativeMathColorHex.resolve(.primary, scheme: .light),
                          NativeMathColorHex.resolve(.primary, scheme: .dark))
    }
}

#if os(macOS)
import AppKit
import WebKit

private final class MathNavigationDelegate: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation
    init(_ finished: XCTestExpectation) { self.finished = finished }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished.fulfill() }
}

extension NativeMathMLTests {
    @MainActor
    func testOfflineWebKitMathMLSnapshot() throws {
        let finished = expectation(description: "offline MathML page loaded")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 720, height: 320))
        let delegate = MathNavigationDelegate(finished)
        web.navigationDelegate = delegate
        let source = "\\left(\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}\\right) + \\sum_{i=1}^{n}i"
        web.loadHTMLString(NativeMathML.html(source, display: true), baseURL: nil)
        wait(for: [finished], timeout: 15)
        let rendered = expectation(description: "MathML snapshot")
        var snapshot: NSImage?
        web.takeSnapshot(with: nil) { image, error in
            XCTAssertNil(error)
            snapshot = image
            rendered.fulfill()
        }
        wait(for: [rendered], timeout: 15)
        let image = try XCTUnwrap(snapshot)
        XCTAssertGreaterThan(image.size.width, 100)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1000)
        if let path = ProcessInfo.processInfo.environment["NATIVE_MATHML_SNAPSHOT_PATH"] {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor
    func testOfflineMathMLFeatureGallerySnapshot() throws {
        let samples: [(String, String)] = [
            ("Math alphabets", "\\mathbb{R}+\\mathfrak{g}+\\mathcal{F}+\\mathbf{B}"),
            ("Accents and fences", "\\left(\\widehat{xyz}+\\widetilde{abc}+\\vec{v}\\right)"),
            ("Nested matrix", "\\begin{pmatrix}\\begin{matrix}a&b\\\\c&d\\end{matrix}&x\\\\y&z\\end{pmatrix}"),
            ("Cases and limits", "\\begin{cases}x&x>0\\\\-x&x\\leq0\\end{cases}+\\sum_{i=1}^{n}i"),
            ("Colors and boxes", "\\textcolor{#bb0022}{\\sqrt{x}}+\\colorbox{#d5f7d5}{y}"),
            ("Integral and fraction", "\\int_{-\\infty}^{\\infty}e^{-x^2}dx=\\frac{\\sqrt{\\pi}}{2}")
        ]
        func card(_ title: String, _ source: String) -> String {
            "<div class=card><b>\(title)</b><math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\">" +
                NativeMathML.markup(NativeMathParser.parse(source), display: true) + "</math></div>"
        }
        let cards = samples.map { card($0.0, $0.1) }.joined()
        let dark = card("Dark mode and color", "\\mathbb{R}+\\textcolor{#ff7777}{\\frac{a}{b}}")
        let html = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:#fff;color:#111;font-family:system-ui}body{padding:24px}
        .card{margin:0 0 18px;padding:12px;border:1px solid #ddd;font-size:22px;min-height:80px}
        b{display:block;font:15px system-ui;margin-bottom:8px}math{font-family:serif}
        .dark{background:#1c1c1e;color:#fff;padding:14px}</style>
        \(cards)<div class=dark>\(dark)</div>
        """
        let finished = expectation(description: "feature gallery loaded")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1100))
        let delegate = MathNavigationDelegate(finished)
        web.navigationDelegate = delegate
        web.loadHTMLString(html, baseURL: nil)
        wait(for: [finished], timeout: 15)
        let captured = expectation(description: "gallery snapshot")
        var snapshot: NSImage?
        web.takeSnapshot(with: nil) { image, _ in snapshot = image; captured.fulfill() }
        wait(for: [captured], timeout: 15)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(snapshot?.tiffRepresentation)))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 20_000)
        if let path = ProcessInfo.processInfo.environment["NATIVE_MATHML_GALLERY_PATH"] {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif

#if os(macOS)
extension NativeMathMLTests {
    @MainActor
    func testSharedOfflineRendererMeasuresAndCachesSnapshots() async throws {
        let renderer = NativeMathSnapshotRenderer.shared
        let first = await renderer.render(latex: "\\left(\\frac{1}{2}\\right)", size: 20,
                                          display: true, colorHex: "#111111")
        let image = try XCTUnwrap(first)
        XCTAssertGreaterThan(image.size.width, 20)
        XCTAssertGreaterThan(image.size.height, 30)
        XCTAssertLessThan(image.size.width, 2048)
        let cached = await renderer.render(latex: "\\left(\\frac{1}{2}\\right)", size: 20,
                                           display: true, colorHex: "#111111")
        XCTAssertTrue(image === cached)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.05,
                          "Cropped formula background should remain transparent")
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        if let path = ProcessInfo.processInfo.environment["NATIVE_MATHML_CROPPED_PATH"] {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor
    func testWideFormulaUsesMeasuredViewport() async throws {
        let formula = String(repeating: "x+", count: 180) + "x"
        let rendered = await NativeMathSnapshotRenderer.shared.render(
            latex: formula, size: 20, display: true, colorHex: "#111111")
        let image = try XCTUnwrap(rendered)
        XCTAssertGreaterThan(image.size.width, 2048)
        XCTAssertLessThan(image.size.width, 8192)
    }

    @MainActor
    func testNegativeMathKernNarrowsRenderedFormula() async throws {
        let normal = await NativeMathSnapshotRenderer.shared.render(
            latex: "ab", size: 28, display: false, colorHex: "#111111")
        let tightened = await NativeMathSnapshotRenderer.shared.render(
            latex: "a\\!b", size: 28, display: false, colorHex: "#111111")
        XCTAssertLessThan(try XCTUnwrap(tightened).size.width, try XCTUnwrap(normal).size.width)
    }
}
#endif
