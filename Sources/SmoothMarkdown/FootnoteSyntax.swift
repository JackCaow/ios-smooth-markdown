import Foundation

/// Footnote definitions and references handled by the native extension pipeline.
enum FootnoteSyntax {
    struct Definition: Equatable {
        let label: String
        let content: String
    }

    enum Section: Equatable {
        case markdown(String)
        case definition(Definition)
    }

    enum Part: Equatable {
        case text(String)
        case reference(String)
    }

    private static let definitionPattern = try! NSRegularExpression(pattern: #"^\[\^([^\]]+)\]:\s+(.+)$"#)

    static func sections(_ markdown: String) -> [Section] {
        let lines = markdown.components(separatedBy: "\n")
        var sections: [Section] = []
        var ordinary: [String] = []
        var fence: Character?
        var fenceLength = 0
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                ordinary.append(line)
                if let run = fenceRun(trimmed), run.0 == marker, run.1 >= fenceLength,
                   trimmed.dropFirst(run.1).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                index += 1
                continue
            }
            if let run = fenceRun(trimmed), run.1 >= 3 {
                fence = run.0
                fenceLength = run.1
                ordinary.append(line)
                index += 1
                continue
            }
            if let definition = definition(on: line) {
                if !ordinary.isEmpty {
                    sections.append(.markdown(ordinary.joined(separator: "\n")))
                    ordinary.removeAll()
                }
                var content = [definition.content]
                index += 1
                while index < lines.count {
                    let continuation = lines[index]
                    if continuation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        index += 1
                    } else if continuation.hasPrefix("    ") || continuation.hasPrefix("\t") {
                        content.append(continuation.trimmingCharacters(in: .whitespaces))
                        index += 1
                    } else {
                        break
                    }
                }
                sections.append(.definition(.init(label: definition.label, content: content.joined(separator: "\n"))))
                continue
            }
            ordinary.append(line)
            index += 1
        }
        if !ordinary.isEmpty { sections.append(.markdown(ordinary.joined(separator: "\n"))) }
        return sections
    }

    static func parts(in text: String) -> [Part] {
        var parts: [Part] = []
        var ordinary = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if text[cursor] == "[" {
                let caret = text.index(after: cursor)
                if caret < text.endIndex, text[caret] == "^",
                   let close = text[caret...].firstIndex(of: "]"), close > text.index(after: caret) {
                    if !ordinary.isEmpty { parts.append(.text(ordinary)); ordinary = "" }
                    parts.append(.reference(String(text[text.index(after: caret)..<close])))
                    cursor = text.index(after: close)
                    continue
                }
            }
            ordinary.append(text[cursor])
            cursor = text.index(after: cursor)
        }
        if !ordinary.isEmpty { parts.append(.text(ordinary)) }
        return parts
    }

    private static func definition(on line: String) -> Definition? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed as NSString
        guard let match = definitionPattern.firstMatch(in: trimmed, range: NSRange(location: 0, length: source.length)) else { return nil }
        return Definition(label: source.substring(with: match.range(at: 1)),
                          content: source.substring(with: match.range(at: 2)))
    }

    private static func fenceRun(_ line: String) -> (Character, Int)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix(while: { $0 == first }).count
        return count >= 3 ? (first, count) : nil
    }
}
