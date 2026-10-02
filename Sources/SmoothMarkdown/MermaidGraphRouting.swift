import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Routes graph edges after placement, then bounds the canvas by actual ink.
/// Specialty plots retain their own axes; this is only graph-node geometry.
enum MermaidGraphRouting {
    private struct PortKey: Hashable { let node: String; let side: Side }
    private struct Endpoint: Equatable { let edge: Int; let start: Bool }
    private enum Side: Hashable { case left, right, top, bottom }

    static func layout(diagram: MermaidDiagram, nodes: [String: CGRect], groups: [String: CGRect],
                       edges: [MermaidPlacedEdge], style: MarkdownMermaidTokens) -> MermaidLayoutResult {
        let shapes = diagram.nodes.reduce(into: [String: MermaidShape]()) { $0[$1.id] = $1.shape }
        let allFrames = Array(nodes.values) + Array(groups.values)
        var ports: [PortKey: [Endpoint]] = [:]
        func sides(_ from: CGRect, _ to: CGRect) -> (Side, Side) {
            let dx = to.midX - from.midX, dy = to.midY - from.midY
            if abs(dx) > abs(dy) { return dx >= 0 ? (.right, .left) : (.left, .right) }
            return dy >= 0 ? (.bottom, .top) : (.top, .bottom)
        }
        for (index, edge) in edges.enumerated() where edge.selfLoop == nil {
            guard let from = nodes[edge.edge.from] ?? groups[edge.edge.from],
                  let to = nodes[edge.edge.to] ?? groups[edge.edge.to] else { continue }
            let (source, target) = sides(from, to)
            ports[.init(node: edge.edge.from, side: source), default: []].append(.init(edge: index, start: true))
            ports[.init(node: edge.edge.to, side: target), default: []].append(.init(edge: index, start: false))
        }
        func fraction(node: String, side: Side, edge: Int, start: Bool) -> CGFloat {
            let requests = ports[.init(node: node, side: side)] ?? []
            guard requests.count > 1, let ordinal = requests.firstIndex(of: .init(edge: edge, start: start)) else { return 0 }
            return (CGFloat(ordinal) / CGFloat(requests.count - 1) - 0.5) * 1.1
        }
        var labels: [CGRect] = []
        let routed = edges.enumerated().map { index, placed -> MermaidPlacedEdge in
            if let loop = placed.selfLoop {
                if let frame = loop.labelFrame { labels.append(frame) }
                return placed
            }
            guard let from = nodes[placed.edge.from] ?? groups[placed.edge.from],
                  let to = nodes[placed.edge.to] ?? groups[placed.edge.to] else { return placed }
            let (side, other) = sides(from, to)
            let horizontal = side == .left || side == .right
            // Incoming and outgoing endpoints share a side's allocation. This
            // separates reverse transitions even when another edge also merges.
            let start = port(from, shape: shapes[placed.edge.from] ?? .rectangle, side: side,
                             fraction: fraction(node: placed.edge.from, side: side, edge: index, start: true))
            let end = port(to, shape: shapes[placed.edge.to] ?? .rectangle, side: other,
                           fraction: fraction(node: placed.edge.to, side: other, edge: index, start: false))
            let gap: CGFloat = max(18, style.arrowSize + style.cornerRadius)
            let outward = vector(side, distance: gap)
            let inward = vector(other, distance: gap)
            let a = CGPoint(x: start.x + outward.x, y: start.y + outward.y)
            let b = CGPoint(x: end.x + inward.x, y: end.y + inward.y)
            var points: [CGPoint]
            if horizontal {
                let middle = (a.x + b.x) / 2
                points = [start, a, .init(x: middle, y: a.y), .init(x: middle, y: b.y), b, end]
            } else {
                let middle = (a.y + b.y) / 2
                points = [start, a, .init(x: a.x, y: middle), .init(x: b.x, y: middle), b, end]
            }
            let obstacles = nodes.filter { $0.key != placed.edge.from && $0.key != placed.edge.to }.map(\.value)
            if intersects(points, obstacles: obstacles) {
                // A backward/skip-layer edge can pass through intermediate nodes.
                // Use a clear outside lane instead of painting through their labels.
                if horizontal {
                    let y = (allFrames.map(\.maxY).max() ?? 0) + gap + CGFloat(index % 4) * 12
                    points = [start, a, .init(x: a.x, y: y), .init(x: b.x, y: y), b, end]
                } else {
                    let x = (allFrames.map(\.maxX).max() ?? 0) + gap + CGFloat(index % 4) * 12
                    points = [start, a, .init(x: x, y: a.y), .init(x: x, y: b.y), b, end]
                }
            }
            if style.edgeRouting == .straight { points = [start, end] }
            points = compact(points)
            let label = placed.edge.label.flatMap { text -> CGRect? in
                guard !text.isEmpty else { return nil }
                return labelFrame(text, route: points, padding: style.labelPadding,
                                  obstacles: allFrames + labels)
            }
            if let label { labels.append(label) }
            func endpointLabel(_ text: String?, route: [CGPoint]) -> CGRect? {
                guard let text, !text.isEmpty else { return nil }
                let frame = labelFrame(text, route: route, padding: style.labelPadding, obstacles: allFrames + labels)
                labels.append(frame)
                return frame
            }
            let sourceLabel = endpointLabel(placed.edge.sourceLabel, route: Array(points.prefix(2)))
            let targetLabel = endpointLabel(placed.edge.targetLabel, route: Array(points.suffix(2)))
            return .init(edge: placed.edge, start: start, end: end, route: points, labelFrame: label,
                         sourceLabelFrame: sourceLabel, targetLabelFrame: targetLabel)
        }
        return bounded(nodes: nodes, groups: groups, edges: routed)
    }

    private static func port(_ frame: CGRect, shape: MermaidShape, side: Side, fraction: CGFloat) -> CGPoint {
        let ellipse = shape == .circle || shape == .stateStart || shape == .stateEnd
        let extent: CGFloat = shape == .diamond ? 1 - abs(fraction) : ellipse ? sqrt(max(0, 1 - fraction * fraction)) : 1
        switch side {
        case .left: return .init(x: frame.midX - frame.width * extent / 2, y: frame.midY + frame.height * fraction / 2)
        case .right: return .init(x: frame.midX + frame.width * extent / 2, y: frame.midY + frame.height * fraction / 2)
        case .top: return .init(x: frame.midX + frame.width * fraction / 2, y: frame.midY - frame.height * extent / 2)
        case .bottom: return .init(x: frame.midX + frame.width * fraction / 2, y: frame.midY + frame.height * extent / 2)
        }
    }

    private static func vector(_ side: Side, distance: CGFloat) -> CGPoint {
        switch side {
        case .left: return .init(x: -distance, y: 0)
        case .right: return .init(x: distance, y: 0)
        case .top: return .init(x: 0, y: -distance)
        case .bottom: return .init(x: 0, y: distance)
        }
    }

    private static func compact(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points where result.last != point { result.append(point) }
        return result
    }

    private static func intersects(_ points: [CGPoint], obstacles: [CGRect]) -> Bool {
        for (a, b) in zip(points, points.dropFirst()) {
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                              width: max(abs(a.x - b.x), 1), height: max(abs(a.y - b.y), 1))
            if obstacles.contains(where: { $0.insetBy(dx: -5, dy: -5).intersects(rect) }) { return true }
        }
        return false
    }

    private static func labelFrame(_ text: String, route: [CGPoint], padding: CGFloat, obstacles: [CGRect]) -> CGRect {
        // Match the default Canvas label font, including multiline/CJK metrics.
        // A custom SwiftUI Font cannot be resolved to platform metrics here.
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: 11)
        #elseif canImport(AppKit)
        let font = NSFont.systemFont(ofSize: 11)
        #endif
        let measured = (text as NSString).boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        let width = ceil(measured.width) + padding * 2
        let height = ceil(measured.height) + padding * 2
        let segments = zip(route, route.dropFirst()).sorted { hypot($0.1.x - $0.0.x, $0.1.y - $0.0.y) > hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        var fallback = CGRect.zero
        for (a, b) in segments {
            let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            // Short endpoint legs may have nodes above and below and another
            // relationship label in between. Search both axes to keep labels
            // beside their endpoint rather than falling back inside a node.
            for horizontal: CGFloat in [0, -width, width, -width * 2, width * 2] {
                for vertical: CGFloat in [0, -height, height, -height * 2, height * 2] {
                    let frame = CGRect(x: middle.x - width / 2 + horizontal,
                        y: middle.y - height / 2 + vertical, width: width, height: height)
                    fallback = frame
                    if !obstacles.contains(where: { $0.insetBy(dx: -3, dy: -3).intersects(frame) }) { return frame }
                }
            }
        }
        return fallback
    }

    private static func bounded(nodes: [String: CGRect], groups: [String: CGRect], edges: [MermaidPlacedEdge]) -> MermaidLayoutResult {
        var bounds = (Array(nodes.values) + Array(groups.values)).reduce(CGRect.null) { $0.union($1) }
        for edge in edges {
            for point in edge.route { bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 1, height: 1)) }
            for label in [edge.labelFrame, edge.sourceLabelFrame, edge.targetLabelFrame].compactMap({ $0 }) { bounds = bounds.union(label) }
            if let loop = edge.selfLoop {
                for point in [loop.control1, loop.control2] { bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 1, height: 1)) }
                if let label = loop.labelFrame { bounds = bounds.union(label) }
            }
        }
        guard !bounds.isNull else { return .init(size: .zero, nodes: nodes, edges: edges, subgraphs: groups) }
        let padding: CGFloat = 24
        let shift = CGPoint(x: padding - bounds.minX, y: padding - bounds.minY)
        func moved(_ point: CGPoint) -> CGPoint { .init(x: point.x + shift.x, y: point.y + shift.y) }
        let shifted = edges.map { edge -> MermaidPlacedEdge in
            let loop = edge.selfLoop.map { MermaidPlacedSelfLoop(control1: moved($0.control1), control2: moved($0.control2),
                labelFrame: $0.labelFrame?.offsetBy(dx: shift.x, dy: shift.y)) }
            return .init(edge: edge.edge, start: moved(edge.start), end: moved(edge.end), selfLoop: loop,
                         route: edge.route.map(moved), labelFrame: edge.labelFrame?.offsetBy(dx: shift.x, dy: shift.y),
                         sourceLabelFrame: edge.sourceLabelFrame?.offsetBy(dx: shift.x, dy: shift.y),
                         targetLabelFrame: edge.targetLabelFrame?.offsetBy(dx: shift.x, dy: shift.y))
        }
        return .init(size: CGSize(width: bounds.width + padding * 2, height: bounds.height + padding * 2),
                     nodes: nodes.mapValues { $0.offsetBy(dx: shift.x, dy: shift.y) }, edges: shifted,
                     subgraphs: groups.mapValues { $0.offsetBy(dx: shift.x, dy: shift.y) })
    }
}
