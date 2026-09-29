import Foundation

/// The Flutter package's bounded, opt-in HTML tag and attribute policy.
public enum SafeHTML {
    public static let maxTagLength = 512
    public static let voidTags: Set<String> = ["br", "hr", "img"]
    private static let allowedSchemes: Set<String> = ["http", "https", "mailto", "tel"]

    public struct Tag: Equatable {
        public let name: String
        public let attributes: [String: String]
        public let isClosing: Bool
        public let isSelfClosing: Bool
        /// UTF-16 offset immediately after the closing `>`.
        public let end: Int
    }

    public struct ImageSpec: Equatable {
        public let source: String
        public let alt: String
        public let title: String?
        public let width: Double?
        public let height: Double?
    }

    public static func imageTag(_ source: String) -> ImageSpec? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tag = lexTag(trimmed), tag.name == "img", !tag.isClosing,
              tag.end == (trimmed as NSString).length,
              let imageSource = tag.attributes["src"], isSafeImageSource(imageSource) else { return nil }
        return ImageSpec(
            source: imageSource,
            alt: tag.attributes["alt"] ?? "",
            title: tag.attributes["title"],
            width: tag.attributes["width"].flatMap(dimension),
            height: tag.attributes["height"].flatMap(dimension)
        )
    }

    public static func imageAlt(_ source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tag = lexTag(trimmed), tag.name == "img", !tag.isClosing,
              tag.end == (trimmed as NSString).length else { return nil }
        return tag.attributes["alt"] ?? ""
    }

    public static func dimension(_ value: String) -> Double? {
        let normalized = value.trimmingCharacters(in: .whitespaces).lowercased()
        let number = normalized.hasSuffix("px") ? String(normalized.dropLast(2)).trimmingCharacters(in: .whitespaces) : normalized
        return Double(number).flatMap { $0 > 0 && $0 <= 10000 ? $0 : nil }
    }

    public enum Block: Equatable {
        case rule
        case container(name: String, content: String, alignment: String?, trailing: String)
    }

    public static func parseBlock(_ source: String) -> Block? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed as NSString
        guard let open = lexTag(trimmed) else { return nil }
        if open.name == "hr", !open.isClosing, open.end == text.length { return .rule }
        guard !open.isClosing, ["div", "p", "center", "blockquote"].contains(open.name) else { return nil }
        let declared = open.attributes["align"]?.lowercased()
        let alignment = open.name == "center" ? "center" : (["left", "center", "right"].contains(declared ?? "") ? declared : nil)
        if open.isSelfClosing { return .container(name: open.name, content: "", alignment: alignment, trailing: "") }
        var depth = 1
        var cursor = open.end
        while cursor < text.length {
            let next = text.range(of: "<", range: NSRange(location: cursor, length: text.length - cursor)).location
            if next == NSNotFound { break }
            guard let tag = lexTag(trimmed, at: next) else { cursor = next + 1; continue }
            if tag.name == open.name {
                if tag.isClosing { depth -= 1 } else if !tag.isSelfClosing { depth += 1 }
                if depth == 0 {
                    return .container(
                        name: open.name,
                        content: text.substring(with: NSRange(location: open.end, length: next - open.end)),
                        alignment: alignment,
                        trailing: text.substring(from: tag.end)
                    )
                }
            }
            cursor = tag.end
        }
        return .container(name: open.name, content: text.substring(from: open.end), alignment: alignment, trailing: "")
    }

    public static func lexTag(_ text: String, at start: Int = 0) -> Tag? {
        let source = text as NSString
        let limit = min(source.length, start + maxTagLength)
        guard start >= 0, start < source.length, source.character(at: start) == 0x3C else { return nil }
        var index = start + 1
        let isClosing = index < limit && source.character(at: index) == 0x2F
        if isClosing { index += 1 }
        guard index < limit, isAsciiLetter(source.character(at: index)) else { return nil }
        let nameStart = index
        index += 1
        while index < limit, isNameChar(source.character(at: index)) { index += 1 }
        let name = source.substring(with: NSRange(location: nameStart, length: index - nameStart)).lowercased()
        var attributes: [String: String] = [:]
        while true {
            while index < limit, isSpace(source.character(at: index)) { index += 1 }
            guard index < limit else { return nil }
            let current = source.character(at: index)
            if current == 0x3E || current == 0x2F {
                let selfClosing = current == 0x2F
                if selfClosing && (index + 1 >= limit || source.character(at: index + 1) != 0x3E) { return nil }
                return Tag(name: name, attributes: attributes, isClosing: isClosing, isSelfClosing: selfClosing, end: index + (selfClosing ? 2 : 1))
            }
            guard isAsciiLetter(current) else { return nil }
            let attributeStart = index
            index += 1
            while index < limit, isNameChar(source.character(at: index)) { index += 1 }
            let attribute = source.substring(with: NSRange(location: attributeStart, length: index - attributeStart)).lowercased()
            while index < limit, isSpace(source.character(at: index)) { index += 1 }
            var value = ""
            if index < limit, source.character(at: index) == 0x3D {
                index += 1
                while index < limit, isSpace(source.character(at: index)) { index += 1 }
                guard index < limit else { return nil }
                let quote = source.character(at: index)
                if quote == 0x22 || quote == 0x27 {
                    index += 1
                    let valueStart = index
                    while index < limit, source.character(at: index) != quote { index += 1 }
                    guard index < limit else { return nil }
                    value = source.substring(with: NSRange(location: valueStart, length: index - valueStart))
                    index += 1
                } else {
                    let valueStart = index
                    while index < limit, !isSpace(source.character(at: index)), source.character(at: index) != 0x3E { index += 1 }
                    value = source.substring(with: NSRange(location: valueStart, length: index - valueStart))
                }
            }
            if attributes[attribute] == nil { attributes[attribute] = value }
        }
    }

    public static func isSafeLink(_ url: String) -> Bool {
        let cleaned = stripUnsafeURLCharacters(url)
        guard !cleaned.isEmpty else { return false }
        for (index, character) in cleaned.enumerated() {
            if character == "/" || character == "?" || character == "#" { return true }
            if character == ":" { return allowedSchemes.contains(String(cleaned.prefix(index)).lowercased()) }
        }
        return true
    }

    public static func isSafeImageSource(_ url: String) -> Bool {
        let cleaned = stripUnsafeURLCharacters(url)
        guard !cleaned.isEmpty else { return false }
        for (index, character) in cleaned.enumerated() {
            if character == "/" || character == "?" || character == "#" { break }
            if character == ":" {
                return ["http", "https"].contains(String(cleaned.prefix(index)).lowercased())
            }
        }
        return !cleaned.hasPrefix("//")
    }

    public static func color(_ value: String) -> UInt32? {
        let normalized = value.trimmingCharacters(in: .whitespaces).lowercased()
        let named: [String: UInt32] = [
            "aqua": 0x00FFFF, "black": 0x000000, "blue": 0x0000FF,
            "brown": 0xA52A2A, "cyan": 0x00FFFF, "fuchsia": 0xFF00FF,
            "gold": 0xFFD700, "gray": 0x808080, "green": 0x008000,
            "grey": 0x808080, "indigo": 0x4B0082, "lime": 0x00FF00,
            "magenta": 0xFF00FF, "maroon": 0x800000, "navy": 0x000080,
            "olive": 0x808000, "orange": 0xFFA500, "pink": 0xFFC0CB,
            "purple": 0x800080, "red": 0xFF0000, "silver": 0xC0C0C0,
            "teal": 0x008080, "violet": 0xEE82EE, "white": 0xFFFFFF,
            "yellow": 0xFFFF00,
        ]
        let rgb: UInt32?
        if normalized.hasPrefix("#") {
            let hex = String(normalized.dropFirst())
            let expanded = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
            guard expanded.count == 6 else { return nil }
            rgb = UInt32(expanded, radix: 16)
        } else {
            rgb = named[normalized]
        }
        return rgb.map { 0xFF000000 | $0 }
    }

    public static func fontSize(_ value: String) -> Double? {
        let normalized = value.trimmingCharacters(in: .whitespaces).lowercased()
        let size: Double?
        if normalized.hasSuffix("px") {
            size = Double(normalized.dropLast(2).trimmingCharacters(in: .whitespaces))
        } else if normalized.hasSuffix("pt") {
            size = Double(normalized.dropLast(2).trimmingCharacters(in: .whitespaces)).map { $0 * 4 / 3 }
        } else {
            size = Double(normalized)
        }
        return size.flatMap { (4...128).contains($0) ? $0 : nil }
    }

    public static func legacyFontSize(_ value: String) -> Double? {
        let normalized = value.trimmingCharacters(in: .whitespaces)
        if normalized.hasPrefix("+") || normalized.hasPrefix("-") { return nil }
        let sizes: [Double] = [10, 13, 16, 18, 24, 32, 48]
        guard let index = Int(normalized), (1...7).contains(index) else { return nil }
        return sizes[index - 1]
    }

    public static func cssDeclarations(_ style: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in style.split(separator: ";") {
            guard let separator = part.firstIndex(of: ":") else { continue }
            let name = part[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = part[part.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !value.isEmpty, result[name] == nil { result[name] = value }
        }
        return result
    }

    /// Withholds a trailing partial tag outside Markdown code until `>` arrives.
    public static func safeRenderPrefix(_ full: String) -> String {
        let source = full as NSString
        let lastGreaterThan = source.range(of: ">", options: .backwards).location
        let boundary = lastGreaterThan == NSNotFound ? 0 : lastGreaterThan + 1
        if source.range(of: "<", range: NSRange(location: boundary, length: source.length - boundary)).location == NSNotFound {
            return full
        }
        var lineStart = 0
        var fenceMarker: Character?
        var fenceLength = 0
        for line in full.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.first
            let run = (marker == "`" || marker == "~") ? trimmed.prefix(while: { $0 == marker }) : Substring()
            if let activeFence = fenceMarker {
                if marker == activeFence, run.count >= fenceLength, trimmed.dropFirst(run.count).isEmpty {
                    fenceMarker = nil
                    fenceLength = 0
                }
            } else if run.count >= 3 {
                fenceMarker = marker
                fenceLength = run.count
            } else {
                let text = line as NSString
                var spans: [(Int, Int)] = []
                var open = -1
                var cursor = 0
                while cursor < text.length {
                    let code = text.character(at: cursor)
                    if code == 0x5C { cursor += 2 }
                    else if code == 0x60 {
                        if open < 0 { open = cursor } else { spans.append((open, cursor)); open = -1 }
                        cursor += 1
                    } else { cursor += 1 }
                }
                for index in 0..<text.length {
                    let absolute = lineStart + index
                    if absolute > (lastGreaterThan == NSNotFound ? -1 : lastGreaterThan),
                       text.character(at: index) == 0x3C,
                       !spans.contains(where: { index > $0.0 && index < $0.1 }),
                       mayStartTag(source, at: absolute) {
                        return source.substring(to: absolute)
                    }
                }
            }
            lineStart += (line as NSString).length + 1
        }
        return full
    }

    private static func mayStartTag(_ source: NSString, at index: Int) -> Bool {
        guard index + 1 < source.length else { return true }
        let code = source.character(at: index + 1)
        return isAsciiLetter(code) || code == 0x2F
    }

    private static func stripUnsafeURLCharacters(_ url: String) -> String {
        String(String.UnicodeScalarView(url.unicodeScalars.filter { $0.value > 0x20 }))
    }
    private static func isAsciiLetter(_ code: unichar) -> Bool { (0x41...0x5A).contains(code) || (0x61...0x7A).contains(code) }
    private static func isNameChar(_ code: unichar) -> Bool { isAsciiLetter(code) || (0x30...0x39).contains(code) || code == 0x2D }
    private static func isSpace(_ code: unichar) -> Bool { code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D }
}
