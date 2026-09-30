#if os(iOS)
import SwiftDraw
import SwiftUI
import UIKit

struct ReaderNativeImageItem {
    let spec: SafeHTML.ImageSpec
    let source: ImageSource
    let localNaturalSize: CGSize?

    var remoteKey: ReaderRemoteImageKey? {
        guard case let .remote(url, svg) = source else { return nil }
        return ReaderRemoteImageKey(url: url, svg: svg)
    }
}

@available(iOS 17.0, *)
struct ReaderNativeImageSelectionContainer: View {
    let document: ReaderBlockRangeDocument
    let styleSheet: MarkdownStyleSheet
    let enableHTML: Bool
    let plugins: ParserPluginRegistry?
    let onLinkTap: ((URL) -> Void)?
    let imageContents: [AnyView]
    let imageItems: [ReaderNativeImageItem]
    let spacing: CGFloat
    let renderSegment: (ReaderBlockRangeDocument.Segment, @escaping () -> Void, ((Int) -> Void)?) -> AnyView
    let renderRemoteImage: (SafeHTML.ImageSpec, ReaderRemoteImageResolution?) -> AnyView

    @State private var usingWholeBlockSelection = false
    @State private var remoteResults: [ReaderRemoteImageKey: ReaderRemoteImageResolution] = [:]
    @State private var failedAt: [ReaderRemoteImageKey: Date] = [:]

    private var remoteKeys: [ReaderRemoteImageKey] {
        Array(Set(imageItems.compactMap(\.remoteKey))).sorted { $0.url.absoluteString < $1.url.absoluteString }
    }

    private var naturalImageSizes: [CGSize]? {
        let sizes = imageItems.compactMap { item in
            item.localNaturalSize ?? item.remoteKey.flatMap { remoteResults[$0]?.naturalSize }
        }
        return sizes.count == imageItems.count ? sizes : nil
    }

    var body: some View {
        Group {
            if usingWholeBlockSelection {
                ReaderBlockRangeView(document: document, enableHTML: enableHTML, plugins: plugins,
                                     spacing: spacing, startSelecting: true,
                                     onSelectionStarted: nil,
                                     onSelectionFinished: { usingWholeBlockSelection = false },
                                     renderSegment: fallbackSegment)
            } else if let naturalImageSizes {
                let contents = zip(imageItems, imageContents).map { item, localContent -> AnyView in
                    guard let key = item.remoteKey else { return localContent }
                    return renderRemoteImage(item.spec, remoteResults[key])
                }
                ReaderNativeImageSelectionView(document: document, styleSheet: styleSheet,
                                               enableHTML: enableHTML, plugins: plugins,
                                               onLinkTap: onLinkTap,
                                               imageContents: contents.map { content in
                    AnyView(content.contextMenu {
                        Button("Select surrounding content") { usingWholeBlockSelection = true }
                    })
                }, imageItems: imageItems, naturalImageSizes: naturalImageSizes)
            } else {
                ReaderBlockRangeView(document: document, enableHTML: enableHTML, plugins: plugins,
                                     spacing: spacing, startSelecting: false,
                                     onSelectionStarted: { usingWholeBlockSelection = true },
                                     onSelectionFinished: nil, renderSegment: fallbackSegment)
            }
        }
        .task(id: remoteKeys) { await loadRemoteImages() }
    }

    private func fallbackSegment(_ segment: ReaderBlockRangeDocument.Segment,
                                 beginSelection: @escaping () -> Void,
                                 onCharacterTap: ((Int) -> Void)?) -> AnyView {
        if segment.isImage,
           let spec = ReaderNativeImageSelectionView.imageSpec(for: segment, enableHTML: enableHTML),
           case let .remote(url, svg) = ImageSource.parse(spec.source) {
            return renderRemoteImage(spec, remoteResults[ReaderRemoteImageKey(url: url, svg: svg)])
        }
        return renderSegment(segment, beginSelection, onCharacterTap)
    }

    private func loadRemoteImages() async {
        remoteResults = remoteResults.filter { remoteKeys.contains($0.key) }
        failedAt = failedAt.filter { remoteKeys.contains($0.key) }
        let now = Date()
        let missing = remoteKeys.filter { key in
            switch remoteResults[key] {
            case nil: return true
            case .failure?: return ReaderRemoteImagePolicy.shouldRetry(failedAt: failedAt[key], now: now)
            case .svg?, .bitmap?, .rejected?: return false
            }
        }
        var remaining = missing.makeIterator()
        await withTaskGroup(of: (ReaderRemoteImageKey, ReaderRemoteImageResolution).self) { group in
            func enqueue(_ key: ReaderRemoteImageKey) {
                group.addTask {
                    let result = await ReaderRemoteImageLoader.fetch(key)
                    switch result {
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
                let resolved = ReaderRemoteImagePolicy.canRetain(pixels: loaded.pixelCost,
                                                                   after: currentPixels) ? loaded : .rejected
                remoteResults[key] = resolved
                if case .failure = resolved { failedAt[key] = Date() }
                else { failedAt.removeValue(forKey: key) }
                if let next = remaining.next() { enqueue(next) }
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
    @Environment(\.readerTextSelectionMenuBuilder) private var textSelectionMenuBuilder
    let document: ReaderBlockRangeDocument
    let styleSheet: MarkdownStyleSheet
    let enableHTML: Bool
    let plugins: ParserPluginRegistry?
    let onLinkTap: ((URL) -> Void)?
    let imageContents: [AnyView]
    let imageItems: [ReaderNativeImageItem]
    let naturalImageSizes: [CGSize]

    static func imageSpec(for segment: ReaderBlockRangeDocument.Segment,
                          enableHTML: Bool) -> SafeHTML.ImageSpec? {
        ReaderImageSelectionEligibility.imageSpec(for: segment, enableHTML: enableHTML)
    }

    static func imageItems(for document: ReaderBlockRangeDocument, enableHTML: Bool,
                           plugins: ParserPluginRegistry?) -> [ReaderNativeImageItem]? {
        guard let specs = ReaderImageSelectionEligibility.imageSpecs(for: document,
                                                                    enableHTML: enableHTML,
                                                                    plugins: plugins) else { return nil }
        var items: [ReaderNativeImageItem] = []
        for spec in specs {
            guard let parsed = ImageSource.parse(spec.source) else { return nil }
            let size: CGSize?
            switch parsed {
            case let .bundled(name, svg: true):
                guard let svg = SVG(named: name, in: .main) else { return nil }
                size = svg.size
            case let .bundled(name, svg: false):
                guard let image = UIImage(named: name) else { return nil }
                size = image.size
            case .remote: size = nil
            }
            if let size {
                guard size.width > 0, size.height > 0,
                      size.width.isFinite, size.height.isFinite else { return nil }
            }
            items.append(.init(spec: spec, source: parsed, localNaturalSize: size))
        }
        guard items.compactMap(\.remoteKey).count <= ReaderRemoteImagePolicy.maxRemoteImages else { return nil }
        return items
    }

    func makeUIView(context: Context) -> ReaderNativeImageTextView {
        let view = ReaderNativeImageTextView(frame: .zero, textContainer: nil)
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
        context.coordinator.textSelectionMenuBuilder = textSelectionMenuBuilder
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
        let sizes: [CGSize] = zip(imageItems, naturalImageSizes).map { item, natural in
            NaturalImageLayout.resolvedSize(natural: natural,
                                            width: item.spec.width.map { CGFloat($0) },
                                            height: item.spec.height.map { CGFloat($0) },
                                            availableWidth: availableWidth)
        }
        let built = attributedContent(traits: MarkdownTypography.traits(for: dynamicTypeSize), imageSizes: sizes)
        view.applyRenderedContent(built.text, imageAnchorsUTF16: built.imageAnchorsUTF16)
        view.updateImageSizes(sizes)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLinkTap: onLinkTap) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onLinkTap: ((URL) -> Void)?
        var textSelectionMenuBuilder: ReaderTextSelectionMenuBuilder?
        init(onLinkTap: ((URL) -> Void)?) { self.onLinkTap = onLinkTap }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let builder = textSelectionMenuBuilder,
                  let imageTextView = textView as? ReaderNativeImageTextView,
                  let selected = ReaderNativeImageTextView.selectedCopyText(
                    in: imageTextView.attributedText, range: range,
                    imageAnchorsUTF16: imageTextView.imageAnchorsUTF16),
                  !selected.isEmpty else { return nil }
            return builder(selected, suggestedActions)
        }

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
    private var imageHosts: [UIHostingController<AnyView>] = []
    private var imageSizes: [CGSize] = []
    private var dragAnchorUTF16: Int?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func applyRenderedContent(_ content: NSAttributedString, imageAnchorsUTF16: [Int]) {
        if !attributedText.isEqual(to: content) {
            let oldText = attributedText.string
            let retained = ReaderImageSelectionProjection.retainedRange(
                selectedRange, oldText: oldText, newText: content.string)
            if oldText != content.string { dragAnchorUTF16 = nil }
            attributedText = content
            selectedRange = retained ?? NSRange(location: 0, length: 0)
            invalidateIntrinsicContentSize()
        }
        self.imageAnchorsUTF16 = imageAnchorsUTF16
    }

    func installCrossImageSelectionGesture() {
        // UIKit's own drag can stop at a tall image line even when the
        // following paragraph belongs to this same text view. The gesture
        // observes the drag alongside UIKit and only corrects a range that
        // actually crosses the image anchor.
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(trackCrossImageSelection(_:)))
        gesture.minimumPressDuration = 0.35
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        addGestureRecognizer(gesture)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // Image taps and its context menu belong to the hosted SwiftUI view.
        // A drag beginning in prose remains tracked as it passes over images.
        !imageHosts.contains { host in
            touch.view?.isDescendant(of: host.view) == true
        }
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
