import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A document-wide TextKit storage with semantic attachment ranges.
struct ReaderTextKitProjection {
    static let segmentIDAttribute = NSAttributedString.Key("SmoothMarkdownReaderSegmentID")
    static let segmentKindAttribute = NSAttributedString.Key("SmoothMarkdownReaderSegmentKind")
    static let attachmentIDAttribute = NSAttributedString.Key("SmoothMarkdownReaderAttachmentID")

    struct Attachment: Equatable {
        enum Content: Equatable {
            case image(SafeHTML.ImageSpec)
            case formula(String)
            case code(String, String?)
            case table(String)
            case plugin(String, BlockPluginMatch)
            /// A custom renderer or visual block without a copy contract.
            case opaque
        }

        let id: String
        let segmentID: String
        let range: NSRange
        let content: Content
    }

    let document: ReaderVisibleDocumentProjection
    let attributedText: NSAttributedString
    let attachments: [Attachment]
    private let attachmentByID: [String: Attachment]

    init(document: ReaderVisibleDocumentProjection) {
        self.document = document
        let storage = NSMutableAttributedString(string: "")
        var mapped: [Attachment] = []
        for segment in document.segments {
            if storage.length > 0 { storage.append(NSAttributedString(string: "\n")) }
            assert(storage.length == segment.range.location)
            for (index, atom) in segment.atoms.enumerated() {
                let range = NSRange(location: storage.length, length: atom.text.utf16.count)
                let run = NSMutableAttributedString(string: atom.text)
                guard range.length > 0 else { continue }
                run.addAttributes([
                    Self.segmentIDAttribute: segment.id,
                    Self.segmentKindAttribute: String(describing: segment.kind),
                ], range: NSRange(location: 0, length: run.length))
                if let content = Self.attachmentContent(for: atom.kind) {
                    // A one-character attachment reserves a selectable position.
                    // The visible host must measure and replace it before display.
                    assert(atom.text == ReaderVisibleDocumentProjection.attachment)
                    let attachment = NSTextAttachment()
                    attachment.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
                    let id = segment.id + "/atom:" + String(index)
                    run.addAttributes([
                        .attachment: attachment,
                        Self.attachmentIDAttribute: id,
                    ], range: NSRange(location: 0, length: run.length))
                    mapped.append(.init(id: id, segmentID: segment.id, range: range,
                                        content: content))
                }
                storage.append(run)
            }
        }
        assert(storage.string == document.text)
        attributedText = NSAttributedString(attributedString: storage)
        attachments = mapped
        attachmentByID = Dictionary(uniqueKeysWithValues: mapped.map { ($0.id, $0) })
    }

    /// Copy uses the visible document's semantic text for hosted blocks.
    func copiedText(in range: NSRange) -> String? { document.copiedText(in: range) }

    func segmentID(atUTF16 offset: Int) -> String? {
        guard offset >= 0, offset < attributedText.length else { return nil }
        return attributedText.attribute(Self.segmentIDAttribute, at: offset,
                                        effectiveRange: nil) as? String
    }

    func attachment(atUTF16 offset: Int) -> Attachment? {
        guard offset >= 0, offset < attributedText.length,
              let id = attributedText.attribute(Self.attachmentIDAttribute, at: offset,
                                                effectiveRange: nil) as? String else { return nil }
        return attachmentByID[id]
    }

    private static func attachmentContent(for kind: ReaderVisibleDocumentProjection.Atom.Kind) -> Attachment.Content? {
        switch kind {
        case .text: nil
        case let .image(spec): .image(spec)
        case let .formula(latex): .formula(latex)
        case let .code(source, language): .code(source, language)
        case let .table(source): .table(source)
        case let .plugin(id, match): .plugin(id, match)
        case .opaque: .opaque
        }
    }
}
