import Foundation

/// Foundation-only source-preserving CommonMark/GFM parser.
public struct MarkdownCoreParser {
    public var enableGFM: Bool
    public var enableExtensions: Bool
    public init(enableGFM: Bool = true) { self.enableGFM = enableGFM; self.enableExtensions = true }
    public init(enableGFM: Bool = true, enableExtensions: Bool) {
        self.enableGFM = enableGFM; self.enableExtensions = enableExtensions
    }
    public func parse(_ source: String) -> NativeMarkdownNode {
        NativeMarkdownASTParser(enableGFM: enableGFM, enableNativeExtensions: enableExtensions).parse(source)
    }
    public func renderHTML(_ source: String) -> String {
        NativeMarkdownHTMLSerializer.format(source, enableGFM: enableGFM)
    }
}
