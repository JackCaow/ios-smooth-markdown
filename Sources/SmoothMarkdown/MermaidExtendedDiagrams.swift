import Foundation

public enum MermaidGanttStatus: Equatable { case normal, done, active, critical, milestone }

public struct MermaidGanttTask: Equatable {
    public let id: String
    public let name: String
    public let section: String?
    public let startDate: Date
    public let endDate: Date
    public let status: MermaidGanttStatus
    public let dependencies: [String]

    public init(id: String, name: String, section: String?, startDate: Date, endDate: Date,
                status: MermaidGanttStatus, dependencies: [String]) {
        self.id = id; self.name = name; self.section = section; self.startDate = startDate
        self.endDate = endDate; self.status = status; self.dependencies = dependencies
    }
}

public enum MermaidKanbanPriority: Equatable { case veryHigh, high, normal, low, veryLow }

public struct MermaidKanbanTask: Equatable {
    public let id: String
    public let description: String
    public let assigned: String?
    public let ticket: String?
    public let priority: MermaidKanbanPriority

    public init(id: String, description: String, assigned: String?, ticket: String?, priority: MermaidKanbanPriority) {
        self.id = id; self.description = description; self.assigned = assigned
        self.ticket = ticket; self.priority = priority
    }
}

public struct MermaidKanbanColumn: Equatable {
    public let id: String
    public let title: String
    public let wipLimit: Int?
    public let tasks: [MermaidKanbanTask]
    public var isOverLimit: Bool { wipLimit.map { tasks.count > $0 } ?? false }

    public init(id: String, title: String, wipLimit: Int?, tasks: [MermaidKanbanTask]) {
        self.id = id; self.title = title; self.wipLimit = wipLimit; self.tasks = tasks
    }
}

/// Parses the Flutter-supported, source-backed Gantt and Kanban subset.
enum MermaidExtendedParser {
    static func gantt(_ lines: [String]) -> MermaidDiagram? {
        var title: String?
        var dateFormat = "YYYY-MM-DD"
        var axisFormat: String?
        var excludes: String?
        var todayMarker = true
        var section: String?
        var tasks: [MermaidGanttTask] = []
        let calendar = Calendar(identifier: .gregorian)
        let baseline = calendar.startOfDay(for: Date())
        var nextStart = baseline
        for source in lines.dropFirst() {
            let line = source.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            if lower.hasPrefix("title ") { title = String(line.dropFirst(6)); continue }
            if lower.hasPrefix("dateformat ") { dateFormat = String(line.dropFirst(11)); continue }
            if lower.hasPrefix("axisformat ") { axisFormat = String(line.dropFirst(11)); continue }
            if lower.hasPrefix("excludes ") { excludes = String(line.dropFirst(9)); continue }
            if lower.hasPrefix("todaymarker ") { todayMarker = String(line.dropFirst(12)).lowercased() != "off"; continue }
            if lower.hasPrefix("section ") { section = String(line.dropFirst(8)); continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let definition = String(line[line.index(after: colon)...])
            let parts = definition.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard !name.isEmpty, !parts.isEmpty else { continue }
            var offset = 0
            let status: MermaidGanttStatus
            switch parts[0].lowercased() {
            case "done": status = .done; offset = 1
            case "active": status = .active; offset = 1
            case "crit", "critical": status = .critical; offset = 1
            case "milestone": status = .milestone; offset = 1
            default: status = .normal
            }
            let remaining = Array(parts.dropFirst(offset))
            guard !remaining.isEmpty else { continue }
            var id = name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            if id.isEmpty { id = "task_\(tasks.count)" }
            var startSpec: String?
            let durationSpec: String
            var dependencies: [String] = []
            switch remaining.count {
            case 1: durationSpec = remaining[0]
            case 2:
                durationSpec = remaining[1]
                if remaining[0].lowercased().hasPrefix("after ") {
                    dependencies = [String(remaining[0].dropFirst(6)).trimmingCharacters(in: .whitespaces)]
                } else if parseDate(remaining[0], format: dateFormat) != nil {
                    startSpec = remaining[0]
                } else { id = remaining[0] }
            default:
                id = remaining[0]
                durationSpec = remaining[2]
                if remaining[1].lowercased().hasPrefix("after ") {
                    dependencies = [String(remaining[1].dropFirst(6)).trimmingCharacters(in: .whitespaces)]
                } else { startSpec = remaining[1] }
            }
            var start = startSpec.flatMap { parseDate($0, format: dateFormat) } ?? nextStart
            if let dependency = dependencies.first, let predecessor = tasks.first(where: { $0.id == dependency }) {
                start = calendar.date(byAdding: .day, value: 1, to: predecessor.endDate) ?? start
            } else if !dependencies.isEmpty { continue }
            let end: Date
            if status == .milestone { end = start }
            else if let date = parseDate(durationSpec, format: dateFormat), date >= start { end = date }
            else if let days = durationDays(durationSpec), days > 0 {
                end = calendar.date(byAdding: .day, value: days - 1, to: start) ?? start
            } else { continue }
            tasks.append(.init(id: id, name: name, section: section, startDate: start,
                               endDate: end, status: status, dependencies: dependencies))
            nextStart = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        guard !tasks.isEmpty else { return nil }
        return .init(kind: .gantt, direction: .leftToRight, title: title, ganttTasks: tasks,
                     ganttDateFormat: dateFormat, ganttAxisFormat: axisFormat,
                     ganttExcludes: excludes, ganttTodayMarker: todayMarker)
    }

    static func kanban(_ lines: [String]) -> MermaidDiagram? {
        var title: String?
        var ticketBaseURL: String?
        var columns: [MermaidKanbanColumn] = []
        var columnID: String?
        var columnTitle = ""
        var wipLimit: Int?
        var tasks: [MermaidKanbanTask] = []
        var start = 0
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<end] {
                if let match = capture(#"ticketBaseUrl:\s*['\"]([^'\"]+)['\"]"#, line) { ticketBaseURL = match[1] }
            }
            start = end + 1
        }
        guard lines.dropFirst(start).first?.trimmingCharacters(in: .whitespaces).lowercased() == "kanban" else { return nil }
        func flush() {
            if let columnID {
                columns.append(.init(id: columnID, title: columnTitle, wipLimit: wipLimit, tasks: tasks))
            }
            tasks = []
        }
        for source in lines.dropFirst(start + 1) {
            let line = source.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.lowercased().hasPrefix("title ") { title = String(line.dropFirst(6)); continue }
            if !source.hasPrefix("    "),
               let match = capture(#"^(\w+)\[([^\]]+)\](?:\s+wip:(\d+))?$"#, line) {
                flush()
                columnID = match[1]; columnTitle = match[2]; wipLimit = Int(match[3])
                continue
            }
            guard source.hasPrefix("    "), columnID != nil,
                  let match = capture(#"^(\w+)\[([^\]]+)\](?:\s+@\{([^}]+)\})?$"#, line) else { continue }
            let metadata = match[3].split(separator: ",").compactMap { pair -> (String, String)? in
                let parts = pair.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return (parts[0].trimmingCharacters(in: .whitespaces),
                        parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\\\"'")))
            }
            let values = Dictionary(metadata, uniquingKeysWith: { first, _ in first })
            let priority: MermaidKanbanPriority = switch values["priority"]?.lowercased() {
            case "very high": .veryHigh
            case "high": .high
            case "low": .low
            case "very low": .veryLow
            default: .normal
            }
            tasks.append(.init(id: match[1], description: match[2], assigned: values["assigned"],
                               ticket: values["ticket"], priority: priority))
        }
        flush()
        guard !columns.isEmpty else { return nil }
        return .init(kind: .kanban, direction: .leftToRight, title: title,
                     kanbanColumns: columns, kanbanTicketBaseURL: ticketBaseURL)
    }

    private static func capture(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
    }

    private static func parseDate(_ value: String, format: String) -> Date? {
        let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "MM-dd-yyyy"]
        for pattern in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = pattern
            formatter.isLenient = false
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func durationDays(_ value: String) -> Int? {
        guard let match = capture(#"^(\d+)([dDwWmMyY]?)$"#, value), let number = Int(match[1]) else { return nil }
        switch match[2].lowercased() {
        case "w": return number * 7
        case "m": return number * 30
        case "y": return number * 365
        default: return number
        }
    }
}
