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
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            #endif
            ScrollView(.horizontal) {
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
                HStack(spacing: 8) {
                    if options.showLanguageTag, let language, !language.isEmpty {
                        Text(language.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(styleSheet.linkColor ?? Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((styleSheet.linkColor ?? Color.accentColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer(minLength: 0)
                    if options.showCopyButton {
                        if let onSelectSurroundingContent {
                            copyButton.contextMenu {
                                Button("Select surrounding content", action: onSelectSurroundingContent)
                            }
                            .accessibilityAction(named: Text("Select surrounding content")) {
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
                .padding(.horizontal, 8)
                .padding(.top, 8)
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
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            #endif
            ScrollView(.horizontal) {
                Text(CodeSyntaxHighlighter.attributed(code, language: language,
                                                      dark: styleSheet.darkCodeHighlighting ?? (colorScheme == .dark),
                                                      enabled: options.enableSyntaxHighlighting))
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

    private var copyButton: some View {
        Button(action: copyCode) {
            Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.medium))
                .foregroundStyle(copied ? Color.green : (styleSheet.linkColor ?? Color.secondary))
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(copied ? Color.green.opacity(0.16) : (styleSheet.linkColor ?? Color.secondary).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 4))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied!" : "Copy code")
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
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
