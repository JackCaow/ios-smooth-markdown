import Markdown

/// A native selection surface can project ordinary prose and headings around
/// standalone images. Other blocks retain the explicit block-range UI.
enum ReaderImageSelectionEligibility {
    static func imageSpec(for segment: ReaderBlockRangeDocument.Segment,
                          enableHTML: Bool) -> SafeHTML.ImageSpec? {
        guard let paragraph = segment.nodes.first as? Paragraph else { return nil }
        return InlineContent.runs(in: paragraph, enableHTML: enableHTML).compactMap { run in
            if case let .image(spec) = run { return spec }
            return nil
        }.first
    }

    static func imageSpecs(for document: ReaderBlockRangeDocument, enableHTML: Bool,
                           plugins: ParserPluginRegistry?) -> [SafeHTML.ImageSpec]? {
        guard document.segments.count >= 2 else { return nil }
        var images: [SafeHTML.ImageSpec] = []
        var hasText = false
        for segment in document.segments {
            switch segment.kind {
            case .text:
                guard let text = ReaderSelectionDocument.compose(segment.nodes,
                                                                 enableHTML: enableHTML, plugins: plugins),
                      text.selectionText == text.copiedText,
                      text.lines.allSatisfy({ line in
                          switch line.kind {
                          case .paragraph, .heading: return true
                          case .list, .quote, .rule, .detailsSummary, .footnoteDefinition: return false
                          }
                      }) else { return nil }
                hasText = true
            case .image:
                guard let spec = imageSpec(for: segment, enableHTML: enableHTML),
                      ImageSource.parse(spec.source) != nil else { return nil }
                images.append(spec)
            case .table, .code, .displayMath: return nil
            }
        }
        return hasText && !images.isEmpty ? images : nil
    }
}
