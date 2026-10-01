# Reader parser and stream benchmark

This is an opt-in host microbenchmark. It measures parsing and stream accumulation; it does not measure SwiftUI layout, drawing, gesture latency, network images, or simulator/device memory.

Fixture: `Tests/SmoothMarkdownTests/Fixtures/FlutterREADME.md` is an exact copy of Flutter Smooth Markdown `README.md` at `80e6bb6`, SHA-256 `c84c04eb11485a1102fde7ab104ef2b86636dda4d45d7862d3289148330ef199`. The test repeats it four times with blank-line separators: 68,282 UTF-8 bytes. The rapid stream divides the document into 32-character chunks and advances synthetic time by 1 ms per chunk. A 50 ms update interval yields 42 intermediate publishes; each publish reparses the visible prefix, then completion reparses the full text. This reflects the stream update pattern in Flutter's stream tests. The test runs 3 parser warmups and 10 measured parses, then 2 stream warmups and 5 measured runs. Buffer-only runs isolate accumulation cost.

Run from this repository root:

```sh
SMOOTH_MARKDOWN_BENCH=1 swift test --filter ReaderPerformanceBenchmarkTests
```

Look for the `BENCH ios` line. On Apple M4, macOS 15.6.1, Apple Swift 6.2, macOS XCTest host process, 2026-09-28: full parse median 12.91 ms, maximum 14.73 ms; stream parse-and-buffer median 294.01 ms; buffer-only median 0.64 ms. Darwin `getrusage` peak process RSS was 19.4 MiB before measured parses, 22.5 MiB after them, and 28.0 MiB after streaming. Peak RSS cannot decrease and includes the XCTest process; it is not equivalent to Android's heap readings. First runs varied under concurrent build load; compare warmed repeated runs on the same host.

The benchmark is skipped during normal test runs. No timing threshold is asserted. A 50 ms synthetic interval is a logical schedule, not a real-time producer; the results cannot establish frame smoothness or long-session memory behavior. See the separate [iOS Simulator rendering measurement](simulator.md) for a repeatable long-document and rapid-stream UI scenario. Physical-device and long-session validation remain separate.


## Shared parser session measurement (2026-10-01)

The streaming reader now owns a parser session and reuses committed AST/Markup
blocks. Reference definitions invalidate dependent blocks. Plugins, math and
footnotes retain whole-document callback parsing; HTML/details keep their existing
source postprocessors. Both ordinary and selectable readers can consume the same
prepared document. Timer deadlines are reused while chunks accumulate.

Run the paired, uncached comparison with:

```sh
SMOOTH_MARKDOWN_BENCH=1 SMOOTH_MARKDOWN_RUST_REQUIRED=1 \
  swift test --filter ReaderPerformanceBenchmarkTests/testIncrementalSharedStreamComparison
```

On the arm64 macOS 15.6.1 host with Swift 6.2, SwiftPM Debug, median of three
runs per mode, 32-character chunks and a synthetic 50 ms publish interval:

| Identical input | UTF-8 bytes | Publishes | Full shared parse | Stream session |
| --- | ---: | ---: | ---: | ---: |
| Prose, headings, code, lists and inline links | 30,340 | 19 | 331.62 ms | 55.37 ms |
| Mixed FlutterREADME × 4 | 68,282 | 43 | 853.20 ms | 814.49 ms |

The prose workload reused 5,851 committed blocks across its publications. The
mixed README reaches conservative extension/postprocessor paths for 42 of 43
publications and improves little. The earlier cache-based benchmark measures warm
static-document hits; its timings are unsuitable as a live-stream baseline.

These measurements include parser/bridge/native projection work only. They exclude
SwiftUI layout, drawing, frame pacing, image loading and physical-device behavior.
There is no speed threshold assertion. Raw metadata is in
[the measurement record](evidence/ios-stream-parser-performance.json).
