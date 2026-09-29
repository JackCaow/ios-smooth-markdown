#if os(iOS)
import UIKit

/// The UIKit half of a future document-wide reader. Callers must measure and
/// supply every attachment before presenting it. SmoothMarkdownView keeps its
/// established SwiftUI renderer until all visual blocks have a host contract.
@available(iOS 17.0, *)
final class ReaderDocumentSelectionTextView: UITextView {
    private(set) var projection: ReaderTextKitProjection?
    private var attachmentViews: [String: UIView] = [:]
    private var attachmentSizes: [String: CGSize] = [:]
    private var measuredWidth: CGFloat = 0
    var isLayoutValid: Bool { abs(bounds.width - measuredWidth) < 0.5 }

    init() {
        // Attachment geometry below is queried through NSLayoutManager. Own a
        // TextKit 1 stack from creation so a first layout read cannot replace
        // a TextKit 2 measurement with different glyph positions.
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = .clear
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        dataDetectorTypes = []
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// An incomplete or invalid measurement never installs a misleading 1 pt
    /// attachment. Width must be the same width used by the hosting SwiftUI row.
    @discardableResult
    func apply(_ newProjection: ReaderTextKitProjection, availableWidth: CGFloat,
               measuredAttachments: [String: CGSize], hostedViews: [String: UIView]) -> Bool {
        guard availableWidth.isFinite, availableWidth > 0,
              newProjection.attachments.allSatisfy({ attachment in
                  guard let size = measuredAttachments[attachment.id],
                        hostedViews[attachment.id] != nil else { return false }
                  return size.width.isFinite && size.height.isFinite &&
                      size.width > 0 && size.height > 0 && size.width <= availableWidth
              }) else { return false }

        let rendered = NSMutableAttributedString(attributedString: newProjection.attributedText)
        for attachment in newProjection.attachments {
            let glyph = NSTextAttachment()
            let size = measuredAttachments[attachment.id]!
            glyph.bounds = CGRect(origin: .zero, size: size)
            rendered.addAttribute(.attachment, value: glyph, range: attachment.range)
        }
        let previousSelection = selectedRange
        let sameText = attributedText.string == rendered.string
        if !attributedText.isEqual(to: rendered) {
            attributedText = rendered
            selectedRange = sameText && previousSelection.location != NSNotFound &&
                NSMaxRange(previousSelection) <= rendered.length
                ? previousSelection : NSRange(location: 0, length: 0)
            invalidateIntrinsicContentSize()
        }
        projection = newProjection
        let expected = Set(newProjection.attachments.map(\.id))
        for (id, view) in attachmentViews where !expected.contains(id) || hostedViews[id] !== view {
            view.removeFromSuperview()
        }
        attachmentViews = hostedViews.filter { expected.contains($0.key) }
        attachmentSizes = measuredAttachments.filter { expected.contains($0.key) }
        measuredWidth = availableWidth
        for view in attachmentViews.values where view.superview !== self { addSubview(view) }
        setNeedsLayout()
        return true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let projection else { return }
        let validWidth = isLayoutValid
        for view in attachmentViews.values { view.isHidden = !validWidth }
        guard validWidth else { return }
        layoutManager.ensureLayout(for: textContainer)
        for attachment in projection.attachments {
            guard let view = attachmentViews[attachment.id],
                  let size = attachmentSizes[attachment.id],
                  attachment.range.location < textStorage.length else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: attachment.range.location)
            let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                                  in: textContainer)
            let target = CGRect(x: textContainerInset.left + rect.minX,
                                y: textContainerInset.top + rect.minY,
                                width: size.width, height: size.height)
            if view.frame != target { view.frame = target }
        }
    }

    override func copy(_ sender: Any?) {
        guard selectedRange.length > 0,
              let copied = projection?.copiedText(in: selectedRange), !copied.isEmpty else { return }
        UIPasteboard.general.string = copied
    }
}
#endif
