import Foundation
#if canImport(CSmoothMarkdownRust)
import CSmoothMarkdownRust
#endif

/// The native batch ABI is optional in source checkouts and linked in packaged builds.
enum RustMarkdownBridge {
    private static let lock = NSLock()
    private static var successfulParses = 0
    private static var successfulHTMLExports = 0
    static var successfulParseCount: Int {
        lock.lock(); defer { lock.unlock() }
        return successfulParses
    }
    static var successfulHTMLExportCount: Int {
        lock.lock(); defer { lock.unlock() }
        return successfulHTMLExports
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
        // Decode synchronously while the Rust buffer remains alive. Nodes retain
        // owned Swift values; no borrowed Data escapes this call.
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: output.len, deallocator: .none)
        guard let root = try? RustMarkdownWire.decode(data, source: source) else { return nil }
        lock.lock(); successfulParses += 1; lock.unlock()
        return root
        #else
        return nil
        #endif
    }
    static func parseWithHooks(_ source: String,
                               inline: ((String, Int, Int) -> NativeMarkdownHookMatch?)?,
                               block: (([String], Int, Int) -> NativeMarkdownHookMatch?)?,
                               inlineOnly: Bool = false, references: NativeMarkdownNode? = nil) -> NativeMarkdownHookedDocument? {
        #if canImport(CSmoothMarkdownRust)
        guard isAvailable else { return nil }
        let context = RustMarkdownHookContext(inline: inline, block: block)
        var hooks = SmrHooks()
        hooks.context = Unmanaged.passUnretained(context).toOpaque()
        hooks.inline_callback = inline == nil ? nil : rustInlineCallback
        hooks.block_callback = block == nil ? nil : rustBlockCallback
        hooks.inline_context = inline == nil ? nil : rustInlineContext
        hooks.block_context = block == nil ? nil : rustBlockContext
        let units = Array(source.utf16)
        var output = SmrBuffer(data: nil, len: 0, owner: nil)
        let status: Int32
        if inlineOnly {
            guard let referenceBytes = RustMarkdownWire.encodeReferences(references) else { return nil }
            status = units.withUnsafeBufferPointer { input in
                referenceBytes.withUnsafeBytes {
                    smr_parse_inline_utf16(input.baseAddress, input.count, 3, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, &hooks, &output)
                }
            }
        } else {
            status = units.withUnsafeBufferPointer {
                smr_parse_with_hooks_utf16($0.baseAddress, $0.count, 3 | 16, &hooks, &output)
            }
        }
        defer { smr_buffer_free(&output) }
        guard status == 0, let pointer = output.data, output.len <= 64 * 1024 * 1024,
              let result = try? RustMarkdownWire.decodeHooked(Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: pointer), count: output.len, deallocator: .none), source: source) else { return nil }
        lock.lock(); successfulParses += 1; lock.unlock()
        return result
        #else
        return nil
        #endif
    }

    static func exportHTML(_ source: String, enableGFM: Bool) -> String? {
        #if canImport(CSmoothMarkdownRust)
        guard isAvailable else { return nil }
        let units = Array(source.utf16)
        var output = SmrBuffer(data: nil, len: 0, owner: nil)
        let status = units.withUnsafeBufferPointer {
            smr_export_html_utf16($0.baseAddress, $0.count, (enableGFM ? 1 : 0) | 2, &output)
        }
        defer { smr_buffer_free(&output) }
        return decodeHTML(status: status, buffer: output)
        #else
        return nil
        #endif
    }

    static func renderHTML(_ node: NativeMarkdownNode) -> String? {
        #if canImport(CSmoothMarkdownRust)
        guard isAvailable, let bytes = RustMarkdownWire.encodeForRendering(node) else { return nil }
        var output = SmrBuffer(data: nil, len: 0, owner: nil)
        // AST values are authoritative: never reparse node.source or apply a
        // source-level GFM tag filter to a caller's explicitly constructed HTML.
        let status = bytes.withUnsafeBytes {
            smr_render_ast_utf16($0.bindMemory(to: UInt8.self).baseAddress, $0.count, 8, &output)
        }
        defer { smr_buffer_free(&output) }
        return decodeHTML(status: status, buffer: output)
        #else
        return nil
        #endif
    }

    #if canImport(CSmoothMarkdownRust)
    private static func decodeHTML(status: Int32, buffer: SmrBuffer) -> String? {
        guard status == 0, buffer.len <= 64 * 1024 * 1024, buffer.len.isMultiple(of: 2),
              buffer.len == 0 || buffer.data != nil else { return nil }
        var units = [UInt16](); units.reserveCapacity(buffer.len / 2)
        if let pointer = buffer.data {
            for offset in stride(from: 0, to: buffer.len, by: 2) {
                units.append(UInt16(pointer[offset]) | UInt16(pointer[offset + 1]) << 8)
            }
        }
        lock.lock(); successfulHTMLExports += 1; lock.unlock()
        return String(decoding: units, as: UTF16.self)
    }
    #endif

}

/// Reads source strings as UTF-16 units rather than round-tripping byte offsets through UTF-8.
enum RustMarkdownWire {
    enum InvalidWire: Error { case malformed }
    static func decode(_ data: Data, source: String) throws -> NativeMarkdownNode {
        let result = try decodeHooked(data, source: source)
        guard result.customNodes.isEmpty else { throw InvalidWire.malformed }
        return result.tree
    }
    static func decodeHooked(_ data: Data, source: String) throws -> NativeMarkdownHookedDocument {
        var reader = Reader(bytes: Array(data), originalSource: source as NSString)
        guard reader.bytes.count >= 8, Array(reader.bytes.prefix(4)) == [83, 77, 82, 49] else { throw InvalidWire.malformed }
        reader.offset = 4
        let total = try reader.integer()
        guard total > 0, total <= reader.bytes.count / 32 else { throw InvalidWire.malformed }
        reader.remainingNodes = total
        let root = try reader.node(depth: 0)
        guard root.kind == .document, root.sourceRange == NSRange(location: 0, length: (source as NSString).length),
              reader.remainingNodes == 0, reader.offset == reader.bytes.count else { throw InvalidWire.malformed }
        return .init(tree: root, customNodes: reader.customNodes)
    }
    static func encodeReferences(_ root: NativeMarkdownNode?) -> Data? {
        var stack = root.map { [$0] } ?? []; var definitions: [(String, String, String?)] = []
        while let node = stack.popLast() {
            if case let .referenceDefinition(label, destination) = node.kind { definitions.append((label, destination, node.title)) }
            stack += node.children.reversed()
        }
        var writer = Writer(maximum: 64 * 1024 * 1024)
        writer.data.append(contentsOf: [83, 77, 70, 49])
        guard writer.word(definitions.count) else { return nil }
        for (label, destination, title) in definitions {
            guard writer.string(label), writer.string(destination), writer.string(title) else { return nil }
        }
        return writer.data
    }
    /// Host AST export always spells out source fields. Source sentinels are
    /// reserved for parser output and cannot describe independently edited nodes.
    static func encodeForRendering(_ root: NativeMarkdownNode) -> Data? {
        let maximum = 64 * 1024 * 1024
        var count = 0
        var stack = [(root, 0)]
        while let (node, depth) = stack.popLast() {
            guard depth <= 256, count < 1_000_000 else { return nil }
            count += 1
            guard node.children.count <= 1_000_000 - count - stack.count else { return nil }
            stack += node.children.reversed().map { ($0, depth + 1) }
        }
        var writer = Writer(maximum: maximum)
        writer.data.append(contentsOf: [83, 77, 82, 49])
        guard writer.word(count) else { return nil }
        var nodes = [root]
        while let node = nodes.popLast() {
            let id: Int; let level = 0; var info = ""; var destination = ""; var label = ""; var flags = 0
            switch node.kind {
            case .document: id = 0
            case .paragraph: id = 1
            case let .heading(value): id = 2; flags |= 128; label = String(value)
            case let .fencedCode(value): id = 3; info = value
            case .indentedCode: id = 4
            case .table: id = 5
            case .tableRow: id = 6
            case .tableCell: id = 7
            case let .list(ordered): id = 8; if ordered { flags |= 1 }
            case let .listItem(checked):
                id = 9
                if let checked { flags |= 4; if checked { flags |= 2 } }
            case .blockQuote: id = 10
            case .thematicBreak: id = 11
            case .text: id = 12
            case .strong: id = 13
            case .emphasis: id = 14
            case .strikethrough: id = 15
            case .inlineCode: id = 16
            case .inlineMath: id = 17
            case .softBreak: id = 18
            case .hardBreak: id = 19
            case .inlineHTML: id = 20
            case .blockMath: id = 21
            case let .footnoteReference(value): id = 22; label = value
            case let .footnoteDefinition(value): id = 23; label = value
            case let .referenceDefinition(value, url): id = 24; label = value; destination = url
            case let .link(url): id = 25; destination = url
            case let .image(url): id = 26; destination = url
            case .htmlBlock: id = 27
            case .raw: id = 28
            }
            if let tight = node.isTight { flags |= 16; if tight { flags |= 8 } }
            var listStartWord = node.listStart ?? 0
            if node.listStart != nil { flags |= 32 }
            if case .list = node.kind, let value = node.listStart {
                flags |= 128; label = String(value); listStartWord = 0
            }
            let start = UInt32(exactly: node.sourceRange.location).map(Int.init) ?? 0
            let length = UInt32(exactly: node.sourceRange.length).map(Int.init) ?? 0
            for word in [id, start, length, level, flags, listStartWord, node.children.count] {
                guard writer.word(word) else { return nil }
            }
            for value in [Optional(node.source), Optional(info), Optional(destination), node.title,
                          node.semanticText ?? node.literalText, Optional(label)] {
                guard writer.string(value) else { return nil }
            }
            guard writer.word(node.tableAlignments.count) else { return nil }
            for alignment in node.tableAlignments { guard writer.string(alignment) else { return nil } }
            nodes += node.children.reversed()
        }
        return writer.data
    }

    private struct Writer {
        let maximum: Int
        var data = Data()
        mutating func word(_ value: Int) -> Bool {
            guard let number = UInt32(exactly: value), data.count <= maximum - 4 else { return false }
            data.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) })
            return true
        }
        mutating func string(_ value: String?) -> Bool {
            guard let value else { return word(Int(UInt32.max)) }
            let units = Array(value.utf16)
            guard units.count <= (maximum - data.count - 4) / 2, word(units.count) else { return false }
            for unit in units { data.append(UInt8(truncatingIfNeeded: unit)); data.append(UInt8(truncatingIfNeeded: unit >> 8)) }
            return true
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        let originalSource: NSString
        var sourceLength: Int { originalSource.length }
        var offset = 0
        var remainingNodes = 0
        var customNodes: [NativeMarkdownHookNode] = []
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
            case 29:
                guard let matchID = UInt32(label), matchID > 0 else { throw InvalidWire.malformed }
                customNodes.append(.init(id: matchID, range: NSRange(location: start, length: length)))
                kind = .raw
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
    public static var isAvailable: Bool { RustMarkdownBridge.isAvailable }
    public static func parse(_ source: String) -> NativeMarkdownNode? {
        RustMarkdownBridge.parse(source, enableGFM: true)
    }
}

/// Callback data is package SPI: host plugin objects remain in the UI module.
@_spi(ReaderInternals) public struct NativeMarkdownHookMatch {
    public let consumed: Int
    public let id: UInt32
    public init(consumed: Int, id: UInt32) { self.consumed = consumed; self.id = id }
}
@_spi(ReaderInternals) public struct NativeMarkdownHookNode {
    public let id: UInt32
    public let range: NSRange
}
@_spi(ReaderInternals) public struct NativeMarkdownHookedDocument {
    public let tree: NativeMarkdownNode
    public let customNodes: [NativeMarkdownHookNode]
}
extension NativeMarkdownExtensionProjection {
    public static func parseInlineWithHooks(_ source: String, references: NativeMarkdownNode,
        inline: ((String, Int, Int) -> NativeMarkdownHookMatch?)? = nil) -> NativeMarkdownHookedDocument? {
        RustMarkdownBridge.parseWithHooks(source, inline: inline, block: nil, inlineOnly: true, references: references)
    }
    public static func parseWithHooks(_ source: String,
        inline: ((String, Int, Int) -> NativeMarkdownHookMatch?)? = nil,
        block: (([String], Int, Int) -> NativeMarkdownHookMatch?)? = nil) -> NativeMarkdownHookedDocument? {
        RustMarkdownBridge.parseWithHooks(source, inline: inline, block: block)
    }
}

#if canImport(CSmoothMarkdownRust)
private final class RustMarkdownHookContext {
    let inline: ((String, Int, Int) -> NativeMarkdownHookMatch?)?
    let block: (([String], Int, Int) -> NativeMarkdownHookMatch?)?
    var inlineScopes: [String] = []
    var blockScopes: [[String]] = []
    init(inline: ((String, Int, Int) -> NativeMarkdownHookMatch?)?, block: (([String], Int, Int) -> NativeMarkdownHookMatch?)?) {
        self.inline = inline; self.block = block
    }
}
private func rustInlineContext(_ opaque: UnsafeMutableRawPointer?, _ source: UnsafePointer<UInt16>?, _ length: Int, _ begin: Int32) -> Int32 {
    guard let opaque else { return -1 }
    let context = Unmanaged<RustMarkdownHookContext>.fromOpaque(opaque).takeUnretainedValue()
    if begin == 0 { guard !context.inlineScopes.isEmpty else { return -1 }; context.inlineScopes.removeLast(); return 0 }
    guard length <= 16 * 1024 * 1024, length == 0 || source != nil else { return -1 }
    context.inlineScopes.append(length == 0 ? "" : String(decoding: UnsafeBufferPointer(start: source, count: length), as: UTF16.self))
    return 0
}
private func rustBlockContext(_ opaque: UnsafeMutableRawPointer?, _ lines: UnsafePointer<UnsafePointer<UInt16>?>?, _ lengths: UnsafePointer<Int>?, _ count: Int, _ begin: Int32) -> Int32 {
    guard let opaque else { return -1 }
    let context = Unmanaged<RustMarkdownHookContext>.fromOpaque(opaque).takeUnretainedValue()
    if begin == 0 { guard !context.blockScopes.isEmpty else { return -1 }; context.blockScopes.removeLast(); return 0 }
    guard count <= 16 * 1024 * 1024, count == 0 || (lines != nil && lengths != nil) else { return -1 }
    var decoded: [String] = []; var total = 0
    for index in 0..<count {
        let length = lengths![index]
        guard length >= 0, length <= 16 * 1024 * 1024 - total, length == 0 || lines![index] != nil else { return -1 }
        total += length
        decoded.append(length == 0 ? "" : String(decoding: UnsafeBufferPointer(start: lines![index], count: length), as: UTF16.self))
    }
    context.blockScopes.append(decoded); return 0
}
private func rustInlineCallback(_ opaque: UnsafeMutableRawPointer?, _ source: UnsafePointer<UInt16>?, _ length: Int,
                                _ index: UInt32, _ absolute: UInt32, _ output: UnsafeMutablePointer<SmrMatch>?) -> Int32 {
    guard let opaque, let output else { return -1 }
    let context = Unmanaged<RustMarkdownHookContext>.fromOpaque(opaque).takeUnretainedValue()
    guard let text = context.inlineScopes.last, let match = context.inline?(text, Int(index), Int(absolute)),
          match.id > 0, match.consumed > 0, let consumed = UInt32(exactly: match.consumed) else { return 0 }
    output.pointee = SmrMatch(consumed: consumed, id: match.id); return 1
}
private func rustBlockCallback(_ opaque: UnsafeMutableRawPointer?, _ source: UnsafePointer<UnsafePointer<UInt16>?>?, _ lengths: UnsafePointer<Int>?, _ count: Int,
                               _ index: UInt32, _ absolute: UInt32, _ output: UnsafeMutablePointer<SmrMatch>?) -> Int32 {
    guard let opaque, let output else { return -1 }
    let context = Unmanaged<RustMarkdownHookContext>.fromOpaque(opaque).takeUnretainedValue()
    guard let lines = context.blockScopes.last, let match = context.block?(lines, Int(index), Int(absolute)),
          match.id > 0, match.consumed > 0, let consumed = UInt32(exactly: match.consumed) else { return 0 }
    output.pointee = SmrMatch(consumed: consumed, id: match.id); return 1
}
#endif
