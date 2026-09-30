#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import SmoothMarkdown

@available(iOS 17.0, *)
final class ReaderDocumentSelectionHostTests: XCTestCase {
    func testInlineMathDetailsAndFootnoteShareContinuousHostAndCurrentCopyState() throws {
        let source = try String(contentsOf: XCTUnwrap(Bundle.module.url(
            forResource: "ReaderRichHost", withExtension: "md")), encoding: .utf8)
        let reader = SmoothMarkdownView(markdown: source, selectable: true)
        let closed = try XCTUnwrap(reader.wholeDocumentSelection)
        let summary = try XCTUnwrap(closed.projection.document.segments.first {
            $0.kind == .detailsSummary
        })
        XCTAssertEqual(closed.selection.selectionText, closed.projection.attributedText.string)
        XCTAssertTrue(closed.projection.attachments.contains {
            if case let .formula(latex) = $0.content { return latex == "x+y" }
            return false
        })
        XCTAssertTrue(closed.projection.document.segments.contains { $0.kind == .footnote })
        let closedCopy = try XCTUnwrap(closed.projection.copiedText(in: NSRange(
            location: 0, length: closed.projection.attributedText.length)))
        XCTAssertTrue(closedCopy.contains("Before x+y and reference[1]."))
        XCTAssertTrue(closedCopy.contains("Show details"))
        XCTAssertTrue(closedCopy.contains("[1]: Definition with bold text."))
        XCTAssertFalse(closedCopy.contains("Hidden"))

        let opened = try XCTUnwrap(reader.wholeDocumentSelection(expansion: [summary.id: true]))
        XCTAssertEqual(opened.projection.document.segments.first { $0.kind == .detailsSummary }?.id,
                       summary.id)
        XCTAssertEqual(opened.selection.selectionText, opened.projection.attributedText.string)
        let openCopy = try XCTUnwrap(opened.projection.copiedText(in: NSRange(
            location: 0, length: opened.projection.attributedText.length)))
        XCTAssertTrue(openCopy.contains("Hidden a+b body."))

        let host = ReaderDocumentSelectionTextView()
        host.disclosureExpanded = [summary.id: false]
        var toggledID: String?
        host.onDisclosureTap = { toggledID = $0 }
        let attachments = Dictionary(uniqueKeysWithValues: closed.projection.attachments.map {
            ($0.id, CGSize(width: 50, height: 24))
        })
        let views = Dictionary(uniqueKeysWithValues: closed.projection.attachments.map {
            ($0.id, UIView())
        })
        XCTAssertTrue(host.apply(closed.projection, availableWidth: 300,
                                 measuredAttachments: attachments, hostedViews: views))
        let disclosure = try XCTUnwrap(host.subviews.compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "reader-disclosure-0" })
        XCTAssertEqual(disclosure.accessibilityValue, "Collapsed")
        disclosure.sendActions(for: .touchUpInside)
        XCTAssertEqual(toggledID, summary.id)
    }

    func testFootnoteOnlyCopiesItsRenderedFirstParagraph() throws {
        let source = "Before[^1].\n\n[^1]: First paragraph.\n    # Second block\n\nAfter."
        let candidate = try XCTUnwrap(SmoothMarkdownView(markdown: source, selectable: true).wholeDocumentSelection)
        XCTAssertEqual(candidate.selection.selectionText, candidate.projection.attributedText.string)
        XCTAssertEqual(candidate.projection.copiedText(in: NSRange(
            location: 0, length: candidate.projection.attributedText.length)),
            "Before[1].\n[1]: First paragraph.\nAfter.")
    }

    func testAdmonitionAndMermaidKeepRenderedCardsInOneNativeRange() throws {
        let source = """
        Before.

        ::: warning Heads up
        Careful.
        :::

        ```mermaid
        flowchart LR
          A --> B
        ```

        After.
        """
        let reader = SmoothMarkdownView(markdown: source, plugins: .builtIns(),
                                        selectable: true)
        let candidate = try XCTUnwrap(reader.wholeDocumentSelection)
        XCTAssertEqual(candidate.selection.selectionText, candidate.projection.attributedText.string)
        XCTAssertEqual(candidate.projection.attachments.count, 2)
        XCTAssertEqual(candidate.projection.copiedText(in: NSRange(
            location: 0, length: candidate.projection.attributedText.length)),
            "Before.\nHeads up\nCareful.\nAfter.")
        for attachment in candidate.projection.attachments {
            guard case .plugin = attachment.content else { return XCTFail("Expected hosted plugin") }
            XCTAssertNotNil(reader.visualAttachmentView(for: attachment.content))
        }
        XCTAssertEqual(candidate.projection.copiedText(in: candidate.projection.attachments[0].range),
                       "Heads up\nCareful.")
        XCTAssertEqual(candidate.projection.copiedText(in: candidate.projection.attachments[1].range), "")
    }

    func testBuiltInInlinePluginsKeepProseInsideNativeSelection() throws {
        let reader = SmoothMarkdownView(markdown: "Hello @alice :smile: #release.\n\nAfter.",
                                        plugins: .builtIns(), selectable: true)
        let candidate = try XCTUnwrap(reader.wholeDocumentSelection)
        XCTAssertEqual(candidate.projection.attachments.count, 0)
        XCTAssertEqual(candidate.selection.selectionText, candidate.projection.attributedText.string)
        XCTAssertEqual(candidate.projection.copiedText(in: NSRange(
            location: 0, length: candidate.projection.attributedText.length)),
            "Hello @alice 😄 #release.\nAfter.")
    }

    func testEnhancedArtifactKeepsCardAndExactCopy() throws {
        let source = "Before.\n\n<artifact id='x' type='code' lang='swift' title='Example'>\nprint(1)\n</artifact>\n\nAfter."
        let reader = SmoothMarkdownView(markdown: source, useEnhancedComponents: true,
                                        plugins: .builtIns(), selectable: true)
        let candidate = try XCTUnwrap(reader.wholeDocumentSelection)
        let artifact = try XCTUnwrap(candidate.projection.attachments.first)
        guard case .plugin("artifact", _) = artifact.content else { return XCTFail("Expected artifact card") }
        XCTAssertNotNil(reader.visualAttachmentView(for: artifact.content))
        XCTAssertEqual(candidate.projection.copiedText(in: artifact.range),
                       "Example\nSWIFT\nprint(1)")
        XCTAssertNil(SmoothMarkdownView(markdown: source, useEnhancedComponents: false,
                                        plugins: .builtIns(), selectable: true).wholeDocumentSelection)
    }

    func testClosedDetailsCanExpandIntoHostedAdmonition() throws {
        let source = """
        Before.

        <details>
        <summary>More</summary>
        ::: tip Helpful
        Body.
        :::
        </details>

        After.
        """
        let reader = SmoothMarkdownView(markdown: source, enableHTML: true,
                                        plugins: .builtIns(), selectable: true)
        let closed = try XCTUnwrap(reader.wholeDocumentSelection)
        let summary = try XCTUnwrap(closed.projection.document.segments.first { $0.kind == .detailsSummary })
        XCTAssertEqual(closed.projection.copiedText(in: NSRange(
            location: 0, length: closed.projection.attributedText.length)),
            "Before.\nMore\nAfter.")
        let opened = try XCTUnwrap(reader.wholeDocumentSelection(expansion: [summary.id: true]))
        XCTAssertEqual(opened.projection.attachments.count, 1)
        XCTAssertEqual(opened.projection.copiedText(in: NSRange(
            location: 0, length: opened.projection.attributedText.length)),
            "Before.\nMore\nHelpful\nBody.\nAfter.")
    }

    func testMultipleDetailsKeepIndependentExpansionAndStableSummaryIDs() throws {
        let source = """
        Before.

        <details>
        <summary>First</summary>
        First body.
        </details>

        Between.

        <details open>
        <summary>Second</summary>
        Second body.
        </details>

        After.
        """
        let reader = SmoothMarkdownView(markdown: source, selectable: true)
        let initial = try XCTUnwrap(reader.wholeDocumentSelection)
        let ids = initial.projection.document.segments.filter { $0.kind == .detailsSummary }.map(\.id)
        XCTAssertEqual(ids.count, 2)
        let initialCopy = try XCTUnwrap(initial.projection.copiedText(in: NSRange(
            location: 0, length: initial.projection.attributedText.length)))
        XCTAssertFalse(initialCopy.contains("First body."))
        XCTAssertTrue(initialCopy.contains("Second body."))
        let switched = try XCTUnwrap(reader.wholeDocumentSelection(expansion: [ids[0]: true, ids[1]: false]))
        XCTAssertEqual(switched.projection.document.segments.filter { $0.kind == .detailsSummary }.map(\.id), ids)
        XCTAssertEqual(switched.selection.selectionText, switched.projection.attributedText.string)
        let switchedCopy = try XCTUnwrap(switched.projection.copiedText(in: NSRange(
            location: 0, length: switched.projection.attributedText.length)))
        XCTAssertTrue(switchedCopy.contains("First body."))
        XCTAssertFalse(switchedCopy.contains("Second body."))
    }

    func testCollapsedDetailsWithCustomCodeBodyKeepsInteractiveLegacyRenderer() {
        let source = """
        Before.

        <details>
        <summary>Code</summary>
        ```swift
        print(1)
        ```
        </details>

        After.
        """
        let reader = SmoothMarkdownView(markdown: source,
                                        codeBuilder: { _, _ in AnyView(Text("Custom")) },
                                        selectable: true)
        XCTAssertNil(reader.wholeDocumentSelection)
    }

    func testDetailsSummaryLinkKeepsLinkActionMetadata() throws {
        let reader = SmoothMarkdownView(markdown: """
        <details>
        <summary>See [site](https://example.com)</summary>
        Body.
        </details>
        """, selectable: true)
        let candidate = try XCTUnwrap(reader.wholeDocumentSelection)
        let summary = try XCTUnwrap(candidate.selection.lines.first { $0.kind == .detailsSummary })
        XCTAssertEqual(summary.runs.first { $0.style.link != nil }?.style.link,
                       URL(string: "https://example.com"))
    }

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

    func testStyledTextUpdateKeepsSelectionButRejectsMismatchedProjection() {
        let projection = ReaderTextKitProjection(document: .init(markdown: "First.\n\nSecond."))
        let view = ReaderDocumentSelectionTextView()
        let small = NSAttributedString(string: projection.attributedText.string,
                                       attributes: [.font: UIFont.systemFont(ofSize: 14)])
        let large = NSAttributedString(string: projection.attributedText.string,
                                       attributes: [.font: UIFont.systemFont(ofSize: 24)])
        XCTAssertTrue(view.apply(projection, availableWidth: 300,
                                 measuredAttachments: [:], hostedViews: [:], styledText: small))
        view.selectedRange = NSRange(location: 0, length: 5)
        XCTAssertTrue(view.apply(projection, availableWidth: 300,
                                 measuredAttachments: [:], hostedViews: [:], styledText: large))
        XCTAssertEqual(view.selectedRange, NSRange(location: 0, length: 5))
        XCTAssertEqual((view.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize,
                       24)
        XCTAssertFalse(view.apply(projection, availableWidth: 300,
                                  measuredAttachments: [:], hostedViews: [:],
                                  styledText: NSAttributedString(string: "Wrong")))
        XCTAssertEqual(view.attributedText.string, projection.attributedText.string)
    }

    func testWholeReaderIncludesBuiltInCodeAndTableAttachments() {
        let plain = SmoothMarkdownView(markdown: "# Heading\n\nFirst paragraph.\n\nSecond paragraph.",
                                       selectable: true)
        let candidate = try! XCTUnwrap(plain.wholeDocumentSelection)
        XCTAssertEqual(candidate.selection.selectionText, candidate.projection.attributedText.string)
        XCTAssertEqual(candidate.projection.document.copiedText(in: NSRange(
            location: 0, length: candidate.projection.attributedText.length)),
            "Heading\nFirst paragraph.\nSecond paragraph.")
        let complex = SmoothMarkdownView(markdown: "A\n\n```swift\nprint(1)\n```\n\n| Name | Value |\n| --- | --- |\n| A | 2 |\n\n$$\na+b\n$$\n\nB",
                                         selectable: true)
        let unified = try! XCTUnwrap(complex.wholeDocumentSelection)
        XCTAssertEqual(unified.projection.attributedText.string, unified.selection.selectionText)
        XCTAssertEqual(unified.projection.attachments.count, 3)
        XCTAssertEqual(unified.projection.copiedText(in: NSRange(
            location: 0, length: unified.projection.attributedText.length)),
            "A\nprint(1)\nName\tValue\nA\t2\na+b\nB")
        for attachment in unified.projection.attachments {
            XCTAssertNotNil(complex.visualAttachmentView(for: attachment.content))
        }
        let image = try! XCTUnwrap(SmoothMarkdownView(
            markdown: "A\n\n![image](https://example.com/a.png)\n\nB",
            selectable: true).wholeDocumentSelection)
        XCTAssertEqual(image.projection.attachments.count, 1)
        XCTAssertEqual(image.projection.copiedText(in: NSRange(
            location: 0, length: image.projection.attributedText.length)), "A\nB")
        XCTAssertNil(SmoothMarkdownView(markdown: "A `two words`.\n\nB",
                                        selectable: true).wholeDocumentSelection)
        XCTAssertNil(SmoothMarkdownView(markdown: "A\n\nB", selectable: true,
                                        enableCrossBlockSelection: false).wholeDocumentSelection)
        XCTAssertNil(SmoothMarkdownView(markdown: "A\n\nB", selectable: false).wholeDocumentSelection)
    }

    func testDefaultHostMeasuresStandaloneAndInlineImagesWithExactSelectionCopy() throws {
        let source = try String(contentsOf: XCTUnwrap(Bundle.module.url(
            forResource: "ReaderImageHost", withExtension: "md")), encoding: .utf8)
        let reader = SmoothMarkdownView(markdown: source, selectable: true)
        let candidate = try XCTUnwrap(reader.wholeDocumentSelection)
        XCTAssertEqual(candidate.projection.attributedText.string, candidate.selection.selectionText)
        let images = candidate.projection.attachments.filter {
            if case .image = $0.content { return true }
            return false
        }
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue(images.allSatisfy { reader.visualAttachmentView(for: $0.content) != nil })
        XCTAssertEqual(images.map(\.range.length), [1, 1])
        XCTAssertEqual(candidate.projection.copiedText(in: NSRange(
            location: 0, length: candidate.projection.attributedText.length)),
            "Gallery\nBefore 🐈 image.\nText  after 😀.\nAfter image.")
        XCTAssertEqual(candidate.projection.copiedText(in: images[0].range), "",
                       "Flutter gives image selection an anchor, while alt and URL remain metadata")
        XCTAssertEqual(candidate.projection.copiedText(in: images[1].range), "")
        if case let .image(spec) = images[1].content {
            XCTAssertEqual(spec.alt, "Inline")
            XCTAssertEqual(spec.source, "https://example.com/inline.png")
        } else { XCTFail("Expected image metadata") }

        let host = ReaderDocumentSelectionTextView()
        let first = UIView()
        let second = UIView()
        XCTAssertTrue(host.apply(candidate.projection, availableWidth: 300,
                                 measuredAttachments: [images[0].id: CGSize(width: 160, height: 90),
                                                       images[1].id: CGSize(width: 80, height: 40)],
                                 hostedViews: [images[0].id: first, images[1].id: second]))
        XCTAssertEqual((host.textStorage.attribute(.attachment, at: images[1].range.location,
                                                  effectiveRange: nil) as? NSTextAttachment)?.bounds.size,
                       CGSize(width: 80, height: 40))
        host.selectedRange = NSRange(location: 0, length: host.textStorage.length)
        host.copy(nil)
        XCTAssertEqual(UIPasteboard.general.string,
                       "Gallery\nBefore 🐈 image.\nText  after 😀.\nAfter image.")
    }

    func testHTMLImageUsesSameHostAndKeepsAltOutOfCopy() throws {
        let reader = SmoothMarkdownView(markdown: "Before.\n\n<img src='https://example.com/p.png' alt='Photo' width='36'>\n\nAfter.",
                                        enableHTML: true, selectable: true)
        let candidate = try XCTUnwrap(reader.wholeDocumentSelection)
        let image = try XCTUnwrap(candidate.projection.attachments.first)
        if case let .image(spec) = image.content {
            XCTAssertEqual(spec.alt, "Photo")
            XCTAssertEqual(spec.width, 36)
        } else { XCTFail("Expected HTML image") }
        XCTAssertEqual(candidate.projection.copiedText(in: NSRange(
            location: 0, length: candidate.projection.attributedText.length)), "Before.\nAfter.")
    }
}
#endif
