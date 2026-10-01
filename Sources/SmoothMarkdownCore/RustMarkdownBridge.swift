import Foundation
#if canImport(CSmoothMarkdownRust)
import CSmoothMarkdownRust
#endif

/// The native batch ABI is optional in source checkouts and linked in packaged builds.
enum RustMarkdownBridge {
    private static let lock = NSLock()
    private static var successfulParses = 0
    static var successfulParseCount: Int {
        lock.lock(); defer { lock.unlock() }
        return successfulParses
    }
    static var isAvailable: Bool {
        #if canImport(CSmoothMarkdownRust)
        return smr_abi_version() == 1
        #else
        return false
        #endif
    }
    static func parse(_ source: String, enableGFM: Bool) -> NativeMarkdownNode? {
        #if canImport(CSmoothMarkdownRust)
        guard isAvailable else { return nil }
        let units = Array(source.utf16)
        var output = SmrBuffer(data: nil, len: 0, owner: nil)
        let status = units.withUnsafeBufferPointer { input in
            smr_parse_utf16(input.baseAddress, input.count, (enableGFM ? 1 : 0) | 2, &output)
        }
        defer { smr_buffer_free(&output) }
        guard status == 0, let pointer = output.data, output.len <= 64 * 1024 * 1024 else { return nil }
        let data = Data(bytes: pointer, count: output.len)
        guard let root = try? RustMarkdownWire.decode(data, source: source) else { return nil }
        lock.lock(); successfulParses += 1; lock.unlock()
        return root
        #else
        return nil
        #endif
    }
}

/// Reads source strings as UTF-16 units rather than round-tripping byte offsets through UTF-8.
enum RustMarkdownWire {
    enum InvalidWire: Error { case malformed }
    static func decode(_ data: Data, source: String) throws -> NativeMarkdownNode {
        var reader = Reader(bytes: Array(data), originalSource: source as NSString)
        guard reader.bytes.count >= 8, Array(reader.bytes.prefix(4)) == [83, 77, 82, 49] else { throw InvalidWire.malformed }
        reader.offset = 4
        let total = try reader.integer()
        guard total > 0, total <= reader.bytes.count / 32 else { throw InvalidWire.malformed }
        reader.remainingNodes = total
        let root = try reader.node(depth: 0)
        guard root.kind == .document, root.sourceRange == NSRange(location: 0, length: (source as NSString).length),
              reader.remainingNodes == 0, reader.offset == reader.bytes.count else { throw InvalidWire.malformed }
        return root
    }
    private struct Reader {
        let bytes: [UInt8]
        let originalSource: NSString
        var sourceLength: Int { originalSource.length }
        var offset = 0
        var remainingNodes = 0
        mutating func word() throws -> UInt32 {
            guard offset <= bytes.count - 4 else { throw InvalidWire.malformed }
            var value: UInt32 = 0
            for index in 0..<4 { value |= UInt32(bytes[offset + index]) << (index * 8) }
            offset += 4
            return value
        }
        mutating func integer() throws -> Int { Int(try word()) }
        mutating func string(length: UInt32? = nil) throws -> String? {
            let length = try length ?? word()
            if length == UInt32.max { return nil }
            guard Int(length) <= (bytes.count - offset) / 2 else { throw InvalidWire.malformed }
            var units = [UInt16](); units.reserveCapacity(Int(length))
            for _ in 0..<Int(length) {
                units.append(UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)); offset += 2
            }
            return String(decoding: units, as: UTF16.self)
        }
        mutating func requiredString() throws -> String {
            guard let value = try string() else { throw InvalidWire.malformed }
            return value
        }
        mutating func node(depth: Int) throws -> NativeMarkdownNode {
            guard depth <= 256, remainingNodes > 0 else { throw InvalidWire.malformed }
            remainingNodes -= 1
            let id = try integer(); let start = try integer(); let length = try integer()
            guard start <= sourceLength, length <= sourceLength - start else { throw InvalidWire.malformed }
            let level = try integer(); let flags = try integer(); let listStart = try integer(); let childCount = try integer()
            guard childCount <= remainingNodes else { throw InvalidWire.malformed }
            let sourceUnits = try word()
            let source: String
            if sourceUnits == UInt32.max - 1 { source = originalSource.substring(with: NSRange(location: start, length: length)) }
            else { guard let decoded = try string(length: sourceUnits) else { throw InvalidWire.malformed }; source = decoded }
            let info = try requiredString(); let destination = try requiredString()
            let title = try string(); let literal = try string(); let label = try requiredString()
            let alignmentCount = try integer()
            guard alignmentCount <= (bytes.count - offset) / 4 else { throw InvalidWire.malformed }
            var alignments = [String?]()
            for _ in 0..<alignmentCount { alignments.append(try string()) }
            var children = [NativeMarkdownNode]()
            for _ in 0..<childCount { children.append(try node(depth: depth + 1)) }
            if id == 8, flags & 16 != 0, flags & 8 != 0 {
                children = children.map { item in
                    guard case .listItem = item.kind else { return item }
                    return .init(kind: item.kind, source: item.source, sourceRange: item.sourceRange,
                                 children: item.children.flatMap { $0.kind == .paragraph ? $0.children : [$0] },
                                 title: item.title, isTight: item.isTight, listStart: item.listStart,
                                 literalText: item.literalText, tableAlignments: item.tableAlignments)
                }
            }
            let kind: NativeMarkdownNode.Kind
            switch id {
            case 0: kind = .document
            case 1: kind = .paragraph
            case 2: kind = .heading(level)
            case 3: kind = .fencedCode(info)
            case 4: kind = .indentedCode
            case 5: kind = .table
            case 6: kind = .tableRow
            case 7: kind = .tableCell
            case 8: kind = .list(ordered: flags & 1 != 0)
            case 9: kind = .listItem(checked: flags & 4 != 0 ? flags & 2 != 0 : nil)
            case 10: kind = .blockQuote
            case 11: kind = .thematicBreak
            case 12: kind = .text
            case 13: kind = .strong
            case 14: kind = .emphasis
            case 15: kind = .strikethrough
            case 16: kind = .inlineCode
            case 17: kind = .inlineMath
            case 18: kind = .softBreak
            case 19: kind = .hardBreak
            case 20: kind = .inlineHTML
            case 21: kind = .blockMath
            case 22: kind = .footnoteReference(label)
            case 23: kind = .footnoteDefinition(label)
            case 24: kind = .referenceDefinition(label, destination)
            case 25: kind = .link(destination)
            case 26: kind = .image(destination)
            case 27: kind = .htmlBlock
            case 28: kind = .raw
            default: throw InvalidWire.malformed
            }
            return .init(kind: kind, source: source, sourceRange: NSRange(location: start, length: length),
                         children: children, title: title, isTight: flags & 16 != 0 ? flags & 8 != 0 : nil,
                         listStart: flags & 32 != 0 ? listStart : nil, literalText: literal, tableAlignments: alignments)
        }
    }
}

/// Package-internal source projection used by extension renderers. A source-only build
/// returns nil so existing extension scanners retain their original behavior.
@_spi(ReaderInternals) public enum NativeMarkdownExtensionProjection {
    public static func parse(_ source: String) -> NativeMarkdownNode? {
        RustMarkdownBridge.parse(source, enableGFM: true)
    }
}
