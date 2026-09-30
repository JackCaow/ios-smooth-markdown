import Foundation

/// Resolves CommonMark delimiter runs after code spans and link labels have been tokenized.
enum NativeMarkdownEmphasisParser {
    private final class Token {
        var node: NativeMarkdownNode?
        weak var previous: Token?
        var next: Token?
        init(_ node: NativeMarkdownNode? = nil) { self.node = node }
    }

    private final class Delimiter {
        let token: Token
        let marker: Character
        let originalCount: Int
        let opens: Bool
        let closes: Bool
        var count: Int
        var active = true

        init(token: Token, marker: Character, count: Int, opens: Bool, closes: Bool) {
            self.token = token
            self.marker = marker
            self.originalCount = count
            self.count = count
            self.opens = opens
            self.closes = closes
        }
    }

    static func resolve(_ nodes: [NativeMarkdownNode], source: String, offset: Int) -> [NativeMarkdownNode] {
        let text = source as NSString
        let characters = Array(source)
        var positions = [Int: Int]()
        var position = 0
        for (index, character) in characters.enumerated() {
            positions[position] = index
            position += String(character).utf16.count
        }
        positions[position] = characters.count

        func punctuation(_ character: Character?) -> Bool {
            guard let character else { return false }
            return character.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
            }
        }
        func flags(_ node: NativeMarkdownNode, marker: Character) -> (Bool, Bool) {
            let start = positions[node.sourceRange.location - offset] ?? 0
            let end = positions[NSMaxRange(node.sourceRange) - offset] ?? characters.count
            let before = start > 0 ? characters[start - 1] : nil
            let after = end < characters.count ? characters[end] : nil
            let beforeSpace = before?.isWhitespace ?? true
            let afterSpace = after?.isWhitespace ?? true
            let beforePunctuation = punctuation(before)
            let afterPunctuation = punctuation(after)
            let left = !afterSpace && (!afterPunctuation || beforeSpace || beforePunctuation)
            let right = !beforeSpace && (!beforePunctuation || afterSpace || afterPunctuation)
            if marker == "_" {
                return (left && (!right || beforePunctuation), right && (!left || afterPunctuation))
            }
            return (left, right)
        }
        let head = Token()
        var tail = head
        var delimiters: [Delimiter] = []
        for node in nodes {
            let token = Token(node)
            token.previous = tail
            tail.next = token
            tail = token
            if node.kind == .text, let marker = node.source.first,
               marker == "*" || marker == "_", node.source.allSatisfy({ $0 == marker }) {
                let (opens, closes) = flags(node, marker: marker)
                delimiters.append(Delimiter(token: token, marker: marker, count: node.source.count,
                                            opens: opens, closes: closes))
            }
        }
        func remove(_ token: Token) {
            token.previous?.next = token.next
            token.next?.previous = token.previous
            token.previous = nil
            token.next = nil
        }
        func spelling(_ range: NSRange) -> String {
            text.substring(with: NSRange(location: range.location - offset, length: range.length))
        }
        for closerIndex in delimiters.indices {
            let closer = delimiters[closerIndex]
            guard closer.active, closer.closes else { continue }
            while closer.count > 0 {
                let openerIndex = (0..<closerIndex).reversed().first { index in
                    let opener = delimiters[index]
                    guard opener.active, opener.opens, opener.count > 0,
                          opener.marker == closer.marker else { return false }
                    let ruleOfThree = (opener.closes || closer.opens) &&
                        (opener.originalCount + closer.originalCount) % 3 == 0 &&
                        (opener.originalCount % 3 != 0 || closer.originalCount % 3 != 0)
                    return !ruleOfThree
                }
                guard let openerIndex else { break }
                let opener = delimiters[openerIndex]
                guard let openNode = opener.token.node, let closeNode = closer.token.node else { break }
                let used = opener.count >= 2 && closer.count >= 2 ? 2 : 1
                let lower = NSMaxRange(openNode.sourceRange) - used
                let upper = closeNode.sourceRange.location + used
                let range = NSRange(location: lower, length: upper - lower)
                var children: [NativeMarkdownNode] = []
                var cursor = opener.token.next
                while let token = cursor, token !== closer.token {
                    if let node = token.node { children.append(node) }
                    cursor = token.next
                }
                let wrapper = Token(.init(kind: used == 2 ? .strong : .emphasis,
                                          source: spelling(range), sourceRange: range, children: children))
                opener.token.next = wrapper
                wrapper.previous = opener.token
                wrapper.next = closer.token
                closer.token.previous = wrapper
                for index in (openerIndex + 1)..<closerIndex { delimiters[index].active = false }
                opener.count -= used
                closer.count -= used
                if opener.count == 0 {
                    opener.active = false
                    remove(opener.token)
                } else {
                    let remaining = NSRange(location: openNode.sourceRange.location, length: opener.count)
                    opener.token.node = .init(kind: .text, source: spelling(remaining), sourceRange: remaining)
                }
                if closer.count == 0 {
                    closer.active = false
                    remove(closer.token)
                } else {
                    let remaining = NSRange(location: upper, length: closer.count)
                    closer.token.node = .init(kind: .text, source: spelling(remaining), sourceRange: remaining)
                }
            }
        }
        var result: [NativeMarkdownNode] = []
        var cursor = head.next
        while let token = cursor {
            if let node = token.node {
                if node.kind == .text, let previous = result.last, previous.kind == .text,
                   NSMaxRange(previous.sourceRange) == node.sourceRange.location {
                    result[result.count - 1] = .init(kind: .text, source: previous.source + node.source,
                        sourceRange: NSRange(location: previous.sourceRange.location,
                                             length: previous.sourceRange.length + node.sourceRange.length))
                } else {
                    result.append(node)
                }
            }
            cursor = token.next
        }
        return result
    }
}
