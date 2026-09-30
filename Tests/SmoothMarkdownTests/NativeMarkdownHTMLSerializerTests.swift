import Foundation
import XCTest
@testable import SmoothMarkdown

final class NativeMarkdownHTMLSerializerTests: XCTestCase {
    func testFullOfficialCommonMarkHTMLExport() throws {
        guard let path = ProcessInfo.processInfo.environment["COMMONMARK_SPEC_JSON"] else {
            throw XCTSkip("Set COMMONMARK_SPEC_JSON to verify all official HTML export examples")
        }
        let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[String: Any]])
        XCTAssertEqual(examples.count, 652)
        for example in examples {
            XCTAssertEqual(NativeMarkdownHTMLSerializer.format(try XCTUnwrap(example["markdown"] as? String), enableGFM: false),
                           example["html"] as? String, "Example \(example["example"]!)")
        }
    }

    func testOfficialGFMHTMLExport() throws {
        for fixture in ["gfm-tables", "gfm-inline", "gfm-tagfilter"] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "json"))
            let examples = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
            for example in examples {
                XCTAssertEqual(NativeMarkdownHTMLSerializer.format(try XCTUnwrap(example["markdown"])), example["html"])
            }
        }
        XCTAssertEqual(NativeMarkdownHTMLSerializer.format("- [x] done\n- [ ] todo\n"),
                       "<ul>\n<li><input checked=\"\" disabled=\"\" type=\"checkbox\"> done</li>\n<li><input disabled=\"\" type=\"checkbox\"> todo</li>\n</ul>\n")
    }
}
