import SwiftUI

/// Appends incoming chunks and renders the accumulated Markdown document.
public struct StreamMarkdownView<Chunks: AsyncSequence>: View where Chunks.Element == String {
    public let chunks: Chunks
    public let onLinkTap: ((URL) -> Void)?
    public let onImageTap: ((URL) -> Void)?
    public let onError: ((Error) -> Void)?

    @State private var markdown = ""

    public init(
        chunks: Chunks,
        onLinkTap: ((URL) -> Void)? = nil,
        onImageTap: ((URL) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.chunks = chunks
        self.onLinkTap = onLinkTap
        self.onImageTap = onImageTap
        self.onError = onError
    }

    public var body: some View {
        SmoothMarkdownView(markdown: markdown, onLinkTap: onLinkTap, onImageTap: onImageTap)
            .task {
                do {
                    for try await chunk in chunks {
                        markdown.append(chunk)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    onError?(error)
                }
            }
    }
}
