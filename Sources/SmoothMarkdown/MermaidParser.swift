import Foundation

public enum MermaidKind: Equatable { case flowchart, sequence, pie, timeline, gantt, kanban }
public enum MermaidDirection: Equatable { case topToBottom, bottomToTop, leftToRight, rightToLeft }
public enum MermaidShape: Equatable { case rectangle, rounded, stadium, diamond, circle, subroutine, cylinder }
public enum MermaidLine: Equatable { case solid, dotted, thick }
public enum MermaidArrow: Equatable { case none, arrow, cross }
public enum MermaidParticipantType: Equatable { case participant, actor }

public struct MermaidNode: Equatable, Identifiable {
    public let id: String
    public let label: String
    public let shape: MermaidShape
    public let participantType: MermaidParticipantType

    public init(id: String, label: String, shape: MermaidShape = .rectangle,
                participantType: MermaidParticipantType = .participant) {
        self.id = id
        self.label = label
        self.shape = shape
        self.participantType = participantType
    }
}

public struct MermaidEdge: Equatable {
    public let from: String
    public let to: String
    public let label: String?
    public let line: MermaidLine
    public let arrow: MermaidArrow

    public init(from: String, to: String, label: String? = nil,
                line: MermaidLine = .solid, arrow: MermaidArrow = .arrow) {
        self.from = from
        self.to = to
        self.label = label
        self.line = line
        self.arrow = arrow
    }
}

public struct MermaidPieSlice: Equatable {
    public let label: String
    public let value: Double
    public init(label: String, value: Double) { self.label = label; self.value = value }
}

public struct MermaidTimelineEvent: Equatable {
    public let title: String
    public let description: String?
    public init(title: String, description: String? = nil) { self.title = title; self.description = description }
}

public struct MermaidTimelineSection: Equatable {
    public let title: String
    public let events: [MermaidTimelineEvent]
    public init(title: String, events: [MermaidTimelineEvent]) { self.title = title; self.events = events }
}

public struct MermaidDiagram: Equatable {
    public let kind: MermaidKind
    public let direction: MermaidDirection
    public let nodes: [MermaidNode]
    public let edges: [MermaidEdge]
    public let title: String?
    public let showData: Bool
    public let pieSlices: [MermaidPieSlice]
    public let timelineSections: [MermaidTimelineSection]
    public let ganttTasks: [MermaidGanttTask]
    public let ganttDateFormat: String
    public let ganttAxisFormat: String?
    public let ganttExcludes: String?
    public let ganttTodayMarker: Bool
    public let kanbanColumns: [MermaidKanbanColumn]
    public let kanbanTicketBaseURL: String?

    public init(kind: MermaidKind, direction: MermaidDirection, nodes: [MermaidNode] = [], edges: [MermaidEdge] = [],
                title: String? = nil, showData: Bool = false, pieSlices: [MermaidPieSlice] = [],
                timelineSections: [MermaidTimelineSection] = [], ganttTasks: [MermaidGanttTask] = [],
                ganttDateFormat: String = "YYYY-MM-DD", ganttAxisFormat: String? = nil,
                ganttExcludes: String? = nil, ganttTodayMarker: Bool = true,
                kanbanColumns: [MermaidKanbanColumn] = [], kanbanTicketBaseURL: String? = nil) {
        self.kind = kind; self.direction = direction; self.nodes = nodes; self.edges = edges
        self.title = title; self.showData = showData; self.pieSlices = pieSlices; self.timelineSections = timelineSections
        self.ganttTasks = ganttTasks; self.ganttDateFormat = ganttDateFormat; self.ganttAxisFormat = ganttAxisFormat
        self.ganttExcludes = ganttExcludes; self.ganttTodayMarker = ganttTodayMarker
        self.kanbanColumns = kanbanColumns; self.kanbanTicketBaseURL = kanbanTicketBaseURL
    }

    public func node(_ id: String) -> MermaidNode? { nodes.first { $0.id == id } }
}

/// Parses the documented native flowchart, sequence, pie, timeline, Gantt, and Kanban subset.
public enum MermaidParser {
    public static func parse(_ source: String) -> MermaidDiagram? {
        let rawLines = source.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                      !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("%%") }
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if lines.first == "---" { return MermaidExtendedParser.kanban(rawLines) }
        guard let header = lines.first else { return nil }
        if let match = RegexCapture.first(#"^(?:graph|flowchart)\s+(TD|TB|BT|LR|RL)$"#, in: header, options: [.caseInsensitive]) {
            let direction: MermaidDirection = switch match[1].uppercased() {
            case "BT": .bottomToTop
            case "LR": .leftToRight
            case "RL": .rightToLeft
            default: .topToBottom
            }
            return flowchart(Array(lines.dropFirst()), direction: direction)
        }
        if header.lowercased() == "sequencediagram" { return sequence(Array(lines.dropFirst())) }
        if header.lowercased() == "pie" || header.lowercased() == "pie showdata" {
            return pie(Array(lines.dropFirst()), showData: header.lowercased().contains("showdata"))
        }
        if header.lowercased() == "timeline" { return timeline(Array(lines.dropFirst())) }
        if header.lowercased() == "gantt" { return MermaidExtendedParser.gantt(lines) }
        if header.lowercased() == "kanban" { return MermaidExtendedParser.kanban(rawLines) }
        return nil
    }

    private static func pie(_ lines: [String], showData: Bool) -> MermaidDiagram? {
        var title: String?
        var slices: [MermaidPieSlice] = []
        for line in lines {
            if line.lowercased().hasPrefix("title ") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let groups = RegexCapture.first(#"^(?:\"([^\"]+)\"|'([^']+)'|([^:]+))\s*:\s*([0-9]+(?:\.[0-9]+)?)$"#, in: line),
                  let value = Double(groups[4]), value.isFinite, value > 0 else { continue }
            let label = [groups[1], groups[2], groups[3]].first { !$0.isEmpty }?.trimmingCharacters(in: .whitespaces) ?? ""
            if !label.isEmpty { slices.append(.init(label: label, value: value)) }
        }
        guard !slices.isEmpty else { return nil }
        return .init(kind: .pie, direction: .leftToRight, title: title, showData: showData, pieSlices: slices)
    }

    private static func timeline(_ lines: [String]) -> MermaidDiagram? {
        var title: String?
        var sections: [MermaidTimelineSection] = []
        var period: String?
        var events: [MermaidTimelineEvent] = []
        func flush() {
            if let period, !events.isEmpty { sections.append(.init(title: period, events: events)) }
            events = []
        }
        for line in lines {
            if line.lowercased().hasPrefix("title ") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if let colon = line.firstIndex(of: ":") {
                let left = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let right = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !left.isEmpty {
                    flush()
                    period = left
                }
                if !right.isEmpty, period != nil { events.append(.init(title: right)) }
            } else if !events.isEmpty {
                let previous = events.removeLast()
                events.append(.init(title: previous.title, description: line))
            }
        }
        flush()
        guard !sections.isEmpty else { return nil }
        return .init(kind: .timeline, direction: .leftToRight, title: title, timelineSections: sections)
    }

    private static func flowchart(_ lines: [String], direction: MermaidDirection) -> MermaidDiagram {
        var nodes: [MermaidNode] = []
        var edges: [MermaidEdge] = []
        let arrowPattern = try! NSRegularExpression(pattern: #"\s*(==>|-->|-\.->|---)\s*(\|[^|]*\|)?\s*"#)
        for line in lines {
            let source = line as NSString
            let matches = arrowPattern.matches(in: line, range: NSRange(location: 0, length: source.length))
            if matches.isEmpty {
                if let node = parseNode(line) { save(node, in: &nodes) }
                continue
            }
            var parts: [String] = []
            var cursor = 0
            for match in matches {
                parts.append(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)).trimmingCharacters(in: .whitespaces))
                cursor = NSMaxRange(match.range)
            }
            parts.append(source.substring(from: cursor).trimmingCharacters(in: .whitespaces))
            guard parts.count == matches.count + 1, parts.allSatisfy({ !$0.isEmpty }) else { continue }
            for part in parts { if let node = parseNode(part) { save(node, in: &nodes) } }
            for (index, match) in matches.enumerated() {
                guard let from = extractID(parts[index]), let to = extractID(parts[index + 1]) else { continue }
                let token = source.substring(with: match.range(at: 1))
                let rawLabel = match.range(at: 2).location == NSNotFound ? "" : source.substring(with: match.range(at: 2))
                let label = rawLabel.isEmpty ? nil : String(rawLabel.dropFirst().dropLast())
                edges.append(.init(from: from, to: to, label: label,
                                   line: token.contains("=") ? .thick : token.contains(".") ? .dotted : .solid,
                                   arrow: token.contains(">") ? .arrow : .none))
            }
        }
        return .init(kind: .flowchart, direction: direction, nodes: nodes, edges: edges)
    }

    private static func save(_ node: MermaidNode, in nodes: inout [MermaidNode]) {
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            let current = nodes[index]
            if (current.label == current.id && node.label != node.id) ||
                (current.shape == .rectangle && node.shape != .rectangle) { nodes[index] = node }
        } else { nodes.append(node) }
    }

    private static func parseNode(_ source: String) -> MermaidNode? {
        let shapes: [(String, MermaidShape)] = [
            (#"^([A-Za-z_]\w*)\(\((.+)\)\)$"#, .circle),
            (#"^([A-Za-z_]\w*)\[\[(.+)\]\]$"#, .subroutine),
            (#"^([A-Za-z_]\w*)\[\((.+)\)\]$"#, .cylinder),
            (#"^([A-Za-z_]\w*)\(\[(.+)\]\)$"#, .stadium),
            (#"^([A-Za-z_]\w*)\[(.+)\]$"#, .rectangle),
            (#"^([A-Za-z_]\w*)\((.+)\)$"#, .rounded),
            (#"^([A-Za-z_]\w*)\{(.+)\}$"#, .diamond),
        ]
        for (pattern, shape) in shapes {
            if let groups = RegexCapture.first(pattern, in: source) {
                return .init(id: groups[1], label: groups[2].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")), shape: shape)
            }
        }
        guard let groups = RegexCapture.first(#"^([A-Za-z_]\w*)$"#, in: source) else { return nil }
        return .init(id: groups[1], label: groups[1])
    }

    private static func extractID(_ source: String) -> String? {
        RegexCapture.first(#"^([A-Za-z_]\w*)"#, in: source)?[1]
    }

    private static func sequence(_ lines: [String]) -> MermaidDiagram {
        var nodes: [MermaidNode] = []
        var edges: [MermaidEdge] = []
        for line in lines {
            if let groups = RegexCapture.first(#"^(participant|actor)\s+([A-Za-z_]\w*)(?:\s+as\s+(.+))?$"#, in: line, options: [.caseInsensitive]) {
                let node = MermaidNode(id: groups[2], label: groups[3].isEmpty ? groups[2] : groups[3],
                                       participantType: groups[1].lowercased() == "actor" ? .actor : .participant)
                save(node, in: &nodes)
                continue
            }
            guard let groups = RegexCapture.first(#"^([A-Za-z_]\w*)(-->>|->>|-->|->|--x|-x|--\)|-\))([A-Za-z_]\w*)(?::\s*(.*))?$"#, in: line) else { continue }
            let from = groups[1], token = groups[2], to = groups[3]
            save(.init(id: from, label: from), in: &nodes)
            save(.init(id: to, label: to), in: &nodes)
            edges.append(.init(from: from, to: to, label: groups[4].isEmpty ? nil : groups[4],
                               line: token.hasPrefix("--") ? .dotted : .solid,
                               arrow: token.hasSuffix("x") ? .cross : token.hasSuffix(">>") || token.hasSuffix(")") ? .arrow : .none))
        }
        return .init(kind: .sequence, direction: .leftToRight, nodes: nodes, edges: edges)
    }
}

private enum RegexCapture {
    static func first(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let source = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else { return nil }
        return (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : source.substring(with: match.range(at: $0)) }
    }
}
