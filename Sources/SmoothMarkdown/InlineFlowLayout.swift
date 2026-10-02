import SwiftUI

struct InlineBreakKey: LayoutValueKey {
    static let defaultValue = false
}

struct InlineImageKey: LayoutValueKey {
    static let defaultValue = false
}

struct InlineMathKey: LayoutValueKey {
    static let defaultValue = false
}

struct InlineBlockKey: LayoutValueKey {
    static let defaultValue = false
}

/// Places text fragments and image views on the same line, wrapping at words.
struct InlineFlowLayout: Layout {
    private struct Arrangement {
        let positions: [CGPoint]
        let sizes: [CGSize]
        let size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 400).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + arrangement.positions[index].x,
                                      y: bounds.minY + arrangement.positions[index].y),
                          proposal: subview[InlineImageKey.self] || subview[InlineMathKey.self] || subview[InlineBlockKey.self]
                              ? ProposedViewSize(arrangement.sizes[index]) : .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> Arrangement {
        let available = max(width, 1)
        var positions = Array(repeating: CGPoint.zero, count: subviews.count)
        var sizes = Array(repeating: CGSize.zero, count: subviews.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            if subview[InlineBlockKey.self] {
                if x > 0 { y += lineHeight; x = 0; lineHeight = 0 }
                let size = subview.sizeThatFits(ProposedViewSize(width: available, height: nil))
                positions[index] = CGPoint(x: 0, y: y)
                sizes[index] = size
                y += size.height
                usedWidth = max(usedWidth, min(size.width, available))
                continue
            }
            if subview[InlineBreakKey.self] {
                y += max(lineHeight, 20)
                x = 0
                lineHeight = 0
                continue
            }
            let constrained = subview[InlineImageKey.self] || subview[InlineMathKey.self]
            var size = subview.sizeThatFits(constrained
                                            ? ProposedViewSize(width: max(1, available - x), height: nil) : .unspecified)
            if x > 0 && x + size.width > available {
                y += max(lineHeight, 20)
                x = 0
                lineHeight = 0
                if constrained { size = subview.sizeThatFits(ProposedViewSize(width: available, height: nil)) }
            }
            positions[index] = CGPoint(x: x, y: y)
            sizes[index] = size
            x += size.width
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, min(x, available))
        }
        return Arrangement(positions: positions, sizes: sizes,
                           size: CGSize(width: usedWidth, height: y + max(lineHeight, 1)))
    }
}
