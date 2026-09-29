#if os(iOS)
import SwiftUI
import UIKit

/// A document-wide native selection surface. Callers must measure and supply
/// every attachment before presenting it.
@available(iOS 17.0, *)
final class ReaderDocumentSelectionTextView: QuoteTextView {
    private(set) var projection: ReaderTextKitProjection?
    var hostedControllers: [String: UIHostingController<AnyView>] = [:]
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
               measuredAttachments: [String: CGSize], hostedViews: [String: UIView],
               styledText: NSAttributedString? = nil) -> Bool {
        guard availableWidth.isFinite, availableWidth > 0,
              styledText == nil || styledText?.string == newProjection.attributedText.string,
              newProjection.attachments.allSatisfy({ attachment in
                  guard let size = measuredAttachments[attachment.id],
                        hostedViews[attachment.id] != nil else { return false }
                  return size.width.isFinite && size.height.isFinite &&
                      size.width > 0 && size.height > 0 && size.width <= availableWidth
              }) else { return false }

        let rendered = NSMutableAttributedString(attributedString: styledText ?? newProjection.attributedText)
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

/// Actual on-screen unified selection. Built-in visual blocks are hosted at
/// their measured TextKit attachment positions and copy through the projection.
@available(iOS 17.0, *)
struct ReaderWholeDocumentSelectionView: UIViewRepresentable {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readerTextSelectionMenuBuilder) private var textSelectionMenuBuilder
    let selectionDocument: ReaderSelectionDocument
    let projection: ReaderTextKitProjection
    let styleSheet: MarkdownStyleSheet
    let onLinkTap: ((URL) -> Void)?
    let sourceView: SmoothMarkdownView

    func makeUIView(context: Context) -> ReaderDocumentSelectionTextView {
        let view = ReaderDocumentSelectionTextView()
        view.delegate = context.coordinator
        context.coordinator.textView = view
        view.accessibilityIdentifier = "reader-whole-document-selection"
        view.accessibilityCustomActions = [UIAccessibilityCustomAction(
            name: "Select all reader text", target: view,
            selector: #selector(QuoteTextView.selectAllReaderText))]
        return view
    }

    func updateUIView(_ view: ReaderDocumentSelectionTextView, context: Context) {
        context.coordinator.onLinkTap = onLinkTap
        context.coordinator.textSelectionMenuBuilder = textSelectionMenuBuilder
        configure(view, width: max(1, view.bounds.width))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReaderDocumentSelectionTextView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        configure(uiView, width: width)
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }

    func makeCoordinator() -> ReaderSelectionTextView.Coordinator {
        ReaderSelectionTextView.Coordinator(onLinkTap: onLinkTap, onTextLongPress: nil,
                                            onCharacterTap: nil)
    }

    private func configure(_ view: ReaderDocumentSelectionTextView, width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        let renderer = ReaderSelectionTextView(document: selectionDocument, styleSheet: styleSheet,
                                               onLinkTap: onLinkTap, onTextLongPress: nil,
                                               selectable: true, onCharacterTap: nil)
        let built = renderer.attributedContent(traits: MarkdownTypography.traits(for: dynamicTypeSize))
        var controllers: [String: UIHostingController<AnyView>] = [:]
        var measured: [String: CGSize] = [:]
        var hosted: [String: UIView] = [:]
        for attachment in projection.attachments {
            guard let content = sourceView.visualAttachmentView(for: attachment.content) else { return }
            let root = AnyView(content
                .frame(width: width, alignment: .leading)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
                .environment(\.colorScheme, colorScheme)
                .environment(\.openURL, OpenURLAction { url in
                    guard MarkdownSyntax.isSafeLink(url) else { return .discarded }
                    if let onLinkTap { onLinkTap(url); return .handled }
                    return .systemAction
                }))
            let controller = view.hostedControllers[attachment.id] ?? UIHostingController(rootView: root)
            controller.rootView = root
            controller.view.backgroundColor = .clear
            let size = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            guard size.height.isFinite, size.height > 0 else { return }
            controllers[attachment.id] = controller
            measured[attachment.id] = CGSize(width: width, height: ceil(size.height))
            hosted[attachment.id] = controller.view
        }
        guard view.apply(projection, availableWidth: width, measuredAttachments: measured, hostedViews: hosted,
                         styledText: built.text) else { return }
        view.hostedControllers = controllers
        let decoration = styleSheet.resolvedBlockquoteDecoration
        view.quoteRegions = built.quoteRegions
        view.ruleRegions = built.ruleRegions
        view.headingRegions = built.headingRegions
        view.ruleColor = UIColor(styleSheet.ruleColor ?? Color.secondary.opacity(0.4))
        view.keycapBorderColor = UIColor(styleSheet.ruleColor ?? Color.secondary.opacity(0.4))
        view.ruleThickness = styleSheet.horizontalRuleThickness
        view.quoteBarColor = UIColor(decoration.borderColor ?? .accentColor)
        view.quoteBackgroundColor = decoration.backgroundColor.map(UIColor.init)
        view.quoteBorderWidth = decoration.borderWidth
        view.quotePadding = styleSheet.blockquotePadding
    }
}
#endif
