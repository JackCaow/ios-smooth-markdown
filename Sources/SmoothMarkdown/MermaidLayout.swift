import CoreGraphics
import Foundation

struct MermaidPlacedEdge {
    let edge: MermaidEdge
    let start: CGPoint
    let end: CGPoint
}

struct MermaidLayoutResult {
    let size: CGSize
    let nodes: [String: CGRect]
    let edges: [MermaidPlacedEdge]
}

/// Deterministic layered placement for the native Mermaid subset.
enum MermaidLayout {
    static func compute(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        switch diagram.kind {
        case .flowchart: flowchart(diagram)
        case .sequence: sequence(diagram)
        }
    }

    private static func flowchart(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        guard !diagram.nodes.isEmpty else { return .init(size: .zero, nodes: [:], edges: []) }
        let ids = Set(diagram.nodes.map(\.id))
        var outgoing = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, [String]()) })
        var indegree = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, 0) })
        for edge in diagram.edges where edge.from != edge.to && ids.contains(edge.from) && ids.contains(edge.to) {
            outgoing[edge.from, default: []].append(edge.to)
            indegree[edge.to, default: 0] += 1
        }
        var rank = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, 0) })
        var queue = diagram.nodes.filter { indegree[$0.id] == 0 }.map(\.id)
        var cursor = 0
        while cursor < queue.count {
            let from = queue[cursor]
            cursor += 1
            for to in outgoing[from] ?? [] {
                rank[to] = max(rank[to] ?? 0, (rank[from] ?? 0) + 1)
                indegree[to, default: 0] -= 1
                if indegree[to] == 0 { queue.append(to) }
            }
        }
        // Nodes left in a cycle retain their initial layer, so layout terminates.
        let grouped = Dictionary(grouping: diagram.nodes) { rank[$0.id] ?? 0 }
        let layers = grouped.keys.sorted().compactMap { grouped[$0] }
        let horizontal = diagram.direction == .leftToRight || diagram.direction == .rightToLeft
        let margin: CGFloat = 24, mainGap: CGFloat = 64, crossGap: CGFloat = 36
        // In a horizontal graph the main axis uses node width, and the cross axis uses height.
        func axisSize(_ node: MermaidNode) -> CGFloat { horizontal ? nodeWidth(node) : nodeHeight(node) }
        func laneSize(_ node: MermaidNode) -> CGFloat { horizontal ? nodeHeight(node) : nodeWidth(node) }
        let layerMain = layers.map { $0.map(axisSize).max() ?? 0 }
        let layerCross = layers.map { layer in
            layer.reduce(CGFloat(0)) { $0 + laneSize($1) } + CGFloat(max(0, layer.count - 1)) * crossGap
        }
        let crossExtent = layerCross.max() ?? 0
        let mainExtent = layerMain.reduce(0, +) + CGFloat(max(0, layers.count - 1)) * mainGap
        let size = horizontal
            ? CGSize(width: mainExtent + margin * 2, height: crossExtent + margin * 2)
            : CGSize(width: crossExtent + margin * 2, height: mainExtent + margin * 2)
        var positions: [String: CGRect] = [:]
        var main = margin
        for (layerIndex, layer) in layers.enumerated() {
            var cross = margin + (crossExtent - layerCross[layerIndex]) / 2
            for node in layer {
                let width = nodeWidth(node), height = nodeHeight(node)
                let frame = horizontal
                    ? CGRect(x: main + (layerMain[layerIndex] - width) / 2, y: cross, width: width, height: height)
                    : CGRect(x: cross, y: main + (layerMain[layerIndex] - height) / 2, width: width, height: height)
                positions[node.id] = frame
                cross += laneSize(node) + crossGap
            }
            main += layerMain[layerIndex] + mainGap
        }
        if diagram.direction == .rightToLeft || diagram.direction == .bottomToTop {
            positions = positions.mapValues { frame in
                horizontal
                    ? CGRect(x: size.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
                    : CGRect(x: frame.minX, y: size.height - frame.maxY, width: frame.width, height: frame.height)
            }
        }
        let placed = diagram.edges.compactMap { edge -> MermaidPlacedEdge? in
            guard let from = positions[edge.from], let to = positions[edge.to] else { return nil }
            let start: CGPoint, end: CGPoint
            switch diagram.direction {
            case .topToBottom:
                start = .init(x: from.midX, y: from.maxY); end = .init(x: to.midX, y: to.minY)
            case .bottomToTop:
                start = .init(x: from.midX, y: from.minY); end = .init(x: to.midX, y: to.maxY)
            case .leftToRight:
                start = .init(x: from.maxX, y: from.midY); end = .init(x: to.minX, y: to.midY)
            case .rightToLeft:
                start = .init(x: from.minX, y: from.midY); end = .init(x: to.maxX, y: to.midY)
            }
            return .init(edge: edge, start: start, end: end)
        }
        return .init(size: size, nodes: positions, edges: placed)
    }

    private static func sequence(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        guard !diagram.nodes.isEmpty else { return .init(size: .zero, nodes: [:], edges: []) }
        let width: CGFloat = 116, height: CGFloat = 44, gap: CGFloat = 48, margin: CGFloat = 24
        var positions: [String: CGRect] = [:]
        for (index, node) in diagram.nodes.enumerated() {
            positions[node.id] = CGRect(x: margin + CGFloat(index) * (width + gap), y: 20, width: width, height: height)
        }
        let placed = diagram.edges.enumerated().compactMap { index, edge -> MermaidPlacedEdge? in
            guard let from = positions[edge.from], let to = positions[edge.to] else { return nil }
            let y = CGFloat(110 + index * 68)
            return .init(edge: edge, start: .init(x: from.midX, y: y), end: .init(x: to.midX, y: y))
        }
        return .init(size: CGSize(width: margin * 2 + CGFloat(diagram.nodes.count) * width + CGFloat(max(0, diagram.nodes.count - 1)) * gap,
                                  height: max(150, CGFloat(110 + diagram.edges.count * 68))),
                     nodes: positions, edges: placed)
    }

    private static func nodeWidth(_ node: MermaidNode) -> CGFloat {
        let base = min(max(CGFloat(node.label.utf16.count) * 8 + 28, 88), 280)
        switch node.shape {
        case .diamond: return base + 30
        case .circle: return max(base, 80)
        default: return base
        }
    }

    private static func nodeHeight(_ node: MermaidNode) -> CGFloat {
        switch node.shape {
        case .diamond, .circle: 76
        default: 48
        }
    }
}
