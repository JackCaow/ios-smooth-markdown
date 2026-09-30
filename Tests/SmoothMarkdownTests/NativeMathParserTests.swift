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
        XCTAssertEqual(base, .largeOperator("∑", limits: true))
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

extension NativeMathParserTests {
    func testCasesArrayAndAlignmentEnvironments() {
        let examples: [(String, String, String, Int, Int)] = [
            ("\\begin{cases}x&x>0\\\\-x&x\\leq0\\end{cases}", "cases", "ll", 2, 2),
            ("\\begin{array}{lcr}a&b&c\\\\d&e&f\\end{array}", "array", "lcr", 2, 3),
            ("\\begin{aligned}a&=b\\\\c&=d\\end{aligned}", "aligned", "rl", 2, 2),
            ("\\begin{gather}x=1\\\\y=2\\end{gather}", "gather", "c", 2, 1)
        ]
        for (source, expectedName, expectedColumns, rowCount, columnCount) in examples {
            guard case let .row(nodes) = NativeMathParser.parse(source),
                  case let .environment(name, columns, rows) = nodes.first else {
                return XCTFail("Expected environment for \(source)")
            }
            XCTAssertEqual(name, expectedName)
            XCTAssertEqual(columns, expectedColumns)
            XCTAssertEqual(rows.count, rowCount)
            XCTAssertEqual(rows.map(\.count), Array(repeating: columnCount, count: rowCount))
        }
    }

    func testMathAlphabetsPreserveScopeAndMapUnicode() {
        XCTAssertEqual(NativeMathParser.parse("\\mathbb{R}+\\mathfrak{g}"),
                       .row([.alphabet("mathbb", .row([.text("R")])), .text("+"),
                             .alphabet("mathfrak", .row([.text("g")]))]))
        XCTAssertEqual(NativeMathGlyphs.styled("RZ", alphabet: "mathbb"), "ℝℤ")
        XCTAssertEqual(NativeMathGlyphs.styled("Ag", alphabet: "mathfrak"), "𝔄𝔤")
        XCTAssertEqual(NativeMathGlyphs.styled("x", alphabet: "mathrm"), "x")
    }

    func testLargeOperatorLimitOverrides() {
        let examples: [(String, NativeMathNode)] = [
            ("\\sum_{i=1}^{n}", .largeOperator("∑", limits: true)),
            ("\\sum\\nolimits_{i=1}^{n}", .largeOperator("∑", limits: false)),
            ("\\int_0^1", .largeOperator("∫", limits: false)),
            ("\\int\\limits_0^1", .largeOperator("∫", limits: true))
        ]
        for (source, expectedBase) in examples {
            guard case let .row(nodes) = NativeMathParser.parse(source),
                  case let .script(base, sub, sup) = nodes.first else {
                return XCTFail("Expected scripted operator for \(source)")
            }
            XCTAssertEqual(base, expectedBase)
            XCTAssertNotNil(sub)
            XCTAssertNotNil(sup)
        }
    }
}

#if os(macOS)
import AppKit
import SwiftUI

extension NativeMathParserTests {
    @MainActor
    func testRenderedDisplayOperatorAndCasesHaveExpectedHeight() {
        func height(_ latex: String, display: Bool) -> CGFloat {
            NSHostingView(rootView: NativeMathView(latex: latex, size: 20, display: display).fixedSize())
                .fittingSize.height
        }
        let inline = height("\\sum_{i=1}^{n} i", display: false)
        let display = height("\\sum_{i=1}^{n} i", display: true)
        XCTAssertGreaterThan(display, inline)
        XCTAssertGreaterThan(height("\\begin{cases}x&x>0\\\\-x&x\\leq0\\end{cases}", display: true),
                             height("x", display: true))
    }
}
#endif
