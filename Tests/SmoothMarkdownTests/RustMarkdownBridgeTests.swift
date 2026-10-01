import XCTest
@testable import SmoothMarkdownCore
@testable import SmoothMarkdown

final class RustMarkdownBridgeTests: XCTestCase {
    private func requireBackend() throws {
        guard RustMarkdownBridge.isAvailable else {
            if ProcessInfo.processInfo.environment["SMOOTH_MARKDOWN_RUST_REQUIRED"] == "1" {
                throw NSError(domain: "RequiredRustBackendUnavailable", code: 1)
            }
            throw XCTSkip("Native Rust framework is optional in source-only builds")
        }
    }
    func testFullOfficialCommonMarkRunsThroughRustForEveryExample() throws {
        try requireBackend()
        guard let path = ProcessInfo.processInfo.environment["COMMONMARK_SPEC_JSON"] else {
            throw XCTSkip("Set COMMONMARK_SPEC_JSON for the full official Rust adapter fixture gate")
        }
        let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[String: Any]])
        XCTAssertEqual(examples.count, 652)
        for example in examples {
            let source = try XCTUnwrap(example["markdown"] as? String)
            let before = RustMarkdownBridge.successfulParseCount
            let root = NativeMarkdownASTParser(enableGFM: false).parse(source)
            XCTAssertGreaterThan(RustMarkdownBridge.successfulParseCount, before, "Rust fallback masked example \(example["example"] ?? "unknown")")
            XCTAssertEqual(NativeMarkdownHTMLSerializer.render(root), example["html"] as? String, "Example \(example["example"] ?? "unknown")")
        }
    }
    func testCoreActuallyUsesRustAndKeepsUnicodeSpans() throws {
        try requireBackend()
        let source = "# 中文🙂e\u{301}\r\n\r\nA **粗体** [链接](https://example.test/🙂)"
        let before = RustMarkdownBridge.successfulParseCount
        let root = MarkdownCoreParser().parse(source)
        XCTAssertGreaterThan(RustMarkdownBridge.successfulParseCount, before)
        XCTAssertEqual(root.sourceRange, NSRange(location: 0, length: source.utf16.count))
        XCTAssertEqual(root.source, source)
        func verify(_ node: NativeMarkdownNode) {
            XCTAssertEqual((source as NSString).substring(with: node.sourceRange), node.source)
            node.children.forEach(verify)
        }
        verify(root)
    }
    func testReaderDocumentActuallyUsesRust() throws {
        try requireBackend()
        let before = RustMarkdownBridge.successfulParseCount
        let document = Document(parsing: "# 中文🙂\n\nA **bold**")
        XCTAssertGreaterThan(RustMarkdownBridge.successfulParseCount, before)
        XCTAssertTrue(document.child(at: 0) is Heading)
        XCTAssertEqual((document.child(at: 0) as? Heading)?.level, 1)
    }
    func testReaderExtensionHelpersActuallyUseRust() throws {
        try requireBackend()
        var before = RustMarkdownBridge.successfulParseCount
        XCTAssertEqual(MathSyntax.sections("Intro\n$$x^2$$"), [.markdown("Intro"), .block("x^2")])
        XCTAssertGreaterThan(RustMarkdownBridge.successfulParseCount, before)
        before = RustMarkdownBridge.successfulParseCount
        XCTAssertEqual(MathSyntax.inlineParts(in: "Given $x=1$"), [.text("Given "), .math("x=1")])
        XCTAssertGreaterThan(RustMarkdownBridge.successfulParseCount, before)
        before = RustMarkdownBridge.successfulParseCount
        XCTAssertEqual(FootnoteSyntax.sections("Text[^a]\n\n[^a]: Notes"), [.markdown("Text[^a]\n"), .definition(.init(label: "a", content: "Notes"))])
        XCTAssertGreaterThan(RustMarkdownBridge.successfulParseCount, before)
        before = RustMarkdownBridge.successfulParseCount
        XCTAssertEqual(FootnoteSyntax.parts(in: "Text[^a]"), [.text("Text"), .reference("a")])
        XCTAssertGreaterThan(RustMarkdownBridge.successfulParseCount, before)
    }
    func testOptionalEndToEndFFIAndHostDecodeBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SMOOTH_MARKDOWN_BENCH"] == "1" else { throw XCTSkip("Set SMOOTH_MARKDOWN_BENCH=1 for observational FFI plus host AST decoding timings") }
        try requireBackend()
        let sample = "# Heading 中文🙂\n\nParagraph with **bold** and [link](https://example.test).\n\n- first\n- second\n\n"
        let source = String(repeating: sample, count: max(1, 100_000 / sample.utf8.count))
        let before = RustMarkdownBridge.successfulParseCount
        let started = Date()
        for _ in 0..<5 { XCTAssertEqual(NativeMarkdownASTParser().parse(source).source, source) }
        XCTAssertEqual(RustMarkdownBridge.successfulParseCount - before, 5)
        print("Rust host end-to-end: bytes=\(source.utf8.count), parses=5, ms=\(Date().timeIntervalSince(started) * 1000)")
    }
    func testWireSourceSentinelReadsOriginalUTF16Slice() throws {
        let source = "中文🙂"
        var bytes = Data([83, 77, 82, 49])
        func word(_ value: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> shift)) } }
        word(1); word(0); word(0); word(UInt32(source.utf16.count))
        word(0); word(0); word(0); word(0)
        word(UInt32.max - 1); word(0); word(0); word(UInt32.max); word(UInt32.max); word(0); word(0)
        let root = try RustMarkdownWire.decode(bytes, source: source)
        XCTAssertEqual(root.source, source)
    }
    func testWirePreservesUTF16AndRejectsTruncation() throws {
        let source = "中文🙂e\u{301}"
        var bytes = Data([83, 77, 82, 49])
        func word(_ value: UInt32) { for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> shift)) } }
        func string(_ value: String?) {
            guard let value else { word(UInt32.max); return }
            let units = Array(value.utf16); word(UInt32(units.count))
            for unit in units { bytes.append(UInt8(truncatingIfNeeded: unit)); bytes.append(UInt8(truncatingIfNeeded: unit >> 8)) }
        }
        func record(_ id: UInt32, _ children: UInt32, _ literal: String? = nil) {
            word(id); word(0); word(UInt32(source.utf16.count)); word(0); word(0); word(0); word(children)
            string(source); string(""); string(""); string(nil); string(literal); string(""); word(0)
        }
        word(3); record(0, 1); record(1, 1); record(12, 0, source)
        let root = try RustMarkdownWire.decode(bytes, source: source)
        XCTAssertEqual(root.children.first?.children.first?.literalText, source)
        XCTAssertThrowsError(try RustMarkdownWire.decode(Data(bytes.dropLast()), source: source))
        var invalidRange = bytes; invalidRange[12] = 127
        XCTAssertThrowsError(try RustMarkdownWire.decode(invalidRange, source: source))
        var trailing = bytes; trailing.append(0)
        XCTAssertThrowsError(try RustMarkdownWire.decode(trailing, source: source))
    }
}
