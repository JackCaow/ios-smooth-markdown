#if os(iOS)
import SwiftUI
import UIKit

/// Builds the native menu for a selected range in a reader text view.
/// `suggestedActions` contains UIKit's standard actions for the range.
public typealias ReaderTextSelectionMenuBuilder = (_ selectedText: String,
                                                    _ suggestedActions: [UIMenuElement]) -> UIMenu?

private struct ReaderTextSelectionMenuKey: EnvironmentKey {
    static let defaultValue: ReaderTextSelectionMenuBuilder? = nil
}

extension EnvironmentValues {
    var readerTextSelectionMenuBuilder: ReaderTextSelectionMenuBuilder? {
        get { self[ReaderTextSelectionMenuKey.self] }
        set { self[ReaderTextSelectionMenuKey.self] = newValue }
    }
}

public extension View {
    /// Customizes native selection menus in SmoothMarkdownView and StreamMarkdownView.
    /// Native text ranges, including ranges across hosted code, image, and math
    /// blocks, receive their exact semantic Copy text. Separate block controls
    /// expose an Actions button for the complete block or manual range.
    /// Return `UIMenu(children: suggestedActions)` to retain system actions.
    func readerTextSelectionMenu(_ builder: ReaderTextSelectionMenuBuilder?) -> some View {
        environment(\.readerTextSelectionMenuBuilder, builder)
    }
}

/// The bundled block plugins expose their parsed body as the block-level Copy value.
/// Custom plugin views can draw unrelated text, so their copy value is left to
/// their own controls rather than inferred from parser input.
enum ReaderPluginSelectionText {
    static func copyText(pluginID: String, content: String) -> String? {
        guard ["thinking", "artifact", "tool_call", "admonition", "mermaid"].contains(pluginID),
              !content.isEmpty else { return nil }
        return content
    }
}

/// An Actions control for blocks and manual ranges without a UIKit text menu.
/// Its suggested Copy action uses the same text supplied to the host builder.
@available(iOS 17.0, *)
struct ReaderSelectionActionsButton: UIViewRepresentable {
    @Environment(\.markdownStrings) private var strings
    let selectedText: String
    let builder: ReaderTextSelectionMenuBuilder
    let copy: () -> Void
    let accessibilityIdentifier: String

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .bordered()
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.configuration?.title = strings.actions
        button.accessibilityIdentifier = accessibilityIdentifier
        button.accessibilityLabel = strings.selectionActions
        button.menu = Self.menu(selectedText: selectedText, builder: builder, copy: copy, copyLabel: strings.copy)
        button.showsMenuAsPrimaryAction = true
        button.isEnabled = !selectedText.isEmpty
    }

    static func menu(selectedText: String, builder: ReaderTextSelectionMenuBuilder,
                     copy: @escaping () -> Void, copyLabel: String = "Copy") -> UIMenu {
        let suggestedCopy = UIAction(title: copyLabel, image: UIImage(systemName: "doc.on.doc")) { _ in copy() }
        return builder(selectedText, [suggestedCopy]) ?? UIMenu(children: [suggestedCopy])
    }
}
#endif
