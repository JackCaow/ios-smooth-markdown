# Reader parser and stream benchmark

This is an opt-in host microbenchmark. It measures parsing and stream accumulation; it does not measure SwiftUI layout, drawing, gesture latency, network images, or simulator/device memory.

Fixture: `Tests/SmoothMarkdownTests/Fixtures/FlutterREADME.md` is an exact copy of Flutter Smooth Markdown `README.md` at `80e6bb6`, SHA-256 `c84c04eb11485a1102fde7ab104ef2b86636dda4d45d7862d3289148330ef199`. The test repeats it four times with blank-line separators: 68,282 UTF-8 bytes. The rapid stream divides the document into 32-character chunks and advances synthetic time by 1 ms per chunk. A 50 ms update interval yields 42 intermediate publishes; each publish reparses the visible prefix, then completion reparses the full text. This reflects the stream update pattern in Flutter's stream tests. The test runs 3 parser warmups and 10 measured parses, then 2 stream warmups and 5 measured runs. Buffer-only runs isolate accumulation cost.

Run from this repository root:

```sh
SMOOTH_MARKDOWN_BENCH=1 swift test --filter ReaderPerformanceBenchmarkTests
```

Look for the `BENCH ios` line. On Apple M4, macOS 15.6.1, Apple Swift 6.2, macOS XCTest host process, 2026-09-28: full parse median 12.91 ms, maximum 14.73 ms; stream parse-and-buffer median 294.01 ms; buffer-only median 0.64 ms. Darwin `getrusage` peak process RSS was 19.4 MiB before measured parses, 22.5 MiB after them, and 28.0 MiB after streaming. Peak RSS cannot decrease and includes the XCTest process; it is not equivalent to Android's heap readings. First runs varied under concurrent build load; compare warmed repeated runs on the same host.

The benchmark is skipped during normal test runs. No timing threshold is asserted. A 50 ms synthetic interval is a logical schedule, not a real-time producer; the results cannot establish frame smoothness or long-session memory behavior. A simulator or device run with rendering and a long streaming session remains necessary for release-level performance acceptance.
