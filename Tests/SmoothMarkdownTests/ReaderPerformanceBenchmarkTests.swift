@testable import SmoothMarkdown
import Foundation
import XCTest
import Darwin

/// Opt-in observational benchmark: SMOOTH_MARKDOWN_BENCH=1 swift test --filter ReaderPerformanceBenchmarkTests
final class ReaderPerformanceBenchmarkTests: XCTestCase {
    func testREADMEParseAndRapidStream() throws {
        guard ProcessInfo.processInfo.environment["SMOOTH_MARKDOWN_BENCH"] == "1" else {
            throw XCTSkip("Set SMOOTH_MARKDOWN_BENCH=1 to run the observational benchmark")
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "FlutterREADME", withExtension: "md"))
        let readme = try String(contentsOf: url, encoding: .utf8)
        let document = Array(repeating: readme, count: 4).joined(separator: "\n\n")
        XCTAssertGreaterThan(document.utf8.count, 60_000)
        func peakRSS() -> Double {
            var usage = rusage()
            _ = getrusage(0, &usage)
            return Double(usage.ru_maxrss) / 1_048_576
        }
        for _ in 0..<3 { _ = MarkdownSyntax.parse(document) }
        let before = peakRSS()
        var parseTimes: [Double] = []
        for _ in 0..<10 {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = MarkdownSyntax.parse(document)
            parseTimes.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        let afterParse = peakRSS()
        let characters = Array(document)
        let chunks = stride(from: 0, to: characters.count, by: 32).map {
            String(characters[$0..<min($0 + 32, characters.count)])
        }
        func stream(parseOnPublish: Bool) -> (Double, Int) {
            var buffer = StreamMarkdownBuffer(intervalMillis: 50, startMillis: 0)
            var published = 0
            let start = DispatchTime.now().uptimeNanoseconds
            for (index, chunk) in chunks.enumerated() {
                if buffer.append(chunk, nowMillis: Int64(index + 1)) == nil {
                    if parseOnPublish { _ = MarkdownSyntax.parse(buffer.visibleText) }
                    published += 1
                }
            }
            buffer.finish(nowMillis: Int64(chunks.count + 1))
            if parseOnPublish { _ = MarkdownSyntax.parse(buffer.visibleText) }
            XCTAssertEqual(buffer.visibleText, document)
            XCTAssertGreaterThan(published, 20)
            return (Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000, published)
        }
        for _ in 0..<2 { _ = stream(parseOnPublish: true) }
        let streamRuns = (0..<5).map { _ in stream(parseOnPublish: true) }
        let bufferOnlyRuns = (0..<5).map { _ in stream(parseOnPublish: false).0 }.sorted()
        let streamMedian = streamRuns.map(\.0).sorted()[2]
        parseTimes.sort()
        print(String(format: "BENCH ios fixtureBytes=%d chunks=%d publishes=%d parseMedianMs=%.2f parseMaxMs=%.2f streamMedianMs=%.2f bufferOnlyMedianMs=%.2f peakRSSBeforeMiB=%.1f peakRSSAfterParseMiB=%.1f peakRSSAfterStreamMiB=%.1f",
                     document.utf8.count, chunks.count, streamRuns[0].1, parseTimes[5], parseTimes[9], streamMedian, bufferOnlyRuns[2],
                     before, afterParse, peakRSS()))
    }
}
