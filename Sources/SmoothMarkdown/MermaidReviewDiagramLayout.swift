import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Native layouts for commit history and indentation trees. Both retain source order.
enum MermaidReviewDiagramLayout {
    static func textWidth(_ value: String, size: CGFloat = 13) -> CGFloat {
        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: size)
        #else
        let font = NSFont.systemFont(ofSize: size)
        #endif
        return ceil((value as NSString).size(withAttributes: [.font: font]).width)
    }

    static func gitGraph(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        let commits = diagram.gitCommits
        guard !commits.isEmpty else { return .init(size: .zero, nodes: [:], edges: []) }
        var branches: [String] = []
        for commit in commits where !branches.contains(commit.branch) { branches.append(commit.branch) }
        let branchWidth = branches.map { textWidth($0) }.max() ?? 0
        let labelSpace = max(72, branchWidth + 20)
        let idWidth = commits.map { textWidth($0.id) }.max() ?? 0
        let tagWidth = commits.compactMap { $0.tag }.map { textWidth($0) }.max() ?? 0
        let annotationWidth = max(idWidth, tagWidth)
        let step = max(104, annotationWidth + 28)
        let startOffset = max(40, step / 2 + 12)
        let vertical = diagram.direction == .topToBottom || diagram.direction == .bottomToTop
        let laneGap: CGFloat = vertical ? max(82, max(annotationWidth, branchWidth) + 44) : 82
        var frames: [String: CGRect] = [:]
        for (index, commit) in commits.enumerated() {
            let lane = branches.firstIndex(of: commit.branch)!
            frames[commit.id] = CGRect(x: labelSpace + startOffset + CGFloat(index) * step - 22,
                                      y: 56 + CGFloat(lane) * laneGap - 22, width: 44, height: 44)
        }
        var size = CGSize(width: labelSpace + startOffset + CGFloat(commits.count - 1) * step + step / 2 + 24,
                          height: 56 + CGFloat(branches.count - 1) * laneGap + (vertical ? max(64, max(annotationWidth, branchWidth) + 34) : 64))
        if vertical {
            frames = frames.mapValues { CGRect(x: $0.minY, y: $0.minX, width: $0.height, height: $0.width) }
            size = CGSize(width: size.height, height: size.width)
            if diagram.direction == .bottomToTop {
                frames = frames.mapValues { CGRect(x: $0.minX, y: size.height - $0.maxY, width: $0.width, height: $0.height) }
            }
        }
        let edges = diagram.edges.compactMap { edge -> MermaidPlacedEdge? in
            guard let from = frames[edge.from], let to = frames[edge.to] else { return nil }
            return .init(edge: edge, start: CGPoint(x: from.midX, y: from.midY),
                         end: CGPoint(x: to.midX, y: to.midY))
        }
        return .init(size: size, nodes: frames, edges: edges)
    }

    static func mindmap(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        guard !diagram.nodes.isEmpty else { return .init(size: .zero, nodes: [:], edges: []) }
        let knownIDs = Set(diagram.nodes.map(\.id))
        let validEdges = diagram.edges.filter { knownIDs.contains($0.from) && knownIDs.contains($0.to) }
        let children = Dictionary(grouping: validEdges, by: \.from).mapValues { $0.map(\.to) }
        let descendants = Set(validEdges.map(\.to))
        guard let root = diagram.nodes.first(where: { !descendants.contains($0.id) }) else {
            return .init(size: .zero, nodes: [:], edges: [])
        }
        var depths = [root.id: 0]
        var positions: [String: CGFloat] = [:]
        var queue = [root.id]
        var sizes: [String: CGSize] = [:]
        for node in diagram.nodes {
            let lines = node.label.components(separatedBy: "\n")
            let width = max(72, (lines.map { textWidth($0) }.max() ?? 0) + 28)
            let height = max(44, CGFloat(lines.count) * 17 + 20)
            sizes[node.id] = node.shape == .circle ? CGSize(width: max(width, height), height: max(width, height))
                                                  : CGSize(width: width, height: height)
        }
        var cursor = 0
        while cursor < queue.count {
            let id = queue[cursor]; cursor += 1
            for child in children[id] ?? [] where depths[child] == nil {
                depths[child] = depths[id]! + 1; queue.append(child)
            }
        }
        func treeChildren(_ id: String) -> [String] {
            (children[id] ?? []).filter { depths[$0] == (depths[id] ?? 0) + 1 }
        }
        var subtreeHeights: [String: CGFloat] = [:]
        func subtreeHeight(_ id: String) -> CGFloat {
            if let cached = subtreeHeights[id] { return cached }
            let ids = treeChildren(id)
            let childrenHeight = ids.map(subtreeHeight).reduce(0, +) + CGFloat(max(0, ids.count - 1)) * 24
            let height = max(sizes[id]!.height, childrenHeight)
            subtreeHeights[id] = height; return height
        }
        var assigned: Set<String> = []
        func assign(_ id: String, top: CGFloat) {
            guard assigned.insert(id).inserted else { return }
            let height = subtreeHeight(id)
            positions[id] = top + height / 2
            let ids = treeChildren(id)
            let childrenHeight = ids.map(subtreeHeight).reduce(0, +) + CGFloat(max(0, ids.count - 1)) * 24
            var childTop = top + (height - childrenHeight) / 2
            for child in ids {
                assign(child, top: childTop)
                childTop += subtreeHeight(child) + 24
            }
        }
        assign(root.id, top: 32)
        let maximumDepth = depths.values.max() ?? 0
        var columnStarts = [CGFloat](repeating: 32, count: maximumDepth + 1)
        for depth in 1...max(1, maximumDepth) where depth <= maximumDepth {
            let previousWidth = diagram.nodes.filter { depths[$0.id] == depth - 1 }
                .compactMap { sizes[$0.id]?.width }.max() ?? 72
            columnStarts[depth] = columnStarts[depth - 1] + previousWidth + 64
        }
        var frames: [String: CGRect] = [:]
        for node in diagram.nodes {
            guard let depth = depths[node.id], let center = positions[node.id], let size = sizes[node.id] else { continue }
            frames[node.id] = CGRect(x: columnStarts[depth], y: center - size.height / 2,
                                    width: size.width, height: size.height)
        }
        let edges = diagram.edges.compactMap { edge -> MermaidPlacedEdge? in
            guard let from = frames[edge.from], let to = frames[edge.to] else { return nil }
            let start = CGPoint(x: from.maxX, y: from.midY)
            let end = CGPoint(x: to.minX, y: to.midY)
            let middle = (start.x + end.x) / 2
            return .init(edge: edge, start: start, end: end,
                         route: [start, CGPoint(x: middle, y: start.y),
                                 CGPoint(x: middle, y: end.y), end])
        }
        return .init(size: CGSize(width: (frames.values.map(\.maxX).max() ?? 0) + 32,
                                  height: (frames.values.map(\.maxY).max() ?? 0) + 32), nodes: frames, edges: edges)
    }
}
