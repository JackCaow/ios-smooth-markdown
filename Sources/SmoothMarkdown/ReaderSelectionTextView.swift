#if os(iOS)
import SwiftUI
import UIKit

/// A single read-only UITextView gives adjacent Markdown blocks one native selection range.
@available(iOS 17.0, *)
struct ReaderSelectionTextView: UIViewRepresentable {
    let document: ReaderSelectionDocument
    let styleSheet: MarkdownStyleSheet
    let onLinkTap: ((URL) -> Void)?

    func makeUIView(context: Context) -> QuoteTextView {
        let view = QuoteTextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.delegate = context.coordinator
        view.accessibilityCustomActions = [UIAccessibilityCustomAction(
            name: "Select all reader text", target: view, selector: #selector(QuoteTextView.selectAllReaderText)
        )]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: QuoteTextView, context: Context) {
        context.coordinator.onLinkTap = onLinkTap
        let built = attributedContent()
        if !view.attributedText.isEqual(to: built.text) {
            view.attributedText = built.text
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
