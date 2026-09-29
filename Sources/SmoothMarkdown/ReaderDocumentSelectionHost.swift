#if os(iOS)
import SwiftUI
import UIKit

/// A document-wide native selection surface. Callers must measure and supply
/// every attachment before presenting it.
@available(iOS 17.0, *)
final class ReaderDocumentSelectionTextView: QuoteTextView, UIGestureRecognizerDelegate {
    private(set) var projection: ReaderTextKitProjection?
    var hostedControllers: [String: UIHostingController<AnyView>] = [:]
    private var attachmentViews: [String: UIView] = [:]
    private var attachmentSizes: [String: CGSize] = [:]
    private var measuredWidth: CGFloat = 0
    private var dragAnchorUTF16: Int?
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
        let imageDrag = UILongPressGestureRecognizer(target: self, action: #selector(trackImageDrag(_:)))
        imageDrag.minimumPressDuration = 0.35
        imageDrag.cancelsTouchesInView = false
        imageDrag.delegate = self
        addGestureRecognizer(imageDrag)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // Image taps belong to the hosted image view. A drag that starts in
        // prose can still cross its measured attachment line.
        !projectionImageIDs.contains { id in
            guard let host = attachmentViews[id] else { return false }
            return touch.view?.isDescendant(of: host) == true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private var projectionImageIDs: [String] {
        projection?.attachments.compactMap { attachment in
            if case .image = attachment.content { return attachment.id }
            return nil
        } ?? []
    }

    @objc private func trackImageDrag(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragAnchorUTF16 = characterOffset(at: gesture.location(in: self))
        case .changed, .ended:
            guard let anchor = dragAnchorUTF16,
                  let focus = characterOffset(at: gesture.location(in: self)),
                  let projection,
                  ReaderImageSelectionProjection.crossesImage(
                    from: anchor, to: focus,
                    imageAnchors: projection.attachments.compactMap { attachment in
                        if case .image = attachment.content { return attachment.range.location }
                        return nil
                    }) else {
                if gesture.state == .ended { dragAnchorUTF16 = nil }
                return
            }
            selectedRange = NSRange(location: min(anchor, focus), length: abs(focus - anchor))
            if gesture.state == .ended { dragAnchorUTF16 = nil }
        default:
            dragAnchorUTF16 = nil
        }
    }

    private func characterOffset(at point: CGPoint) -> Int? {
        guard let position = closestPosition(to: point) else { return nil }
        return min(max(offset(from: beginningOfDocument, to: position), 0), textStorage.length)
    }

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
struct ReaderWholeDocumentSelectionContainer: View {
    let selectionDocument: ReaderSelectionDocument
    let projection: ReaderTextKitProjection
    let styleSheet: MarkdownStyleSheet
    let onLinkTap: ((URL) -> Void)?
    let sourceView: SmoothMarkdownView
    let selectionController: SmoothSelectionController?

    @State private var remoteResults: [ReaderRemoteImageKey: ReaderRemoteImageResolution] = [:]

    private var remoteKeys: [ReaderRemoteImageKey] {
        Array(Set(projection.attachments.compactMap { attachment -> ReaderRemoteImageKey? in
            guard case let .image(spec) = attachment.content,
                  let source = ImageSource.parse(spec.source),
                  case let .remote(url, svg) = source else { return nil }
            return .init(url: url, svg: svg)
        })).sorted { $0.url.absoluteString < $1.url.absoluteString }
    }

    var body: some View {
        ReaderWholeDocumentSelectionView(selectionDocument: selectionDocument, projection: projection,
                                         styleSheet: styleSheet, onLinkTap: onLinkTap,
                                         sourceView: sourceView, selectionController: selectionController,
                                         remoteResults: remoteResults)
            .task(id: remoteKeys) { await loadRemoteImages() }
    }

    private func loadRemoteImages() async {
        remoteResults = remoteResults.filter { remoteKeys.contains($0.key) }
        let missing = remoteKeys.filter { remoteResults[$0] == nil }
        var remaining = missing.makeIterator()
        await withTaskGroup(of: (ReaderRemoteImageKey, ReaderRemoteImageResolution).self) { group in
            func enqueue(_ key: ReaderRemoteImageKey) {
                group.addTask {
                    switch await ReaderRemoteImageLoader.fetch(key) {
                    case let .data(data): return (key, ReaderRemoteImageResolution.decode(data, key: key))
                    case .failure: return (key, .failure)
                    case .rejected: return (key, .rejected)
                    }
                }
            }
            for _ in 0..<min(ReaderRemoteImagePolicy.maxConcurrentRequests, missing.count) {
                if let key = remaining.next() { enqueue(key) }
            }
            while let (key, loaded) = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                let currentPixels = remoteResults.values.reduce(0) { $0 + $1.pixelCost }
                remoteResults[key] = ReaderRemoteImagePolicy.canRetain(pixels: loaded.pixelCost,
                                                                       after: currentPixels)
                    ? loaded : .rejected
                if let next = remaining.next() { enqueue(next) }
            }
        }
    }
}

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
    let selectionController: SmoothSelectionController?
    let remoteResults: [ReaderRemoteImageKey: ReaderRemoteImageResolution]

    func makeUIView(context: Context) -> ReaderDocumentSelectionTextView {
        let view = ReaderDocumentSelectionTextView()
        view.delegate = context.coordinator
        context.coordinator.textView = view
        context.coordinator.selectionController = selectionController
        selectionController?.attach(view)
        view.accessibilityIdentifier = "reader-whole-document-selection"
        view.accessibilityCustomActions = [UIAccessibilityCustomAction(
            name: "Select all reader text", target: view,
            selector: #selector(QuoteTextView.selectAllReaderText))]
        return view
    }

    func updateUIView(_ view: ReaderDocumentSelectionTextView, context: Context) {
        if context.coordinator.selectionController !== selectionController {
            context.coordinator.selectionController?.detach(view)
            context.coordinator.selectionController = selectionController
        }
        selectionController?.attach(view)
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

    static func dismantleUIView(_ view: ReaderDocumentSelectionTextView, coordinator: ReaderSelectionTextView.Coordinator) {
        coordinator.selectionController?.detach(view)
        coordinator.selectionController = nil
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
            let isImage: Bool
            let remoteResolution: ReaderRemoteImageResolution?
            if case let .image(spec) = attachment.content {
                isImage = true
                if let source = ImageSource.parse(spec.source), case let .remote(url, svg) = source {
                    remoteResolution = remoteResults[.init(url: url, svg: svg)]
                } else { remoteResolution = nil }
            } else {
                isImage = false
                remoteResolution = nil
            }
            guard let content = sourceView.visualAttachmentView(for: attachment.content,
                                                                 remoteResolution: remoteResolution) else { return }
            let measuredContent = isImage ? content : AnyView(content.frame(width: width, alignment: .leading))
            let root = AnyView(measuredContent
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
            guard size.width.isFinite, size.width > 0,
                  size.height.isFinite, size.height > 0 else { return }
            controllers[attachment.id] = controller
            measured[attachment.id] = CGSize(width: isImage ? min(width, ceil(size.width)) : width,
                                             height: ceil(size.height))
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
