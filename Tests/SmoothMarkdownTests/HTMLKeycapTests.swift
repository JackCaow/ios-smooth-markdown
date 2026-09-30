import Markdown
import XCTest
@testable import SmoothMarkdown

final class HTMLKeycapTests: XCTestCase {
    func testKeycapKeepsPlainTextAndNativeSelectionProjection() {
        let nodes = Array(MarkdownSyntax.parse("Press <kbd>Ctrl + C</kbd> now.", enableHTML: true).children)
        let document = ReaderSelectionDocument.compose(nodes, enableHTML: true, plugins: nil)!
        XCTAssertEqual(document.copiedText, "Press Ctrl + C now.")
        XCTAssertEqual(document.selectionText,
                       "Press \(ReaderSelectionDocument.keycapPadding)Ctrl + C\(ReaderSelectionDocument.keycapPadding) now.")
        XCTAssertEqual(document.copiedTextSlice(lowerUTF16: 6, upperUTF16: 15), "Ctrl + C")
    }

    func testAdjacentKeycapsRemainSeparateRunsAndSourceSpacesSurvive() {
        let paragraph = MarkdownSyntax.parse("<kbd>Ctrl</kbd>+<kbd>C</kbd> \u{2007} end", enableHTML: true).child(at: 0)!
        let document = ReaderSelectionDocument.inline(paragraph, enableHTML: true, plugins: nil)!
        XCTAssertEqual(document.lines[0].runs.filter(\.keycap).map(\.text), ["Ctrl", "C"])
        XCTAssertEqual(document.copiedTextSlice(lowerUTF16: nil, upperUTF16: nil), "Ctrl+C \u{2007} end")
    }

    func testUnsupportedHTMLDoesNotEnterNativeKeycapPath() {
        let paragraph = MarkdownSyntax.parse("<kbd>Ctrl</kbd> <span style=\"color:red\">highlight</span>", enableHTML: true).child(at: 0)!
        XCTAssertNil(ReaderSelectionDocument.inline(paragraph, enableHTML: true, plugins: nil))
        let splitKeycap = MarkdownSyntax.parse("<kbd>Ctrl **C**</kbd>", enableHTML: true).child(at: 0)!
        XCTAssertNil(ReaderSelectionDocument.inline(splitKeycap, enableHTML: true, plugins: nil))
    }

    func testStreamingKeycapPublishesOnlyCompleteTagAndKeepsCopyText() {
        var buffer = StreamMarkdownBuffer(startMillis: 0, enableHTML: true)
        _ = buffer.append("Press <kbd", nowMillis: 50)
        XCTAssertEqual(buffer.visibleText, "Press ")
        _ = buffer.append(">Ctrl</kbd> now", nowMillis: 100)
        let paragraph = MarkdownSyntax.parse(buffer.visibleText, enableHTML: true).child(at: 0)!
        XCTAssertEqual(ReaderSelectionDocument.inline(paragraph, enableHTML: true, plugins: nil)?.copiedText,
                       "Press Ctrl now")
    }

    func testKeycapKeepsPreciseCopyEndpointAcrossImageBridge() {
        let nodes = Array(MarkdownSyntax.parse("Press <kbd>Ctrl</kbd> now.\n\n![figure](https://example.com/a.png)",
                                               enableHTML: true).children)
        let bridge = ReaderBlockRangeDocument(nodes, enableHTML: true, plugins: nil)!
        XCTAssertEqual(bridge.copiedText(in: 0...1, startUTF16: 7, enableHTML: true, plugins: nil),
                       "Ctrl now.")
    }

    func testTableCellCanUseNativeInlineKeycapPath() {
        let table = MarkdownSyntax.parse("| Key |\n| --- |\n| <kbd>Ctrl</kbd> |", enableHTML: true)
            .child(at: 0) as! Markdown.Table
        let cell = table.body.child(at: 0)!.child(at: 0)!
        XCTAssertEqual(ReaderSelectionDocument.inline(cell, enableHTML: true, plugins: nil)?.copiedText, "Ctrl")
    }

    #if os(iOS)
    @MainActor
    func testNativeKeycapPreservesVisibleLabelAndCopyAcrossProse() {
        let paragraph = MarkdownSyntax.parse("Press <kbd>Ctrl + C</kbd> now", enableHTML: true).child(at: 0)!
        let document = ReaderSelectionDocument.inline(paragraph, enableHTML: true, plugins: nil)!
        let renderer = ReaderSelectionTextView(document: document, styleSheet: .light(),
                                               onLinkTap: nil, onTextLongPress: nil,
                                               selectable: true, onCharacterTap: nil)
        let built = renderer.attributedContent(traits: MarkdownTypography.traits(for: .large)).text
        XCTAssertEqual(built.string.replacingOccurrences(of: "\u{00A0}", with: " "), document.selectionText)
        let all = NSRange(location: 0, length: built.length)
        XCTAssertEqual(QuoteTextView.transformedCopyText(in: built, ruleRegions: [], range: all),
                       "Press Ctrl + C now")
        let key = (built.string as NSString).range(of: "Ctrl\u{00A0}+\u{00A0}C")
        XCTAssertEqual(QuoteTextView.transformedCopyText(in: built, ruleRegions: [], range: key), "Ctrl + C")
        let font = built.attribute(.font, at: key.location, effectiveRange: nil) as? UIFont
        XCTAssertEqual(font?.pointSize ?? 0, 13, accuracy: 0.1)
        let native = ReaderSelectionTextView.makeTextView()
        native.attributedText = built
        native.frame = CGRect(x: 0, y: 0, width: 120, height: 200)
        XCTAssertGreaterThan(native.sizeThatFits(CGSize(width: 120, height: 200)).height, 20)
    }
    #endif
}
