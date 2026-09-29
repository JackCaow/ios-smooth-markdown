import Foundation
import SmoothMarkdown
import SwiftUI

/// Keeps a reply's accumulated text alive even when LazyVStack recycles its bubble.
@MainActor
final class DemoChatReplyStreams {
    private(set) var runID = UUID()
    private var replies: [UUID: StreamMarkdownAccumulator] = [:]

    func start(messageID: UUID) -> UUID {
        let accumulator = StreamMarkdownAccumulator()
        replies[messageID] = accumulator
        return runID
    }

    func stream(for messageID: UUID) -> StreamMarkdownAccumulator? {
        replies[messageID]
    }

    @discardableResult
    func append(_ fragment: String, to messageID: UUID, in run: UUID) -> Bool {
        guard runID == run, let accumulator = replies[messageID] else { return false }
        accumulator.append(fragment)
        return true
    }

    func finish(messageID: UUID, in run: UUID) -> String? {
        guard runID == run, let accumulator = replies.removeValue(forKey: messageID) else { return nil }
        accumulator.finish()
        return accumulator.visibleText
    }

    func cancelAll() -> [UUID: String] {
        runID = UUID()
        var partial: [UUID: String] = [:]
        for (id, accumulator) in replies {
            accumulator.finish()
            partial[id] = accumulator.visibleText
        }
        replies.removeAll()
        return partial
    }
}

struct DemoStreamingMarkdownBubble: View {
    @ObservedObject var stream: StreamMarkdownAccumulator
    let styleSheet: MarkdownStyleSheet
    let plugins: ParserPluginRegistry?
    let emptyLabel: String

    var body: some View {
        Group {
            if stream.visibleText.isEmpty {
                ProgressView().accessibilityLabel(emptyLabel)
            } else {
                SmoothMarkdownView(markdown: stream.visibleText,
                                   styleSheet: styleSheet, plugins: plugins,
                                   enableCache: false,
                                   scrollable: false)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
