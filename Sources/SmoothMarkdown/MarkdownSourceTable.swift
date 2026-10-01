import Foundation
#if canImport(SmoothMarkdownCore)
@_spi(ReaderInternals) import SmoothMarkdownCore
#endif

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
        var escaped = ""
        var slashCount = 0
        for character in text {
            if character == "|", slashCount.isMultiple(of: 2) { escaped.append("\\") }
            escaped.append(character)
            slashCount = character == "\\" ? slashCount + 1 : 0
        }
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
        guard let tree = NativeMarkdownExtensionProjection.parse(source),
              tree.children.count == 1, let table = tree.children.first, table.kind == .table else { return nil }
        return fromAST(table)
    }

    /// Cell source is supplied by the shared grammar. Only editable source
    /// formatting is projected here; no table delimiter or pipe grammar is scanned.
    static func fromAST(_ table: NativeMarkdownNode) -> Self {
        let headers = table.children.first?.children.map(\.source) ?? []
        let rows = table.children.dropFirst().map { row in
            headers.indices.map { column in column < row.children.count ? row.children[column].source : "" }
        }
        let alignments = headers.indices.map { column -> MarkdownTableAlignment? in
            guard column < table.tableAlignments.count else { return nil }
            switch table.tableAlignments[column] {
            case "left": return .left
            case "center": return .center
            case "right": return .right
            default: return nil
            }
        }
        return Self(headers: headers, rows: rows, alignments: alignments)
    }

}

public enum MarkdownTableAlignment: Equatable { case left, center, right }

struct MarkdownSourceTableAtRange {
    let range: NSRange
    let table: MarkdownSourceTable
}

/// Locates a GFM table containing a UTF-16 source offset, excluding fenced code blocks.
func findSourceTable(_ source: String, offset: Int) -> MarkdownSourceTableAtRange? {
    guard let tree = NativeMarkdownExtensionProjection.parse(source) else { return nil }
    let text = source as NSString
    for node in tree.children where node.kind == .table {
        var range = node.sourceRange
        // The controller leaves the original physical row terminator untouched.
        if node.source.hasSuffix("\r\n") { range.length -= 2 }
        else if node.source.hasSuffix("\n") || node.source.hasSuffix("\r") { range.length -= 1 }
        guard range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= text.length, offset >= range.location,
              offset <= NSMaxRange(range) else { continue }
        return .init(range: range, table: .fromAST(node))
    }
    return nil
}
