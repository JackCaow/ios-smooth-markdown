import SwiftUI

/// Optional editor chrome overrides. Nil values retain the native appearance.
public struct MarkdownEditorTheme {
    public var editorBackgroundColor: Color?
    public var editorBorderColor: Color?
    public var editorBorderRadius: CGFloat?
    public var toolbarColor: Color?
    public var toolbarIconColor: Color?
    public var searchBarColor: Color?
    public var dividerColor: Color?
    public var sourceBackgroundColor: Color?
    public var sourceTextColor: Color?
    public var sourceFontName: String?
    public var sourceFontSize: CGFloat?
    public var sourcePadding: EdgeInsets?
    public var previewBackgroundColor: Color?
    public var previewPadding: EdgeInsets?
    public var contentPadding: EdgeInsets?

    public init(editorBackgroundColor: Color? = nil, editorBorderColor: Color? = nil,
                editorBorderRadius: CGFloat? = nil, toolbarColor: Color? = nil,
                toolbarIconColor: Color? = nil, searchBarColor: Color? = nil,
                dividerColor: Color? = nil, sourceBackgroundColor: Color? = nil,
                sourceTextColor: Color? = nil, sourceFontName: String? = nil,
                sourceFontSize: CGFloat? = nil, sourcePadding: EdgeInsets? = nil,
                previewBackgroundColor: Color? = nil, previewPadding: EdgeInsets? = nil,
                contentPadding: EdgeInsets? = nil) {
        self.editorBackgroundColor = editorBackgroundColor
        self.editorBorderColor = editorBorderColor
        self.editorBorderRadius = editorBorderRadius
        self.toolbarColor = toolbarColor
        self.toolbarIconColor = toolbarIconColor
        self.searchBarColor = searchBarColor
        self.dividerColor = dividerColor
        self.sourceBackgroundColor = sourceBackgroundColor
        self.sourceTextColor = sourceTextColor
        self.sourceFontName = sourceFontName
        self.sourceFontSize = sourceFontSize
        self.sourcePadding = sourcePadding
        self.previewBackgroundColor = previewBackgroundColor
        self.previewPadding = previewPadding
        self.contentPadding = contentPadding
    }

    /// Explicit editor values override the theme installed in the environment.
    public func merging(_ override: MarkdownEditorTheme?) -> MarkdownEditorTheme {
        guard let override else { return self }
        return .init(
            editorBackgroundColor: override.editorBackgroundColor ?? editorBackgroundColor,
            editorBorderColor: override.editorBorderColor ?? editorBorderColor,
            editorBorderRadius: override.editorBorderRadius ?? editorBorderRadius,
            toolbarColor: override.toolbarColor ?? toolbarColor,
            toolbarIconColor: override.toolbarIconColor ?? toolbarIconColor,
            searchBarColor: override.searchBarColor ?? searchBarColor,
            dividerColor: override.dividerColor ?? dividerColor,
            sourceBackgroundColor: override.sourceBackgroundColor ?? sourceBackgroundColor,
            sourceTextColor: override.sourceTextColor ?? sourceTextColor,
            sourceFontName: override.sourceFontName ?? sourceFontName,
            sourceFontSize: override.sourceFontSize ?? sourceFontSize,
            sourcePadding: override.sourcePadding ?? sourcePadding,
            previewBackgroundColor: override.previewBackgroundColor ?? previewBackgroundColor,
            previewPadding: override.previewPadding ?? previewPadding,
            contentPadding: override.contentPadding ?? contentPadding)
    }
}

private struct MarkdownEditorThemeKey: EnvironmentKey {
    static let defaultValue = MarkdownEditorTheme()
}

public extension EnvironmentValues {
    var markdownEditorTheme: MarkdownEditorTheme {
        get { self[MarkdownEditorThemeKey.self] }
        set { self[MarkdownEditorThemeKey.self] = newValue }
    }
}

public extension View {
    func markdownEditorTheme(_ theme: MarkdownEditorTheme) -> some View {
        environment(\.markdownEditorTheme, theme)
    }
}
