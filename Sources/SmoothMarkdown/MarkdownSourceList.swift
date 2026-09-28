import Foundation

/// One physical list line. Keeping its marker, spacing, and line ending makes edits lossless.
public struct MarkdownSourceListItem: Equatable {
    public enum Kind: Equatable { case unordered, ordered, task }

    public let indent: String
    public let marker: String
    public let spacing: String
    public let taskMarker: String?
    public let taskSpacing: String
    public let content: String
    public let lineEnding: String

    public var kind: Kind {
        if taskMarker != nil { return .task }
        return marker.first?.isNumber == true ? .ordered : .unordered
    }
    public var checked: Bool? { taskMarker.map { $0 == "[x]" || $0 == "[X]" } }
    public var source: String { indent + marker + spacing + (taskMarker ?? "") + taskSpacing + content + lineEnding }

    fileprivate func replacingContent(_ value: String) -> Self? {
        guard !value.contains("\n"), !value.contains("\r") else { return nil }
        return .init(indent: indent, marker: marker, spacing: spacing, taskMarker: taskMarker,
                     taskSpacing: taskSpacing, content: value, lineEnding: lineEnding)
    }

    fileprivate func settingChecked(_ checked: Bool) -> Self? {
        guard let taskMarker else { return nil }
        let nextMarker = checked ? (taskMarker == "[X]" ? "[X]" : "[x]") : "[ ]"
        return .init(indent: indent, marker: marker, spacing: spacing, taskMarker: nextMarker,
                     taskSpacing: taskSpacing, content: content, lineEnding: lineEnding)
    }

    fileprivate init(indent: String, marker: String, spacing: String, taskMarker: String?,
                     taskSpacing: String, content: String, lineEnding: String) {
        self.indent = indent
        self.marker = marker
        self.spacing = spacing
        self.taskMarker = taskMarker
        self.taskSpacing = taskSpacing
        self.content = content
        self.lineEnding = lineEnding
    }
}

/// A deliberately bounded, one-line-per-item list model. Complex list bodies remain raw source.
public struct MarkdownSourceList: Equatable {
    public let items: [MarkdownSourceListItem]

    public func toMarkdown() -> String { items.map(\.source).joined() }

    public func replacingItemContent(at index: Int, with content: String) -> Self? {
        guard items.indices.contains(index), let item = items[index].replacingContent(content) else { return nil }
        var next = items
        next[index] = item
        return .init(items: next)
    }

    public func settingTaskChecked(at index: Int, to checked: Bool) -> Self? {
        guard items.indices.contains(index), let item = items[index].settingChecked(checked) else { return nil }
        var next = items
        next[index] = item
        return .init(items: next)
    }

    public static func parse(_ source: String) -> Self? {
        guard !source.isEmpty else { return nil }
        let components = source.components(separatedBy: "\n")
        var items: [MarkdownSourceListItem] = []
        for index in components.indices {
            if index == components.count - 1 && components[index].isEmpty { break }
            let component = components[index]
            let hasNewline = index < components.count - 1
            let hasCR = component.hasSuffix("\r")
            let line = hasCR ? String(component.dropLast()) : component
            let ending = hasNewline ? (hasCR ? "\r\n" : "\n") : ""
            guard let parts = match(#"^([ \t]*)([-+*]|[0-9]+[.)])([ \t]+)(.*)$"#, line) else { return nil }
            let remainder = parts[4]
            let task = match(#"^(\[[ xX]\])([ \t]*)(.*)$"#, remainder)
            let validTask = task != nil && (!task![2].isEmpty || task![3].isEmpty)
            items.append(.init(indent: parts[1], marker: parts[2], spacing: parts[3],
                               taskMarker: validTask ? task![1] : nil,
                               taskSpacing: validTask ? task![2] : "",
                               content: validTask ? task![3] : remainder, lineEnding: ending))
        }
        return items.isEmpty ? nil : .init(items: items)
    }

    static func isListStart(_ line: String) -> Bool {
        match(#"^[ \t]{0,3}(?:[-+*]|[0-9]+[.)])[ \t]+"#, line) != nil
    }

    private static func match(_ pattern: String, _ value: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsValue = value as NSString
        guard let result = expression.firstMatch(in: value, range: NSRange(location: 0, length: nsValue.length)) else { return nil }
        return (0..<result.numberOfRanges).map { result.range(at: $0).location == NSNotFound ? "" : nsValue.substring(with: result.range(at: $0)) }
    }
}
