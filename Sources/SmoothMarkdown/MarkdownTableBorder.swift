import SwiftUI

/// A visible side of a Markdown table border. A nil side draws no line.
public struct MarkdownTableBorderSide {
    public var color: Color
    public var width: CGFloat

    public init(color: Color, width: CGFloat = 1) {
        self.color = color
        self.width = max(0, width)
    }
}

/// Outer and inner rules corresponding to Flutter's `TableBorder` sides.
public struct MarkdownTableBorder {
    public var top: MarkdownTableBorderSide?
    public var right: MarkdownTableBorderSide?
    public var bottom: MarkdownTableBorderSide?
    public var left: MarkdownTableBorderSide?
    public var horizontalInside: MarkdownTableBorderSide?
    public var verticalInside: MarkdownTableBorderSide?

    public init(top: MarkdownTableBorderSide? = nil, right: MarkdownTableBorderSide? = nil,
                bottom: MarkdownTableBorderSide? = nil, left: MarkdownTableBorderSide? = nil,
                horizontalInside: MarkdownTableBorderSide? = nil,
                verticalInside: MarkdownTableBorderSide? = nil) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
        self.horizontalInside = horizontalInside
        self.verticalInside = verticalInside
    }

    public static func all(color: Color, width: CGFloat = 1) -> Self {
        let side = MarkdownTableBorderSide(color: color, width: width)
        return Self(top: side, right: side, bottom: side, left: side,
                    horizontalInside: side, verticalInside: side)
    }
}

/// One rule is emitted for each shared edge, so adjacent cells cannot double its width.
internal enum MarkdownTableGridLayout {
    struct Segment {
        let start: CGPoint
        let end: CGPoint
        let side: MarkdownTableBorderSide
    }

    static func segments(border: MarkdownTableBorder?, rowIndex: Int, rowCount: Int,
                         columnCount: Int, columnWidth: CGFloat, rowHeight: CGFloat) -> [Segment] {
        guard let border, rowIndex >= 0, rowIndex < rowCount,
              rowCount > 0, columnCount > 0, columnWidth > 0, rowHeight > 0 else { return [] }
        let tableWidth = CGFloat(columnCount) * columnWidth
        var result: [Segment] = []

        func add(_ side: MarkdownTableBorderSide?, _ start: CGPoint, _ end: CGPoint) {
            guard let side, side.width > 0 else { return }
            result.append(Segment(start: start, end: end, side: side))
        }

        if rowIndex == 0 {
            let inset = (border.top?.width ?? 0) / 2
            add(border.top, CGPoint(x: 0, y: inset), CGPoint(x: tableWidth, y: inset))
        } else {
            let inset = (border.horizontalInside?.width ?? 0) / 2
            add(border.horizontalInside, CGPoint(x: 0, y: inset), CGPoint(x: tableWidth, y: inset))
        }
        if rowIndex == rowCount - 1 {
            let inset = (border.bottom?.width ?? 0) / 2
            add(border.bottom, CGPoint(x: 0, y: rowHeight - inset),
                CGPoint(x: tableWidth, y: rowHeight - inset))
        }
        let leftInset = (border.left?.width ?? 0) / 2
        add(border.left, CGPoint(x: leftInset, y: 0), CGPoint(x: leftInset, y: rowHeight))
        let rightInset = (border.right?.width ?? 0) / 2
        add(border.right, CGPoint(x: tableWidth - rightInset, y: 0),
            CGPoint(x: tableWidth - rightInset, y: rowHeight))
        if columnCount > 1 {
            for column in 1..<columnCount {
                let x = CGFloat(column) * columnWidth
                add(border.verticalInside, CGPoint(x: x, y: 0), CGPoint(x: x, y: rowHeight))
            }
        }
        return result
    }
}
