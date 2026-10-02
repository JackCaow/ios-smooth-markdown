import SwiftUI

extension MermaidDiagramView {
    func drawGitGraph(in context: GraphicsContext, diagram: MermaidDiagram,
                      layout: MermaidLayoutResult, ink: Color) {
        let commits = diagram.gitCommits
        let vertical = diagram.direction == .topToBottom || diagram.direction == .bottomToTop
        var branches: [String] = []
        for commit in commits where !branches.contains(commit.branch) { branches.append(commit.branch) }
        for branch in branches {
            guard let commit = commits.first(where: { $0.branch == branch }), let frame = layout.nodes[commit.id] else { continue }
            var lane = Path()
            lane.move(to: vertical ? CGPoint(x: frame.midX, y: 16) : CGPoint(x: 16, y: frame.midY))
            lane.addLine(to: vertical ? CGPoint(x: frame.midX, y: layout.size.height - 16)
                                      : CGPoint(x: layout.size.width - 16, y: frame.midY))
            context.stroke(lane, with: .color(resolvedPalette.edgeColor.opacity(0.25)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            let label = Text(branch).font(resolvedTokens.font ?? .system(size: 13, weight: .semibold)).foregroundColor(ink)
            context.draw(label, at: vertical ? CGPoint(x: frame.midX + 12, y: 16)
                                                : CGPoint(x: 16, y: frame.midY - 20), anchor: .leading)
        }
        for edge in layout.edges {
            var path = Path(); path.move(to: edge.start)
            if resolvedTokens.edgeRouting == .straight {
                path.addLine(to: edge.end)
            } else if vertical {
                let midY = (edge.start.y + edge.end.y) / 2
                path.addCurve(to: edge.end, control1: CGPoint(x: edge.start.x, y: midY),
                              control2: CGPoint(x: edge.end.x, y: midY))
            } else {
                let midX = (edge.start.x + edge.end.x) / 2
                path.addCurve(to: edge.end, control1: CGPoint(x: midX, y: edge.start.y),
                              control2: CGPoint(x: midX, y: edge.end.y))
            }
            context.stroke(path, with: .color(resolvedPalette.edgeColor), lineWidth: resolvedTokens.strokeWidth)
        }
        for commit in commits {
            guard let frame = layout.nodes[commit.id] else { continue }
            let circle = CGRect(x: frame.midX - 8, y: frame.midY - 8, width: 16, height: 16)
            let path = commit.type == .highlight ? Path(roundedRect: circle, cornerRadius: 3) : Path(ellipseIn: circle)
            context.fill(path, with: .color(resolvedPalette.nodeFillColor))
            context.stroke(path, with: .color(resolvedPalette.nodeStrokeColor), lineWidth: resolvedTokens.strokeWidth)
            if commit.type == .reverse {
                var cross = Path(); cross.move(to: CGPoint(x: circle.minX + 4, y: circle.minY + 4))
                cross.addLine(to: CGPoint(x: circle.maxX - 4, y: circle.maxY - 4))
                cross.move(to: CGPoint(x: circle.maxX - 4, y: circle.minY + 4))
                cross.addLine(to: CGPoint(x: circle.minX + 4, y: circle.maxY - 4))
                context.stroke(cross, with: .color(ink), lineWidth: resolvedTokens.strokeWidth)
            }
            context.draw(Text(commit.id).font(resolvedTokens.font ?? .system(size: 12)).foregroundColor(ink),
                         at: vertical ? CGPoint(x: frame.maxX + 4, y: frame.midY) : CGPoint(x: frame.midX, y: frame.midY + 25),
                         anchor: vertical ? .leading : .center)
            if let tag = commit.tag {
                context.draw(Text(tag).font(resolvedTokens.font ?? .system(size: 11, weight: .medium)).foregroundColor(ink),
                             at: vertical ? CGPoint(x: frame.maxX + 4, y: frame.midY + 18) : CGPoint(x: frame.midX, y: frame.midY - 25),
                             anchor: vertical ? .leading : .center)
            }
        }
    }

    func drawMindmap(in context: GraphicsContext, diagram: MermaidDiagram,
                     layout: MermaidLayoutResult, ink: Color) {
        for edge in layout.edges {
            let rendered = resolvedTokens.edgeRouting == .straight
                ? MermaidPlacedEdge(edge: edge.edge, start: edge.start, end: edge.end) : edge
            drawEdge(rendered, in: context, ink: resolvedPalette.edgeColor, background: resolvedPalette.backgroundColor)
        }
        for node in diagram.nodes {
            guard let frame = layout.nodes[node.id] else { continue }
            let path = nodePath(node.shape, frame: frame)
            context.fill(path, with: .color(resolvedPalette.nodeFillColor))
            context.stroke(path, with: .color(resolvedPalette.nodeStrokeColor), lineWidth: resolvedTokens.strokeWidth)
            context.draw(Text(node.label).font(resolvedTokens.font ?? .system(size: 13, weight: .medium)).foregroundColor(ink),
                         at: CGPoint(x: frame.midX, y: frame.midY))
        }
    }
}
