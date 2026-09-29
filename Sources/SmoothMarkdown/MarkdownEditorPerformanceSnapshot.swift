import Foundation

/// Lightweight editor state sent to a host after changes settle on the main actor.
/// The Flutter-only formatted segment cache and suggestion-panel counters are nil
/// until the native editor has equivalent observable state.
public struct MarkdownEditorPerformanceSnapshot {
    public let sourceLength: Int
    public let blockCount: Int
    public let formattedSegmentCount: Int
    public let formattedSegmentCacheHit: Bool?
    public let retainedFormattedSegmentKeyCount: Int?
    public let mode: MarkdownEditorMode
    public let isComposing: Bool
    public let searchMatchCount: Int
    public let slashSuggestionsVisible: Bool?
    public let wikilinkSuggestionsVisible: Bool?
    public let timestamp: Date

    @MainActor
    static func capture(controller: MarkdownEditorController, searchQuery: String,
                        isComposing: Bool, timestamp: Date = Date(), blockCount: Int? = nil) -> Self {
        let blocks = blockCount ?? controller.semanticDocument.blocks.count
        return .init(sourceLength: (controller.text as NSString).length,
                     blockCount: blocks, formattedSegmentCount: blocks,
                     formattedSegmentCacheHit: nil, retainedFormattedSegmentKeyCount: nil,
                     mode: controller.mode, isComposing: isComposing,
                     searchMatchCount: searchQuery.isEmpty ? 0 : controller.findMatches(searchQuery).count,
                     slashSuggestionsVisible: nil, wikilinkSuggestionsVisible: nil,
                     timestamp: timestamp)
    }
}

/// Coalesces synchronous state changes into one snapshot while reading the final state.
@MainActor
final class MarkdownEditorPerformanceReporter {
    typealias Enqueue = (@escaping @MainActor () -> Void) -> Void
    private let enqueue: Enqueue
    private var pending = false
    private var latestSnapshot: (() -> MarkdownEditorPerformanceSnapshot)?
    private var latestCallback: ((MarkdownEditorPerformanceSnapshot) -> Void)?
    private var cachedSource: String?
    private var cachedBlockCount: Int?

    init(enqueue: @escaping Enqueue = { action in
        DispatchQueue.main.async { action() }
    }) {
        self.enqueue = enqueue
    }

    func schedule(snapshot: @escaping () -> MarkdownEditorPerformanceSnapshot,
                  callback: @escaping (MarkdownEditorPerformanceSnapshot) -> Void) {
        latestSnapshot = snapshot
        latestCallback = callback
        guard !pending else { return }
        pending = true
        enqueue { [weak self] in
            guard let self, self.pending else { return }
            self.pending = false
            let snapshot = self.latestSnapshot?()
            let callback = self.latestCallback
            self.latestSnapshot = nil
            self.latestCallback = nil
            if let snapshot { callback?(snapshot) }
        }
    }

    func capture(controller: MarkdownEditorController, searchQuery: String,
                 isComposing: Bool) -> MarkdownEditorPerformanceSnapshot {
        if cachedSource != controller.text {
            cachedSource = controller.text
            cachedBlockCount = controller.semanticDocument.blocks.count
        }
        return MarkdownEditorPerformanceSnapshot.capture(controller: controller,
                                                         searchQuery: searchQuery, isComposing: isComposing,
                                                         blockCount: cachedBlockCount)
    }

    func cancel() {
        pending = false
        latestSnapshot = nil
        latestCallback = nil
        cachedSource = nil
        cachedBlockCount = nil
    }
}

/// Source focus is distinct from the formatted pane's focus, matching Flutter's
/// source FocusNode callback. Repeated UIKit notifications do not reach the host.
@MainActor
final class MarkdownEditorSourceFocusTracker {
    private(set) var isFocused = false

    func setFocused(_ focused: Bool, callback: ((Bool) -> Void)?) {
        guard focused != isFocused else { return }
        isFocused = focused
        callback?(focused)
    }
}
