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
    public let continuations: [MarkdownSourceListContinuation]

    public var kind: Kind {
        if taskMarker != nil { return .task }
        return marker.first?.isNumber == true ? .ordered : .unordered
    }
    public var checked: Bool? { taskMarker.map { $0 == "[x]" || $0 == "[X]" } }
    public var source: String {
        indent + marker + spacing + (taskMarker ?? "") + taskSpacing + content + lineEnding
            + continuations.map(\.source).joined()
    }

    fileprivate func replacingContent(_ value: String) -> Self? {
        guard !value.contains("\n"), !value.contains("\r") else { return nil }
        return .init(indent: indent, marker: marker, spacing: spacing, taskMarker: taskMarker,
                     taskSpacing: taskSpacing, content: value, lineEnding: lineEnding,
                     continuations: continuations)
    }

    fileprivate func settingChecked(_ checked: Bool) -> Self? {
        guard let taskMarker else { return nil }
        let nextMarker = checked ? (taskMarker == "[X]" ? "[X]" : "[x]") : "[ ]"
        return .init(indent: indent, marker: marker, spacing: spacing, taskMarker: nextMarker,
                     taskSpacing: taskSpacing, content: content, lineEnding: lineEnding,
                     continuations: continuations)
    }

    fileprivate func replacingContinuation(at index: Int, with value: String) -> Self? {
        guard continuations.indices.contains(index), !value.contains("\n"), !value.contains("\r") else { return nil }
        var next = continuations
        next[index] = next[index].replacingContent(value)
        return .init(indent: indent, marker: marker, spacing: spacing, taskMarker: taskMarker,
                     taskSpacing: taskSpacing, content: content, lineEnding: lineEnding,
                     continuations: next)
    }

    fileprivate init(indent: String, marker: String, spacing: String, taskMarker: String?,
                     taskSpacing: String, content: String, lineEnding: String,
                     continuations: [MarkdownSourceListContinuation] = []) {
        self.indent = indent
        self.marker = marker
        self.spacing = spacing
        self.taskMarker = taskMarker
        self.taskSpacing = taskSpacing
        self.content = content
        self.lineEnding = lineEnding
        self.continuations = continuations
    }
}

/// An indented paragraph continuation belonging to the preceding list item.
public struct MarkdownSourceListContinuation: Equatable {
    public let indent: String
    public let content: String
    public let lineEnding: String

    public var source: String { indent + content + lineEnding }

    fileprivate func replacingContent(_ value: String) -> Self {
        .init(indent: indent, content: value, lineEnding: lineEnding)
    }
}

/// Source-preserving list items, including nested items and indented paragraph continuations.
public struct MarkdownSourceList: Equatable {
    public let items: [MarkdownSourceListItem]

    public func toMarkdown() -> String { items.map(\.source).joined() }

    /// Deletes a contiguous run of siblings while retaining every other item's exact source.
    /// Nested descendants are never silently detached from a selected parent.
    public func removingSiblingItems(from first: Int, to last: Int) -> Self? {
        guard items.indices.contains(first), items.indices.contains(last), first != last else { return nil }
        let range = min(first, last)...max(first, last)
        guard range.count < items.count else { return nil }
        let indent = items[range.lowerBound].indent
        guard items[range].allSatisfy({ $0.indent == indent }) else { return nil }
        var next = items
        next.removeSubrange(range)
        return .init(items: next)
    }

    public func replacingItemContent(at index: Int, with content: String) -> Self? {
        guard items.indices.contains(index), let item = items[index].replacingContent(content) else { return nil }
        var next = items
        next[index] = item
        return .init(items: next)
    }

    /// Adds a sibling after this item's nested subtree, retaining the surrounding source lines.
    public func insertingEmptyItem(after index: Int) -> Self? {
        guard items.indices.contains(index) else { return nil }
        let item = items[index]
        let width = Self.indentationWidth(item.indent)
        var insertion = index + 1
        while insertion < items.count && Self.indentationWidth(items[insertion].indent) > width {
            insertion += 1
        }
        let newline = items.lazy.map(\.lineEnding).first(where: { !$0.isEmpty }) ?? "\n"
        let marker: String
        if item.kind == .ordered, let number = Int(item.marker.dropLast()), let delimiter = item.marker.last {
            marker = String(number + 1) + String(delimiter)
        } else {
            marker = item.marker
        }
        let sibling = MarkdownSourceListItem(indent: item.indent, marker: marker, spacing: item.spacing,
                                             taskMarker: item.taskMarker.map { _ in "[ ]" },
                                             taskSpacing: item.taskSpacing, content: "",
                                             lineEnding: insertion < items.count ? newline : item.lineEnding)
        var next = items
        if let lastContinuation = next[insertion - 1].continuations.last,
           lastContinuation.lineEnding.isEmpty { return nil }
        if next[insertion - 1].lineEnding.isEmpty {
            let last = next[insertion - 1]
            next[insertion - 1] = .init(indent: last.indent, marker: last.marker, spacing: last.spacing,
                                         taskMarker: last.taskMarker, taskSpacing: last.taskSpacing,
                                         content: last.content, lineEnding: newline,
                                         continuations: last.continuations)
        }
        next.insert(sibling, at: insertion)
        return .init(items: next)
    }

    /// Splits a leaf item's text at a UTF-16 caret offset. A continuation or
    /// nested subtree needs a separate semantic split to assign its children.
    public func splittingItem(at index: Int, contentOffset: Int) -> Self? {
        guard items.indices.contains(index), items[index].continuations.isEmpty,
              !hasNestedItems(at: index) else { return nil }
        let item = items[index]
        let length = (item.content as NSString).length
        guard contentOffset >= 0, contentOffset < length,
              let prefixRange = Range(NSRange(location: 0, length: contentOffset), in: item.content)
        else { return nil }
        let prefix = String(item.content[prefixRange])
        let suffix = String(item.content[prefixRange.upperBound...])
        // Foundation can bridge a range ending inside a surrogate pair. Do
        // not replace one character with two replacement characters.
        guard (prefix as NSString).length == contentOffset,
              prefix + suffix == item.content else { return nil }
        guard let inserted = insertingEmptyItem(after: index),
              let before = inserted.items[index].replacingContent(prefix),
              let after = inserted.items[index + 1].replacingContent(suffix) else { return nil }
        var next = inserted.items
        next[index] = before
        next[index + 1] = after
        return .init(items: next)
    }

    public func settingTaskChecked(at index: Int, to checked: Bool) -> Self? {
        guard items.indices.contains(index), let item = items[index].settingChecked(checked) else { return nil }
        var next = items
        next[index] = item
        return .init(items: next)
    }

    public func replacingContinuationContent(at itemIndex: Int, lineIndex: Int, with content: String) -> Self? {
        guard items.indices.contains(itemIndex),
              let item = items[itemIndex].replacingContinuation(at: lineIndex, with: content) else { return nil }
        var next = items
        next[itemIndex] = item
        return .init(items: next)
    }

    /// Moves an item and its descendants under the preceding item at the same level.
    public func indentingItem(at index: Int) -> Self? {
        guard items.indices.contains(index), index > 0 else { return nil }
        let currentWidth = Self.indentationWidth(items[index].indent)
        guard let parentIndex = (0..<index).reversed().first(where: {
            Self.indentationWidth(items[$0].indent) == currentWidth
        }) else { return nil }
        let parent = items[parentIndex]
        let contentColumn = Self.indentationWidth(parent.indent + parent.marker + parent.spacing
                                                + (parent.taskMarker ?? "") + parent.taskSpacing)
        guard contentColumn > currentWidth else { return nil }
        return shiftingSubtree(at: index, by: contentColumn - currentWidth)
    }

    /// Moves an item and its descendants to the level of its nearest ancestor.
    public func outdentingItem(at index: Int) -> Self? {
        guard items.indices.contains(index) else { return nil }
        let currentWidth = Self.indentationWidth(items[index].indent)
        guard currentWidth > 0 else { return nil }
        let parentWidth = (0..<index).reversed().lazy.map { Self.indentationWidth(items[$0].indent) }
            .first(where: { $0 < currentWidth }) ?? 0
        return shiftingSubtree(at: index, by: parentWidth - currentWidth)
    }

    /// Distinguishes a nested item from a root item whose source starts with spaces.
    func isNestedItem(at index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        let currentWidth = Self.indentationWidth(items[index].indent)
        return (0..<index).reversed().contains { Self.indentationWidth(items[$0].indent) < currentWidth }
    }

    /// An empty item with child items still owns content and must not exit its list.
    func hasNestedItems(at index: Int) -> Bool {
        guard items.indices.contains(index), items.indices.contains(index + 1) else { return false }
        return Self.indentationWidth(items[index + 1].indent) > Self.indentationWidth(items[index].indent)
    }

    private func shiftingSubtree(at index: Int, by columns: Int) -> Self? {
        guard columns != 0 else { return nil }
        let baseWidth = Self.indentationWidth(items[index].indent)
        var next = items
        var end = index + 1
        while end < items.count && Self.indentationWidth(items[end].indent) > baseWidth { end += 1 }
        for position in index..<end {
            let item = items[position]
            guard let indent = Self.shiftingIndent(item.indent, by: columns) else { return nil }
            let continuations = item.continuations.compactMap { line -> MarkdownSourceListContinuation? in
                guard let shifted = Self.shiftingIndent(line.indent, by: columns) else { return nil }
                return .init(indent: shifted, content: line.content, lineEnding: line.lineEnding)
            }
            guard continuations.count == item.continuations.count else { return nil }
            next[position] = .init(indent: indent, marker: item.marker, spacing: item.spacing,
                                   taskMarker: item.taskMarker, taskSpacing: item.taskSpacing,
                                   content: item.content, lineEnding: item.lineEnding,
                                   continuations: continuations)
        }
        return .init(items: next)
    }

    private static func shiftingIndent(_ indent: String, by columns: Int) -> String? {
        if columns > 0 { return indent + String(repeating: " ", count: columns) }
        let target = indentationWidth(indent) + columns
        guard target >= 0 else { return nil }
        var result = ""
        for character in indent {
            let next = indentationWidth(result + String(character))
            if next > target { break }
            result.append(character)
        }
        return result + String(repeating: " ", count: target - indentationWidth(result))
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
            if let parts = match(#"^([ \t]*)([-+*]|[0-9]+[.)])([ \t]+)(.*)$"#, line) {
                let remainder = parts[4]
                let task = match(#"^(\[[ xX]\])([ \t]*)(.*)$"#, remainder)
                let validTask = task != nil && (!task![2].isEmpty || task![3].isEmpty)
                items.append(.init(indent: parts[1], marker: parts[2], spacing: parts[3],
                                   taskMarker: validTask ? task![1] : nil,
                                   taskSpacing: validTask ? task![2] : "",
                                   content: validTask ? task![3] : remainder, lineEnding: ending))
            } else if let parts = match(#"^([ \t]+)(.*)$"#, line), let previous = items.last {
                // A paragraph continuation must reach the preceding marker's content column.
                let contentColumn = indentationWidth(previous.indent + previous.marker + previous.spacing
                                                    + (previous.taskMarker ?? "") + previous.taskSpacing)
                guard indentationWidth(parts[1]) >= contentColumn else { return nil }
                let continuation = MarkdownSourceListContinuation(indent: parts[1], content: parts[2], lineEnding: ending)
                items[items.count - 1] = .init(indent: previous.indent, marker: previous.marker,
                                               spacing: previous.spacing, taskMarker: previous.taskMarker,
                                               taskSpacing: previous.taskSpacing, content: previous.content,
                                               lineEnding: previous.lineEnding,
                                               continuations: previous.continuations + [continuation])
            } else { return nil }
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

    private static func indentationWidth(_ whitespace: String) -> Int {
        whitespace.reduce(0) { width, character in character == "\t" ? ((width / 4) + 1) * 4 : width + 1 }
    }
}
