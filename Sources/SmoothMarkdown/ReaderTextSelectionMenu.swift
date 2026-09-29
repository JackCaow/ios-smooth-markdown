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
    /// Applies to their UIKit text surfaces. Code, images, math, plugin views,
    /// and manual cross-block range controls keep their own menus.
    /// Return `UIMenu(children: suggestedActions)` to retain system actions.
    func readerTextSelectionMenu(_ builder: ReaderTextSelectionMenuBuilder?) -> some View {
        environment(\.readerTextSelectionMenuBuilder, builder)
    }
}
#endif
