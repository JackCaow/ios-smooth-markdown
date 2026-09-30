import Foundation

public enum NativeMarkdownCodeSemantics {
    public static func text(source: String, fenced: Bool) -> String {
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if fenced {
            guard let opening = lines.first else { return "" }
            let indent = opening.prefix(while: { $0 == " " }).count
            let fence = opening.dropFirst(indent).prefix(while: { $0 == "`" || $0 == "~" })
            lines.removeFirst()
            if let last = lines.last, let marker = fence.first {
                let closing = last.drop(while: { $0 == " " })
                let run = closing.prefix(while: { $0 == marker }).count
                if last.count - closing.count <= 3, run >= fence.count,
                   closing.dropFirst(run).allSatisfy({ $0 == " " || $0 == "\t" }) {
                    lines.removeLast()
                }
            }
            lines = lines.map { removingIndent($0, columns: indent) }
        } else {
            while lines.last?.allSatisfy({ $0 == " " || $0 == "\t" }) == true { lines.removeLast() }
            lines = lines.map { removingIndent($0, columns: 4) }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private static func removingIndent(_ line: String, columns: Int) -> String {
        var index = line.startIndex
        var width = 0
        while index < line.endIndex, width < columns {
            let character = line[index]
            guard character == " " || character == "\t" else { break }
            width += character == "\t" ? 4 - width % 4 : 1
            index = line.index(after: index)
        }
        return String(repeating: " ", count: max(0, width - columns)) + line[index...]
    }
}
