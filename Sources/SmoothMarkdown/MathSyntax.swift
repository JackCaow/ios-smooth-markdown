import Foundation
#if canImport(SmoothMarkdownCore)
@_spi(ReaderInternals) import SmoothMarkdownCore
#endif

/// Flutter's dollar-delimited math extension, kept separate from CommonMark parsing.
enum MathSyntax {
    enum Section: Equatable {
        case markdown(String)
        case block(String)
    }

    enum InlinePart: Equatable {
        case text(String)
        case math(String)
    }

    static func sections(_ source: String, useNativeProjection: Bool = true) -> [Section] {
        if useNativeProjection, let root = NativeMarkdownExtensionProjection.parse(source) {
            let nodes = root.children.filter { $0.kind == .blockMath }
            let original = source as NSString
            var sections: [Section] = []; var cursor = 0
            for node in nodes {
                if node.sourceRange.location > cursor {
                    sections.append(.markdown(boundaryText(original.substring(with: NSRange(location: cursor, length: node.sourceRange.location - cursor)))))
                }
                var content = node.source.trimmingCharacters(in: .whitespacesAndNewlines)
                if content.hasPrefix("$$") || content.hasPrefix("\\[") { content = String(content.dropFirst(2)) }
                if content.hasSuffix("$$") || content.hasSuffix("\\]") { content = String(content.dropLast(2)) }
                sections.append(.block(node.literalText ?? content.trimmingCharacters(in: .whitespacesAndNewlines)))
                cursor = NSMaxRange(node.sourceRange)
                // A closed display formula owns its delimiters; consume only
                // an immediately following line ending, retaining any prose.
                if cursor < original.length, original.character(at: cursor) == 13 {
                    cursor += 1
                    if cursor < original.length, original.character(at: cursor) == 10 { cursor += 1 }
                } else if cursor < original.length, original.character(at: cursor) == 10 { cursor += 1 }
            }
            if cursor < original.length { sections.append(.markdown(original.substring(from: cursor))) }
            return sections
        }
        let lines = source.components(separatedBy: "\n")
        var result: [Section] = []
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
            guard trimmed.hasPrefix("$$") || backslashMathOpen(trimmed) else {
                ordinary.append(line)
                index += 1
                continue
            }
            if !ordinary.isEmpty {
                result.append(.markdown(ordinary.joined(separator: "\n")))
                ordinary.removeAll()
            }
            let closing = trimmed.hasPrefix("$$") ? "$$" : "\\]"
            var body = String(trimmed.dropFirst(2))
            index += 1
            while mathClosing(body, delimiter: closing) == nil, index < lines.count {
                body += "\n" + lines[index]; index += 1
            }
            if let close = mathClosing(body, delimiter: closing) {
                result.append(.block(String(body[..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)))
                let trailing = String(body[close.upperBound...])
                if closing == #"\]"#, !trailing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { ordinary.append(trailing) }
            } else {
                result.append(.block(body.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        if !ordinary.isEmpty { result.append(.markdown(ordinary.joined(separator: "\n"))) }
        return result
    }

    static func inlineParts(in source: String, useNativeProjection: Bool = true) -> [InlinePart] {
        if useNativeProjection, let root = NativeMarkdownExtensionProjection.parse(source) {
            func mathNodes(_ node: NativeMarkdownNode) -> [NativeMarkdownNode] {
                node.kind == .inlineMath ? [node] : node.children.flatMap(mathNodes)
            }
            let original = source as NSString
            var result: [InlinePart] = []; var cursor = 0
            for node in mathNodes(root) {
                if node.sourceRange.location > cursor { result.append(.text(original.substring(with: NSRange(location: cursor, length: node.sourceRange.location - cursor)))) }
                result.append(.math(node.literalText ?? String(node.source.dropFirst(node.source.hasPrefix("\\(") ? 2 : 1).dropLast(node.source.hasPrefix("\\(") ? 2 : 1))))
                cursor = NSMaxRange(node.sourceRange)
            }
            if cursor < original.length { result.append(.text(original.substring(from: cursor))) }
            return result
        }
        var result: [InlinePart] = []
        var ordinary = ""
        var cursor = source.startIndex
        while cursor < source.endIndex {
            if source[cursor...].hasPrefix(#"\\"#) {
                ordinary += #"\\"#; cursor = source.index(cursor, offsetBy: 2); continue
            }
            if source[cursor...].hasPrefix(#"\("#) {
                let bodyStart = source.index(cursor, offsetBy: 2)
                var end = bodyStart
                while end < source.endIndex {
                    if source[end...].hasPrefix(#"\)"#) { break }
                    if source[end] == "\\" {
                        end = source.index(after: end)
                        if end < source.endIndex { end = source.index(after: end) }
                    } else { end = source.index(after: end) }
                }
                if end > bodyStart, end < source.endIndex {
                    if !ordinary.isEmpty { result.append(.text(ordinary)); ordinary = "" }
                    result.append(.math(String(source[bodyStart..<end])))
                    cursor = source.index(end, offsetBy: 2); continue
                }
            }
            guard source[cursor] == "$" else {
                ordinary.append(source[cursor])
                cursor = source.index(after: cursor)
                continue
            }
            let bodyStart = source.index(after: cursor)
            if bodyStart < source.endIndex, source[bodyStart] != "$",
               let end = source[bodyStart...].firstIndex(of: "$"), end > bodyStart {
                if !ordinary.isEmpty { result.append(.text(ordinary)); ordinary = "" }
                result.append(.math(String(source[bodyStart..<end])))
                cursor = source.index(after: end)
            } else {
                ordinary.append("$")
                cursor = bodyStart
            }
        }
        if !ordinary.isEmpty { result.append(.text(ordinary)) }
        return result
    }

    private static func backslashMathOpen(_ text: String) -> Bool {
        guard text.hasPrefix(#"\["#) else { return false }
        let payload = String(text.dropFirst(2))
        if mathClosing(payload, delimiter: #"\]"#) != nil { return true }
        var depth = 0
        var escaped = false
        for ch in payload {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true }
            else if ch == "[" { depth += 1 }
            else if ch == "]" {
                if depth == 0 { return false }
                depth -= 1
            }
        }
        return true
    }

    private static func mathClosing(_ source: String, delimiter: String) -> Range<String.Index>? {
        if delimiter == "$$" { return source.range(of: delimiter) }
        var cursor = source.startIndex
        while cursor < source.endIndex, let found = source.range(of: delimiter, range: cursor..<source.endIndex) {
            var before = found.lowerBound; var escapes = 0
            while before > source.startIndex {
                let previous = source.index(before: before)
                guard source[previous] == "\\" else { break }
                escapes += 1; before = previous
            }
            if escapes % 2 == 0 { return found }
            cursor = found.upperBound
        }
        return nil
    }

    private static func boundaryText(_ text: String) -> String {
        if text.hasSuffix("\r\n") { return String(text.dropLast(2)) }
        if text.hasSuffix("\n") { return String(text.dropLast()) }
        return text
    }

    private static func fenceRun(_ line: String) -> (Character, Int)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix(while: { $0 == first }).count
        return count >= 3 ? (first, count) : nil
    }
}
