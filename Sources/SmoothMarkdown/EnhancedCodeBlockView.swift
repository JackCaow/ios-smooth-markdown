import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Flutter's default code builder: source text inside the configured decoration,
/// without a language badge, copy control, or syntax coloring.
struct StandardCodeBlockView: View {
    let code: String
    let language: String?
    let styleSheet: MarkdownStyleSheet
    let selectable: Bool
    let onCopy: ((String, String?) -> Void)?
    #if os(iOS)
    @Environment(\.readerTextSelectionMenuBuilder) private var textSelectionMenuBuilder
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
            if selectable, let textSelectionMenuBuilder, !code.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    ReaderSelectionActionsButton(selectedText: code, builder: textSelectionMenuBuilder,
                                                 copy: copyCode,
                                                 accessibilityIdentifier: "reader-code-actions")
                }
                .padding(styleSheet.designTokens.code.headerPadding)
            }
            #endif
            ScrollView(.horizontal, showsIndicators: styleSheet.designTokens.code.showScrollbar) {
                Text(code)
                    .font(styleSheet.codeFont ?? .system(.body, design: .monospaced))
                    .foregroundColor(styleSheet.codeTextColor ?? styleSheet.textColor)
                    .fixedSize(horizontal: true, vertical: false)
                    .markdownTextSelection(selectable)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .padding(styleSheet.resolvedCodeBlockPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let decoration = styleSheet.resolvedCodeBlockDecoration
            RoundedRectangle(cornerRadius: decoration.cornerRadius)
                .fill(decoration.backgroundColor ?? .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: decoration.cornerRadius)
                        .strokeBorder(decoration.borderColor ?? .clear, lineWidth: decoration.borderWidth)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: styleSheet.resolvedCodeBlockDecoration.cornerRadius))
    }

    private func copyCode() {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(code, forType: .string) else { return }
        #else
        return
        #endif
        onCopy?(code, language)
    }
}

struct EnhancedCodeBlockView: View {
    @Environment(\.markdownStrings) private var strings
    let code: String
    let language: String?
    let options: CodeBlockOptions
    let onCopy: ((String, String?) -> Void)?
    let styleSheet: MarkdownStyleSheet
    let selectable: Bool
    let onSelectSurroundingContent: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.readerTextSelectionMenuBuilder) private var textSelectionMenuBuilder
    #endif
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if (options.showLanguageTag && !(language?.isEmpty ?? true)) || options.showCopyButton {
                HStack(spacing: styleSheet.designTokens.code.headerSpacing) {
                    if options.showLanguageTag, let language, !language.isEmpty {
                        languageBadge(language)
                    }
                    Spacer(minLength: 0)
                    if options.showCopyButton {
                        if let onSelectSurroundingContent {
                            copyButton.contextMenu {
                                Button(strings.selectSurroundingContent, action: onSelectSurroundingContent)
                            }
                            .accessibilityAction(named: Text(strings.selectSurroundingContent)) {
                                onSelectSurroundingContent()
                            }
                        } else {
                            copyButton
                        }
                    }
                    #if os(iOS)
                    if selectable, let textSelectionMenuBuilder, !code.isEmpty {
                        ReaderSelectionActionsButton(selectedText: code, builder: textSelectionMenuBuilder,
                                                     copy: copyCode,
                                                     accessibilityIdentifier: "reader-code-actions")
                    }
                    #endif
                }
                .padding(styleSheet.designTokens.code.headerPadding)
            }
            #if os(iOS)
            if !options.showCopyButton && (!options.showLanguageTag || language?.isEmpty != false),
               selectable, let textSelectionMenuBuilder, !code.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    ReaderSelectionActionsButton(selectedText: code, builder: textSelectionMenuBuilder,
                                                 copy: copyCode,
                                                 accessibilityIdentifier: "reader-code-actions")
                }
                .padding(styleSheet.designTokens.code.headerPadding)
            }
            #endif
            ScrollView(.horizontal, showsIndicators: styleSheet.designTokens.code.showScrollbar) {
                Text(CodeSyntaxHighlighter.attributed(code, language: language,
                                                      dark: styleSheet.darkCodeHighlighting ?? (colorScheme == .dark),
                                                      enabled: options.enableSyntaxHighlighting, colors: styleSheet.designTokens.code.syntaxColors))
                    .font(styleSheet.codeFont ?? .system(.body, design: .monospaced))
                    .foregroundColor(styleSheet.codeTextColor ?? styleSheet.textColor)
                    .fixedSize(horizontal: true, vertical: false)
                    .markdownTextSelection(selectable)
                    .padding(styleSheet.resolvedCodeBlockPadding)
            }
            // A long, unwrapped code line must stay inside this viewport while
            // the user scrolls it. Text selection can otherwise draw beyond the
            // horizontal ScrollView's visible bounds on iOS.
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let decoration = styleSheet.resolvedCodeBlockDecoration
            RoundedRectangle(cornerRadius: decoration.cornerRadius)
                .fill(decoration.backgroundColor ?? .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: decoration.cornerRadius)
                        .strokeBorder(decoration.borderColor ?? .clear, lineWidth: decoration.borderWidth)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: styleSheet.resolvedCodeBlockDecoration.cornerRadius))
        .onDisappear { resetTask?.cancel() }
    }

    private func languageBadge(_ language: String) -> some View {
        let tokens = styleSheet.designTokens.code
        let foreground = tokens.languageColor ?? styleSheet.linkColor ?? Color.accentColor
        let background = tokens.languageBackgroundColor ?? foreground.opacity(tokens.languageBackgroundAlpha)
        return Text(language.uppercased())
            .font(tokens.languageFont ?? .caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(tokens.languagePadding)
            .background(background, in: RoundedRectangle(cornerRadius: tokens.languageCornerRadius))
    }

    private var copyButton: some View {
        let tokens = styleSheet.designTokens.code
        let normalColor = tokens.copyColor ?? styleSheet.linkColor ?? Color.secondary
        let foreground = copied ? tokens.copiedColor : normalColor
        let background = copied
            ? (tokens.copiedBackgroundColor ?? tokens.copiedColor.opacity(tokens.copiedBackgroundAlpha))
            : (tokens.copyBackgroundColor ?? normalColor.opacity(tokens.copyBackgroundAlpha))
        let title = copied ? (tokens.copiedLabel ?? strings.copied) : (tokens.copyLabel ?? strings.copy)
        return Button(action: copyCode) {
            Label(title, systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(tokens.copyFont ?? .caption.weight(.medium))
                .foregroundStyle(foreground)
                .padding(tokens.copyPadding)
                .background(background, in: RoundedRectangle(cornerRadius: tokens.copyCornerRadius))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func copyCode() {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(code, forType: .string) else { return }
        #else
        return
        #endif
        onCopy?(code, language)
        copied = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, styleSheet.designTokens.code.copyFeedbackSeconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
