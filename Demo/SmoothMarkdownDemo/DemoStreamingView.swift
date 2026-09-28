import CryptoKit
import Foundation
import SmoothMarkdown
import SwiftUI

/// Each element matches one string literal in Flutter's `_responseChunks` array.
private struct DemoStreamingFixture: Decodable {
    let markdownSha256: String
    let delayMillis: UInt64
    let chunks: [String]

    var markdown: String { chunks.joined() }

    static func load(bundle: Bundle = .main) -> Result<Self, FixtureError> {
        guard let url = bundle.url(forResource: "streaming", withExtension: "json", subdirectory: "Examples/Streaming")
            ?? bundle.url(forResource: "streaming", withExtension: "json", subdirectory: "Streaming")
            ?? bundle.url(forResource: "streaming", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let fixture = try? JSONDecoder().decode(Self.self, from: data) else {
            return .failure(.missing)
        }
        let digest = SHA256.hash(data: Data(fixture.markdown.utf8))
            .map { String(format: "%02x", $0) }.joined()
        guard !fixture.chunks.isEmpty, fixture.delayMillis == 50, digest == fixture.markdownSha256 else {
            return .failure(.invalid)
        }
        return .success(fixture)
    }

    enum FixtureError: Error {
        case missing, invalid
        var message: String {
            switch self {
            case .missing: "Flutter streaming fixture is missing or unreadable."
            case .invalid: "Flutter streaming fixture failed its checksum or timing check."
            }
        }
    }
}

struct DemoStreamingView: View {
    let styleSheet: MarkdownStyleSheet
    let plugins: ParserPluginRegistry

    @State private var stream: AsyncStream<String>?
    @State private var continuation: AsyncStream<String>.Continuation?
    @State private var producer: Task<Void, Never>?
    @State private var runID = UUID()
    @State private var deliveredChunks = 0
    @State private var phase: Phase = .ready

    private let fixtureResult = DemoStreamingFixture.load()

    private enum Phase {
        case ready, streaming, complete, error
    }

    var body: some View {
        switch fixtureResult {
        case let .failure(error):
            ContentUnavailableView("Streaming demo unavailable", systemImage: "doc.questionmark",
                                   description: Text(error.message))
                .accessibilityIdentifier("stream-demo-fixture-error")
        case let .success(fixture):
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button {
                        start(fixture)
                    } label: {
                        Label("Start Stream", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(stream != nil)
                    .accessibilityIdentifier("stream-demo-start")

                    Button {
                        reset()
                    } label: {
                        Label("Reset", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(stream == nil)
                    .accessibilityIdentifier("stream-demo-reset")
                }
                .padding(16)

                switch phase {
                case .streaming:
                    ProgressView(value: Double(deliveredChunks), total: Double(fixture.chunks.count))
                        .accessibilityIdentifier("stream-demo-progress")
                case .complete:
                    Rectangle().fill(.green).frame(height: 4)
                case .ready, .error:
                    EmptyView()
                }

                Text(status(total: fixture.chunks.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("stream-demo-status")

                if let stream {
                    StreamMarkdownView(
                        chunks: stream,
                        streamID: runID.uuidString,
                        onError: { _ in
                            phase = .error
                        },
                        onComplete: { markdown in
                            guard phase == .streaming else { return }
                            phase = markdown == fixture.markdown ? .complete : .error
                        },
                        styleSheet: styleSheet,
                        plugins: plugins
                    )
                } else {
                    ContentUnavailableView {
                        Label("Click \"Start Stream\" to begin", systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text("Watch as Markdown renders in real-time")
                    }
                }
            }
            .onDisappear { reset() }
        }
    }

    private func status(total: Int) -> String {
        switch phase {
        case .ready: "Ready"
        case .streaming: "Streaming \(deliveredChunks)/\(total) chunks"
        case .complete: "Complete \(deliveredChunks)/\(total) chunks"
        case .error: "Stream error"
        }
    }

    private func start(_ fixture: DemoStreamingFixture) {
        guard stream == nil else { return }
        deliveredChunks = 0
        phase = .streaming
        runID = UUID()
        let currentRunID = runID
        let nextStream = AsyncStream<String> { continuation = $0 }
        stream = nextStream
        guard let continuation else { return }
        producer = Task { @MainActor in
            for (index, chunk) in fixture.chunks.enumerated() {
                if index > 0 {
                    do {
                        try await Task.sleep(nanoseconds: fixture.delayMillis * 1_000_000)
                    } catch {
                        break
                    }
                }
                guard !Task.isCancelled, runID == currentRunID else { break }
                continuation.yield(chunk)
                deliveredChunks = index + 1
            }
            continuation.finish()
        }
    }

    private func reset() {
        producer?.cancel()
        continuation?.finish()
        producer = nil
        continuation = nil
        stream = nil
        runID = UUID()
        deliveredChunks = 0
        phase = .ready
    }
}
