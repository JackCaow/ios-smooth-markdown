import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias NativeBitmap = UIImage
private func bitmapView(_ bitmap: NativeBitmap) -> SwiftUI.Image { SwiftUI.Image(uiImage: bitmap) }
#elseif canImport(AppKit)
import AppKit
private typealias NativeBitmap = NSImage
private func bitmapView(_ bitmap: NativeBitmap) -> SwiftUI.Image { SwiftUI.Image(nsImage: bitmap) }
#endif

/// Keeps a decoded image's natural aspect ratio and shrinks it only when the
/// containing Markdown line is narrower. HTML width/height remain explicit.
struct NaturalImageLayout: Layout {
    let naturalSize: CGSize
    let explicitWidth: CGFloat?
    let explicitHeight: CGFloat?

    static func resolvedSize(natural: CGSize, width: CGFloat?, height: CGFloat?, availableWidth: CGFloat?) -> CGSize {
        let naturalWidth = max(natural.width, 1)
        let naturalHeight = max(natural.height, 1)
        let ratio = naturalWidth / naturalHeight
        var result: CGSize
        switch (width, height) {
        case let (w?, h?): result = CGSize(width: max(w, 1), height: max(h, 1))
        case let (w?, nil): result = CGSize(width: max(w, 1), height: max(w, 1) / ratio)
        case let (nil, h?): result = CGSize(width: max(h, 1) * ratio, height: max(h, 1))
        case (nil, nil): result = CGSize(width: naturalWidth, height: naturalHeight)
        }
        if let availableWidth, availableWidth.isFinite, availableWidth > 0, result.width > availableWidth {
            let scale = availableWidth / result.width
            result = CGSize(width: availableWidth, height: result.height * scale)
        }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Self.resolvedSize(natural: naturalSize, width: explicitWidth, height: explicitHeight,
                          availableWidth: proposal.width)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// AsyncImage does not expose its decoded pixel size to the layout. Decode once
/// here so a remote bitmap can take the same natural-size path as a bundle image.
struct RemoteBitmapView: View {
    @Environment(\.markdownResources) private var resources
    @Environment(\.markdownDesignTokens) private var designTokens
    let url: URL
    let width: CGFloat?
    let height: CGFloat?
    let fallback: String

    @State private var bitmap: NativeBitmap?
    @State private var svg: SVG?
    @State private var failed = false

    var body: some View {
        Group {
            if let svg {
                NaturalImageLayout(naturalSize: svg.size, explicitWidth: width, explicitHeight: height) {
                    SVGView(svg: svg)
                }
            } else if let bitmap {
                NaturalImageLayout(naturalSize: bitmap.size, explicitWidth: width, explicitHeight: height) {
                    bitmapView(bitmap).resizable().scaledToFit()
                }
            } else if failed {
                if let error = resources.error {
                    error(url, fallback)
                } else if url.pathExtension.lowercased() == "svg" {
                    SwiftUI.Text(fallback)
                } else {
                    RemoteBitmapFailureView(label: fallback)
                }
            } else {
                if let placeholder = resources.placeholder { placeholder(url, fallback) } else {
                ProgressView().frame(minWidth: designTokens.imagePlaceholderMinSize, minHeight: designTokens.imagePlaceholderMinSize)
                }
            }
        }
        .task(id: url.absoluteString + resources.requestIdentity) {
            bitmap = nil
            svg = nil
            failed = false
            #if os(iOS)
            let key = ReaderRemoteImageKey(url: url, svg: url.pathExtension.lowercased() == "svg")
            let fetched = await ReaderRemoteImageLoader.fetch(key, options: resources)
            guard !Task.isCancelled else { return }
            switch fetched {
            case let .data(data):
                switch ReaderRemoteImageResolution.decode(data, key: key) {
                case let .svg(image): svg = image
                case let .bitmap(image): bitmap = image
                case .failure, .rejected: failed = true
                }
            case .failure, .rejected: failed = true
            }
            #else
            do {
                let request = MarkdownResourceRequest(url: url, headers: resources.headers, cachePolicy: resources.cachePolicy)
                let data = try await MarkdownResourceDataCache.shared.load(request, loader: resources.loader, identity: resources.cacheIdentity)
                guard !Task.isCancelled else { return }
                if data.count <= ReaderRemoteImagePolicy.maxSVGBytes,
                   let decoded = SVG(data: data, baseURL: url) {
                    svg = decoded
                } else if data.count <= ReaderRemoteImagePolicy.maxBitmapBytes,
                          let decoded = NativeBitmap(data: data) {
                    bitmap = decoded
                } else {
                    failed = true
                }
            } catch is CancellationError {
                // A changed image source starts another task; do not show an error.
            } catch {
                failed = true
            }
            #endif
        }
    }
}

/// Mirrors Flutter's network-bitmap error icon while retaining the alt text
/// for accessibility and image-tap callbacks.
struct RemoteBitmapFailureView: View {
    let label: String

    var body: some View {
        SwiftUI.Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 24))
            .accessibilityLabel(label)
    }
}

struct BundledBitmapView: View {
    let name: String
    let width: CGFloat?
    let height: CGFloat?
    let fallback: String

    var body: some View {
        if let bitmap = NativeBitmap(named: name) {
            NaturalImageLayout(naturalSize: bitmap.size, explicitWidth: width, explicitHeight: height) {
                bitmapView(bitmap).resizable().scaledToFit()
            }
        } else {
            SwiftUI.Text(fallback)
        }
    }
}
