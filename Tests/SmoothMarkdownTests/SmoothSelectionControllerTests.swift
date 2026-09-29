#if os(iOS)
import UIKit
import XCTest
@testable import SmoothMarkdown

@available(iOS 17.0, *)
final class SmoothSelectionControllerTests: XCTestCase {
    func testControllerSelectsCopiesAndClearsLiveNativeDocument() {
        let projection = ReaderTextKitProjection(document: .init(markdown: "Alpha beta.\n\nGamma delta."))
        let view = ReaderDocumentSelectionTextView()
        XCTAssertTrue(view.apply(projection, availableWidth: 320,
                                 measuredAttachments: [:], hostedViews: [:]))
        let controller = SmoothSelectionController()
        XCTAssertFalse(controller.isAttached)
        XCTAssertFalse(controller.selectAll())
        controller.attach(view)
        XCTAssertTrue(controller.isAttached)
        XCTAssertTrue(controller.selectAll())
        XCTAssertEqual(controller.selectedRange, NSRange(location: 0, length: view.textStorage.length))
        XCTAssertEqual(controller.selectedText, projection.copiedText(in: view.selectedRange))
        XCTAssertTrue(controller.copySelection())
        XCTAssertEqual(UIPasteboard.general.string, controller.selectedText)

        controller.clearSelection()
        XCTAssertNil(controller.selectedRange)
        XCTAssertNil(controller.selectedText)
        XCTAssertFalse(controller.copySelection())
        controller.detach(view)
        XCTAssertFalse(controller.isAttached)
    }

    func testScreenPointSelectsWordAndParagraph() {
        let projection = ReaderTextKitProjection(document: .init(markdown: "Alpha beta.\n\nGamma delta."))
        let view = ReaderDocumentSelectionTextView()
        XCTAssertTrue(view.apply(projection, availableWidth: 320,
                                 measuredAttachments: [:], hostedViews: [:]))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.frame = CGRect(x: 10, y: 20, width: 300, height: 150)
        window.addSubview(view)
        view.layoutIfNeeded()
        let controller = SmoothSelectionController()
        controller.attach(view)

        let source = view.textStorage.string as NSString
        let beta = source.range(of: "beta")
        XCTAssertNotEqual(beta.location, NSNotFound)
        let glyph = view.layoutManager.glyphIndexForCharacter(at: beta.location + 1)
        let rect = view.layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                                   in: view.textContainer)
        let local = CGPoint(x: rect.midX + view.textContainerInset.left,
                            y: rect.midY + view.textContainerInset.top)
        let windowPoint = view.convert(local, to: window)
        let screenPoint = window.convert(windowPoint, to: window.screen.coordinateSpace)

        XCTAssertTrue(controller.selectWordAt(screenPoint))
        XCTAssertEqual(controller.selectedText, "beta")
        XCTAssertTrue(controller.selectParagraphAt(screenPoint))
        XCTAssertEqual(controller.selectedText, "Alpha beta.")
        XCTAssertFalse(controller.selectWordAt(CGPoint(x: -100, y: -100)))
    }

    func testControllerFollowsNativeSelectionAndDocumentReplacement() {
        let first = ReaderTextKitProjection(document: .init(markdown: "First paragraph."))
        let second = ReaderTextKitProjection(document: .init(markdown: "Different text."))
        let view = ReaderDocumentSelectionTextView()
        XCTAssertTrue(view.apply(first, availableWidth: 300,
                                 measuredAttachments: [:], hostedViews: [:]))
        let controller = SmoothSelectionController()
        controller.attach(view)
        view.selectedRange = NSRange(location: 0, length: 5)
        XCTAssertEqual(controller.selectedText, "First")
        XCTAssertTrue(view.apply(second, availableWidth: 300,
                                 measuredAttachments: [:], hostedViews: [:]))
        XCTAssertNil(controller.selectedText)
        controller.detach(view)
        XCTAssertFalse(controller.selectAll())
    }

    func testSingleParagraphUsesCompleteNativeHost() {
        let controller = SmoothSelectionController()
        let reader = SmoothMarkdownView(markdown: "A single paragraph.", selectable: true,
                                        selectionController: controller)
        XCTAssertNotNil(reader.wholeDocumentSelection)
        XCTAssertTrue(reader.selectionController === controller)
        let stream = AsyncStream<String> { $0.finish() }
        XCTAssertTrue(StreamMarkdownView(chunks: stream, selectable: true,
                                         selectionController: controller).selectionController === controller)
        XCTAssertNil(SmoothMarkdownView(markdown: "A single paragraph.", selectable: false,
                                        selectionController: SmoothSelectionController()).wholeDocumentSelection)
    }
}
#endif
