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
        XCTAssertEqual(NativeMathGlyphs.styled("F", alphabet: "mathcal"), "ℱ")
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

extension NativeMathParserTests {
    func testColorAndStretchyDelimitersRetainStructure() {
        XCTAssertEqual(NativeMathParser.parse("\\textcolor{#ff0000}{x}"),
                       .row([.color("#ff0000", .row([.text("x")]))]))
        XCTAssertEqual(NativeMathParser.parse("\\left(\\frac{1}{2}\\right)"),
                       .row([.delimited("(", ")", .row([.fraction(.row([.text("1")]),
                                                                    .row([.text("2")]))]))]))
        XCTAssertEqual(NativeMathParser.parse("\\left\\langle x \\right\\rangle"),
                       .row([.delimited("⟨", "⟩", .row([.text(" "), .text("x"), .text(" ")]))]))
        XCTAssertTrue(NativeMathColor.isValid("#00aaff"))
        XCTAssertFalse(NativeMathColor.isValid("red"))
    }

    func testCoreTextMetricsAndMathSpacing() {
        XCTAssertGreaterThan(NativeMathMetrics.ascent(size: 20), 0)
        XCTAssertGreaterThan(NativeMathMetrics.lineHeight(size: 20), NativeMathMetrics.ascent(size: 20))
        XCTAssertGreaterThan(NativeMathMetrics.operatorGap(size: 20), 0)
        XCTAssertTrue(NativeMathSpacing.needsGap(before: .text("+"), after: .text("x")))
        XCTAssertFalse(NativeMathSpacing.needsGap(before: .text("y"), after: .text("x")))
        XCTAssertFalse(NativeMathSpacing.needsGap(before: .text("+"), after: .text(" ")))
    }
}

#if os(macOS)
extension NativeMathParserTests {
    @MainActor
    func testActualMathViewRendersToBitmap() throws {
        let content = VStack(alignment: .leading, spacing: 18) {
            NativeMathView(latex: "\\left(\\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}\\right)", size: 20, display: true)
            NativeMathView(latex: "\\sum_{i=1}^{n}i + \\mathbb{R}", size: 20, display: true)
            NativeMathView(latex: "\\begin{cases}x&x>0\\\\-x&x\\leq0\\end{cases}", size: 20, display: true)
            NativeMathView(latex: "\\textcolor{#cc0000}{a}+\\textcolor{#0000cc}{b}", size: 20, display: true)
            NativeMathView(latex: "\\begin{Bmatrix}a&b\\\\c&d\\end{Bmatrix} + \\mathcal{F}", size: 20, display: true)
            NativeMathView(latex: "\\underline{x} + \\colorbox{#aaffaa}{y} + \\sqrt[3]{z}", size: 20, display: true)
        }.padding(20).background(Color.white).environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: content)
        let fitting = host.fittingSize
        XCTAssertGreaterThan(fitting.width, 100)
        XCTAssertGreaterThan(fitting.height, 100)
        host.frame = NSRect(origin: .zero, size: fitting)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1000)
        if let path = ProcessInfo.processInfo.environment["NATIVE_MATH_SNAPSHOT_PATH"] {
            try png.write(to: URL(fileURLWithPath: path))
        }
    }
}
#endif

#if os(macOS)
extension NativeMathParserTests {
    @MainActor
    func testConstrainedMathRowWrapsAtOperators() {
        let formula = "a+b+c+d+e+f+g+h"
        let natural = NSHostingView(rootView: NativeMathView(latex: formula, size: 20, display: true).fixedSize())
            .fittingSize
        let constrained = NSHostingView(rootView: NativeMathView(latex: formula, size: 20, display: true)
            .frame(width: 90)).fittingSize
        XCTAssertGreaterThan(constrained.height, natural.height)
        XCTAssertLessThanOrEqual(constrained.width, 90)
    }
}
#endif

#if os(macOS)
extension NativeMathParserTests {
    @MainActor
    func testInlineFlowConstrainsFormulaInsteadOfClippingIt() {
        let formula = "a+b+c+d+e+f+g+h"
        let view = InlineFlowLayout {
            Text("Before ").fixedSize()
            NativeMathView(latex: formula, size: 16, display: false)
                .layoutValue(key: InlineMathKey.self, value: true)
        }.frame(width: 100)
        let constrained = NSHostingView(rootView: view).fittingSize
        let natural = NSHostingView(rootView: NativeMathView(latex: formula, size: 16, display: false).fixedSize())
            .fittingSize
        XCTAssertGreaterThan(constrained.height, natural.height)
        XCTAssertEqual(constrained.width, 100)
    }
}
#endif

extension NativeMathParserTests {
    func testUpstreamSymbolInventoryRendersEveryAlphabeticCommand() {
        XCTAssertGreaterThanOrEqual(NativeMathSymbols.glyphs.count, 230)
        for (name, glyph) in NativeMathSymbols.glyphs where name.allSatisfy(\.isLetter) {
            guard case let .row(nodes) = NativeMathParser.parse("\\" + name), let first = nodes.first else {
                return XCTFail("Missing symbol: \\(name)")
            }
            if let limits = NativeMathSymbols.operatorLimits[name] {
                XCTAssertEqual(first, .largeOperator(glyph, limits: limits), name)
            } else {
                XCTAssertEqual(first, .text(glyph), name)
            }
        }
    }

    func testInfixFractionsAndAccentsDoNotSharePrefixes() {
        XCTAssertEqual(NativeMathParser.parse("{a\\over b}"),
                       .row([.row([.fraction(.row([.text("a")]), .row([.text(" "), .text("b")]))])]))
        XCTAssertEqual(NativeMathParser.parse("\\overline{x}"),
                       .row([.accent("¯", .row([.text("x")]))]))
        XCTAssertEqual(NativeMathParser.parse("\\leftarrow"), .row([.text("←")]))
    }

    func testAdditionalEnvironmentAndDecorations() {
        guard case let .row(nodes) = NativeMathParser.parse("\\begin{Bmatrix}a&b\\\\c&d\\end{Bmatrix}"),
              case let .matrix(rows, left, right) = nodes.first else { return XCTFail("Bmatrix missing") }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(left + right, "{}")
        XCTAssertEqual(NativeMathParser.parse("\\underline{x}"), .row([.underline(.row([.text("x")]))]))
        XCTAssertEqual(NativeMathParser.parse("\\colorbox{#00ff00}{x}"),
                       .row([.colorBox("#00ff00", .row([.text("x")]))]))
        XCTAssertEqual(NativeMathParser.parse("\\not\\subseteq"), .row([.text("⊈")]))
        XCTAssertEqual(NativeMathParser.parse("\\quad"), .row([.space(18)]))
        XCTAssertEqual(NativeMathParser.parse("\\sqrt[3]{x}"),
                       .row([.indexedRoot(.row([.text("3")]), .row([.text("x")]))]))
    }
}

extension NativeMathParserTests {
    func testUpstreamFontAndAccentCommandInventory() {
        let fonts = ["mathnormal", "mathrm", "textrm", "rm", "mathbf", "bf", "textbf",
                     "mathcal", "cal", "mathtt", "texttt", "mathit", "textit", "mit",
                     "mathsf", "textsf", "mathfrak", "frak", "mathbb", "mathbfit", "bm", "text"]
        XCTAssertEqual(fonts.count, 22)
        for name in fonts {
            guard case let .row(nodes) = NativeMathParser.parse("\\" + name + "{x}"),
                  case .alphabet = nodes.first else { return XCTFail("Font command missing: \(name)") }
        }
        let accents = ["grave", "acute", "hat", "tilde", "bar", "breve", "dot", "ddot",
                       "check", "vec", "widehat", "widetilde"]
        XCTAssertEqual(accents.count, 12)
        for name in accents {
            guard case let .row(nodes) = NativeMathParser.parse("\\" + name + "{x}"),
                  case .accent = nodes.first else { return XCTFail("Accent missing: \(name)") }
        }
    }

    func testUpstreamEnvironmentInventory() {
        let matrices = ["matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix",
                        "matrix*", "pmatrix*", "bmatrix*", "Bmatrix*", "vmatrix*", "Vmatrix*"]
        XCTAssertEqual(matrices.count, 13)
        for name in matrices {
            let optionalAlignment = name.hasSuffix("*") ? "[r]" : ""
            let source = "\\begin{" + name + "}" + optionalAlignment + "a&b\\\\c&d\\end{" + name + "}"
            guard case let .row(nodes) = NativeMathParser.parse(source), let first = nodes.first else {
                return XCTFail("Matrix missing: \(name)")
            }
            switch first {
            case .matrix, .alignedMatrix, .style: break
            default: XCTFail("Matrix not rendered structurally: \(name)")
            }
        }
        let others: [(String, String)] = [
            ("eqalign", "a&=b\\\\c&=d"), ("split", "a&=b\\\\c&=d"),
            ("aligned", "a&=b\\\\c&=d"), ("displaylines", "a\\\\b"),
            ("gather", "a\\\\b"), ("eqnarray", "a&=&b\\\\c&=&d"),
            ("cases", "a&x>0\\\\b&x<0")
        ]
        XCTAssertEqual(others.count, 7)
        for (name, body) in others {
            let source = "\\begin{" + name + "}" + body + "\\end{" + name + "}"
            guard case let .row(nodes) = NativeMathParser.parse(source),
                  case let .environment(parsedName, _, rows) = nodes.first else {
                return XCTFail("Environment missing: \(name)")
            }
            XCTAssertEqual(parsedName, name)
            XCTAssertEqual(rows.count, 2)
        }
    }
}
