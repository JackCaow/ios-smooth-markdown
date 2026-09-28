import Foundation
import SmoothMarkdown
import SwiftUI

/// Companion to Flutter's `HtmlDemo`: its Markdown is loaded from the checked fixture.
struct DemoHTMLView: View {
    let markdown: String
    let styleSheet: MarkdownStyleSheet
    let plugins: ParserPluginRegistry

    @State private var enableHTML = true
    @State private var stream: AsyncStream<String>?
    @State private var continuation: AsyncStream<String>.Continuation?
    @State private var producer: Task<Void, Never>?
    @State private var runID = UUID()
    @State private var isStreaming = false
    @State private var deliveredChunks = 0

    private var chunks: [String] { Self.wordChunks(markdown) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Toggle("HTML", isOn: $enableHTML)
                    .accessibilityIdentifier("html-demo-toggle")
                Button {
                    if isStreaming { stop() } else { start() }
                } label: {
                    Image(systemName: isStreaming ? "stop.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isStreaming ? "Stop streaming" : "Simulate streaming")
                .accessibilityIdentifier("html-demo-stream-control")
            }
            .padding(16)

            if isStreaming {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("html-demo-progress")
            }

            Text("\(isStreaming ? "Streaming \(deliveredChunks)/\(chunks.count) chunks" : "Ready") · HTML \(enableHTML ? "on" : "off")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("html-demo-status")

            ScrollView {
                Group {
                    if let stream {
                        StreamMarkdownView(chunks: stream, streamID: runID.uuidString,
                                           throttleMillis: 40, enableHTML: enableHTML,
                                           onComplete: { _ in isStreaming = false },
                                           styleSheet: styleSheet, plugins: plugins)
                    } else {
                        SmoothMarkdownView(markdown: markdown, enableHTML: enableHTML,
                                           styleSheet: styleSheet, plugins: plugins)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .accessibilityIdentifier("html-demo-reader")
        }
        .onChange(of: enableHTML) { _, _ in
            // The stream has a single consumer; show the full document with the
            // new renderer configuration instead of restarting from mid-stream.
            if stream != nil { stop() }
        }
        .onDisappear { stop() }
    }

    /// Dart's `RegExp(r'\S+\s*')`: words retain their trailing whitespace.
    static func wordChunks(_ content: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"\S+\s*"#)
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return pattern.matches(in: content, range: range).compactMap { match in
            Range(match.range, in: content).map { String(content[$0]) }
        }
    }

    private func start() {
        guard !isStreaming else { return }
        stop()
        let words = chunks
        deliveredChunks = 0
        isStreaming = true
        runID = UUID()
        let currentRunID = runID
        let nextStream = AsyncStream<String> { continuation = $0 }
        stream = nextStream
        guard let continuation else { return }
        producer = Task { @MainActor in
            for (index, chunk) in words.enumerated() {
                guard !Task.isCancelled, runID == currentRunID else { break }
                continuation.yield(chunk)
                deliveredChunks = index + 1
                do {
                    try await Task.sleep(nanoseconds: 40_000_000)
                } catch {
                    break
                }
            }
            continuation.finish()
        }
    }

    private func stop() {
        producer?.cancel()
        continuation?.finish()
        producer = nil
        continuation = nil
        stream = nil
        runID = UUID()
        deliveredChunks = 0
        isStreaming = false
    }
}
