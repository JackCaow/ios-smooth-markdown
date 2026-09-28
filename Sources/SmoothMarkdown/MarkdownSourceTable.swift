import Foundation

/// Editable GFM table source. Structural edits preserve the cells' inline Markdown.
public struct MarkdownSourceTable: Equatable {
    public var headers: [String]
    public var rows: [[String]]
    public var alignments: [MarkdownTableAlignment?]

    public var columnCount: Int { headers.count }

    public func toMarkdown() -> String {
        func line(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }
        let markers = headers.indices.map { index -> String in
            switch alignments[index] {
            case .left: ":---"
            case .center: ":---:"
            case .right: "---:"
            case nil: "---"
            }
        }
        return ([line(headers), line(markers)] + rows.map(line)).joined(separator: "\n")
    }

    public func replacingCell(rowIndex: Int, columnIndex: Int, text: String, header: Bool = false) -> Self {
        guard headers.indices.contains(columnIndex) else { return self }
        var result = self
        let escaped = text.replacingOccurrences(of: "|", with: "\\|")
        if header {
            result.headers[columnIndex] = escaped
        } else if rows.indices.contains(rowIndex) {
            result.rows[rowIndex][columnIndex] = escaped
        }
        return result
    }

    public func insertingRowBefore(_ index: Int) -> Self { insertingRow(at: min(max(0, index), rows.count)) }
    public func insertingRowAfter(_ index: Int) -> Self { insertingRow(at: min(max(0, index + 1), rows.count)) }
    private func insertingRow(at index: Int) -> Self {
        var result = self
        result.rows.insert(Array(repeating: "", count: columnCount), at: index)
        return result
    }
    public func deletingRow(_ index: Int) -> Self {
        guard rows.indices.contains(index) else { return self }
        var result = self
        result.rows.remove(at: index)
        return result
    }

    public func insertingColumnBefore(_ index: Int) -> Self { insertingColumn(at: min(max(0, index), columnCount)) }
    public func insertingColumnAfter(_ index: Int) -> Self { insertingColumn(at: min(max(0, index + 1), columnCount)) }
    private func insertingColumn(at index: Int) -> Self {
        var result = self
        result.headers.insert("", at: index)
        result.alignments.insert(nil, at: index)
        for row in result.rows.indices { result.rows[row].insert("", at: index) }
        return result
    }
    public func deletingColumn(_ index: Int) -> Self {
        guard headers.indices.contains(index), columnCount > 1 else { return self }
        var result = self
        result.headers.remove(at: index)
        result.alignments.remove(at: index)
        for row in result.rows.indices { result.rows[row].remove(at: index) }
        return result
    }
    public func settingColumnAlignment(_ index: Int, to alignment: MarkdownTableAlignment?) -> Self {
        guard headers.indices.contains(index) else { return self }
        var result = self
        result.alignments[index] = alignment
        return result
    }

    public static func parse(_ source: String) -> Self? {
        let lines = source.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        let headers = splitCells(lines[0])
        let markers = splitCells(lines[1])
        guard !headers.isEmpty, headers.count == markers.count else { return nil }
        guard markers.allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) else { return nil }
        let alignments: [MarkdownTableAlignment?] = markers.map { marker in
            if marker.hasPrefix(":"), marker.hasSuffix(":") { return .center }
            if marker.hasPrefix(":") { return .left }
            if marker.hasSuffix(":") { return .right }
            return nil
        }
        let rows = lines.dropFirst(2).map { line -> [String] in
            let cells = splitCells(line)
            return headers.indices.map { $0 < cells.count ? cells[$0] : "" }
        }
        return Self(headers: headers, rows: rows, alignments: alignments)
    }

    private static func splitCells(_ line: String) -> [String] {
        let characters = Array(line)
        var parts: [String] = []
        var start = 0
        var slashCount = 0
        for index in characters.indices {
            let character = characters[index]
            if character == "|", slashCount.isMultiple(of: 2) {
                parts.append(String(characters[start..<index]).trimmingCharacters(in: .whitespaces))
                start = index + 1
            }
            slashCount = character == "\\" ? slashCount + 1 : 0
        }
        parts.append(String(characters[start...]).trimmingCharacters(in: .whitespaces))
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("|"), parts.first == "" { parts.removeFirst() }
        if line.trimmingCharacters(in: .whitespaces).hasSuffix("|"), parts.last == "" { parts.removeLast() }
        return parts
    }
}

public enum MarkdownTableAlignment: Equatable { case left, center, right }

struct MarkdownSourceTableAtRange {
    let range: NSRange
    let table: MarkdownSourceTable
}

/// Locates a GFM table containing a UTF-16 source offset, excluding fenced code blocks.
func findSourceTable(_ source: String, offset: Int) -> MarkdownSourceTableAtRange? {
    let lines = source.components(separatedBy: "\n")
    var starts: [Int] = []
    var position = 0
    for line in lines {
        starts.append(position)
        position += (line as NSString).length + 1
    }
    var fence: Character?
    var fenceLength = 0
    var index = 0
    while index + 1 < lines.count {
        let indentation = lines[index].prefix(while: { $0 == " " }).count
        let trimmed = lines[index].dropFirst(indentation)
        let marker = trimmed.first
        let run = (marker == "`" || marker == "~") ? trimmed.prefix(while: { $0 == marker }) : Substring()
        if let activeFence = fence {
            if indentation <= 3, marker == activeFence, run.count >= fenceLength,
               trimmed.dropFirst(run.count).allSatisfy({ $0 == " " || $0 == "\t" }) {
                fence = nil
                fenceLength = 0
            }
            index += 1
            continue
        }
        if indentation <= 3, run.count >= 3 {
            fence = marker
            fenceLength = run.count
            index += 1
            continue
        }
        guard MarkdownSourceTable.parse(lines[index...index + 1].joined(separator: "\n")) != nil else {
            index += 1
            continue
        }
        var endLine = index + 1
        while endLine + 1 < lines.count, lines[endLine + 1].contains("|"), !lines[endLine + 1].isEmpty {
            endLine += 1
        }
        let end = starts[endLine] + (lines[endLine] as NSString).length
        let range = NSRange(location: starts[index], length: end - starts[index])
        if offset >= range.location, offset <= NSMaxRange(range),
           let table = MarkdownSourceTable.parse(lines[index...endLine].joined(separator: "\n")) {
            return MarkdownSourceTableAtRange(range: range, table: table)
        }
        index = endLine + 1
    }
    return nil
}
