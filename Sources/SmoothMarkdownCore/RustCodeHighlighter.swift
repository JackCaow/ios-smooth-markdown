import Foundation
#if canImport(CSmoothMarkdownRust)
import CSmoothMarkdownRust
#endif

/// Token stream from the shared Rust highlighter (`smr_highlight_utf16`).
/// Offsets are UTF-16 code units; `kind` values follow the Rust `Kind` enum.
@_spi(ReaderInternals) public struct RustCodeToken: Equatable, Sendable {
    @_spi(ReaderInternals) public let start: Int
    @_spi(ReaderInternals) public let length: Int
    @_spi(ReaderInternals) public let kind: UInt8
}

@_spi(ReaderInternals) public enum RustCodeHighlighter {
    @_spi(ReaderInternals) public static var isAvailable: Bool { RustMarkdownBridge.isAvailable }

    /// Tokens for `code`, or nil when the native highlighter is not linked.
    @_spi(ReaderInternals) public static func tokens(_ code: String, language: String) -> [RustCodeToken]? {
        #if canImport(CSmoothMarkdownRust)
        guard isAvailable else { return nil }
        let units = Array(code.utf16)
        let name = Array(language.utf8)
        var output = SmrBuffer(data: nil, len: 0, owner: nil)
        let status = units.withUnsafeBufferPointer { source in
            name.withUnsafeBufferPointer { lang in
                smr_highlight_utf16(source.baseAddress, source.count, lang.baseAddress, lang.count, &output)
            }
        }
        defer { smr_buffer_free(&output) }
        guard status == 0, let pointer = output.data, output.len >= 8 else { return nil }
        let bytes = UnsafeRawBufferPointer(start: pointer, count: output.len)
        func word(_ offset: Int) -> Int { Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian) }
        guard bytes[0] == 0x53, bytes[1] == 0x4D, bytes[2] == 0x48, bytes[3] == 0x31 else { return nil }
        let count = word(4)
        guard output.len >= 8 + count * 12 else { return nil }
        return (0..<count).map { index in
            let base = 8 + index * 12
            return RustCodeToken(start: word(base), length: word(base + 4), kind: UInt8(truncatingIfNeeded: word(base + 8)))
        }
        #else
        return nil
        #endif
    }

    /// Canonical language name, or nil when unsupported or the native core is not linked.
    @_spi(ReaderInternals) public static func normalizedLanguage(_ language: String) -> String? {
        #if canImport(CSmoothMarkdownRust)
        guard isAvailable else { return nil }
        let name = Array(language.utf8)
        var output = SmrBuffer(data: nil, len: 0, owner: nil)
        let status = name.withUnsafeBufferPointer { smr_highlight_language($0.baseAddress, $0.count, &output) }
        defer { smr_buffer_free(&output) }
        guard status == 0, let pointer = output.data, output.len > 0 else { return nil }
        return String(decoding: UnsafeRawBufferPointer(start: pointer, count: output.len), as: UTF8.self)
        #else
        return nil
        #endif
    }
}

/// One display line from the native core: text with tabs expanded and its tokens.
@_spi(ReaderInternals) public struct RustCodeLine: Sendable {
    @_spi(ReaderInternals) public let text: String
    @_spi(ReaderInternals) public let tokens: [RustCodeToken]
}

/// One unified-diff row from the native core.
@_spi(ReaderInternals) public struct RustDiffRow: Sendable {
    /// 0 hunk, 1 context, 2 added, 3 removed, 4 note.
    @_spi(ReaderInternals) public let kind: UInt8
    @_spi(ReaderInternals) public let number: Int?
    /// Word-level change in UTF-16 units of `line.text`.
    @_spi(ReaderInternals) public let changed: Range<Int>?
    @_spi(ReaderInternals) public let line: RustCodeLine
}

@_spi(ReaderInternals) extension RustCodeHighlighter {
    @_spi(ReaderInternals) public static func lines(_ code: String, language: String, tabWidth: Int) -> [RustCodeLine]? {
        #if canImport(CSmoothMarkdownRust)
        return call(code, language: language) { source, count, lang, langCount, output in
            smr_highlight_lines_utf16(source, count, lang, langCount, UInt32(max(0, tabWidth)), output)
        } decode: { reader in
            guard reader.magic("SML1") else { return nil }
            return (0..<reader.word()).compactMap { _ in reader.line() }
        }
        #else
        return nil
        #endif
    }

    @_spi(ReaderInternals) public static func diff(_ patch: String, language: String, tabWidth: Int) -> [RustDiffRow]? {
        #if canImport(CSmoothMarkdownRust)
        return call(patch, language: language) { source, count, lang, langCount, output in
            smr_diff_utf16(source, count, lang, langCount, UInt32(max(0, tabWidth)), output)
        } decode: { reader in
            guard reader.magic("SMD1") else { return nil }
            return (0..<reader.word()).compactMap { _ in
                let kind = UInt8(truncatingIfNeeded: reader.word())
                let number = reader.word()
                let start = reader.word(), length = reader.word()
                guard let line = reader.line() else { return nil }
                return RustDiffRow(kind: kind, number: number == 0xFFFF_FFFF ? nil : number,
                                   changed: start == 0xFFFF_FFFF ? nil : start..<(start + length), line: line)
            }
        }
        #else
        return nil
        #endif
    }

    #if canImport(CSmoothMarkdownRust)
    private static func call<T>(_ text: String, language: String,
                                _ native: (UnsafePointer<UInt16>?, Int, UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<SmrBuffer>) -> Int32,
                                decode: (WireReader) -> [T]?) -> [T]? {
        guard isAvailable else { return nil }
        let units = Array(text.utf16)
        let name = Array(language.utf8)
        var output = SmrBuffer(data: nil, len: 0, owner: nil)
        let status = units.withUnsafeBufferPointer { source in
            name.withUnsafeBufferPointer { lang in native(source.baseAddress, source.count, lang.baseAddress, lang.count, &output) }
        }
        defer { smr_buffer_free(&output) }
        guard status == 0, let pointer = output.data else { return nil }
        return decode(WireReader(UnsafeRawBufferPointer(start: pointer, count: output.len)))
    }
    #endif
}

/// Bounds-checked little-endian reader over a native result buffer.
private final class WireReader {
    private let bytes: UnsafeRawBufferPointer
    private var offset = 0
    private var failed = false
    init(_ bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

    func magic(_ tag: String) -> Bool {
        let expected = Array(tag.utf8)
        guard bytes.count >= 4, Array(bytes[0..<4]) == expected else { return false }
        offset = 4
        return true
    }
    func word() -> Int {
        guard !failed, offset + 4 <= bytes.count else { failed = true; return 0 }
        defer { offset += 4 }
        return Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian)
    }
    func line() -> RustCodeLine? {
        let length = word()
        guard !failed, offset + length * 2 <= bytes.count else { failed = true; return nil }
        let units = (0..<length).map { bytes.loadUnaligned(fromByteOffset: offset + $0 * 2, as: UInt16.self).littleEndian }
        offset += length * 2
        let count = word()
        guard !failed, offset + count * 12 <= bytes.count else { failed = true; return nil }
        let tokens = (0..<count).map { _ in RustCodeToken(start: word(), length: word(), kind: UInt8(truncatingIfNeeded: word())) }
        return RustCodeLine(text: String(decoding: units, as: UTF16.self), tokens: tokens)
    }
}
