import Foundation
import XCTest
@testable import SmoothMarkdown

final class ReaderTextKitProjectionTests: XCTestCase {
    func testInlineMathAndFootnoteDefinitionUseSourceBackedAnchors() throws {
        let source = "Before $x+y$ reference[^1].\n\n[^1]: Definition **bold**.\n\nAfter."
        let sections = FootnoteSyntax.sections(source)
        var items: [ReaderBlockRangeDocument.Item] = []
        for section in sections {
            switch section {
            case let .markdown(markdown):
                items += Array(MarkdownSyntax.parse(markdown).children)
                    .map(ReaderBlockRangeDocument.Item.markup)
            case let .definition(definition): items.append(.footnoteDefinition(definition))
            }
        }
        let styled = try XCTUnwrap(ReaderSelectionDocument.composeItems(
            items, enableHTML: false, plugins: nil, visualBlockAnchors: true))
        let projection = ReaderTextKitProjection(document: .init(markdown: source))
        XCTAssertEqual(styled.selectionText, projection.attributedText.string)
        XCTAssertEqual(styled.copiedText, "Before x+y reference[1].\n[1]: Definition bold.\nAfter.")
        let formula = try XCTUnwrap(projection.attachments.first)
        XCTAssertEqual(projection.copiedText(in: formula.range), "x+y")
        XCTAssertEqual(styled.copiedTextSlice(lowerUTF16: formula.range.location,
                                             upperUTF16: NSMaxRange(formula.range)), "x+y")
        XCTAssertEqual(projection.copiedText(in: NSRange(location: 0,
                                                        length: projection.attributedText.length)),
                       styled.copiedText)
        let complex = FootnoteSyntax.Definition(label: "1", content: "First.\n# Second block")
        XCTAssertEqual(ReaderSelectionDocument.composeItems(
            [.footnoteDefinition(complex)], enableHTML: false, plugins: nil,
            visualBlockAnchors: true)?.copiedText, "[1]: First.")
        let paragraphs = FootnoteSyntax.Definition(label: "1", content: "First.\n\nSecond.")
        XCTAssertEqual(ReaderSelectionDocument.composeItems(
            [.footnoteDefinition(paragraphs)], enableHTML: false, plugins: nil,
            visualBlockAnchors: true)?.copiedText, "[1]: First.")
    }

    func testImageFixtureSharesSourceBackedOffsetsAndSkipsAltOnCopy() throws {
        let source = try String(contentsOf: XCTUnwrap(Bundle.module.url(
            forResource: "ReaderImageHost", withExtension: "md")), encoding: .utf8)
        let nodes = Array(MarkdownSyntax.parse(source, enableHTML: false).children)
        let styled = try XCTUnwrap(ReaderSelectionDocument.compose(
            nodes, enableHTML: false, plugins: nil, visualBlockAnchors: true))
        let projection = ReaderTextKitProjection(document: .init(markdown: source))
        XCTAssertEqual(styled.selectionText, projection.attributedText.string)
        XCTAssertEqual(projection.attachments.count, 2)
        XCTAssertEqual(styled.copiedText,
                       "Gallery\nBefore 🐈 image.\nText  after 😀.\nAfter image.")
        XCTAssertEqual(projection.copiedText(in: NSRange(location: 0,
                                                        length: projection.attributedText.length)),
                       "Gallery\nBefore 🐈 image.\nText  after 😀.\nAfter image.")
        let image = projection.attachments[1]
        XCTAssertEqual(projection.copiedText(in: image.range), "")
        if case let .image(spec) = image.content {
            XCTAssertEqual(spec.alt, "Inline")
            XCTAssertEqual(spec.source, "https://example.com/inline.png")
        } else { XCTFail("Expected image attachment") }
        XCTAssertNil(ReaderSelectionDocument.compose(nodes, enableHTML: false, plugins: nil),
                     "An unhosted legacy text view must not expose image placeholder glyphs")
    }

    func testCodeTableAndDisplayMathAreAtomicVisibleAttachmentsWithExactCopy() throws {
        let source = try String(contentsOf: XCTUnwrap(Bundle.module.url(
            forResource: "ReaderComplexSelection", withExtension: "md")), encoding: .utf8)
        let projection = ReaderTextKitProjection(document: .init(markdown: source))
        let items = MathSyntax.sections(source).flatMap { section -> [ReaderBlockRangeDocument.Item] in
            switch section {
            case let .markdown(markdown):
                return Array(MarkdownSyntax.parse(markdown, enableHTML: false).children)
                    .map(ReaderBlockRangeDocument.Item.markup)
            case let .block(latex): return [.displayMath(latex)]
            }
        }
        let styled = try XCTUnwrap(ReaderSelectionDocument.composeItems(
            items, enableHTML: false, plugins: nil, visualBlockAnchors: true))
        XCTAssertEqual(styled.selectionText, projection.attributedText.string)
        XCTAssertEqual(projection.attachments.count, 3)
        XCTAssertEqual(projection.document.segments.map(\.kind),
                       [.heading, .text, .code, .table, .displayMath, .text])
        for attachment in projection.attachments {
            XCTAssertEqual(attachment.range.length, 1)
            XCTAssertEqual(projection.attachment(atUTF16: attachment.range.location), attachment)
            XCTAssertEqual(projection.document.text[Range(attachment.range,
                                                          in: projection.document.text)!],
                           ReaderVisibleDocumentProjection.attachment[...])
        }
        XCTAssertEqual(projection.copiedText(in: NSRange(
            location: 0, length: projection.attributedText.length)),
            "Reader selection\nBefore documentation and 😀.\nlet answer = 42\nName\tValue\nA\t2\na+b\nAfter the visual blocks.")
        XCTAssertEqual(projection.copiedText(in: projection.attachments[0].range),
                       "let answer = 42\n")
        XCTAssertEqual(projection.copiedText(in: projection.attachments[1].range),
                       "Name\tValue\nA\t2")
        if case let .table(markdown) = projection.attachments[1].content {
            let reparsed = try XCTUnwrap(MarkdownSyntax.parse(markdown, enableHTML: false)
                .child(at: 0) as? Markdown.Table)
            XCTAssertEqual(ReaderBlockRangeDocument.tableText(reparsed, enableHTML: false,
                                                               plugins: nil), "Name\tValue\nA\t2")
        } else { XCTFail("Expected a renderable table attachment") }
        XCTAssertEqual(projection.copiedText(in: projection.attachments[2].range), "a+b")
    }

    func testCompleteProseDocumentMatchesExistingSelectableTextOffsets() {
        let cases = [
            ("# Heading\n\nFirst paragraph.\n\nSecond paragraph.",
             "Heading\nFirst paragraph.\nSecond paragraph."),
            ("## Tasks\n\n- One\n- Two\n\n> Quoted line.\n\nAfter [link](https://example.com).",
             "Tasks\n• One\n• Two\nQuoted line.\nAfter link."),
        ]
        for (markdown, copied) in cases {
            let nodes = Array(MarkdownSyntax.parse(markdown, enableHTML: false).children)
            let native = ReaderSelectionDocument.compose(nodes, enableHTML: false, plugins: nil)
            let projected = ReaderTextKitProjection(document: .init(markdown: markdown))
            XCTAssertNotNil(native)
            XCTAssertTrue(projected.attachments.isEmpty)
            XCTAssertEqual(native?.selectionText, projected.attributedText.string)
            XCTAssertEqual(projected.copiedText(in: NSRange(location: 0,
                                                           length: projected.attributedText.length)), copied)
        }
    }

    func testOneAttributedStringMapsEveryVisibleSegmentAndAttachment() {
        let source = """
        # Heading

        Before $x+y$ and ![cat](https://example.com/cat.png) after.

        $$
        a+b
        $$
        """
        let visible = ReaderVisibleDocumentProjection(markdown: source)
        let storage = ReaderTextKitProjection(document: visible)
        XCTAssertEqual(storage.attributedText.string, visible.text)
        XCTAssertEqual(storage.attributedText.length, visible.text.utf16.count)
        XCTAssertEqual(storage.attachments.count, 3)
        for segment in visible.segments {
            XCTAssertEqual(storage.segmentID(atUTF16: segment.range.location), segment.id)
        }
        for attachment in storage.attachments {
            XCTAssertEqual(attachment.range.length, 1)
            XCTAssertEqual(storage.attachment(atUTF16: attachment.range.location), attachment)
            XCTAssertNotNil(storage.attributedText.attribute(.attachment,
                                                              at: attachment.range.location,
                                                              effectiveRange: nil))
        }
        XCTAssertEqual(storage.attachments.compactMap { item -> String? in
            if case let .formula(latex) = item.content { return latex }
            return nil
        }, ["x+y", "a+b"])
        let image = storage.attachments.first { item in
            if case .image = item.content { return true }
            return false
        }!
        if case let .image(spec) = image.content {
            XCTAssertEqual(spec.source, "https://example.com/cat.png")
            XCTAssertEqual(spec.alt, "cat")
        }
        XCTAssertEqual(storage.copiedText(in: NSRange(location: 0, length: storage.attributedText.length)),
                       "Heading\nBefore x+y and  after.\na+b")
    }

    func testAttachmentIDsStayStableAcrossUnrelatedInsertion() {
        let source = "Before $x$ ![photo](https://example.com/p.png) after."
        let initial = ReaderTextKitProjection(document: .init(markdown: source))
        let revised = ReaderTextKitProjection(document: .init(markdown: "New paragraph.\n\n" + source))
        XCTAssertEqual(initial.attachments.map(\.id), revised.attachments.map(\.id))
        XCTAssertNotEqual(initial.attachments.map(\.range.location), revised.attachments.map(\.range.location))
    }

    func testDisclosureSnapshotChangesOnlyVisibleStorage() {
        let source = """
        <details>
        <summary>Show</summary>
        Hidden $x$ content.
        </details>

        After.
        """
        let closedVisible = ReaderVisibleDocumentProjection(markdown: source)
        let closed = ReaderTextKitProjection(document: closedVisible)
        XCTAssertFalse(closed.attributedText.string.contains("Hidden"))
        XCTAssertTrue(closed.attachments.isEmpty)
        let detailID = closedVisible.segments.first!.id
        let opened = ReaderTextKitProjection(document: .init(markdown: source,
                                                              expansion: [detailID: true]))
        XCTAssertTrue(opened.attributedText.string.contains("Hidden"))
        XCTAssertEqual(opened.attachments.count, 1)
        XCTAssertEqual(closedVisible.segments.last?.id, opened.document.segments.last?.id)
    }

    func testSeparatorsAndOutOfBoundsOffsetsDoNotResolveToSegments() {
        let storage = ReaderTextKitProjection(document: .init(markdown: "First.\n\nSecond."))
        let separator = storage.document.segments[0].range.length
        XCTAssertNil(storage.segmentID(atUTF16: separator))
        XCTAssertNil(storage.attachment(atUTF16: separator))
        XCTAssertNil(storage.segmentID(atUTF16: -1))
        XCTAssertNil(storage.segmentID(atUTF16: storage.attributedText.length))
    }
}
