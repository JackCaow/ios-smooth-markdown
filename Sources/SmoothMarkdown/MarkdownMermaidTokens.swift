import SwiftUI

/// How graph edges travel between their node attachment ports.
public enum MermaidEdgeRouting: Equatable {
    case straight, rounded, curved
}

/// Mermaid palette, label font and fence viewport. Custom colors override named fence themes;
/// nil font/colors preserve platform defaults. Graph layout and specialty status/series palettes
/// remain diagram-specific. Standalone views retain their caller's viewport modifiers.
public struct MarkdownMermaidTokens {
    public var colors: MermaidPalette?
    public var font: Font?
    public var outerPadding: EdgeInsets
    public var maxHeight: CGFloat
    public var edgeRouting: MermaidEdgeRouting = .rounded
    /// Radius for edge bends, measured in the diagram's unscaled coordinates.
    public var cornerRadius: CGFloat = 12
    public var strokeWidth: CGFloat = 1.5
    public var arrowSize: CGFloat = 10
    public var labelPadding: CGFloat = 4

    public init(colors: MermaidPalette? = nil, font: Font? = nil,
                outerPadding: EdgeInsets = EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0),
                maxHeight: CGFloat = 420) {
        self.colors = colors
        self.font = font
        self.outerPadding = outerPadding
        self.maxHeight = maxHeight.isFinite ? max(1, maxHeight) : 420
        self = normalized()
    }
}
