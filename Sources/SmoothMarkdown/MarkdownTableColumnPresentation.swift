import Markdown
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The delimiter row is the source of truth for both reader and formatted editor cells.
enum MarkdownTableColumnPresentation: Equatable {
    case left, center, right

    init(_ alignment: Markdown.Table.ColumnAlignment?) {
        switch alignment {
        case .center: self = .center
        case .right: self = .right
        case .left, nil: self = .left
        }
    }

    init(_ alignment: MarkdownTableAlignment?) {
        switch alignment {
        case .center: self = .center
        case .right: self = .right
        case .left, nil: self = .left
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }

    #if os(iOS)
    var fieldTextAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
    #endif
}

private struct MarkdownTableViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Keeps every column equally wide within the reader viewport. A table with
/// more columns than can accommodate its cell padding still scrolls horizontally.
struct MarkdownTableViewport<Content: View>: View {
    let columnCount: Int
    let padding: CGFloat
    let content: (CGFloat) -> Content
    @State private var viewportWidth: CGFloat = 0

    static func columnWidth(viewportWidth: CGFloat, columnCount: Int, padding: CGFloat) -> CGFloat {
        let minimum = max(1, padding * 2 + 1)
        guard viewportWidth.isFinite, viewportWidth > 0 else { return 150 + padding * 2 }
        return max(minimum, viewportWidth / CGFloat(max(1, columnCount)))
    }

    var body: some View {
        content(Self.columnWidth(viewportWidth: viewportWidth, columnCount: columnCount, padding: padding))
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: MarkdownTableViewportWidthKey.self, value: geometry.size.width)
                }
            }
            .onPreferenceChange(MarkdownTableViewportWidthKey.self) { viewportWidth = $0 }
    }
}
