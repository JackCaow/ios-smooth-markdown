#if os(iOS)
import SwiftUI
import UIKit

private let codeSpaceAttribute = NSAttributedString.Key("SmoothMarkdownCodeSpace")
private let inlineCodeBackgroundAttribute = NSAttributedString.Key("SmoothMarkdownInlineCodeBackground")
private let keycapAttribute = NSAttributedString.Key("SmoothMarkdownKeycap")
private let keycapPaddingAttribute = NSAttributedString.Key("SmoothMarkdownKeycapPadding")

/// A single read-only UITextView gives adjacent Markdown blocks one native selection range.
@available(iOS 17.0, *)
struct ReaderSelectionTextView: UIViewRepresentable {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.readerTextSelectionMenuBuilder) private var textSelectionMenuBuilder
    let document: ReaderSelectionDocument
    let styleSheet: MarkdownStyleSheet
    let onLinkTap: ((URL) -> Void)?
    let onTextLongPress: ((@escaping () -> Void) -> Void)?
    let selectable: Bool
    /// Used by a range spanning a visual block to place a UTF-16 text endpoint.
    let onCharacterTap: ((Int) -> Void)?

    static func makeTextView() -> QuoteTextView {
        // Decorations use NSLayoutManager glyph coordinates. Creating a default
        // UITextView uses TextKit 2 on iOS 16+, then accessing layoutManager
        // while drawing switches it to TextKit 1 after SwiftUI has measured it.
        // Keep measurement, text drawing, and decoration geometry on TextKit 1.
        let view = QuoteTextView(usingTextLayoutManager: false)
        view.backgroundColor = .clear
        view.isEditable = false
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func makeUIView(context: Context) -> QuoteTextView {
        let view = Self.makeTextView()
        // Conversation bubbles own the first long press. Enabling UITextView's
        // selection at this point lets its private recognizers win first.
        view.isSelectable = selectable && onTextLongPress == nil && onCharacterTap == nil
        view.delegate = context.coordinator
        // UITextView requires isSelectable for its built-in link interaction.
        // Keep links tappable when the reader itself is not selectable.
        let linkTap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.didTapLink(_:)))
        linkTap.delegate = context.coordinator
        view.addGestureRecognizer(linkTap)
        let characterTap = UITapGestureRecognizer(target: context.coordinator,
                                                  action: #selector(Coordinator.didTapCharacter(_:)))
        characterTap.delegate = context.coordinator
        characterTap.isEnabled = onCharacterTap != nil
        view.addGestureRecognizer(characterTap)
        context.coordinator.characterTap = characterTap
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
        return view
    }

    func updateUIView(_ view: QuoteTextView, context: Context) {
        context.coordinator.onLinkTap = onLinkTap
        context.coordinator.onTextLongPress = onTextLongPress
        context.coordinator.onCharacterTap = onCharacterTap
        context.coordinator.textSelectionMenuBuilder = textSelectionMenuBuilder
        context.coordinator.longPress?.isEnabled = onTextLongPress != nil
        context.coordinator.characterTap?.isEnabled = onCharacterTap != nil
        view.accessibilityIdentifier = onCharacterTap == nil ? nil : "reader-character-endpoint-text"
        if onCharacterTap != nil { view.isSelectable = false }
        else if onTextLongPress == nil { view.isSelectable = selectable }
        view.accessibilityCustomActions = selectionAccessibilityActions(for: view)
        let built = attributedContent(traits: MarkdownTypography.traits(for: dynamicTypeSize))
        if !view.attributedText.isEqual(to: built.text) {
            view.attributedText = built.text
            view.isSelectable = selectable && onTextLongPress == nil && onCharacterTap == nil
            view.invalidateIntrinsicContentSize()
        }
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

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: QuoteTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(measured.height))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap, onTextLongPress: onTextLongPress,
                    onCharacterTap: onCharacterTap)
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
        var onCharacterTap: ((Int) -> Void)?
        var textSelectionMenuBuilder: ReaderTextSelectionMenuBuilder?
        weak var textView: QuoteTextView?
        weak var longPress: UILongPressGestureRecognizer?
        weak var characterTap: UITapGestureRecognizer?
        weak var editMenu: UIEditMenuInteraction?
        init(onLinkTap: ((URL) -> Void)?, onTextLongPress: ((@escaping () -> Void) -> Void)?,
             onCharacterTap: ((Int) -> Void)?) {
            self.onLinkTap = onLinkTap
            self.onTextLongPress = onTextLongPress
            self.onCharacterTap = onCharacterTap
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer === characterTap { return onCharacterTap != nil }
            if onCharacterTap != nil { return false }
            guard let textView, !textView.isSelectable else { return false }
            return link(at: touch.location(in: textView), in: textView) != nil
        }

        @objc func didTapCharacter(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let textView, let onCharacterTap,
                  let position = textView.closestPosition(to: recognizer.location(in: textView)) else { return }
            let offset = textView.offset(from: textView.beginningOfDocument, to: position)
            onCharacterTap(min(max(0, offset), textView.textStorage.length))
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
            if let textSelectionMenuBuilder {
                return customMenu(in: textView, range: textView.selectedRange,
                                  suggestedActions: suggestedActions,
                                  builder: textSelectionMenuBuilder)
            }
            return UIMenu(children: [UIAction(title: "复制", image: UIImage(systemName: "doc.on.doc")) {
                [weak textView] _ in textView?.copy(nil)
            }])
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let textSelectionMenuBuilder else { return nil }
            return customMenu(in: textView, range: range, suggestedActions: suggestedActions,
                              builder: textSelectionMenuBuilder)
        }

        private func customMenu(in textView: UITextView, range: NSRange,
                                suggestedActions: [UIMenuElement],
                                builder: ReaderTextSelectionMenuBuilder) -> UIMenu? {
            guard range.location >= 0, range.length > 0,
                  NSMaxRange(range) <= textView.textStorage.length else { return nil }
            let selected = (textView as? ReaderDocumentSelectionTextView)?
                .projection?.copiedText(in: range)
                ?? QuoteTextView.transformedCopyText(in: textView.textStorage,
                                                             ruleRegions: (textView as? QuoteTextView)?.ruleRegions ?? [],
                                                             range: range)
                ?? (textView.textStorage.string as NSString).substring(with: range)
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

    func attributedContent(traits: UITraitCollection) ->
        (text: NSAttributedString, quoteRegions: [QuoteTextView.Region], ruleRegions: [NSRange],
         headingRegions: [NSRange]) {
        let output = NSMutableAttributedString(string: "")
        var ruleRegions: [NSRange] = []
        var headingRegions: [NSRange] = []
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
            case .paragraph, .list, .quote, .rule: headingLevel = nil; weight = .regular
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = CGFloat(line.indent) * styleSheet.listIndent
                + CGFloat(line.quoteDepth) * styleSheet.blockquotePadding.leading
            if let headingLevel, headingLevel <= 2 {
                paragraph.firstLineHeadIndent += 16
            }
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
            if let headingLevel, headingLevel <= 2 {
                paragraph.paragraphSpacingBefore += 8
                paragraph.paragraphSpacing += 10
            }
            let semanticStyle = headingLevel.flatMap { level -> Font.TextStyle? in
                let index = level - 1
                return styleSheet.readerHeadingTextStyles.indices.contains(index)
                    ? styleSheet.readerHeadingTextStyles[index] : nil
            } ?? styleSheet.readerParagraphTextStyle
            let textStyle = MarkdownTypography.uiTextStyle(semanticStyle)
            let baseFont = MarkdownTypography.font(textStyle: textStyle, weight: weight,
                                                   customSize: nil, traits: traits)
            // Flutter's light stylesheet uses 1.5 for prose and 1.3/1.4 for headings.
            // A minimum height respects larger inline glyphs and keeps Dynamic Type scaling.
            let heightFactor: CGFloat = headingLevel.map { $0 <= 2 ? 1.3 : 1.4 } ?? 1.5
            paragraph.minimumLineHeight = baseFont.pointSize * heightFactor
            paragraph.lineBreakStrategy = headingLevel == nil ? [] : .pushOut
            for (runIndex, run) in line.runs.enumerated() {
                let inlineStyle = styleSheet.resolvedHTMLStyle(
                    styleSheet.resolvedInlineStyle(
                        bold: run.style.bold, italic: run.style.italic, strike: run.style.strike,
                        link: run.style.link != nil, code: run.code),
                    underline: run.htmlUnderline, highlight: run.highlighted)
                let fontWeight: UIFont.Weight = inlineStyle.bold == true ? .bold : weight
                let keycapStyle = styleSheet.kbdStyle
                let scaledFont = MarkdownTypography.font(textStyle: textStyle,
                                                         weight: fontWeight,
                                                         customSize: run.keycap ? (keycapStyle?.fontSize ?? 13) : inlineStyle.fontSize,
                                                         traits: traits)
                let font = run.keycap || inlineStyle.monospaced == true
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
                if line.kind == .rule {
                    // The anchor supplies a native selection position; UIKit draws the rule over its line.
                    attributes[.foregroundColor] = UIColor.clear
                    attributes[.font] = UIFont.systemFont(ofSize: 14)
                }
                if inlineStyle.italic == true { attributes[.obliqueness] = 0.18 }
                if inlineStyle.strikethrough == true {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                if inlineStyle.underline == true {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if let background = inlineStyle.backgroundColor {
                    // TextKit stretches .backgroundColor to the paragraph's minimum line height.
                    // Draw code backgrounds from the run's baseline instead so the smaller
                    // monospace glyphs sit vertically centered inside the same fill.
                    attributes[run.code ? inlineCodeBackgroundAttribute : .backgroundColor] = UIColor(background)
                }
                if let link = run.style.link {
                    attributes[.link] = link
                }
                if run.keycap {
                    if let color = keycapStyle?.textColor { attributes[.foregroundColor] = UIColor(color) }
                    // An integer keeps adjacent <kbd> elements as separate boxes.
                    attributes[keycapAttribute] = output.length + runIndex
                }
                if run.footnoteReference {
                    // Match SmoothMarkdownView.footnoteReference while retaining
                    // the reference inside the native paragraph selection range.
                    attributes[.font] = MarkdownTypography.font(textStyle: .footnote,
                                                                 weight: .regular, customSize: nil,
                                                                 traits: traits)
                    attributes[.baselineOffset] = 5
                    attributes[.foregroundColor] = UIColor(styleSheet.footnoteColor ?? .blue)
                }
                // Keep short inline code together when wrapping. NBSP has the
                // same UTF-16 length as a space, so native selection offsets stay
                // valid; the marker restores exact source text on Copy.
                let codeText = NSMutableString(string: run.text)
                var replacedSpaces: [Int] = []
                if run.code || run.keycap {
                    for offset in 0..<codeText.length where codeText.character(at: offset) == 32 {
                        codeText.replaceCharacters(in: NSRange(location: offset, length: 1), with: "\u{00A0}")
                        replacedSpaces.append(offset)
                    }
                }
                let attributedRun = NSMutableAttributedString(string: codeText as String, attributes: attributes)
                for offset in replacedSpaces {
                    attributedRun.addAttribute(codeSpaceAttribute, value: true,
                                               range: NSRange(location: offset, length: 1))
                }
                if run.keycap {
                    let paddingFont = UIFont.systemFont(ofSize: 1)
                    let padding: [NSAttributedString.Key: Any] = [
                        .font: paddingFont, .foregroundColor: UIColor.clear,
                        .paragraphStyle: paragraph, .kern: 4.5,
                        keycapAttribute: output.length + runIndex,
                        keycapPaddingAttribute: true,
                    ]
                    output.append(NSAttributedString(string: ReaderSelectionDocument.keycapPadding,
                                                     attributes: padding))
                    output.append(attributedRun)
                    output.append(NSAttributedString(string: ReaderSelectionDocument.keycapPadding,
                                                     attributes: padding))
                } else { output.append(attributedRun) }
            }
            if line.kind == .rule {
                ruleRegions.append(NSRange(location: start, length: output.length - start))
            }
            if let headingLevel, headingLevel <= 2, output.length > start {
                headingRegions.append(NSRange(location: start, length: output.length - start))
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
        return (output, quoteRegions, ruleRegions, headingRegions)
    }
}

@available(iOS 17.0, *)
class QuoteTextView: UITextView {
    struct Region {
        let range: NSRange
        let depth: Int
    }

    var quoteRegions: [Region] = [] { didSet { setNeedsDisplay() } }
    var ruleRegions: [NSRange] = [] { didSet { setNeedsDisplay() } }
    var headingRegions: [NSRange] = [] { didSet { setNeedsDisplay() } }
    var ruleColor: UIColor = .secondaryLabel { didSet { setNeedsDisplay() } }
    var keycapBorderColor: UIColor = .separator { didSet { setNeedsDisplay() } }
    var ruleThickness: CGFloat = 1 { didSet { setNeedsDisplay() } }
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

    override func copy(_ sender: Any?) {
        let range = selectedRange
        guard range.length > 0, NSMaxRange(range) <= textStorage.length else { return }
        guard let transformed = Self.transformedCopyText(in: textStorage,
                                                        ruleRegions: ruleRegions, range: range) else {
            super.copy(sender)
            return
        }
        UIPasteboard.general.string = transformed
    }

    /// Returns plain text only when visual anchors or nonbreaking code spaces
    /// need to be restored. Otherwise UITextView keeps its native Copy behavior.
    static func transformedCopyText(in text: NSAttributedString, ruleRegions: [NSRange],
                                    range: NSRange) -> String? {
        guard range.location >= 0, range.length > 0,
              NSMaxRange(range) <= text.length else { return nil }
        let selectedRules = ruleRegions.filter { NSIntersectionRange($0, range).length > 0 }
            .sorted { $0.location > $1.location }
        let selected = NSMutableString(string: (text.string as NSString).substring(with: range))
        var restoredCodeSpace = false
        var paddingOffsets: [Int] = []
        for offset in 0..<range.length where selected.character(at: offset) == 160 {
            if text.attribute(codeSpaceAttribute, at: range.location + offset,
                              effectiveRange: nil) != nil {
                selected.replaceCharacters(in: NSRange(location: offset, length: 1), with: " ")
                restoredCodeSpace = true
            }
        }
        for offset in 0..<range.length where selected.character(at: offset) == 0x2007 {
            if text.attribute(keycapPaddingAttribute, at: range.location + offset,
                              effectiveRange: nil) != nil { paddingOffsets.append(offset) }
        }
        guard restoredCodeSpace || !selectedRules.isEmpty || !paddingOffsets.isEmpty else { return nil }
        let deletions = selectedRules.map { NSRange(location: $0.location - range.location, length: $0.length) }
            + paddingOffsets.map { NSRange(location: $0, length: 1) }
        for deletion in deletions.sorted(by: { $0.location > $1.location }) {
            // A thematic-break anchor and a keycap inset can never share a run.
            selected.deleteCharacters(in: deletion)
        }
        return selected as String
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
        // Geometry below must come from the completed layout used by the text.
        layoutManager.ensureLayout(for: textContainer)
        let quoteFrames = quoteFrames()
        if let quoteBackgroundColor {
            quoteBackgroundColor.setFill()
            for (frame, _) in quoteFrames.sorted(by: { $0.1 < $1.1 }) {
                UIRectFill(frame)
            }
        }
        drawInlineCodeBackgrounds()
        drawKeycaps()
        if ruleThickness > 0 {
            ruleColor.setFill()
            for range in ruleRegions where range.location < textStorage.length {
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let glyphFrame = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                let y = textContainerInset.top + glyphFrame.midY - ruleThickness / 2
                UIRectFill(CGRect(x: textContainerInset.left, y: y,
                                  width: max(0, bounds.width - textContainerInset.left - textContainerInset.right),
                                  height: ruleThickness))
            }
        }
        super.draw(rect)
        drawHeadingDecorations()
        guard quoteBorderWidth > 0 else { return }
        quoteBarColor.setFill()
        for (frame, _) in quoteFrames {
            UIRectFill(CGRect(x: frame.minX, y: frame.minY,
                              width: min(quoteBorderWidth, frame.width), height: frame.height))
        }
    }

    private func drawInlineCodeBackgrounds() {
        guard textStorage.length > 0 else { return }
        textStorage.enumerateAttribute(inlineCodeBackgroundAttribute,
                                       in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let color = value as? UIColor else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            color.setFill()
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineGlyphs, _ in
                let segment = NSIntersectionRange(glyphs, lineGlyphs)
                guard segment.length > 0 else { return }
                let glyphRect = self.layoutManager.boundingRect(forGlyphRange: segment, in: self.textContainer)
                let character = self.layoutManager.characterIndexForGlyph(at: segment.location)
                guard let font = self.textStorage.attribute(.font, at: character,
                                                            effectiveRange: nil) as? UIFont else { return }
                let baseline = lineRect.minY + self.layoutManager.location(forGlyphAt: segment.location).y
                let height = glyphRect.height
                // Center the visible monospace letterforms inside the fill. Font line metrics
                // include leading and descender space, which places the ink visibly low.
                let inkHeight = (font.xHeight + font.capHeight) / 2
                let y = baseline - inkHeight / 2 - height / 2
                // TextKit's glyph bounds leave more space after this monospace run than before it.
                // Balance those side bearings and retain a small inset on either side.
                let horizontalPadding = font.pointSize * 0.10
                let bearingOffset = font.pointSize * 0.08
                UIRectFill(CGRect(x: self.textContainerInset.left + glyphRect.minX
                                      - horizontalPadding - bearingOffset,
                                  y: self.textContainerInset.top + y,
                                  width: glyphRect.width + 2 * horizontalPadding, height: height))
            }
        }
    }

    private func drawKeycaps() {
        guard textStorage.length > 0 else { return }
        textStorage.enumerateAttribute(keycapAttribute,
                                       in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard value != nil else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineGlyphs, _ in
                let segment = NSIntersectionRange(glyphs, lineGlyphs)
                guard segment.length > 0 else { return }
                let glyphRect = self.layoutManager.boundingRect(forGlyphRange: segment, in: self.textContainer)
                let character = min(range.location + 1, self.textStorage.length - 1)
                guard let font = self.textStorage.attribute(.font, at: character,
                                                            effectiveRange: nil) as? UIFont else { return }
                let baseline = lineRect.minY + self.layoutManager.location(forGlyphAt: segment.location).y
                let frame = CGRect(x: self.textContainerInset.left + glyphRect.minX,
                                   y: self.textContainerInset.top + baseline - font.ascender - 1,
                                   width: glyphRect.width,
                                   height: font.ascender - font.descender + 2)
                let path = UIBezierPath(roundedRect: frame, cornerRadius: 4)
                self.keycapBorderColor.withAlphaComponent(0.12).setFill()
                path.fill()
                self.keycapBorderColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    private func drawHeadingDecorations() {
        guard let context = UIGraphicsGetCurrentContext(),
              let barGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                           colors: [tintColor.cgColor, tintColor.withAlphaComponent(0.3).cgColor] as CFArray,
                                           locations: [0, 1]),
              let underlineGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                 colors: [tintColor.withAlphaComponent(0.3).cgColor,
                                                          tintColor.withAlphaComponent(0).cgColor] as CFArray,
                                                 locations: [0, 1]) else { return }
        for range in headingRegions where range.location < textStorage.length {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let glyphFrame = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            guard glyphFrame.width > 0, glyphFrame.height > 0 else { continue }
            let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
            let barHeight = font?.pointSize ?? 24
            let x = textContainerInset.left + glyphFrame.minX - 16
            let y = textContainerInset.top + glyphFrame.midY - barHeight / 2
            context.saveGState()
            context.addPath(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 4, height: barHeight),
                                         cornerRadius: 2).cgPath)
            context.clip()
            context.drawLinearGradient(barGradient, start: CGPoint(x: x, y: y),
                                       end: CGPoint(x: x, y: y + barHeight), options: [])
            context.restoreGState()

            let underlineY = textContainerInset.top + glyphFrame.maxY + 8
            let underlineWidth = max(0, bounds.width - x - textContainerInset.right)
            context.saveGState()
            context.clip(to: CGRect(x: x, y: underlineY, width: underlineWidth, height: 2))
            context.drawLinearGradient(underlineGradient, start: CGPoint(x: x, y: underlineY),
                                       end: CGPoint(x: x + underlineWidth, y: underlineY), options: [])
            context.restoreGState()
        }
    }
}
#endif
