import SwiftUI
#if canImport(SmoothMarkdownCore)
@_spi(ReaderInternals) import SmoothMarkdownCore
#endif

/// View-owned parser state, separate from the global static-document cache.
@MainActor
final class StreamMarkdownRenderSession {
    struct Snapshot {
        let source: String
        let document: Document
        let pluginIdentity: ObjectIdentifier?
        let pluginRevision: UInt64
        let enableHTML: Bool

        func matches(_ source: String, plugins: ParserPluginRegistry?, enableHTML: Bool) -> Bool {
            self.source.utf16.elementsEqual(source.utf16) && self.enableHTML == enableHTML &&
                pluginIdentity == plugins.map(ObjectIdentifier.init) && pluginRevision == (plugins?.revision ?? 0)
        }
    }

    private let native = NativeMarkdownStreamSession()
    private var sourceMap = StreamMarkdownSourceMap()
    private var markup: [Markup?] = []
    private var latest: Snapshot?
    private var plugins: ParserPluginRegistry?
    private var enableHTML = false
    private var appliedVersion: UInt64 = 0
    private var appliedEpoch: StreamMarkdownWorkerResult.Epoch?
    private(set) var reusedBlocks = 0

    func configure(plugins: ParserPluginRegistry?, enableHTML: Bool) {
        if self.plugins !== plugins || self.enableHTML != enableHTML { reset() }
        self.plugins = plugins
        self.enableHTML = enableHTML
    }

    func setHTML(_ enabled: Bool) { configure(plugins: plugins, enableHTML: enabled) }

    func reset() {
        native.reset(); markup.removeAll(); sourceMap = StreamMarkdownSourceMap(); latest = nil; reusedBlocks = 0
        appliedVersion = 0; appliedEpoch = nil
    }

    func update(_ source: String) -> Snapshot? {
        if plugins == nil, let latest, latest.matches(source, plugins: plugins, enableHTML: enableHTML) { return latest }
        // HTML restoration and details segmentation are source postprocessors.
        // Preserve their whole-document path until they have an incremental contract.
        guard !enableHTML, !source.localizedCaseInsensitiveContains("<details") else { reset(); return nil }
        let document: Document
        // Math and footnote semantics follow the existing reader callback projection.
        // Keep that batch path for these extensions throughout streaming.
        if plugins != nil || source.contains("[^") || source.contains("$") {
            native.reset(); markup.removeAll(); reusedBlocks = 0
            guard let full = PluginSharedSyntax.document(source, registry: plugins, enableHTML: false) else { latest = nil; return nil }
            document = full
        } else {
            guard let update = native.update(source), update.retainedBlocks <= markup.count else { reset(); return nil }
            return adapt(source: source, tree: update.tree, retainedBlocks: update.retainedBlocks)
        }
        let snapshot = Snapshot(source: source, document: document,
                                pluginIdentity: plugins.map(ObjectIdentifier.init),
                                pluginRevision: plugins?.revision ?? 0, enableHTML: enableHTML)
        latest = snapshot
        return snapshot
    }

    func isBackgroundEligible(_ source: String) -> Bool {
        plugins == nil && !enableHTML && !source.contains("$") && !source.contains("[^") &&
            !source.localizedCaseInsensitiveContains("<details")
    }

    func accept(_ result: StreamMarkdownWorkerResult) -> Snapshot {
        guard let tree = result.tree else {
            reset()
            // Preserve the existing owned-parser fallback on backend rejection.
            // This exceptional path and all mutable Markup remain on MainActor.
            let document = MarkdownSyntax.parse(result.source, useCache: false)
            return Snapshot(source: result.source, document: document,
                            pluginIdentity: nil, pluginRevision: 0, enableHTML: false)
        }
        let continuous = appliedEpoch == result.epoch && appliedVersion == result.baseVersion
        let retained = continuous ? result.retainedBlocks : 0
        if !continuous { markup.removeAll(); sourceMap = StreamMarkdownSourceMap() }
        let snapshot = adapt(source: result.source, tree: tree, retainedBlocks: retained)
        appliedEpoch = result.epoch
        appliedVersion = result.version
        return snapshot
    }

    private func adapt(source: String, tree: NativeMarkdownNode, retainedBlocks: Int) -> Snapshot {
        let retained = retainedBlocks <= markup.count ? retainedBlocks : 0
        let adapter = NativeMarkdownMarkupAdapter(source: source, sourceLocations: sourceMap.update(source),
                                                  resolveCustom: { _ in nil })
        let appended = tree.children.dropFirst(retained).map { node -> Markup? in
            if case .referenceDefinition = node.kind { return nil }
            return adapter.convert(node)
        }
        markup = Array(markup.prefix(retained)) + appended
        reusedBlocks = retained
        let document = Document(markup.compactMap { $0 }, source: source)
        document.sourcePluginsResolved = true
        let snapshot = Snapshot(source: source, document: document, pluginIdentity: nil,
                                pluginRevision: 0, enableHTML: false)
        latest = snapshot
        return snapshot
    }

}

private struct StreamMarkdownSnapshotKey: EnvironmentKey {
    static var defaultValue: StreamMarkdownRenderSession.Snapshot? { nil }
}
extension EnvironmentValues {
    var markdownStreamSnapshot: StreamMarkdownRenderSession.Snapshot? {
        get { self[StreamMarkdownSnapshotKey.self] }
        set { self[StreamMarkdownSnapshotKey.self] = newValue }
    }
}

/// Appends byte-column locations without rescanning the committed source on each publish.
private struct StreamMarkdownSourceMap {
    private var source = ""
    private var positions = [SourceLocation(line: 1, column: 1)]

    mutating func update(_ next: String) -> [SourceLocation] {
        if !next.utf16.starts(with: source.utf16) {
            source = ""; positions = [SourceLocation(line: 1, column: 1)]
        }
        let start = String.Index(utf16Offset: source.utf16.count, in: next)
        var line = positions.last!.line
        var column = positions.last!.column
        for scalar in next.unicodeScalars[start...] {
            let spelling = String(scalar)
            for _ in 1..<spelling.utf16.count { positions.append(.init(line: line, column: column)) }
            if scalar == "\n" { line += 1; column = 1 }
            else { column += spelling.utf8.count }
            positions.append(.init(line: line, column: column))
        }
        source = next
        return positions
    }
}
