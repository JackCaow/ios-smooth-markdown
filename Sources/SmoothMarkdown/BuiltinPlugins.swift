import Foundation
import SwiftUI

public struct MentionPlugin: InlineParserPlugin {
    public let id = "mention"
    public let name = "Mention Plugin"
    public let priority = 10
    public let triggerCharacter: Character = "@"
    public init() {}

    public func canParse(_ text: String, at index: String.Index) -> Bool {
        guard index < text.endIndex, text[index] == "@" else { return false }
        let next = text.index(after: index)
        return next < text.endIndex && text[next].isASCIIAlpha
    }

    public func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        guard canParse(text, at: index) else { return nil }
        var end = text.index(after: index)
        while end < text.endIndex, text[end].isASCIIAlphaNumeric || text[end] == "_" || text[end] == "-" {
            end = text.index(after: end)
        }
        let username = String(text[text.index(after: index)..<end])
        return .init(consumed: text.distance(from: index, to: end), text: "@" + username, attributes: ["username": username])
    }

    public func render(_ match: InlinePluginMatch) -> AnyView {
        AnyView(SwiftUI.Text(match.text).foregroundColor(.blue).accessibilityLabel("Mention \(match.text)"))
    }
}

public struct HashtagPlugin: InlineParserPlugin {
    public let id = "hashtag"
    public let name = "Hashtag Plugin"
    public let priority = 10
    public let triggerCharacter: Character = "#"
    public init() {}

    public func canParse(_ text: String, at index: String.Index) -> Bool {
        guard index < text.endIndex, text[index] == "#" else { return false }
        let next = text.index(after: index)
        return next < text.endIndex && (text[next].isASCIIAlpha || text[next] == "_")
    }

    public func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        guard canParse(text, at: index) else { return nil }
        var end = text.index(after: index)
        while end < text.endIndex, text[end].isASCIIAlphaNumeric || text[end] == "_" {
            end = text.index(after: end)
        }
        let tag = String(text[text.index(after: index)..<end])
        return .init(consumed: text.distance(from: index, to: end), text: "#" + tag, attributes: ["tag": tag])
    }

    public func render(_ match: InlinePluginMatch) -> AnyView {
        AnyView(SwiftUI.Text(match.text).foregroundColor(.blue).accessibilityLabel("Hashtag \(match.text)"))
    }
}

public struct EmojiPlugin: InlineParserPlugin {
    public let id = "emoji"
    public let name = "Emoji Plugin"
    public let priority = 5
    public let triggerCharacter: Character = ":"
    public let customEmojis: [String: String]

    public init(customEmojis: [String: String] = [:]) {
        self.customEmojis = Dictionary(uniqueKeysWithValues: customEmojis.map { ($0.key.lowercased(), $0.value) })
    }

    public func canParse(_ text: String, at index: String.Index) -> Bool {
        guard index < text.endIndex, text[index] == ":" else { return false }
        let next = text.index(after: index)
        return next < text.endIndex && (text[next].isASCIIAlphaNumeric || text[next] == "_")
    }

    public func parse(_ text: String, at index: String.Index) -> InlinePluginMatch? {
        guard canParse(text, at: index) else { return nil }
        var end = text.index(after: index)
        let start = end
        while end < text.endIndex, text[end].isASCIIAlphaNumeric || text[end] == "_" {
            end = text.index(after: end)
        }
        guard end < text.endIndex, text[end] == ":" else { return nil }
        let shortcode = String(text[start..<end]).lowercased()
        guard let emoji = customEmojis[shortcode] ?? Self.defaultEmojis[shortcode] else { return nil }
        let after = text.index(after: end)
        return .init(consumed: text.distance(from: index, to: after), text: emoji,
                     attributes: ["shortcode": shortcode, "emoji": emoji])
    }

    public func render(_ match: InlinePluginMatch) -> AnyView {
        AnyView(SwiftUI.Text(match.text).accessibilityLabel(match.attributes["shortcode"] ?? match.text))
    }

    public static let defaultEmojis: [String: String] = [
        // Generated from Flutter Smooth Markdown's EmojiPlugin.defaultEmojis.
        "smile": "😄",
        "grinning": "😀",
        "laughing": "😆",
        "joy": "😂",
        "rofl": "🤣",
        "wink": "😉",
        "blush": "😊",
        "innocent": "😇",
        "heart_eyes": "😍",
        "star_struck": "🤩",
        "thinking": "🤔",
        "raised_eyebrow": "🤨",
        "neutral_face": "😐",
        "expressionless": "😑",
        "unamused": "😒",
        "roll_eyes": "🙄",
        "worried": "😟",
        "frowning": "😦",
        "cry": "😢",
        "sob": "😭",
        "angry": "😠",
        "rage": "😡",
        "skull": "💀",
        "poop": "💩",
        "clown": "🤡",
        "ghost": "👻",
        "alien": "👽",
        "robot": "🤖",
        "sunglasses": "😎",
        "nerd": "🤓",
        "thumbsup": "👍",
        "thumbsdown": "👎",
        "ok_hand": "👌",
        "pinching_hand": "🤏",
        "wave": "👋",
        "clap": "👏",
        "pray": "🙏",
        "handshake": "🤝",
        "muscle": "💪",
        "point_up": "☝️",
        "point_down": "👇",
        "point_left": "👈",
        "point_right": "👉",
        "middle_finger": "🖕",
        "raised_hand": "✋",
        "vulcan_salute": "🖖",
        "fist": "✊",
        "punch": "👊",
        "heart": "❤️",
        "orange_heart": "🧡",
        "yellow_heart": "💛",
        "green_heart": "💚",
        "blue_heart": "💙",
        "purple_heart": "💜",
        "black_heart": "🖤",
        "white_heart": "🤍",
        "broken_heart": "💔",
        "sparkling_heart": "💖",
        "heartbeat": "💓",
        "two_hearts": "💕",
        "kiss": "💋",
        "sun": "☀️",
        "moon": "🌙",
        "star": "⭐",
        "cloud": "☁️",
        "rain": "🌧️",
        "snow": "❄️",
        "fire": "🔥",
        "rainbow": "🌈",
        "ocean": "🌊",
        "earth": "🌍",
        "tree": "🌳",
        "flower": "🌸",
        "rose": "🌹",
        "dog": "🐶",
        "cat": "🐱",
        "mouse": "🐭",
        "rabbit": "🐰",
        "fox": "🦊",
        "bear": "🐻",
        "panda": "🐼",
        "koala": "🐨",
        "tiger": "🐯",
        "lion": "🦁",
        "cow": "🐮",
        "pig": "🐷",
        "frog": "🐸",
        "monkey": "🐵",
        "chicken": "🐔",
        "penguin": "🐧",
        "bird": "🐦",
        "eagle": "🦅",
        "owl": "🦉",
        "butterfly": "🦋",
        "snail": "🐌",
        "bug": "🐛",
        "ant": "🐜",
        "bee": "🐝",
        "spider": "🕷️",
        "turtle": "🐢",
        "snake": "🐍",
        "dragon": "🐉",
        "whale": "🐳",
        "dolphin": "🐬",
        "fish": "🐟",
        "octopus": "🐙",
        "crab": "🦀",
        "unicorn": "🦄",
        "apple": "🍎",
        "banana": "🍌",
        "grapes": "🍇",
        "watermelon": "🍉",
        "strawberry": "🍓",
        "peach": "🍑",
        "pizza": "🍕",
        "hamburger": "🍔",
        "fries": "🍟",
        "hotdog": "🌭",
        "taco": "🌮",
        "burrito": "🌯",
        "sushi": "🍣",
        "ramen": "🍜",
        "cake": "🎂",
        "cookie": "🍪",
        "chocolate": "🍫",
        "candy": "🍬",
        "icecream": "🍦",
        "coffee": "☕",
        "tea": "🍵",
        "beer": "🍺",
        "wine": "🍷",
        "cocktail": "🍸",
        "soccer": "⚽",
        "basketball": "🏀",
        "football": "🏈",
        "baseball": "⚾",
        "tennis": "🎾",
        "golf": "⛳",
        "trophy": "🏆",
        "medal": "🥇",
        "video_game": "🎮",
        "dart": "🎯",
        "bowling": "🎳",
        "phone": "📱",
        "computer": "💻",
        "keyboard": "⌨️",
        "camera": "📷",
        "tv": "📺",
        "radio": "📻",
        "book": "📖",
        "pen": "🖊️",
        "pencil": "✏️",
        "scissors": "✂️",
        "lock": "🔒",
        "key": "🔑",
        "hammer": "🔨",
        "wrench": "🔧",
        "bulb": "💡",
        "money": "💰",
        "gem": "💎",
        "gift": "🎁",
        "balloon": "🎈",
        "check": "✅",
        "x": "❌",
        "warning": "⚠️",
        "question": "❓",
        "exclamation": "❗",
        "plus": "➕",
        "minus": "➖",
        "100": "💯",
        "sparkles": "✨",
        "boom": "💥",
        "zzz": "💤",
        "speech_balloon": "💬",
        "thought_balloon": "💭",
        "checkered_flag": "🏁",
        "triangular_flag": "🚩",
        "white_flag": "🏳️",
        "rainbow_flag": "🏳️‍🌈",
        "rocket": "🚀",
        "airplane": "✈️",
        "car": "🚗",
        "bus": "🚌",
        "train": "🚂",
        "ship": "🚢",
        "anchor": "⚓",
        "construction": "🚧",
    ]
}

public struct AdmonitionPlugin: BlockParserPlugin {
    public let id = "admonition"
    public let name = "Admonition Plugin"
    public let priority = 10
    public init() {}

    private static let startPattern = try! NSRegularExpression(pattern: #"^:::\s*(\w+)(?:\s+(.+))?$"#)

    public func canParse(_ line: String, lines: [String], at index: Int) -> Bool {
        startMatch(line) != nil
    }

    public func parse(_ lines: [String], at index: Int) -> BlockPluginMatch? {
        guard lines.indices.contains(index), let match = startMatch(lines[index]) else { return nil }
        let type = match.0.lowercased()
        let title = match.1
        var end = index + 1
        while end < lines.count, lines[end].trimmingCharacters(in: .whitespaces) != ":::" { end += 1 }
        let closed = end < lines.count
        let consumed = end - index + (closed ? 1 : 0)
        let content = lines[(index + 1)..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: String = switch type {
        case "info": "note"
        case "hint": "tip"
        case "caution": "warning"
        case "error": "danger"
        case "note", "tip", "warning", "danger", "important": type
        default: "custom"
        }
        let source = lines[index..<(index + consumed)].joined(separator: "\n")
        return .init(linesConsumed: consumed, source: source, content: content,
                     attributes: ["type": resolved, "customType": resolved == "custom" ? type : "", "title": title])
    }

    public func render(_ match: BlockPluginMatch) -> AnyView {
        let type = match.attributes["type"] ?? "custom"
        let title = match.attributes["title"].flatMap { $0.isEmpty ? nil : $0 } ?? type.capitalized
        let color: Color = switch type {
        case "tip": .green
        case "warning": .orange
        case "danger": .red
        case "important": .purple
        default: .blue
        }
        return AnyView(VStack(alignment: .leading, spacing: 6) {
            SwiftUI.Text(title).bold().foregroundColor(color)
            if !match.content.isEmpty { SwiftUI.Text(match.content) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .accessibilityElement(children: .combine))
    }

    private func startMatch(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let source = trimmed as NSString
        guard let match = Self.startPattern.firstMatch(in: trimmed, range: NSRange(location: 0, length: source.length)) else { return nil }
        let title = match.range(at: 2).location == NSNotFound ? "" : source.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        return (source.substring(with: match.range(at: 1)), title)
    }
}

private extension Character {
    var isASCIIAlpha: Bool {
        guard unicodeScalars.count == 1, let value = unicodeScalars.first?.value else { return false }
        return (65...90).contains(value) || (97...122).contains(value)
    }
    var isASCIIAlphaNumeric: Bool {
        guard unicodeScalars.count == 1, let value = unicodeScalars.first?.value else { return false }
        return isASCIIAlpha || (48...57).contains(value)
    }
}
