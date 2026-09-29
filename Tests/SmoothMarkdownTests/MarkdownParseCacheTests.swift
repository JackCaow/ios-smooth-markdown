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

    func testUncachedParseDoesNotReadOrPopulateSharedCache() {
        SmoothMarkdownView.clearCache()
        _ = MarkdownSyntax.parse("# Uncached reader fixture", useCache: false)
        _ = MarkdownSyntax.parse("# Uncached reader fixture", useCache: false)
        XCTAssertEqual(SmoothMarkdownView.cacheStatistics.size, 0)
        XCTAssertEqual(SmoothMarkdownView.cacheStatistics.hits, 0)
        XCTAssertEqual(SmoothMarkdownView.cacheStatistics.misses, 0)
        _ = MarkdownSyntax.parse("# Uncached reader fixture")
        XCTAssertEqual(SmoothMarkdownView.cacheStatistics.size, 1)
        XCTAssertEqual(SmoothMarkdownView.cacheStatistics.misses, 1)
    }

    func testReaderSelectionAndCacheDefaultsMatchFlutter() {
        let reader = SmoothMarkdownView(markdown: "# Default reader")
        XCTAssertTrue(reader.enableCache)
        XCTAssertFalse(reader.selectable)
        XCTAssertTrue(reader.usesParseCache)
        let explicit = SmoothMarkdownView(markdown: "# Selectable reader",
                                          enableCache: false, selectable: true)
        XCTAssertFalse(explicit.enableCache)
        XCTAssertTrue(explicit.selectable)
        XCTAssertFalse(explicit.usesParseCache)
        let withPlugins = SmoothMarkdownView(markdown: "# Plugin reader", plugins: ParserPluginRegistry())
        XCTAssertFalse(withPlugins.usesParseCache)
    }
}
