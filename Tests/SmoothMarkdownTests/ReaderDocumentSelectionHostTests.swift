#if os(iOS)
import UIKit
import XCTest
@testable import SmoothMarkdown

@available(iOS 17.0, *)
final class ReaderDocumentSelectionHostTests: XCTestCase {
    func testMeasuredAttachmentHasTextKitSizeAndSemanticCopyAcrossIt() {
        let projection = ReaderTextKitProjection(document: .init(
            markdown: "Before $x+y$ after.\n\nSecond 😀 paragraph."))
        let attachment = try! XCTUnwrap(projection.attachments.first)
        let host = UIView()
        let view = ReaderDocumentSelectionTextView()
        XCTAssertNil(view.textLayoutManager)

        XCTAssertFalse(view.apply(projection, availableWidth: 300,
                                  measuredAttachments: [:], hostedViews: [:]))
        XCTAssertNil(view.projection)
        XCTAssertTrue(view.apply(projection, availableWidth: 300,
                                 measuredAttachments: [attachment.id: CGSize(width: 80, height: 32)],
                                 hostedViews: [attachment.id: host]))
        XCTAssertEqual(view.textStorage.length, projection.attributedText.length)
        XCTAssertEqual((view.textStorage.attribute(.attachment,
                       at: attachment.range.location, effectiveRange: nil) as? NSTextAttachment)?.bounds.size,
                       CGSize(width: 80, height: 32))
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        view.layoutIfNeeded()
        XCTAssertTrue(view.isLayoutValid)
        XCTAssertEqual(host.superview, view)
        XCTAssertEqual(host.frame.size, CGSize(width: 80, height: 32))

        view.frame.size.width = 200
        view.layoutIfNeeded()
        XCTAssertFalse(view.isLayoutValid)
        XCTAssertTrue(host.isHidden, "A rotated layout must be remeasured before showing its attachment")

        view.selectedRange = NSRange(location: 0, length: projection.attributedText.length)
        view.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string, "Before x+y after.\nSecond 😀 paragraph.")
    }

    func testRejectsOversizedAttachmentWithoutReplacingCurrentContent() {
        let original = ReaderTextKitProjection(document: .init(markdown: "Original text."))
        let replacement = ReaderTextKitProjection(document: .init(markdown: "A $x$ B"))
        let attachment = try! XCTUnwrap(replacement.attachments.first)
        let host = UIView()
        let view = ReaderDocumentSelectionTextView()
        XCTAssertTrue(view.apply(original, availableWidth: 100,
                                 measuredAttachments: [:], hostedViews: [:]))
        XCTAssertFalse(view.apply(replacement, availableWidth: 100,
                                  measuredAttachments: [attachment.id: CGSize(width: 101, height: 30)],
                                  hostedViews: [attachment.id: host]))
        XCTAssertEqual(view.attributedText.string, original.attributedText.string)
        XCTAssertNil(host.superview)
    }

    func testSelectionRetainsOnlyForSameVisibleTextAndRemovedHostDetaches() {
        let source = ReaderTextKitProjection(document: .init(markdown: "A $x$ B"))
        let attachment = try! XCTUnwrap(source.attachments.first)
        let host = UIView()
        let view = ReaderDocumentSelectionTextView()
        XCTAssertTrue(view.apply(source, availableWidth: 300,
                                 measuredAttachments: [attachment.id: CGSize(width: 40, height: 20)],
                                 hostedViews: [attachment.id: host]))
        view.selectedRange = NSRange(location: 0, length: 1)
        XCTAssertTrue(view.apply(source, availableWidth: 300,
                                 measuredAttachments: [attachment.id: CGSize(width: 50, height: 25)],
                                 hostedViews: [attachment.id: host]))
        XCTAssertEqual(view.selectedRange, NSRange(location: 0, length: 1))
        let replacementHost = UIView()
        XCTAssertTrue(view.apply(source, availableWidth: 300,
                                 measuredAttachments: [attachment.id: CGSize(width: 50, height: 25)],
                                 hostedViews: [attachment.id: replacementHost]))
        XCTAssertNil(host.superview)
        let revised = ReaderTextKitProjection(document: .init(markdown: "Revised text."))
        XCTAssertTrue(view.apply(revised, availableWidth: 300,
                                 measuredAttachments: [:], hostedViews: [:]))
        XCTAssertEqual(view.selectedRange.length, 0)
        XCTAssertNil(replacementHost.superview)
    }
}
#endif
