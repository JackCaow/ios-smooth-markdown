import Markdown
import XCTest
@testable import SmoothMarkdown

final class InlineContentTests: XCTestCase {
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
