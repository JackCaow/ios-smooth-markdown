#if os(iOS)
import SwiftUI
import UIKit

/// Keeps SwiftUI non-text blocks in their original layout while exposing a
/// block range that can cross them. Its manual Copy button and optional Actions
/// menu use the same semantic range text without taking text gestures.
@available(iOS 17.0, *)
struct ReaderBlockRangeView: View {
    @Environment(\.readerTextSelectionMenuBuilder) private var textSelectionMenuBuilder
    let document: ReaderBlockRangeDocument
    let enableHTML: Bool
    let plugins: ParserPluginRegistry?
    let spacing: CGFloat
    let startSelecting: Bool
    let onSelectionStarted: (() -> Void)?
    let onSelectionFinished: (() -> Void)?
    let renderSegment: (ReaderBlockRangeDocument.Segment, @escaping () -> Void, ((Int) -> Void)?) -> AnyView

    @State private var selecting = false
    @State private var anchor: Endpoint?
    @State private var focus: Endpoint?

    private struct Endpoint {
        let block: Int
        let utf16: Int?
    }

    private struct Selection {
        let blocks: ClosedRange<Int>
        let startUTF16: Int?
        let endUTF16: Int?
    }

    private var selection: Selection? {
        guard let anchor, let focus else { return nil }
        if anchor.block < focus.block {
            return .init(blocks: anchor.block...focus.block, startUTF16: anchor.utf16,
                         endUTF16: focus.utf16)
        }
        if focus.block < anchor.block {
            return .init(blocks: focus.block...anchor.block, startUTF16: focus.utf16,
                         endUTF16: anchor.utf16)
        }
        guard let first = anchor.utf16, let last = focus.utf16, first != last else { return nil }
        return .init(blocks: anchor.block...anchor.block, startUTF16: min(first, last),
                     endUTF16: max(first, last))
    }

    private var selectedCopyText: String? {
        guard let selection else { return nil }
        return document.copiedText(in: selection.blocks,
                                   startUTF16: selection.startUTF16,
                                   endUTF16: selection.endUTF16,
                                   enableHTML: enableHTML, plugins: plugins)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(document.segments.indices, id: \.self) { index in
                let segment = document.segments[index]
                Group {
                    if segment.isCode && !selecting {
                        renderSegment(segment, beginSelection, nil)
                    } else if segment.isBridge && !selecting {
                        renderSegment(segment, beginSelection, nil)
                            .contextMenu {
                                Button("Select surrounding content") { beginSelection() }
                            }
                            .accessibilityAction(named: Text("Select surrounding content")) {
                                beginSelection()
                            }
                    } else {
                        renderSegment(segment, beginSelection, selecting && !segment.isBridge
                                      ? { selectEndpoint(.init(block: index, utf16: $0)) } : nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    if selecting && segment.isBridge {
                        Button {
                            selectEndpoint(.init(block: index, utf16: nil))
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
                if selecting && !segment.isBridge {
                    Button("Select entire block") {
                        selectEndpoint(.init(block: index, utf16: nil))
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("reader-image-range-block-\(index)")
                }
            }
            if selecting {
                HStack(spacing: 12) {
                    Text(anchor == nil ? "Tap text or choose first block" : focus == nil
                         ? "Tap text or choose last block" : "Range selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Copy") {
                        copySelection()
                    }
                    .disabled(selectedCopyText == nil)
                    .accessibilityIdentifier("reader-image-range-copy")
                    if let textSelectionMenuBuilder, let selectedCopyText, !selectedCopyText.isEmpty {
                        ReaderSelectionActionsButton(selectedText: selectedCopyText,
                                                     builder: textSelectionMenuBuilder,
                                                     copy: copySelection,
                                                     accessibilityIdentifier: "reader-range-actions")
                    }
                    Button("Cancel") { reset() }
                        .accessibilityIdentifier("reader-image-range-cancel")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            if startSelecting { beginSelection() }
        }
    }

    private func isSelected(_ index: Int) -> Bool {
        if let selection { return selection.blocks.contains(index) }
        return anchor?.block == index
    }

    private func copySelection() {
        guard let selectedCopyText else { return }
        UIPasteboard.general.string = selectedCopyText
        reset()
    }

    private func selectEndpoint(_ endpoint: Endpoint) {
        if anchor == nil || focus != nil {
            anchor = endpoint
            focus = nil
        } else {
            focus = endpoint
        }
    }

    private func beginSelection() {
        let wasSelecting = selecting
        selecting = true
        anchor = nil
        focus = nil
        if !wasSelecting { onSelectionStarted?() }
    }

    private func reset() {
        selecting = false
        anchor = nil
        focus = nil
        onSelectionFinished?()
    }
}
#endif
