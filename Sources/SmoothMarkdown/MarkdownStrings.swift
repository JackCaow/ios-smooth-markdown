import SwiftUI
import Foundation

/// Library-owned control and accessibility labels. Author content is not translated.
public struct MarkdownStrings {
    public var copy = "Copy"
    public var copied = "Copied!"
    public var copyArtifact = "Copy artifact"
    public var copyFormula = "Copy formula"
    public var copyMarkdown = "Copy Markdown"
    public var copyTextRange = "Copy text range"
    public var copyCells = "Copy cells"
    public var copyItems = "Copy items"
    public var copyTSV = "Copy TSV"
    public var expanded = "Expanded"
    public var collapsed = "Collapsed"
    public var detailsToggleHint = "Double tap to expand or collapse"
    public var expandDetails = "Expand details"
    public var collapseDetails = "Collapse details"
    public var expandThinking = "Expand thinking"
    public var collapseThinking = "Collapse thinking"
    public var thinking = "Thinking"
    public var thinkingInProgress = "Thinking..."
    public var selectSurroundingContent = "Select surrounding content"
    public var tool = "Tool"
    public var identifier = "ID"
    public var running = "Running"
    public var completed = "Completed"
    public var failed = "Failed"
    public var cancelled = "Cancelled"
    public var pending = "Pending"
    public var parameters = "Parameters"
    public var result = "Result"
    public var error = "Error"
    public var code = "CODE"
    public var document = "DOCUMENT"
    public var component = "COMPONENT"
    public var diagram = "DIAGRAM"
    public var artifact = "ARTIFACT"
    public var actions = "Actions"
    public var selectionActions = "Selection actions"
    public var selectAllReaderText = "Select all reader text"
    public var cancel = "Cancel"
    public var selectEntireBlock = "Select entire block"
    public var selectFirstBlock = "Tap text or choose first block"
    public var selectLastBlock = "Tap text or choose last block"
    public var rangeSelected = "Range selected"
    /// Additional editor/admonition labels keyed by their English default, including command titles.
    public var overrides: [String: String] = [:]
    public subscript(_ defaultLabel: String) -> String {
        if let override = overrides[defaultLabel] { return override }
        switch defaultLabel {
        case "Copy": return copy
        case "Copied!": return copied
        case "Copy artifact": return copyArtifact
        case "Copy formula": return copyFormula
        case "Copy Markdown": return copyMarkdown
        case "Copy text range": return copyTextRange
        case "Copy cells": return copyCells
        case "Copy items": return copyItems
        case "Copy TSV": return copyTSV
        case "Expanded": return expanded
        case "Collapsed": return collapsed
        case "Double tap to expand or collapse": return detailsToggleHint
        case "Expand details": return expandDetails
        case "Collapse details": return collapseDetails
        case "Expand thinking": return expandThinking
        case "Collapse thinking": return collapseThinking
        case "Thinking": return thinking
        case "Thinking...": return thinkingInProgress
        case "Select surrounding content": return selectSurroundingContent
        case "Tool": return tool
        case "ID": return identifier
        case "Running": return running
        case "Completed": return completed
        case "Failed": return failed
        case "Cancelled": return cancelled
        case "Pending": return pending
        case "Parameters": return parameters
        case "Result": return result
        case "Error": return error
        case "CODE": return code
        case "DOCUMENT": return document
        case "COMPONENT": return component
        case "DIAGRAM": return diagram
        case "ARTIFACT": return artifact
        case "Actions": return actions
        case "Selection actions": return selectionActions
        case "Select all reader text": return selectAllReaderText
        case "Cancel": return cancel
        case "Select entire block": return selectEntireBlock
        case "Tap text or choose first block": return selectFirstBlock
        case "Tap text or choose last block": return selectLastBlock
        case "Range selected": return rangeSelected
        default: return defaultLabel
        }
    }
    /// Localize a complete template, then replace named placeholders literally in one pass.
    /// Replacement values are author data and never interpreted as new templates.
    public func format(_ template: String, _ values: [String: String]) -> String {
        let localized = self[template]
        guard let regex = try? NSRegularExpression(pattern: #"\{([A-Za-z_][A-Za-z0-9_]*)\}"#) else { return localized }
        let source = localized as NSString
        let output = NSMutableString(string: localized)
        for match in regex.matches(in: localized, range: NSRange(location: 0, length: source.length)).reversed() {
            let key = source.substring(with: match.range(at: 1))
            if let value = values[key] { output.replaceCharacters(in: match.range, with: value) }
        }
        return output as String
    }
    public init() {}
}

private struct MarkdownStringsKey: EnvironmentKey {
    static let defaultValue = MarkdownStrings()
}

public extension EnvironmentValues {
    var markdownStrings: MarkdownStrings {
        get { self[MarkdownStringsKey.self] }
        set { self[MarkdownStringsKey.self] = newValue }
    }
}
