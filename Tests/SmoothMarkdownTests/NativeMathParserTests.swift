import XCTest
@testable import SmoothMarkdown

final class NativeMathParserTests: XCTestCase {
    func testNestedFractionRootAndScripts() {
        let parsed = NativeMathParser.parse("x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}")
        guard case let .row(nodes) = parsed else { return XCTFail("Expected a row") }
        XCTAssertTrue(nodes.contains { if case .fraction = $0 { return true }; return false })
        guard case let .fraction(numerator, denominator) = nodes.last else {
            return XCTFail("Expected a fraction")
        }
        XCTAssertTrue(String(describing: numerator).contains("root"))
        XCTAssertEqual(denominator, .row([.text("2"), .text("a")]))
    }

    func testSummationBoundsAndGreekSymbols() {
        let parsed = NativeMathParser.parse("\\sum_{i=1}^{n} \\alpha_i + \\infty")
        guard case let .row(nodes) = parsed else { return XCTFail("Expected a row") }
        guard case let .script(base, sub, sup) = nodes.first else {
            return XCTFail("Expected summation bounds")
        }
        XCTAssertEqual(base, .text("∑"))
        XCTAssertEqual(sub, .row([.text("i"), .text("="), .text("1")]))
        XCTAssertEqual(sup, .row([.text("n")]))
        XCTAssertTrue(nodes.contains(.text("∞")))
    }

    func testMatrixCellsAndDelimiters() {
        let parsed = NativeMathParser.parse("\\begin{pmatrix}a & b \\\\ c & d\\end{pmatrix}")
        guard case let .row(nodes) = parsed, case let .matrix(rows, left, right) = nodes.first else {
            return XCTFail("Expected matrix")
        }
        XCTAssertEqual((left + right), "()")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.count), [2, 2])
        XCTAssertEqual(rows[1][0], .row([.text("c")]))
    }

    func testUnknownCommandAndUnclosedGroupStayVisible() {
        let parsed = NativeMathParser.parse("\\unsupported{x")
        guard case let .row(nodes) = parsed else { return XCTFail("Expected a row") }
        XCTAssertEqual(nodes.first, .text("\\unsupported"))
        XCTAssertFalse(nodes.isEmpty)
    }
}

extension NativeMathParserTests {
    func testAccentAndDemoFormulaCorpus() {
        XCTAssertEqual(NativeMathParser.parse("\\hat{H}"), .row([.accent("ˆ", .row([.text("H")]))]))
        let examples = [
            "e^{i\\pi} + 1 = 0",
            "i\\hbar\\frac{\\partial}{\\partial t}\\Psi(\\mathbf{r},t) = \\hat{H}\\Psi(\\mathbf{r},t)",
            "\\nabla \\cdot \\mathbf{E} = \\frac{\\rho}{\\epsilon_0}",
            "\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}",
            "\\int_{-\\infty}^{\\infty} e^{-x^2} dx = \\sqrt{\\pi}"
        ]
        for example in examples {
            guard case let .row(nodes) = NativeMathParser.parse(example) else {
                return XCTFail("Expected a row for \(example)")
            }
            XCTAssertFalse(nodes.isEmpty, example)
        }
    }
}
