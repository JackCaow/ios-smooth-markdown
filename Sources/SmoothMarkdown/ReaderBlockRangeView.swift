#if os(iOS)
import SwiftUI
import UIKit

/// Keeps SwiftUI images and tables in their original layout while exposing a
/// block range that can cross them.
@available(iOS 17.0, *)
struct ReaderBlockRangeView: View {
    let document: ReaderBlockRangeDocument
    let enableHTML: Bool
    let plugins: ParserPluginRegistry?
    let spacing: CGFloat
    let renderSegment: (ReaderBlockRangeDocument.Segment) -> AnyView

    @State private var selecting = false
    @State private var anchor: Int?
    @State private var focus: Int?

    private var selectedRange: ClosedRange<Int>? {
        guard let anchor, let focus, anchor != focus else { return nil }
        return min(anchor, focus)...max(anchor, focus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(document.segments.indices, id: \.self) { index in
                let segment = document.segments[index]
                Group {
                    if segment.isBridge && !selecting {
                        renderSegment(segment)
                            .contextMenu {
                                Button("Select surrounding content") { beginSelection() }
                            }
                            .accessibilityAction(named: Text("Select surrounding content")) {
                                beginSelection()
                            }
                    } else {
                        renderSegment(segment)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    if selecting {
                        Button {
                            if anchor == nil || focus != nil {
                                anchor = index
                                focus = nil
                            } else {
                                focus = index
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(isSelected(index) ? 0.12 : 0.001))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor.opacity(isSelected(index) ? 0.55 : 0), lineWidth: 2))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select block \(index + 1)")
                        .accessibilityIdentifier("reader-image-range-block-\(index)")
                    }
                }
            }
            if selecting {
                HStack(spacing: 12) {
                    Text(anchor == nil ? "Choose first block" : focus == nil ? "Choose last block" : "Range selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Copy") {
                        if let selectedRange,
                           let copied = document.copiedText(in: selectedRange,
                                                            enableHTML: enableHTML, plugins: plugins) {
                            UIPasteboard.general.string = copied
                            reset()
                        }
                    }
                    .disabled(selectedRange == nil)
                    .accessibilityIdentifier("reader-image-range-copy")
                    Button("Cancel") { reset() }
                        .accessibilityIdentifier("reader-image-range-cancel")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
    }

    private func isSelected(_ index: Int) -> Bool {
        if let selectedRange { return selectedRange.contains(index) }
        return anchor == index
    }

    private func beginSelection() {
        selecting = true
        anchor = nil
        focus = nil
    }

    private func reset() {
        selecting = false
        anchor = nil
        focus = nil
    }
}
#endif
