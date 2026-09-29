import SwiftUI

/// Themes accepted by Flutter's `mermaid theme=...` fenced blocks.
public enum MermaidTheme: String, Sendable {
    case light
    case dark
    case forest
    case neutral

    static func fromFenceInfo(_ info: String) -> Self? {
        guard info.split(whereSeparator: \.isWhitespace).first == "mermaid" else { return nil }
        guard let range = info.range(of: #"(?<!\S)theme\s*=\s*\w+"#, options: .regularExpression) else {
            return nil
        }
        let value = info[range].split(separator: "=", maxSplits: 1)[1]
            .trimmingCharacters(in: .whitespaces)
        return Self(rawValue: value.lowercased()) ?? .light
    }

    var palette: MermaidPalette {
        switch self {
        case .light:
            return .init(background: 0xFFFFFF, text: 0x212121, nodeFill: 0xE3F2FD,
                         nodeStroke: 0x1976D2, edge: 0x616161)
        case .dark:
            return .init(background: 0x1E1E1E, text: 0xE0E0E0, nodeFill: 0x2D2D2D,
                         nodeStroke: 0x64B5F6, edge: 0x9E9E9E)
        case .forest:
            return .init(background: 0xF1F8E9, text: 0x1B5E20, nodeFill: 0xC8E6C9,
                         nodeStroke: 0x388E3C, edge: 0x4CAF50)
        case .neutral:
            return .init(background: 0xFAFAFA, text: 0x424242, nodeFill: 0xEEEEEE,
                         nodeStroke: 0x757575, edge: 0x9E9E9E)
        }
    }
}

struct MermaidPalette {
    let background: UInt32
    let text: UInt32
    let nodeFill: UInt32
    let nodeStroke: UInt32
    let edge: UInt32

    var backgroundColor: Color { Self.color(background) }
    var textColor: Color { Self.color(text) }
    var nodeFillColor: Color { Self.color(nodeFill) }
    var nodeStrokeColor: Color { Self.color(nodeStroke) }
    var edgeColor: Color { Self.color(edge) }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}
