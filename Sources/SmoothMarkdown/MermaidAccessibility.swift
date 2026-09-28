import Foundation

extension MermaidDiagram {
    /// One spoken description for the Canvas, whose drawn shapes have no individual accessibility nodes.
    var voiceOverSummary: String {
        let type: String = switch kind {
        case .flowchart: "Flowchart"
        case .sequence: "Sequence diagram"
        case .classDiagram: "Class diagram"
        case .stateDiagram: "State diagram"
        case .erDiagram: "ER diagram"
        case .pie: "Pie chart"
        case .timeline: "Timeline"
        case .gantt: "Gantt chart"
        case .kanban: "Kanban board"
        case .radar: "Radar chart"
        case .xyChart: "XY chart"
        }
        var parts = [type]
        if let title, !title.isEmpty { parts.append(title) }
        switch kind {
        case .flowchart, .sequence, .classDiagram, .stateDiagram, .erDiagram:
            let names = nodes.filter { $0.shape != .stateStart && $0.shape != .stateEnd }
                .map(\.label).filter { !$0.isEmpty }
            if !names.isEmpty { parts.append("Nodes: \(spokenList(names))") }
            let transitions = edges.map { edge in
                let from = node(edge.from)?.label ?? edge.from
                let to = node(edge.to)?.label ?? edge.to
                let label = edge.label.map { ", \($0)" } ?? ""
                return "\(from.isEmpty ? "start" : from) to \(to.isEmpty ? "end" : to)\(label)"
            }
            if !transitions.isEmpty { parts.append("Connections: \(spokenList(transitions))") }
        case .pie:
            parts.append("Slices: \(spokenList(pieSlices.map { "\($0.label) \($0.value.formatted())" }))")
        case .timeline:
            parts.append("Periods: \(spokenList(timelineSections.map(\.title)))")
        case .gantt:
            parts.append("Tasks: \(spokenList(ganttTasks.map(\.name)))")
        case .kanban:
            parts.append("Columns: \(spokenList(kanbanColumns.map { "\($0.title), \($0.tasks.count) tasks" }))")
        case .radar:
            parts.append("Axes: \(spokenList(radarAxes.map(\.label)))")
            parts.append("Curves: \(spokenList(radarCurves.map(\.label)))")
        case .xyChart:
            if !xyCategories.isEmpty { parts.append("Categories: \(spokenList(xyCategories))") }
            parts.append("\(xySeries.count) data series")
        }
        return parts.joined(separator: ". ")
    }
}

private func spokenList(_ values: [String]) -> String {
    let limit = 8
    let spoken = values.prefix(limit).joined(separator: ", ")
    return values.count > limit ? "\(spoken), and \(values.count - limit) more" : spoken
}
