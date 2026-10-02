import XCTest
@testable import SmoothMarkdown

final class InlineContentTests: XCTestCase {
    func testHTMLCodeKeepsMarkdownMarkersVerbatim() {
        let paragraph = MarkdownSyntax.parse("before <code>a<b **c**</code> after", enableHTML: true).child(at: 0)!
        let runs = InlineContent.runs(in: paragraph, enableHTML: true)
        let segments = runs.compactMap { run -> (String, Bool)? in
            if case let .text(value, _, _, code) = run {
                return (value, code)
            }
            return nil
        }
        XCTAssertEqual(segments.map(\.0).joined(), "before a<b **c** after")
        XCTAssertEqual(segments.filter(\.1).map(\.0).joined(), "a<b **c**")
        XCTAssertNotNil(ReaderSelectionDocument.copyableInlineRuns(paragraph, enableHTML: true, plugins: nil))
    }

    func testHTMLCodeDoesNotInterpretInnerTagsOrPlugins() {
        let paragraph = MarkdownSyntax.parse("<code><b>@john $x$</b></code> **after**", enableHTML: true).child(at: 0)!
        let runs = InlineContent.runs(in: paragraph, enableHTML: true)
        let codeText = runs.compactMap { run -> String? in
            if case let .text(value, _, _, code) = run, code { return value }
            return nil
        }.joined()
        XCTAssertEqual(codeText, "<b>@john $x$</b>")
        XCTAssertFalse(runs.contains { if case .math = $0 { return true }; return false })
        XCTAssertFalse(runs.contains { if case .plugin = $0 { return true }; return false })
        XCTAssertTrue(runs.contains { if case let .text("after", style, _, _) = $0 { return style.bold }; return false })
    }

    func testHTMLCodePreservesAlternateMarkdownMarkers() {
        let paragraph = MarkdownSyntax.parse("<code>__c__ and \\*x\\*</code>", enableHTML: true).child(at: 0)!
        let text = InlineContent.runs(in: paragraph, enableHTML: true).compactMap { run -> String? in
            if case let .text(value, _, _, _) = run { return value }
            return nil
        }.joined()
        XCTAssertEqual(text, "__c__ and \\*x\\*")
    }

    func testHTMLCodeAcrossBlockquoteLinesOmitsQuoteMarkers() {
        let quote = MarkdownSyntax.parse("> <code>a\n> **b**</code>", enableHTML: true).child(at: 0)!
        let paragraph = quote.child(at: 0)!
        let codeText = InlineContent.runs(in: paragraph, enableHTML: true).compactMap { run -> String? in
            if case let .text(value, _, _, code) = run, code {
                return value
            }
            return nil
        }.joined()
        XCTAssertEqual(codeText, "a\n**b**")
    }

    func testMultipleAndUnclosedHTMLCodeTagsKeepSource() {
        for (source, expected) in [
            ("<code>**a**</code> and <code>[b](url)</code>", "**a** and [b](url)"),
            ("before <code>__still raw__", "before __still raw__"),
        ] {
            let paragraph = MarkdownSyntax.parse(source, enableHTML: true).child(at: 0)!
            let text = InlineContent.runs(in: paragraph, enableHTML: true).compactMap { run -> String? in
                if case let .text(value, _, _, _) = run { return value }
                return nil
            }.joined()
            XCTAssertEqual(text, expected)
        }
    }

    func testHTMLCodeKeepsUnicodeAndLineBreakSpacing() {
        for content in ["😀 a  \nb", "a\\\nb"] {
            let paragraph = MarkdownSyntax.parse("<code>\(content)</code>", enableHTML: true).child(at: 0)!
            let codeText = InlineContent.runs(in: paragraph, enableHTML: true).compactMap { run -> String? in
                if case let .text(value, _, _, code) = run, code { return value }
                return nil
            }.joined()
            XCTAssertEqual(codeText, content)
        }
    }

    func testHTMLCodeParseCacheDoesNotAlterPlainMarkdownMode() {
        let source = "<code>__raw__</code>"
        let plainBefore = MarkdownSyntax.parse(source).child(at: 0)!
        let html = MarkdownSyntax.parse(source, enableHTML: true).child(at: 0)!
        let plainAfter = MarkdownSyntax.parse(source).child(at: 0)!
        func text(_ paragraph: Markup, html: Bool) -> String {
            InlineContent.runs(in: paragraph, enableHTML: html).compactMap { run -> String? in
                if case let .text(value, _, _, _) = run { return value }
                return nil
            }.joined()
        }
        XCTAssertEqual(text(plainBefore, html: false), "<code>raw</code>")
        XCTAssertEqual(text(html, html: true), "__raw__")
        XCTAssertEqual(text(plainAfter, html: false), "<code>raw</code>")
    }

    func testMixedMarkdownAndHTMLImagesStayBetweenText() {
        let paragraph = MarkdownSyntax.parse("before ![one](https://example.com/one.png) middle <img src='assets/two.png' alt='two' width='32'> after")
            .child(at: 0)!
        let runs = InlineContent.runs(in: paragraph, enableHTML: true)
        let labels = runs.compactMap { run -> String? in
            switch run {
            case let .text(value, _, _, _): return value
            case let .image(image): return "[\(image.alt)]"
            case let .footnote(label): return "[^\(label)]"
            case let .math(latex): return "$\(latex)$"
            case let .plugin(_, match): return match.text
            case .custom, .details: return nil
            }
        }.joined()
        XCTAssertEqual(labels, "before [one] middle [two] after")
        let images = runs.compactMap { run -> SafeHTML.ImageSpec? in
            if case let .image(image) = run { return image }
            return nil
        }
        XCTAssertEqual(images.map(\.source), ["https://example.com/one.png", "assets/two.png"])
        XCTAssertEqual(images.last?.width, 32)
    }

    func testHTMLImageOptInAndUnsafeSourceFallback() {
        let source = "a <img src='javascript:alert(1)' alt='unsafe'> b <img src='https://example.com/a.png' alt='safe'> c"
        let paragraph = MarkdownSyntax.parse(source).child(at: 0)!
        let enabled = InlineContent.runs(in: paragraph, enableHTML: true)
        XCTAssertEqual(enabled.filter { if case .image = $0 { return true }; return false }.count, 1)
        let enabledText = enabled.compactMap { if case let .text(value, _, _, _) = $0 { return value }; return nil }.joined()
        XCTAssertTrue(enabledText.contains("unsafe"))
        XCTAssertFalse(enabledText.contains("<img"))

        let disabled = InlineContent.runs(in: paragraph, enableHTML: false)
        XCTAssertFalse(disabled.contains { if case .image = $0 { return true }; return false })
        let disabledText = disabled.compactMap { if case let .text(value, _, _, _) = $0 { return value }; return nil }.joined()
        XCTAssertTrue(disabledText.contains("<img"))
    }

    func testFormattingContinuesAcrossInlineImage() {
        let paragraph = MarkdownSyntax.parse("**before ![logo](https://example.com/logo.png) after**").child(at: 0)!
        let textRuns = InlineContent.runs(in: paragraph, enableHTML: false).compactMap { run -> InlineContent.Style? in
            if case let .text(value, style, _, _) = run, !value.isEmpty { return style }
            return nil
        }
        XCTAssertEqual(textRuns.count, 2)
        XCTAssertTrue(textRuns.allSatisfy(\.bold))
    }
}
