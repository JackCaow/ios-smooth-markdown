import Foundation

/// Foundation-only source-preserving CommonMark/GFM parser.
public struct MarkdownCoreParser {
    public var enableGFM: Bool
    public init(enableGFM: Bool = true) { self.enableGFM = enableGFM }
    public func parse(_ source: String) -> NativeMarkdownNode {
        NativeMarkdownASTParser(enableGFM: enableGFM).parse(source)
    }
    public func renderHTML(_ source: String) -> String {
        NativeMarkdownHTMLSerializer.render(parse(source))
    }
}
