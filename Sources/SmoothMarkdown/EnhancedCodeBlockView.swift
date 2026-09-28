import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct EnhancedCodeBlockView: View {
    let code: String
    let language: String?
    let options: CodeBlockOptions
    let onCopy: ((String, String?) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if (options.showLanguageTag && !(language?.isEmpty ?? true)) || options.showCopyButton {
                HStack(spacing: 8) {
                    if options.showLanguageTag, let language, !language.isEmpty {
                        Text(language.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer(minLength: 0)
                    if options.showCopyButton {
                        Button(action: copyCode) {
                            Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(copied ? Color.green : Color.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(copied ? Color.green.opacity(0.16) : Color.secondary.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(copied ? "Copied!" : "Copy code")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            ScrollView(.horizontal) {
                Text(CodeSyntaxHighlighter.attributed(code, language: language,
                                                      dark: colorScheme == .dark,
                                                      enabled: options.enableSyntaxHighlighting))
                    .font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .onDisappear { resetTask?.cancel() }
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
