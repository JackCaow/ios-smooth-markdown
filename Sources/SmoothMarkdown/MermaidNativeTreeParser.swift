import Foundation

/// Rendering metadata lives in existing node compartments so the public diagram
/// initializer and its stored model remain source compatible.
enum MermaidGitCommitType: String { case normal = "NORMAL", reverse = "REVERSE", highlight = "HIGHLIGHT" }
struct MermaidGitCommit: Equatable {
    let id: String
    let branch: String
    let tag: String?
    let type: MermaidGitCommitType
    let parents: [String]
}

extension MermaidDiagram {
    var gitCommits: [MermaidGitCommit] {
        guard kind == .gitGraph else { return [] }
        return nodes.map { node in
            let branch = node.compartments.first?.first ?? "main"
            let tag = node.compartments.count > 1 ? node.compartments[1].first : nil
            let type = node.compartments.count > 2
                ? MermaidGitCommitType(rawValue: node.compartments[2].first ?? "") ?? .normal : .normal
            return .init(id: node.id, branch: branch, tag: tag, type: type,
                         parents: edges.filter { $0.to == node.id }.map(\.from))
        }
    }
}

/// Bounded basic Git history and indentation-tree parsers. Unsupported commands
/// are rejected rather than silently dropping a portion of the diagram.
enum MermaidNativeTreeParser {
    static func gitGraph(_ lines: [String]) -> MermaidDiagram? {
        guard bounded(lines), let header = lines.first,
              let declaration = capture(#"^gitGraph(?:\s+(LR|TB|BT))?\s*:?$"#, header.trimmingCharacters(in: .whitespacesAndNewlines), insensitive: true) else { return nil }
        let direction: MermaidDirection = switch declaration[1].uppercased() {
        case "TB": .topToBottom
        case "BT": .bottomToTop
        default: .leftToRight
        }
        var nodes: [MermaidNode] = []
        var edges: [MermaidEdge] = []
        var branches: Set<String> = ["main"]
        var heads: [String: String] = [:]
        var current = "main"
        var actionCount = 0
        var serial = 1
        var usedIDs: Set<String> = []
        for raw in lines.dropFirst() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let tokens = tokens(line), let command = tokens.first?.lowercased() else { return nil }
            if command == "init" {
                guard tokens.count == 1, actionCount == 0 else { return nil }
                actionCount += 1
                continue
            }
            actionCount += 1
            if command == "branch" {
                guard tokens.count == 2, validName(tokens[1]), !branches.contains(tokens[1]) else { return nil }
                let branch = tokens[1]
                branches.insert(branch)
                if let head = heads[current] { heads[branch] = head }
                current = branch
                continue
            }
            if command == "checkout" || command == "switch" {
                guard tokens.count == 2, branches.contains(tokens[1]) else { return nil }
                current = tokens[1]
                continue
            }
            guard command == "commit" || command == "merge" else { return nil }
            var parents = heads[current].map { [$0] } ?? []
            let attributesStart: Int
            if command == "merge" {
                guard tokens.count >= 2, tokens[1] != current, branches.contains(tokens[1]),
                      let ownHead = heads[current], let otherHead = heads[tokens[1]], ownHead != otherHead else { return nil }
                parents = [ownHead, otherHead]
                attributesStart = 2
            } else { attributesStart = 1 }
            guard let attributes = attributes(Array(tokens.dropFirst(attributesStart))) else { return nil }
            let id: String
            if let custom = attributes["id"] { id = custom }
            else {
                while usedIDs.contains("commit-\(serial)") { serial += 1 }
                id = "commit-\(serial)"
                serial += 1
            }
            guard !id.isEmpty, usedIDs.insert(id).inserted else { return nil }
            let type = MermaidGitCommitType(rawValue: attributes["type"] ?? "NORMAL") ?? .normal
            let tag = attributes["tag"].map { [$0] } ?? []
            nodes.append(.init(id: id, label: id,
                               shape: type == .highlight ? .rectangle : .circle,
                               compartments: [[current], tag, [type.rawValue]]))
            for parent in parents { edges.append(.init(from: parent, to: id, arrow: .none)) }
            heads[current] = id
        }
        guard !nodes.isEmpty else { return nil }
        return .init(kind: .gitGraph, direction: direction, nodes: nodes, edges: edges)
    }

    static func mindmap(_ lines: [String]) -> MermaidDiagram? {
        guard bounded(lines), lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mindmap" else { return nil }
        var nodes: [MermaidNode] = []
        var edges: [MermaidEdge] = []
        var ancestors: [(indent: Int, id: String)] = []
        var rootIndent: Int?
        var usedIDs: Set<String> = []
        var serial = 1
        for raw in lines.dropFirst() {
            let indent = indentation(raw)
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let declaration = mindmapNode(text) else { return nil }
            let id: String
            if let explicit = declaration.id { id = explicit }
            else {
                while usedIDs.contains("mindmap:\(serial)") { serial += 1 }
                id = "mindmap:\(serial)"
                serial += 1
            }
            // A repeated explicit ID could create a cycle or a second parent.
            guard usedIDs.insert(id).inserted else { return nil }
            if let rootIndent {
                guard indent > rootIndent else { return nil }
                while let previous = ancestors.last, previous.indent >= indent { ancestors.removeLast() }
                guard let parent = ancestors.last else { return nil }
                edges.append(.init(from: parent.id, to: id, arrow: .none))
            } else { rootIndent = indent }
            nodes.append(.init(id: id, label: declaration.label, shape: declaration.shape))
            ancestors.append((indent, id))
        }
        guard !nodes.isEmpty else { return nil }
        return .init(kind: .mindmap, direction: .leftToRight, nodes: nodes, edges: edges)
    }

    private static func bounded(_ lines: [String]) -> Bool {
        lines.count <= 500 && lines.joined(separator: "\n").utf16.count <= 50_000
    }

    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains(where: { $0.isNewline || $0 == ":" || $0 == ";" })
    }

    private static func attributes(_ tokens: [String]) -> [String: String]? {
        var result: [String: String] = [:]
        var index = 0
        while index < tokens.count {
            guard let colon = tokens[index].firstIndex(of: ":") else { return nil }
            let key = String(tokens[index][..<colon]).lowercased()
            guard ["id", "tag", "type"].contains(key), result[key] == nil else { return nil }
            var value = String(tokens[index][tokens[index].index(after: colon)...])
            if value.isEmpty {
                index += 1
                guard index < tokens.count else { return nil }
                value = tokens[index]
            }
            guard !value.isEmpty else { return nil }
            if key == "type" {
                value = value.uppercased()
                guard MermaidGitCommitType(rawValue: value) != nil else { return nil }
            }
            result[key] = value
            index += 1
        }
        return result
    }

    private static func tokens(_ text: String) -> [String]? {
        var result: [String] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if text[cursor].isWhitespace { cursor = text.index(after: cursor); continue }
            var value = ""
            if text[cursor] == "\"" {
                cursor = text.index(after: cursor)
                var closed = false
                while cursor < text.endIndex {
                    let character = text[cursor]
                    cursor = text.index(after: cursor)
                    if character == "\"" { closed = true; break }
                    if character == "\\" {
                        guard cursor < text.endIndex else { return nil }
                        value.append(text[cursor]); cursor = text.index(after: cursor)
                    } else { value.append(character) }
                }
                guard closed else { return nil }
                if cursor < text.endIndex, !text[cursor].isWhitespace { return nil }
            } else {
                while cursor < text.endIndex, !text[cursor].isWhitespace, text[cursor] != "\"" {
                    value.append(text[cursor]); cursor = text.index(after: cursor)
                }
            }
            guard !value.isEmpty else { return nil }
            result.append(value)
        }
        return result
    }

    private static func mindmapNode(_ text: String) -> (id: String?, label: String, shape: MermaidShape)? {
        let identifier = #"([\p{L}_][\p{L}\p{M}\p{N}_-]*)?"#
        let forms: [(String, MermaidShape)] = [
            (#"\(\((.+)\)\)"#, .circle), (#"\((.+)\)"#, .rounded),
            (#"\[(.+)\]"#, .rectangle), (#"\{\{(.+)\}\}"#, .hexagon)
        ]
        for (form, shape) in forms {
            if let groups = capture("^" + identifier + form + "$", text) {
                let label = groups[2].trimmingCharacters(in: .whitespaces)
                guard !label.isEmpty else { return nil }
                // Do not reinterpret an unclosed double-circle opener as a
                // rounded node whose label merely starts with `(`.
                if shape == .rounded, label.hasPrefix("(") { return nil }
                return (groups[1].isEmpty ? nil : groups[1], label, shape)
            }
        }
        guard !text.contains(where: { "[](){}".contains($0) }),
              !text.hasPrefix("::"), !text.contains("-->") else { return nil }
        return (nil, text, .rectangle)
    }

    private static func indentation(_ text: String) -> Int {
        var result = 0
        for character in text {
            if character == " " { result += 1 }
            else if character == "\t" { result += 4 - result % 4 }
            else { break }
        }
        return result
    }

    private static func capture(_ pattern: String, _ text: String, insensitive: Bool = false) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: insensitive ? [.caseInsensitive] : []),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
        return (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : (text as NSString).substring(with: match.range(at: $0)) }
    }
}
