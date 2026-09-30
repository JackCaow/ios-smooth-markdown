import CoreGraphics

/// Fit and hit-test geometry shared by the native Mermaid viewport.
enum MermaidInteractiveViewportGeometry {
    static func fittedScale(content: CGSize, viewport: CGSize, minScale: CGFloat = 0.5,
                            maxScale: CGFloat = 3, padding: CGFloat = 40) -> CGFloat {
        guard content.width > 0, content.height > 0,
              viewport.width > 0, viewport.height > 0,
              content.width.isFinite, content.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite else { return 1 }
        let lower = max(0.01, minScale)
        let upper = max(lower, maxScale)
        let availableWidth = max(1, viewport.width - padding * 2)
        let availableHeight = max(1, viewport.height - padding * 2)
        let fit = min(1, availableWidth / content.width, availableHeight / content.height)
        return min(upper, max(lower, fit))
    }

    static func centeredInset(content: CGSize, viewport: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(0, (viewport.width - content.width * scale) / 2),
               height: max(0, (viewport.height - content.height * scale) / 2))
    }

    static func nodeID(at point: CGPoint, layout: MermaidLayoutResult,
                       diagram: MermaidDiagram, contentScale: CGFloat) -> String? {
        guard contentScale > 0 else { return nil }
        let unscaled = CGPoint(x: point.x / contentScale, y: point.y / contentScale)
        return diagram.nodes.first { node in layout.nodes[node.id]?.contains(unscaled) == true }?.id
    }
}
