import Foundation
import Markdown
import XCTest
@testable import SmoothMarkdown

final class ReaderTextKitProjectionTests: XCTestCase {
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
