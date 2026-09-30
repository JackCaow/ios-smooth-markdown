import Foundation

/// The source package recognizes these two details openers as Markdown blocks,
/// independently of its optional generic HTML parser.
enum DetailsSyntax {
    struct Block: Equatable {
        let summary: String
        let content: String
        let isOpen: Bool
    }

    enum Section: Equatable {
        case markdown(String)
        case details(Block)
    }

    static func sections(_ markdown: String) -> [Section] {
        let lines = markdown.components(separatedBy: "\n")
        var sections: [Section] = []
        var ordinary: [String] = []
        var fence: Character?
        var fenceLength = 0
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if let marker = fence {
                ordinary.append(line)
                if let run = fenceRun(trimmed), run.0 == marker, run.1 >= fenceLength,
                   trimmed.dropFirst(run.1).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                index += 1
                continue
            }
            if let run = fenceRun(trimmed) {
                fence = run.0
                fenceLength = run.1
                ordinary.append(line)
                index += 1
                continue
            }
            if trimmed == "<details>" || trimmed == "<details open>" {
                if !ordinary.isEmpty {
                    sections.append(.markdown(ordinary.joined(separator: "\n")))
                    ordinary.removeAll()
                }
                let parsed = block(lines: lines, startingAt: index, isOpen: trimmed == "<details open>")
                sections.append(.details(parsed.block))
                index = parsed.nextIndex
                continue
            }
            ordinary.append(line)
            index += 1
        }
        if !ordinary.isEmpty { sections.append(.markdown(ordinary.joined(separator: "\n"))) }
        return sections
    }

    private static func block(lines: [String], startingAt start: Int, isOpen: Bool) -> (block: Block, nextIndex: Int) {
        var index = start + 1
        var summary = ""
        var content: [String] = []
        var foundSummary = false
        var inSummary = false
        var depth = 1
        var fence: Character?
        var fenceLength = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if let marker = fence {
                if foundSummary { content.append(line) }
                if let run = fenceRun(lower), run.0 == marker, run.1 >= fenceLength,
                   lower.dropFirst(run.1).trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                index += 1
                continue
            }
            if let run = fenceRun(lower) {
                fence = run.0
                fenceLength = run.1
                if foundSummary { content.append(line) }
                index += 1
                continue
            }
            if lower == "<details>" || lower == "<details open>" {
                depth += 1
                if foundSummary { content.append(line) }
                index += 1
                continue
            }
            if lower == "</details>" {
                depth -= 1
                index += 1
                if depth == 0 { break }
                if foundSummary { content.append(line) }
                continue
            }
            if depth == 1, lower.hasPrefix("<summary>") {
                foundSummary = true
                inSummary = true
                let afterOpen = String(trimmed.dropFirst("<summary>".count))
                if let close = afterOpen.range(of: "</summary>", options: .caseInsensitive) {
                    summary = String(afterOpen[..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
                    inSummary = false
                } else if !afterOpen.isEmpty {
                    summary = afterOpen
                }
                index += 1
                continue
            }
            if inSummary, let close = line.range(of: "</summary>", options: .caseInsensitive) {
                let lastLine = String(line[..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !lastLine.isEmpty { summary = lastLine }
                inSummary = false
                index += 1
                continue
            }
            if inSummary {
                summary = "\(summary) \(trimmed)"
                index += 1
                continue
            }
            if foundSummary { content.append(line) }
            index += 1
        }
        return (Block(summary: summary, content: content.joined(separator: "\n"), isOpen: isOpen), index)
    }

    private static func fenceRun(_ line: String) -> (Character, Int)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix(while: { $0 == first }).count
        return count >= 3 ? (first, count) : nil
    }
}
