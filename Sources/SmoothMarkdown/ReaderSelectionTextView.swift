#if os(iOS)
import SwiftUI
import UIKit

/// A single read-only UITextView gives adjacent Markdown blocks one native selection range.
@available(iOS 17.0, *)
struct ReaderSelectionTextView: UIViewRepresentable {
    let document: ReaderSelectionDocument
    let styleSheet: MarkdownStyleSheet
    let onLinkTap: ((URL) -> Void)?
    let onTextLongPress: ((@escaping () -> Void) -> Void)?

    func makeUIView(context: Context) -> QuoteTextView {
        let view = QuoteTextView()
        view.backgroundColor = .clear
        view.isEditable = false
        // Conversation bubbles own the first long press. Enabling UITextView's
        // selection at this point lets its private recognizers win first.
        view.isSelectable = onTextLongPress == nil
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.delegate = context.coordinator
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
        view.accessibilityCustomActions = [UIAccessibilityCustomAction(
            name: "Select all reader text", target: view, selector: #selector(QuoteTextView.selectAllReaderText)
        )]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: QuoteTextView, context: Context) {
        context.coordinator.onLinkTap = onLinkTap
        context.coordinator.onTextLongPress = onTextLongPress
        context.coordinator.longPress?.isEnabled = onTextLongPress != nil
        let built = attributedContent()
        if !view.attributedText.isEqual(to: built.text) {
            view.attributedText = built.text
            view.isSelectable = onTextLongPress == nil
            view.invalidateIntrinsicContentSize()
        }
        view.quoteRanges = built.quoteRanges
        view.quoteBarColor = UIColor(styleSheet.quoteBarColor ?? .accentColor)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: QuoteTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap, onTextLongPress: onTextLongPress)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIEditMenuInteractionDelegate {
        var onLinkTap: ((URL) -> Void)?
        var onTextLongPress: ((@escaping () -> Void) -> Void)?
        weak var textView: QuoteTextView?
        weak var longPress: UILongPressGestureRecognizer?
        weak var editMenu: UIEditMenuInteraction?
        init(onLinkTap: ((URL) -> Void)?, onTextLongPress: ((@escaping () -> Void) -> Void)?) {
            self.onLinkTap = onLinkTap
            self.onTextLongPress = onTextLongPress
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

    private func attributedContent() -> (text: NSAttributedString, quoteRanges: [NSRange]) {
        let output = NSMutableAttributedString(string: "")
        var quoteRanges: [NSRange] = []
        let normalColor = UIColor(styleSheet.textColor ?? .primary)
        for (index, line) in document.lines.enumerated() {
            if index > 0 { output.append(NSAttributedString(string: "\n")) }
            let start = output.length
            let size: CGFloat
            let weight: UIFont.Weight
            switch line.kind {
            case let .heading(level): size = CGFloat(32 - (level - 1) * 3); weight = .bold
            case .paragraph, .list, .quote: size = 16; weight = .regular
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = CGFloat(line.indent) * styleSheet.listIndent + CGFloat(line.quoteDepth) * 16
            paragraph.headIndent = paragraph.firstLineHeadIndent
            paragraph.paragraphSpacing = line.kind == .list ? styleSheet.listSpacing : styleSheet.blockSpacing
            paragraph.lineSpacing = 2
            for run in line.runs {
                let font = UIFont.systemFont(ofSize: size,
                                             weight: run.style.bold || weight == .bold ? .bold : .regular)
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: run.code ? UIFont.monospacedSystemFont(ofSize: size, weight: .regular) : font,
                    .foregroundColor: {
                        if case .heading = line.kind {
                            return UIColor(styleSheet.headingColor ?? styleSheet.textColor ?? .primary)
                        }
                        return normalColor
                    }(),
                    .paragraphStyle: paragraph,
                ]
                if run.style.italic { attributes[.obliqueness] = 0.18 }
                if run.style.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if run.code, let background = styleSheet.inlineCodeBackground {
                    attributes[.backgroundColor] = UIColor(background)
                }
                if let link = run.style.link {
                    attributes[.link] = link
                    attributes[.foregroundColor] = UIColor(styleSheet.linkColor ?? .blue)
                }
                output.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            if line.quoteDepth > 0 {
                quoteRanges.append(NSRange(location: start, length: max(1, output.length - start)))
            }
        }
        return (output, quoteRanges)
    }
}

@available(iOS 17.0, *)
final class QuoteTextView: UITextView {
    var quoteRanges: [NSRange] = [] { didSet { setNeedsDisplay() } }
    var quoteBarColor: UIColor = .tintColor { didSet { setNeedsDisplay() } }

    @objc func selectAllReaderText() -> Bool {
        guard textStorage.length > 0 else { return false }
        isSelectable = true
        becomeFirstResponder()
        selectedRange = NSRange(location: 0, length: textStorage.length)
        return true
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        quoteBarColor.setFill()
        for range in quoteRanges {
            guard range.location < textStorage.length else { continue }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let frame = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            UIBezierPath(roundedRect: CGRect(x: textContainerInset.left + 3, y: textContainerInset.top + frame.minY,
                                             width: 3, height: max(frame.height, 18)), cornerRadius: 1.5).fill()
        }
    }
}
#endif
