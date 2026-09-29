#if os(iOS)
import Markdown
import SwiftDraw
import SwiftUI
import UIKit

@available(iOS 17.0, *)
struct ReaderNativeImageSelectionContainer: View {
    let document: ReaderBlockRangeDocument
    let styleSheet: MarkdownStyleSheet
    let enableHTML: Bool
    let plugins: ParserPluginRegistry?
    let onLinkTap: ((URL) -> Void)?
    let imageContents: [AnyView]
    let naturalImageSizes: [CGSize]
    let spacing: CGFloat
    let renderSegment: (ReaderBlockRangeDocument.Segment, @escaping () -> Void, ((Int) -> Void)?) -> AnyView

    @State private var usingWholeBlockSelection = false

    var body: some View {
        Group {
            if usingWholeBlockSelection {
                ReaderBlockRangeView(document: document, enableHTML: enableHTML, plugins: plugins,
                                     spacing: spacing, startSelecting: true,
                                     onSelectionFinished: { usingWholeBlockSelection = false },
                                     renderSegment: renderSegment)
            } else {
                ReaderNativeImageSelectionView(document: document, styleSheet: styleSheet,
                                               enableHTML: enableHTML, plugins: plugins,
                                               onLinkTap: onLinkTap,
                                               imageContents: imageContents.map { content in
                    AnyView(content.contextMenu {
                        Button("Select surrounding content") { usingWholeBlockSelection = true }
                    })
                }, naturalImageSizes: naturalImageSizes)
            }
        }
    }
}

/// A single TextKit 1 selection surface spans prose, an image, and more prose.
/// An invisible glyph reserves layout. Its visible image remains the normal
/// SwiftUI renderer, hosted at the glyph's measured position. A simultaneous
/// long-press recognizer extends UIKit's selectedRange past the image line.
@available(iOS 17.0, *)
struct ReaderNativeImageSelectionView: UIViewRepresentable {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let document: ReaderBlockRangeDocument
    let styleSheet: MarkdownStyleSheet
    let enableHTML: Bool
    let plugins: ParserPluginRegistry?
    let onLinkTap: ((URL) -> Void)?
    let imageContents: [AnyView]
    let naturalImageSizes: [CGSize]

    static func imageSizes(for document: ReaderBlockRangeDocument, enableHTML: Bool,
                           plugins: ParserPluginRegistry?) -> [CGSize]? {
        guard document.segments.count >= 3,
              document.segments.first?.kind == .text,
              document.segments.last?.kind == .text else { return nil }
        var sizes: [CGSize] = []
        for segment in document.segments {
            switch segment.kind {
            case .text:
                guard let text = ReaderSelectionDocument.compose(segment.nodes,
                                                                 enableHTML: enableHTML, plugins: plugins),
                      text.selectionText == text.copiedText,
                      text.lines.allSatisfy({ $0.kind == .paragraph }) else { return nil }
            case .image:
                guard let paragraph = segment.nodes.first as? Paragraph,
                      let image = paragraph.children.compactMap({ $0 as? Markdown.Image }).first,
                      let source = image.source,
                      let parsed = ImageSource.parse(source) else { return nil }
                let size: CGSize
                switch parsed {
                case let .bundled(name, svg: true):
                    guard let svg = SVG(named: name, in: .main) else { return nil }
                    size = svg.size
                case let .bundled(name, svg: false):
                    guard let image = UIImage(named: name) else { return nil }
                    size = image.size
                case .remote: return nil
                }
                guard size.width > 0, size.height > 0,
                      size.width.isFinite, size.height.isFinite else { return nil }
                sizes.append(size)
            case .table, .code, .displayMath: return nil
            }
        }
        return sizes.isEmpty ? nil : sizes
    }

    func makeUIView(context: Context) -> ReaderNativeImageTextView {
        let view = ReaderNativeImageTextView(usingTextLayoutManager: false)
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.delegate = context.coordinator
        view.installCrossImageSelectionGesture()
        view.accessibilityIdentifier = "reader-native-image-selection"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: ReaderNativeImageTextView, context: Context) {
        context.coordinator.onLinkTap = onLinkTap
        configure(view, availableWidth: view.bounds.width > 0 ? view.bounds.width : nil)
        view.setImageOverlays(contents: imageContents)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReaderNativeImageTextView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        configure(uiView, availableWidth: width)
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }

    private func configure(_ view: ReaderNativeImageTextView, availableWidth: CGFloat?) {
        let sizes = naturalImageSizes.map {
            NaturalImageLayout.resolvedSize(natural: $0, width: nil, height: nil,
                                            availableWidth: availableWidth)
        }
        let built = attributedContent(traits: MarkdownTypography.traits(for: dynamicTypeSize), imageSizes: sizes)
        if !view.attributedText.isEqual(to: built.text) || view.renderedDynamicType != dynamicTypeSize {
            view.attributedText = built.text
            view.renderedDynamicType = dynamicTypeSize
            view.imageAnchorsUTF16 = built.imageAnchorsUTF16
            view.invalidateIntrinsicContentSize()
        }
        view.updateImageSizes(sizes)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLinkTap: onLinkTap) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onLinkTap: ((URL) -> Void)?
        init(onLinkTap: ((URL) -> Void)?) { self.onLinkTap = onLinkTap }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            guard case let .link(url) = textItem.content else { return defaultAction }
            guard MarkdownSyntax.isSafeLink(url) else { return nil }
            guard let onLinkTap else { return defaultAction }
            return UIAction { _ in onLinkTap(url) }
        }
    }

    private func attributedContent(traits: UITraitCollection, imageSizes: [CGSize]) ->
        (text: NSAttributedString, imageAnchorsUTF16: [Int]) {
        let output = NSMutableAttributedString(string: "")
        var imageAnchorsUTF16: [Int] = []
        var imageIndex = 0
        for index in document.segments.indices {
            let segment = document.segments[index]
            if index > 0 { output.append(NSAttributedString(string: "\n")) }
            if segment.kind == .image {
                let imageSize = imageSizes[imageIndex]
                imageIndex += 1
                imageAnchorsUTF16.append(output.length)
                let attributed = NSMutableAttributedString(string: ReaderNativeImageTextView.imageAnchor)
                let paragraph = NSMutableParagraphStyle()
                paragraph.minimumLineHeight = imageSize.height
                paragraph.paragraphSpacing = styleSheet.blockSpacing
                attributed.addAttributes([
                    .paragraphStyle: paragraph,
                    // The paragraph reserves the image height. A tiny glyph
                    // avoids wrapping tall portrait images by glyph width.
                    .font: UIFont.systemFont(ofSize: 1),
                    .foregroundColor: UIColor.clear,
                ], range: NSRange(location: 0, length: attributed.length))
                output.append(attributed)
            } else if let textDocument = ReaderSelectionDocument.compose(segment.nodes,
                                                                         enableHTML: enableHTML,
                                                                         plugins: plugins) {
                let renderer = ReaderSelectionTextView(document: textDocument, styleSheet: styleSheet,
                                                       onLinkTap: onLinkTap, onTextLongPress: nil,
                                                       selectable: true, onCharacterTap: nil)
                output.append(renderer.attributedContent(traits: traits).text)
            }
        }
        return (output, imageAnchorsUTF16)
    }
}

@available(iOS 17.0, *)
final class ReaderNativeImageTextView: UITextView, UIGestureRecognizerDelegate {
    static let imageAnchor = "\u{2588}"

    var imageAnchorsUTF16: [Int] = []
    var renderedDynamicType: DynamicTypeSize?
    private var imageHosts: [UIHostingController<AnyView>] = []
    private var imageSizes: [CGSize] = []
    private var dragAnchorUTF16: Int?

    func installCrossImageSelectionGesture() {
        // UIKit's own drag can stop at a tall image line even when the
        // following paragraph belongs to this same text view. The gesture
        // observes the drag alongside UIKit and only corrects a range that
        // actually crosses the image anchor.
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(trackCrossImageSelection(_:)))
        gesture.minimumPressDuration = 0.35
        gesture.delegate = self
        addGestureRecognizer(gesture)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func trackCrossImageSelection(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragAnchorUTF16 = characterOffset(at: gesture.location(in: self))
        case .changed, .ended:
            guard let anchor = dragAnchorUTF16,
                  let focus = characterOffset(at: gesture.location(in: self)),
                  ReaderImageSelectionProjection.crossesImage(from: anchor, to: focus,
                                                               imageAnchors: imageAnchorsUTF16) else {
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

    func setImageOverlays(contents: [AnyView]) {
        for (index, content) in contents.enumerated() {
            if imageHosts.indices.contains(index) {
                imageHosts[index].rootView = content
            } else {
                let host = UIHostingController(rootView: content)
                host.view.backgroundColor = .clear
                addSubview(host.view)
                imageHosts.append(host)
            }
        }
        while imageHosts.count > contents.count {
            imageHosts.removeLast().view.removeFromSuperview()
        }
        setNeedsLayout()
    }

    func updateImageSizes(_ sizes: [CGSize]) {
        guard imageSizes != sizes else { return }
        imageSizes = sizes
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard imageAnchorsUTF16.count == imageHosts.count,
              imageAnchorsUTF16.count == imageSizes.count else { return }
        layoutManager.ensureLayout(for: textContainer)
        for index in imageAnchorsUTF16.indices {
            let anchor = imageAnchorsUTF16[index]
            guard anchor < textStorage.length else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: anchor)
            let frame = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                                   in: textContainer)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let size = imageSizes[index]
            let target = CGRect(x: textContainerInset.left + frame.minX,
                                y: textContainerInset.top + line.minY,
                                width: size.width, height: size.height)
            let host = imageHosts[index]
            if host.view.frame != target { host.view.frame = target }
        }
    }

    override func copy(_ sender: Any?) {
        guard let copied = Self.selectedCopyText(in: attributedText, range: selectedRange,
                                                imageAnchorsUTF16: imageAnchorsUTF16),
              !copied.isEmpty else { return }
        UIPasteboard.general.string = copied
    }

    static func selectedCopyText(in source: NSAttributedString, range: NSRange,
                                 imageAnchorsUTF16: [Int]) -> String? {
        let text = source.string as NSString
        guard range.location != NSNotFound, range.location >= 0,
              range.length > 0, NSMaxRange(range) <= text.length,
              !imageAnchorsUTF16.isEmpty,
              imageAnchorsUTF16.allSatisfy({ $0 >= 0 && $0 < text.length &&
                  text.character(at: $0) == ReaderImageSelectionProjection.anchorCharacter })
        else { return nil }
        let selected = NSMutableString(string: text.substring(with: range))
        // ReaderSelectionTextView substitutes NBSP to keep inline code together.
        // Keep its exact plain-text copy semantics when this range crosses an image.
        let codeSpaceAttribute = NSAttributedString.Key("SmoothMarkdownCodeSpace")
        for offset in 0..<range.length where selected.character(at: offset) == 160 {
            if source.attribute(codeSpaceAttribute, at: range.location + offset,
                                effectiveRange: nil) != nil {
                selected.replaceCharacters(in: NSRange(location: offset, length: 1), with: " ")
            }
        }
        return ReaderImageSelectionProjection.copiedText(selected as String,
                                                         selectionStart: range.location,
                                                         imageAnchors: imageAnchorsUTF16)
    }
}
#endif
