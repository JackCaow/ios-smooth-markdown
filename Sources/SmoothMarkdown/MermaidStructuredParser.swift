import Foundation

/// Strict, bounded parser for the basic class, state, and ER diagram forms.
enum MermaidStructuredParser {
    private static let id = #"[\p{L}\p{N}_-]+"#
    private static let entity = #"(?:"[^"]+"|[\p{L}\p{N}_-]+)"#

    static func parse(_ lines: [String]) -> MermaidDiagram? {
        guard let header = lines.first, lines.count <= 500,
              lines.joined(separator: "\n").utf16.count <= 50_000 else { return nil }
        let kind: MermaidKind
        switch header.lowercased() {
        case "classdiagram": kind = .classDiagram
        case "statediagram", "statediagram-v2": kind = .stateDiagram
        case "erdiagram": kind = .erDiagram
        default: return nil
        }
        var parser = Parser(kind: kind)
        return parser.parse(Array(lines.dropFirst()))
    }

    private struct Draft {
        let id: String
        var label: String
        var shape: MermaidShape
        var compartments: [[String]]
    }

    private struct Parser {
        let kind: MermaidKind
        var direction: MermaidDirection = .topToBottom
        var order: [String] = []
        var drafts: [String: Draft] = [:]
        var edges: [MermaidEdge] = []
        var openBlock: String?
        var blockRows: [String] = []

        mutating func parse(_ lines: [String]) -> MermaidDiagram? {
            for raw in lines {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #";$"#, with: "", options: .regularExpression)
                if line.isEmpty { continue }
                if let block = openBlock {
                    if line == "}" {
                        finishBlock(block)
                        openBlock = nil
                        blockRows.removeAll()
                    } else {
                        guard !line.contains("{") && !line.contains("}") else { return nil }
                        blockRows.append(line)
                    }
                    continue
                }
                if let groups = capture(#"^direction\s+(TB|TD|BT|LR|RL)$"#, line) {
                    direction = switch groups[1] {
                    case "BT": .bottomToTop
                    case "LR": .leftToRight
                    case "RL": .rightToLeft
                    default: .topToBottom
                    }
                    continue
                }
                let accepted = switch kind {
                case .classDiagram: parseClass(line)
                case .stateDiagram: parseState(line)
                case .erDiagram: parseER(line)
                default: false
                }
                if !accepted || order.count > 200 || edges.count > 500 { return nil }
            }
            guard openBlock == nil, !order.isEmpty else { return nil }
            let nodes = order.compactMap { key -> MermaidNode? in
                guard let draft = drafts[key] else { return nil }
                return .init(id: draft.id, label: draft.label, shape: draft.shape,
                             compartments: draft.compartments)
            }
            return .init(kind: kind, direction: direction, nodes: nodes, edges: edges)
        }

        mutating func add(_ id: String, label: String? = nil, shape: MermaidShape? = nil) {
            if drafts[id] == nil {
                order.append(id)
                drafts[id] = .init(id: id, label: id, shape: kind == .stateDiagram ? .rounded : .rectangle,
                                   compartments: kind == .classDiagram ? [[], []] : kind == .erDiagram ? [[]] : [])
            }
            if let label { drafts[id]?.label = label }
            if let shape { drafts[id]?.shape = shape }
        }

        mutating func finishBlock(_ id: String) {
            guard var draft = drafts[id] else { return }
            for row in blockRows {
                let index = kind == .classDiagram && row.contains("(") ? 1 : 0
                draft.compartments[index].append(row)
            }
            drafts[id] = draft
        }

        mutating func parseState(_ line: String) -> Bool {
            let endpoint = #"(?:\[\*\]|[\p{L}\p{N}_-]+)"#
            if let groups = capture("^(\(endpoint))\\s*-->\\s*(\(endpoint))(?:\\s*:\\s*(.*))?$", line) {
                let source = stateEndpoint(groups[1], initial: true)
                let target = stateEndpoint(groups[2], initial: false)
                edges.append(.init(from: source, to: target, label: groups[3].isEmpty ? nil : groups[3]))
                return true
            }
            if let groups = capture("^state\\s+\"(.*)\"\\s+as\\s+(\(MermaidStructuredParser.id))$", line) {
                add(groups[2], label: groups[1]); return true
            }
            if let groups = capture("^state\\s+(\(MermaidStructuredParser.id))(?:\\s+<<choice>>)?$", line) {
                add(groups[1], label: line.hasSuffix("<<choice>>") ? "" : nil,
                    shape: line.hasSuffix("<<choice>>") ? .diamond : nil)
                return true
            }
            if let groups = capture("^(\(MermaidStructuredParser.id))\\s*:\\s*(.+)$", line) {
                add(groups[1], label: groups[2]); return true
            }
            if capture("^(\(MermaidStructuredParser.id))$", line) != nil { add(line); return true }
            return false
        }

        mutating func stateEndpoint(_ token: String, initial: Bool) -> String {
            guard token == "[*]" else { add(token); return token }
            let id = initial ? "$state:start" : "$state:end"
            add(id, label: "", shape: initial ? .stateStart : .stateEnd)
            return id
        }

        mutating func parseClass(_ line: String) -> Bool {
            if let groups = capture("^class\\s+(\(MermaidStructuredParser.id))(?:\\s*\\[\"(.*)\"\\])?\\s*(\\{)?$", line) {
                add(groups[1], label: groups[2].isEmpty ? nil : groups[2])
                if !groups[3].isEmpty { openBlock = groups[1] }
                return true
            }
            let operatorPattern = #"(?:<\|--|--\|>|<\|\.\.|\.\.\|>|\*--|--\*|o--|--o|<--|-->|<\.\.|\.\.>|--|\.\.)"#
            let pattern = "^(\(MermaidStructuredParser.id))(?:\\s+\"([^\"]*)\")?\\s*(\(operatorPattern))(?:\\s+\"([^\"]*)\")?\\s*(\(MermaidStructuredParser.id))(?:\\s*:\\s*(.*))?$"
            if let groups = capture(pattern, line) {
                let from = groups[1], token = groups[3], to = groups[5]
                add(from); add(to)
                let marker: MermaidMarker? = token.contains("|") ? .inheritance :
                    token.contains("*") ? .composition : token.contains("o") ? .aggregation : nil
                let atSource = token.hasPrefix("<") || token.hasPrefix("*") || token.hasPrefix("o")
                // Flutter treats a plain left-pointing relation as a directed
                // edge from the right-hand class. Keep that direction in the
                // model too, so layout ranks and endpoint labels agree.
                let reverse = atSource && marker == nil && token.hasPrefix("<")
                let sourceLabel = reverse ? groups[4] : groups[2]
                let targetLabel = reverse ? groups[2] : groups[4]
                edges.append(.init(from: reverse ? to : from, to: reverse ? from : to,
                                   label: groups[6].isEmpty ? nil : groups[6],
                                   line: token.contains(".") ? .dotted : .solid,
                                   arrow: marker == nil && (token.hasSuffix(">") || reverse) ? .arrow : .none,
                                   sourceMarker: atSource ? marker : nil,
                                   targetMarker: atSource ? nil : marker,
                                   sourceLabel: sourceLabel.isEmpty ? nil : sourceLabel,
                                   targetLabel: targetLabel.isEmpty ? nil : targetLabel))
                return true
            }
            if let groups = capture("^(\(MermaidStructuredParser.id))\\s*:\\s*(.+)$", line) {
                add(groups[1])
                drafts[groups[1]]?.compartments[groups[2].contains("(") ? 1 : 0].append(groups[2])
                return true
            }
            return false
        }

        mutating func parseER(_ line: String) -> Bool {
            if let groups = capture("^(\(MermaidStructuredParser.entity))(?:\\s*\\[\"?(.*?)\"?\\])?\\s*(\\{)?$", line) {
                let id = unquote(groups[1])
                add(id, label: groups[2].isEmpty ? nil : groups[2])
                if !groups[3].isEmpty { openBlock = id }
                return true
            }
            let relation = "^(\(MermaidStructuredParser.entity))\\s+(\\|\\||o\\||\\|o|\\}\\||\\}o)\\s*(--|\\.\\.)\\s*(\\|\\||o\\||\\|o|\\|\\{|o\\{)\\s+(\(MermaidStructuredParser.entity))\\s*:\\s*(.+)$"
            if let groups = capture(relation, line) {
                let from = unquote(groups[1]), to = unquote(groups[5])
                add(from); add(to)
                edges.append(.init(from: from, to: to, label: unquote(groups[6]),
                                   line: groups[3] == ".." ? .dotted : .solid, arrow: .none,
                                   sourceMarker: erMarker(groups[2]), targetMarker: erMarker(groups[4])))
                return true
            }
            return false
        }

        func erMarker(_ token: String) -> MermaidMarker {
            if token.contains("{") || token.contains("}") {
                return token.contains("o") ? .zeroOrMore : .oneOrMore
            }
            return token.contains("o") ? .zeroOrOne : .exactlyOne
        }

        func unquote(_ text: String) -> String {
            text.hasPrefix("\"") && text.hasSuffix("\"") ? String(text.dropFirst().dropLast()) : text
        }

        func capture(_ pattern: String, _ text: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
            let source = text as NSString
            return (0..<match.numberOfRanges).map {
                match.range(at: $0).location == NSNotFound ? "" : source.substring(with: match.range(at: $0))
            }
        }
    }
}
