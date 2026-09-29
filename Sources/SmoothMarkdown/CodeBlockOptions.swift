/// Display choices for fenced code blocks. Existing reader initializers keep these defaults.
public struct CodeBlockOptions: Equatable, Sendable {
    public var showCopyButton: Bool
    public var showLanguageTag: Bool
    public var enableSyntaxHighlighting: Bool

    public init(
        showCopyButton: Bool = true,
        showLanguageTag: Bool = true,
        enableSyntaxHighlighting: Bool = true
    ) {
        self.showCopyButton = showCopyButton
        self.showLanguageTag = showLanguageTag
        self.enableSyntaxHighlighting = enableSyntaxHighlighting
    }
}
