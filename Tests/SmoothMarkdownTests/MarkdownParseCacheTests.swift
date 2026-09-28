import XCTest
@testable import SmoothMarkdown

final class MarkdownParseCacheTests: XCTestCase {
    func testExactSourceReuseAndLRUEviction() {
        let cache = MarkdownParseCache(maxSize: 2)
        _ = cache.parse("# A")
        _ = cache.parse("# B")
        _ = cache.parse("# A") // A is now most recently used.
        _ = cache.parse("# C") // Evicts B.
        _ = cache.parse("# A")
        _ = cache.parse("# B") // Parses B again and evicts C.

        let stats = cache.statistics
        XCTAssertEqual(stats.size, 2)
        XCTAssertEqual(stats.maxSize, 2)
        XCTAssertEqual(stats.hits, 2)
        XCTAssertEqual(stats.misses, 4)
        XCTAssertEqual(stats.utilization, 1)
    }

    func testReaderParsePathReportsRealOccupancyAndClearResetsIt() {
        SmoothMarkdownView.clearCache()
        _ = MarkdownSyntax.parse("# Reader cache fixture")
        _ = MarkdownSyntax.parse("# Reader cache fixture")
        let stats = SmoothMarkdownView.cacheStatistics
        XCTAssertEqual(stats.size, 1)
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.misses, 1)
        SmoothMarkdownView.clearCache()
        XCTAssertEqual(SmoothMarkdownView.cacheStatistics.size, 0)
        XCTAssertEqual(SmoothMarkdownView.cacheStatistics.hits, 0)
    }
}
