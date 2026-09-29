import CoreGraphics
import Foundation

struct MermaidPlacedEdge {
    let edge: MermaidEdge
    let start: CGPoint
    let end: CGPoint
    let selfLoop: MermaidPlacedSelfLoop?

    init(edge: MermaidEdge, start: CGPoint, end: CGPoint, selfLoop: MermaidPlacedSelfLoop? = nil) {
        self.edge = edge; self.start = start; self.end = end; self.selfLoop = selfLoop
    }
}

struct MermaidPlacedSelfLoop {
    let control1: CGPoint
    let control2: CGPoint
    let labelFrame: CGRect?
}

struct MermaidLayoutResult {
    let size: CGSize
    let nodes: [String: CGRect]
    let edges: [MermaidPlacedEdge]
    let subgraphs: [String: CGRect]

    init(size: CGSize, nodes: [String: CGRect], edges: [MermaidPlacedEdge],
         subgraphs: [String: CGRect] = [:]) {
        self.size = size; self.nodes = nodes; self.edges = edges; self.subgraphs = subgraphs
    }
}

/// Deterministic layered placement for the native Mermaid subset.
enum MermaidLayout {
    static func compute(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        switch diagram.kind {
        case .flowchart, .classDiagram, .stateDiagram, .erDiagram: flowchart(diagram)
        case .sequence: sequence(diagram)
        case .pie: pie(diagram)
        case .timeline: timeline(diagram)
        case .gantt: gantt(diagram)
        case .kanban: kanban(diagram)
        case .radar: radar(diagram)
        case .xyChart: xyChart(diagram)
        }
    }

    private static func pie(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        let legendHeight = CGFloat(diagram.pieSlices.count) * 24
        return .init(size: CGSize(width: 440, height: max(270, 90 + legendHeight)), nodes: [:], edges: [])
    }

    private static func timeline(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        let count = diagram.timelineSections.count
        let eventRows = diagram.timelineSections.map { $0.events.count }.max() ?? 0
        return .init(size: CGSize(width: max(320, CGFloat(count) * 180 + 64),
                                  height: CGFloat(200 + eventRows * 30)), nodes: [:], edges: [])
    }

    private static func gantt(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        guard let first = diagram.ganttTasks.map(\.startDate).min(),
              let last = diagram.ganttTasks.map(\.endDate).max() else { return .init(size: .zero, nodes: [:], edges: []) }
        let days = max(1, Calendar(identifier: .gregorian).dateComponents([.day], from: first, to: last).day ?? 0)
        return .init(size: CGSize(width: max(460, CGFloat(days + 1) * 12 + 210),
                                  height: CGFloat(100 + diagram.ganttTasks.count * 48)), nodes: [:], edges: [])
    }

    static func ganttBars(_ diagram: MermaidDiagram) -> [CGRect] {
        guard let first = diagram.ganttTasks.map(\.startDate).min() else { return [] }
        let calendar = Calendar(identifier: .gregorian)
        return diagram.ganttTasks.enumerated().map { index, task in
            let offset = max(0, calendar.dateComponents([.day], from: first, to: task.startDate).day ?? 0)
            let duration = max(1, (calendar.dateComponents([.day], from: task.startDate, to: task.endDate).day ?? 0) + 1)
            return CGRect(x: 180 + CGFloat(offset) * 12, y: 82 + CGFloat(index) * 48,
                          width: task.status == .milestone ? 12 : CGFloat(duration) * 12, height: 22)
        }
    }

    /// Position of the current-day indicator on the same date scale as the task bars.
    static func ganttTodayMarkerX(_ diagram: MermaidDiagram, today: Date,
                                  timeZone: TimeZone = .current) -> CGFloat? {
        guard diagram.ganttTodayMarker,
              let first = diagram.ganttTasks.map(\.startDate).min(),
              let last = diagram.ganttTasks.map(\.endDate).max() else { return nil }
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = localCalendar.dateComponents([.year, .month, .day], from: today)
        guard let day = calendar.date(from: parts) else { return nil }
        guard day >= calendar.startOfDay(for: first),
              day <= calendar.startOfDay(for: last) else { return nil }
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: day).day ?? 0
        return 180 + CGFloat(offset) * 12
    }

    private static func kanban(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        let rows = diagram.kanbanColumns.map { $0.tasks.count }.max() ?? 0
        return .init(size: CGSize(width: CGFloat(diagram.kanbanColumns.count) * 216 + 32,
                                  height: CGFloat(120 + rows * 86)), nodes: [:], edges: [])
    }

    static func kanbanColumns(_ diagram: MermaidDiagram) -> [CGRect] {
        let height = CGFloat(86 + (diagram.kanbanColumns.map { $0.tasks.count }.max() ?? 0) * 86)
        return diagram.kanbanColumns.indices.map { index in
            CGRect(x: 24 + CGFloat(index) * 216, y: 50, width: 200, height: height)
        }
    }

    private static func radar(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        let legend = diagram.radarShowLegend ? CGFloat(diagram.radarCurves.count) * 22 : 0
        return .init(size: CGSize(width: 420, height: 390 + legend), nodes: [:], edges: [])
    }

    static func radarPoint(index: Int, count: Int, radius: CGFloat) -> CGPoint {
        let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(max(1, count)) - .pi / 2
        return CGPoint(x: 210 + cos(angle) * radius, y: 200 + sin(angle) * radius)
    }

    private static func xyChart(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        let count = max(diagram.xyCategories.count, diagram.xySeries.map { $0.values.count }.max() ?? 0)
        return .init(size: CGSize(width: max(380, CGFloat(count) * 66 + 90), height: 330), nodes: [:], edges: [])
    }

    static func xyPlotFrame(_ diagram: MermaidDiagram) -> CGRect {
        let size = xyChart(diagram).size
        return CGRect(x: 56, y: 54, width: size.width - 86, height: 220)
    }

    private static func flowchart(_ diagram: MermaidDiagram) -> MermaidLayoutResult {
        guard !diagram.nodes.isEmpty else { return .init(size: .zero, nodes: [:], edges: []) }
        let ids = Set(diagram.nodes.map(\.id))
        var outgoing = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, [String]()) })
        var indegree = Dictionary(uniqueKeysWithValues: diagram.nodes.map { ($0.id, 0) })
        func members(_ endpoint: String) -> [String] {
            if ids.contains(endpoint) { return [endpoint] }
            return diagram.subgraphs.first { $0.id == endpoint }?.nodeIDs.filter { ids.contains($0) } ?? []
        }
        for edge in diagram.edges where edge.from != edge.to {
            for from in members(edge.from) {
                for to in members(edge.to) where from != to {
                    outgoing[from, default: []].append(to)
                    indegree[to, default: 0] += 1
                }
            }
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
        let hasSubgraphs = !diagram.subgraphs.isEmpty
        let loopLabels = Dictionary(grouping: diagram.edges.filter { $0.from == $0.to }, by: \.from)
            .mapValues { edges in edges.compactMap(\.label).map(labelWidth).max() ?? 0 }
        let widestLoopLabel = loopLabels.values.max() ?? 0
        let margin: CGFloat = max(hasSubgraphs ? 72 : diagram.kind == .flowchart ? 24 : 64,
                                  horizontal && !loopLabels.isEmpty ? widestLoopLabel / 2 + 24 : 0)
        let mainGap: CGFloat = max(hasSubgraphs ? 100 : 72,
                                   horizontal && !loopLabels.isEmpty ? widestLoopLabel + 24 : 0)
        let crossGap: CGFloat = hasSubgraphs ? 80 : 40
        // In a horizontal graph the main axis uses node width, and the cross axis uses height.
        func axisSize(_ node: MermaidNode) -> CGFloat { horizontal ? nodeWidth(node) : nodeHeight(node) }
        func laneSize(_ node: MermaidNode) -> CGFloat {
            let base = horizontal ? nodeHeight(node) : nodeWidth(node)
            guard let labelWidth = loopLabels[node.id] else { return base }
            return base + (horizontal ? 86 : max(80, labelWidth + 80))
        }
        let layerMain = layers.map { $0.map(axisSize).max() ?? 0 }
        let layerCross = layers.map { layer in
            layer.reduce(CGFloat(0)) { $0 + laneSize($1) } + CGFloat(max(0, layer.count - 1)) * crossGap
        }
        let crossExtent = layerCross.max() ?? 0
        let mainExtent = layerMain.reduce(0, +) + CGFloat(max(0, layers.count - 1)) * mainGap
        var size = horizontal
            ? CGSize(width: mainExtent + margin * 2, height: crossExtent + margin * 2)
            : CGSize(width: crossExtent + margin * 2, height: mainExtent + margin * 2)
        var positions: [String: CGRect] = [:]
        var main = margin
        for (layerIndex, layer) in layers.enumerated() {
            var cross = margin + (crossExtent - layerCross[layerIndex]) / 2
            for node in layer {
                let width = nodeWidth(node), height = nodeHeight(node)
                let frame = horizontal
                    ? CGRect(x: main + (layerMain[layerIndex] - width) / 2,
                             y: cross + (loopLabels[node.id] == nil ? 0 : 86), width: width, height: height)
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
        var groupFrames: [String: CGRect] = [:]
        for group in diagram.subgraphs.reversed() {
            let memberFrames = group.nodeIDs.compactMap { positions[$0] } +
                diagram.subgraphs.filter { $0.parentID == group.id }.compactMap { groupFrames[$0.id] }
            guard let first = memberFrames.first else { continue }
            let bounds = memberFrames.dropFirst().reduce(first) { $0.union($1) }
            groupFrames[group.id] = CGRect(x: bounds.minX - 20, y: bounds.minY - 38,
                                           width: bounds.width + 40, height: bounds.height + 58)
        }
        if !groupFrames.isEmpty {
            let minX = groupFrames.values.map(\.minX).min() ?? 16
            let minY = groupFrames.values.map(\.minY).min() ?? 16
            let shiftX = max(0, 16 - minX)
            let shiftY = max(0, 16 - minY)
            positions = positions.mapValues { $0.offsetBy(dx: shiftX, dy: shiftY) }
            groupFrames = groupFrames.mapValues { $0.offsetBy(dx: shiftX, dy: shiftY) }
            size.width = max(size.width + shiftX, (groupFrames.values.map(\.maxX).max() ?? 0) + 16)
            size.height = max(size.height + shiftY, (groupFrames.values.map(\.maxY).max() ?? 0) + 16)
        }
        let placed = diagram.edges.compactMap { edge -> MermaidPlacedEdge? in
            guard let from = positions[edge.from] ?? groupFrames[edge.from],
                  let to = positions[edge.to] ?? groupFrames[edge.to] else { return nil }
            if edge.from == edge.to, positions[edge.from] != nil {
                let labelFrame: CGRect?
                let start: CGPoint, end: CGPoint, control1: CGPoint, control2: CGPoint
                if horizontal {
                    start = .init(x: from.minX + from.width * 0.3, y: from.minY)
                    end = .init(x: from.minX + from.width * 0.7, y: from.minY)
                    control1 = .init(x: start.x - 25, y: start.y - 45)
                    control2 = .init(x: end.x + 25, y: end.y - 45)
                    labelFrame = edge.label.map { label in
                        CGRect(x: from.midX - labelWidth(label) / 2, y: from.minY - 78,
                               width: labelWidth(label), height: 18)
                    }
                } else {
                    start = .init(x: from.maxX, y: from.midY - 10)
                    end = .init(x: from.maxX, y: from.midY + 10)
                    control1 = .init(x: start.x + 45, y: start.y - 25)
                    control2 = .init(x: end.x + 45, y: end.y + 25)
                    labelFrame = edge.label.map { label in
                        CGRect(x: from.maxX + 62, y: from.midY - 9,
                               width: labelWidth(label), height: 18)
                    }
                }
                return .init(edge: edge, start: start, end: end,
                             selfLoop: .init(control1: control1, control2: control2, labelFrame: labelFrame))
            }
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
        return .init(size: size, nodes: positions, edges: placed, subgraphs: groupFrames)
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
        if node.shape == .stateStart || node.shape == .stateEnd { return 28 }
        if !node.compartments.isEmpty {
            let longest = ([node.label] + node.compartments.flatMap { $0 }).map(\.utf16.count).max() ?? 0
            return min(max(CGFloat(longest) * 7.5 + 28, 110), 360)
        }
        let base = min(max(CGFloat(node.label.utf16.count) * 8 + 28, 88), 280)
        switch node.shape {
        case .diamond: return base + 30
        case .circle: return max(base, 80)
        default: return base
        }
    }

    private static func labelWidth(_ label: String) -> CGFloat {
        // 10-point Canvas labels need wider cells for CJK glyphs than Latin glyphs.
        CGFloat(label.unicodeScalars.reduce(0) { $0 + ($1.value > 0xFF ? 11 : 7) }) + 12
    }

    private static func nodeHeight(_ node: MermaidNode) -> CGFloat {
        if node.shape == .stateStart || node.shape == .stateEnd { return 28 }
        if !node.compartments.isEmpty {
            let rows = node.compartments.reduce(0) { $0 + $1.count }
            return CGFloat(48 + rows * 20 + node.compartments.count * 10)
        }
        switch node.shape {
        case .diamond, .circle: return 76
        default: return 48
        }
    }
}
