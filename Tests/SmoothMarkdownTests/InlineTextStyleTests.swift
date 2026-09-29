import SwiftUI
import XCTest
@testable import SmoothMarkdown

@MainActor
final class InlineTextStyleTests: XCTestCase {
    func testCustomInlineStylesMergeWithSemanticDefaults() {
        let style = MarkdownStyleSheet(
            linkColor: .blue,
            inlineCodeTextColor: .red,
            boldStyle: .init(textColor: .green),
            italicStyle: .init(fontSize: 21, italic: false),
            strikethroughStyle: .init(strikethrough: false, underline: true),
            linkStyle: .init(textColor: .orange, underline: false),
            inlineCodeStyle: .init(fontSize: 13, backgroundColor: .yellow)
        )
        let bold = style.resolvedInlineStyle(bold: true, italic: false, strike: false, link: false, code: false)
        XCTAssertEqual(bold.bold, true)
        #if os(iOS)
        XCTAssertEqual(UIColor(bold.textColor!), UIColor(.green))
        #endif
        let italic = style.resolvedInlineStyle(bold: false, italic: true, strike: false, link: false, code: false)
        XCTAssertEqual(italic.italic, false)
        XCTAssertEqual(italic.fontSize, 21)
        let strike = style.resolvedInlineStyle(bold: false, italic: false, strike: true, link: false, code: false)
        XCTAssertEqual(strike.strikethrough, false)
        XCTAssertEqual(strike.underline, true)
        let link = style.resolvedInlineStyle(bold: false, italic: false, strike: false, link: true, code: false)
        XCTAssertEqual(link.underline, false)
        let nested = style.resolvedInlineStyle(bold: true, italic: false, strike: false, link: true, code: false)
        XCTAssertEqual(nested.bold, true)
        #if os(iOS)
        XCTAssertEqual(UIColor(nested.textColor!), UIColor(.orange))
        #endif
        let code = style.resolvedInlineStyle(bold: false, italic: false, strike: false, link: false, code: true)
        XCTAssertEqual(code.fontSize, 13)
        XCTAssertEqual(code.monospaced, true)
    }

    #if os(iOS)
    func testCrossBlockReaderAppliesCustomInlineStylesToTextRuns() {
        let source = "**bold** *italic* ~~strike~~ [link](https://example.com) `code`\n\nAnother block."
        let nodes = Array(MarkdownSyntax.parse(source).children)
        let document = ReaderSelectionDocument.compose(nodes, enableHTML: false, plugins: nil)!
        let style = MarkdownStyleSheet(
            boldStyle: .init(textColor: .green),
            italicStyle: .init(fontSize: 21),
            strikethroughStyle: .init(underline: true),
            linkStyle: .init(textColor: .orange),
            inlineCodeStyle: .init(fontSize: 13, backgroundColor: .yellow)
        )
        let text = ReaderSelectionTextView(document: document, styleSheet: style,
                                           onLinkTap: nil, onTextLongPress: nil,
                                           selectable: true, onCharacterTap: nil)
            .attributedContent(traits: MarkdownTypography.traits(for: .large)).text
        XCTAssertEqual(text.string, document.selectionText)
        XCTAssertEqual(document.selectionText, document.copiedText)
        func attributes(for word: String) -> [NSAttributedString.Key: Any] {
            let range = (text.string as NSString).range(of: word)
            XCTAssertNotEqual(range.location, NSNotFound)
            return text.attributes(at: range.location, effectiveRange: nil)
        }
        XCTAssertEqual(attributes(for: "bold")[.foregroundColor] as? UIColor, UIColor(.green))
        XCTAssertEqual((attributes(for: "italic")[.font] as? UIFont)?.pointSize, 21)
        XCTAssertEqual(attributes(for: "strike")[.underlineStyle] as? Int,
                       NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(attributes(for: "link")[.foregroundColor] as? UIColor, UIColor(.orange))
        XCTAssertEqual(attributes(for: "link")[.link] as? URL, URL(string: "https://example.com"))
        XCTAssertEqual((attributes(for: "code")[.font] as? UIFont)?.pointSize, 13)
        XCTAssertEqual(attributes(for: "code")[.backgroundColor] as? UIColor, UIColor(.yellow))
    }
    #endif
}
