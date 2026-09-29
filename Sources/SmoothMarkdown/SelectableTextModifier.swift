import SwiftUI

/// SwiftUI's enabled and disabled text-selection values have distinct types.
/// Branch in a view builder instead of selecting between them with a ternary.
internal struct SelectableTextModifier: ViewModifier {
    let selectable: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if selectable {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

internal extension View {
    func markdownTextSelection(_ selectable: Bool) -> some View {
        modifier(SelectableTextModifier(selectable: selectable))
    }
}
