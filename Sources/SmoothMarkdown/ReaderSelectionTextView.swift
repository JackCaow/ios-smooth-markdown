#if os(iOS)
import SwiftUI
import UIKit

/// A single read-only UITextView gives adjacent Markdown blocks one native selection range.
@available(iOS 17.0, *)
struct ReaderSelectionTextView: UIViewRepresentable {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let document: ReaderSelectionDocument
    let styleSheet: MarkdownStyleSheet
    let onLinkTap: ((URL) -> Void)?
    let onTextLongPress: ((@escaping () -> Void) -> Void)?
    let selectable: Bool

    func makeUIView(context: Context) -> QuoteTextView {
        let view = QuoteTextView()
        view.backgroundColor = .clear
        view.isEditable = false
        // Conversation bubbles own the first long press. Enabling UITextView's
        // selection at this point lets its private recognizers win first.
        view.isSelectable = selectable && onTextLongPress == nil
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.delegate = context.coordinator
        // UITextView requires isSelectable for its built-in link interaction.
        // Keep links tappable when the reader itself is not selectable.
        let linkTap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.didTapLink(_:)))
        linkTap.delegate = context.coordinator
        view.addGestureRecognizer(linkTap)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator,
                                                    action: #selector(Coordinator.didLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.isEnabled = onTextLongPress != nil
        // The message menu takes the long press before UITextView's built-in word
        // selection. Ordinary taps, links and drag gestures remain native.
        for recognizer in view.gestureRecognizers ?? [] where recognizer is UILongPressGestureRecognizer {
            recognizer.require(toFail: longPress)
        }
        view.addGestureRecognizer(longPress)
        context.coordinator.longPress = longPress
        context.coordinator.textView = view
        if onTextLongPress != nil {
            let editMenu = UIEditMenuInteraction(delegate: context.coordinator)
            view.addInteraction(editMenu)
            context.coordinator.editMenu = editMenu
        }
        view.accessibilityCustomActions = selectionAccessibilityActions(for: view)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: QuoteTextView, context: Context) {
        context.coordinator.onLinkTap = onLinkTap
        context.coordinator.onTextLongPress = onTextLongPress
        context.coordinator.longPress?.isEnabled = onTextLongPress != nil
        if onTextLongPress == nil { view.isSelectable = selectable }
        view.accessibilityCustomActions = selectionAccessibilityActions(for: view)
        let built = attributedContent(traits: MarkdownTypography.traits(for: dynamicTypeSize))
        if !view.attributedText.isEqual(to: built.text) {
            view.attributedText = built.text
            view.isSelectable = selectable && onTextLongPress == nil
            view.invalidateIntrinsicContentSize()
        }
        let decoration = styleSheet.resolvedBlockquoteDecoration
        view.quoteRegions = built.quoteRegions
        view.quoteBarColor = UIColor(decoration.borderColor ?? .accentColor)
        view.quoteBackgroundColor = decoration.backgroundColor.map(UIColor.init)
        view.quoteBorderWidth = decoration.borderWidth
        view.quotePadding = styleSheet.blockquotePadding
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: QuoteTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap, onTextLongPress: onTextLongPress)
    }

    private func selectionAccessibilityActions(for view: QuoteTextView) -> [UIAccessibilityCustomAction] {
        guard selectable || onTextLongPress != nil else { return [] }
        return [UIAccessibilityCustomAction(
            name: "Select all reader text", target: view, selector: #selector(QuoteTextView.selectAllReaderText)
        )]
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
        var onLinkTap: ((URL) -> Void)?
        var onTextLongPress: ((@escaping () -> Void) -> Void)?
        weak var textView: QuoteTextView?
        weak var longPress: UILongPressGestureRecognizer?
        weak var editMenu: UIEditMenuInteraction?
        init(onLinkTap: ((URL) -> Void)?, onTextLongPress: ((@escaping () -> Void) -> Void)?) {
            self.onLinkTap = onLinkTap
            self.onTextLongPress = onTextLongPress
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let textView, !textView.isSelectable else { return false }
            return link(at: touch.location(in: textView), in: textView) != nil
        }

        @objc func didTapLink(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let textView,
                  let url = link(at: recognizer.location(in: textView), in: textView) else { return }
            if let onLinkTap { onLinkTap(url) }
            else { UIApplication.shared.open(url) }
        }

        private func link(at point: CGPoint, in textView: UITextView) -> URL? {
            guard textView.textStorage.length > 0 else { return nil }
            let containerPoint = CGPoint(x: point.x - textView.textContainerInset.left + textView.contentOffset.x,
                                         y: point.y - textView.textContainerInset.top + textView.contentOffset.y)
            let manager = textView.layoutManager
            let glyph = manager.glyphIndex(for: containerPoint, in: textView.textContainer)
            guard glyph < manager.numberOfGlyphs,
                  manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                       in: textView.textContainer).contains(containerPoint) else { return nil }
            let character = manager.characterIndexForGlyph(at: glyph)
            guard character < textView.textStorage.length,
                  let url = textView.textStorage.attribute(.link, at: character, effectiveRange: nil) as? URL,
                  MarkdownSyntax.isSafeLink(url) else { return nil }
            return url
        }

        @objc func didLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let textView,
                  let onTextLongPress, textView.textStorage.length > 0 else { return }
            let point = recognizer.location(in: textView)
            guard let position = textView.closestPosition(to: point) else { return }
            let offset = textView.offset(from: textView.beginningOfDocument, to: position)
            let source = textView.text as NSString
            let index = min(max(0, offset), source.length - 1)
            var paragraph = source.paragraphRange(for: NSRange(location: index, length: 0))
            while paragraph.length > 0 {
                let last = source.character(at: NSMaxRange(paragraph) - 1)
                guard last == 10 || last == 13 else { break }
                paragraph.length -= 1
            }
            guard paragraph.length > 0 else { return }
            onTextLongPress { [weak self, weak textView] in
                guard let textView, textView.window != nil else { return }
                textView.isSelectable = true
                textView.becomeFirstResponder()
                textView.selectedRange = paragraph
                textView.scrollRangeToVisible(paragraph)
                if let editMenu = self?.editMenu,
                   let start = textView.position(from: textView.beginningOfDocument,
                                                 offset: paragraph.location) {
                    let caret = textView.caretRect(for: start)
                    editMenu.presentEditMenu(with: UIEditMenuConfiguration(
                        identifier: nil, sourcePoint: CGPoint(x: caret.midX, y: caret.midY)))
                }
            }
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                 menuFor configuration: UIEditMenuConfiguration,
                                 suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let textView, textView.selectedRange.length > 0 else { return nil }
            return UIMenu(children: [UIAction(title: "复制", image: UIImage(systemName: "doc.on.doc")) {
                [weak textView] _ in textView?.copy(nil)
            }])
        }
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            guard case let .link(url) = textItem.content else { return defaultAction }
            guard MarkdownSyntax.isSafeLink(url) else { return nil }
            guard let onLinkTap else { return defaultAction }
            return UIAction { _ in onLinkTap(url) }
        }
    }

    func attributedContent(traits: UITraitCollection) -> (text: NSAttributedString, quoteRegions: [QuoteTextView.Region]) {
        let output = NSMutableAttributedString(string: "")
        var quoteBounds: [Int: (start: Int, end: Int, depth: Int)] = [:]
        var quoteOrder: [Int] = []
        var firstQuoteLine: [Int: Int] = [:]
        var lastQuoteLine: [Int: Int] = [:]
        for (index, line) in document.lines.enumerated() {
            for id in line.quoteIDs {
                if firstQuoteLine[id] == nil { firstQuoteLine[id] = index }
                lastQuoteLine[id] = index
            }
        }
        let normalColor = UIColor(styleSheet.textColor ?? .primary)
        for (index, line) in document.lines.enumerated() {
            if index > 0 { output.append(NSAttributedString(string: "\n")) }
            let start = output.length
            let headingLevel: Int?
            let weight: UIFont.Weight
            switch line.kind {
            case let .heading(level): headingLevel = level; weight = .semibold
            case .paragraph, .list, .quote: headingLevel = nil; weight = .regular
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = CGFloat(line.indent) * styleSheet.listIndent
                + CGFloat(line.quoteDepth) * styleSheet.blockquotePadding.leading
            paragraph.headIndent = paragraph.firstLineHeadIndent
            if line.quoteDepth > 0 {
                paragraph.tailIndent = -CGFloat(line.quoteDepth) * styleSheet.blockquotePadding.trailing
                paragraph.paragraphSpacingBefore = CGFloat(line.quoteIDs.filter { firstQuoteLine[$0] == index }.count)
                    * styleSheet.blockquotePadding.top
                let closingCount = line.quoteIDs.filter { lastQuoteLine[$0] == index }.count
                paragraph.paragraphSpacing = closingCount > 0
                    ? CGFloat(closingCount) * styleSheet.blockquotePadding.bottom + styleSheet.blockSpacing
                    : styleSheet.quoteSpacing
            } else {
                paragraph.paragraphSpacing = line.kind == .list ? styleSheet.listSpacing : styleSheet.blockSpacing
            }
            paragraph.lineSpacing = UIFontMetrics(forTextStyle: .body).scaledValue(for: 2, compatibleWith: traits)
            for run in line.runs {
                let inlineStyle = styleSheet.resolvedInlineStyle(
                    bold: run.style.bold, italic: run.style.italic, strike: run.style.strike,
                    link: run.style.link != nil, code: run.code)
                let fontWeight: UIFont.Weight = inlineStyle.bold == true ? .bold : weight
                let semanticStyle = headingLevel.flatMap { level -> Font.TextStyle? in
                    let index = level - 1
                    return styleSheet.readerHeadingTextStyles.indices.contains(index)
                        ? styleSheet.readerHeadingTextStyles[index] : nil
                } ?? styleSheet.readerParagraphTextStyle
                let scaledFont = MarkdownTypography.font(textStyle: MarkdownTypography.uiTextStyle(semanticStyle),
                                                         weight: fontWeight, customSize: inlineStyle.fontSize,
                                                         traits: traits)
                let font = inlineStyle.monospaced == true
                    ? UIFont.monospacedSystemFont(ofSize: scaledFont.pointSize, weight: fontWeight)
                    : scaledFont
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: inlineStyle.textColor.map(UIColor.init) ?? {
                        if case .heading = line.kind {
                            return UIColor(styleSheet.headingColor ?? styleSheet.textColor ?? .primary)
                        }
                        return normalColor
                    }(),
                    .paragraphStyle: paragraph,
                ]
                if inlineStyle.italic == true { attributes[.obliqueness] = 0.18 }
                if inlineStyle.strikethrough == true {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                if inlineStyle.underline == true {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if let background = inlineStyle.backgroundColor {
                    attributes[.backgroundColor] = UIColor(background)
                }
                if let link = run.style.link {
                    attributes[.link] = link
                }
                output.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            for (depth, id) in line.quoteIDs.enumerated() {
                if quoteBounds[id] == nil {
                    quoteOrder.append(id)
                    quoteBounds[id] = (start: start, end: output.length, depth: depth + 1)
                } else if var bounds = quoteBounds[id] {
                    bounds.end = output.length
                    quoteBounds[id] = bounds
                }
            }
        }
        let quoteRegions = quoteOrder.compactMap { id -> QuoteTextView.Region? in
            guard let bounds = quoteBounds[id] else { return nil }
            return .init(range: NSRange(location: bounds.start, length: max(1, bounds.end - bounds.start)),
                         depth: bounds.depth)
        }
        return (output, quoteRegions)
    }
}

@available(iOS 17.0, *)
final class QuoteTextView: UITextView {
    struct Region {
        let range: NSRange
        let depth: Int
    }

    var quoteRegions: [Region] = [] { didSet { setNeedsDisplay() } }
    var quoteBarColor: UIColor = .tintColor { didSet { setNeedsDisplay() } }
    var quoteBackgroundColor: UIColor? { didSet { setNeedsDisplay() } }
    var quoteBorderWidth: CGFloat = 4 { didSet { setNeedsDisplay() } }
    var quotePadding = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16) { didSet { setNeedsDisplay() } }

    @objc func selectAllReaderText() -> Bool {
        guard textStorage.length > 0 else { return false }
        isSelectable = true
        becomeFirstResponder()
        selectedRange = NSRange(location: 0, length: textStorage.length)
        return true
    }

    func quoteFrames() -> [(CGRect, Int)] {
        quoteRegions.compactMap { region -> (CGRect, Int)? in
            guard region.range.location < textStorage.length else { return nil }
            let glyphs = layoutManager.glyphRange(forCharacterRange: region.range, actualCharacterRange: nil)
            let textFrame = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            let x = textContainerInset.left + CGFloat(region.depth - 1) * quotePadding.leading
            let frame = CGRect(x: x, y: textContainerInset.top + textFrame.minY - quotePadding.top,
                               width: max(0, bounds.width - x - textContainerInset.right),
                               height: max(textFrame.height, 18) + quotePadding.top + quotePadding.bottom)
            return (frame, region.depth)
        }
    }

    override func draw(_ rect: CGRect) {
        let quoteFrames = quoteFrames()
        if let quoteBackgroundColor {
            quoteBackgroundColor.setFill()
            for (frame, _) in quoteFrames.sorted(by: { $0.1 < $1.1 }) {
                UIRectFill(frame)
            }
        }
        super.draw(rect)
        guard quoteBorderWidth > 0 else { return }
        quoteBarColor.setFill()
        for (frame, _) in quoteFrames {
            UIRectFill(CGRect(x: frame.minX, y: frame.minY,
                              width: min(quoteBorderWidth, frame.width), height: frame.height))
        }
    }
}
#endif
