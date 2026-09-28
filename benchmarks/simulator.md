# iOS reader Simulator measurement

The Demo **Perf** screen loads `Tests/SmoothMarkdownTests/Fixtures/FlutterREADME.md` four times, separated by blank lines. The source is 68,282 UTF-8 bytes, identical to the host benchmark. **Static** renders it at once. **Rapid stream** supplies 32 Swift characters every 1 ms to `StreamMarkdownView`; set `SMOOTH_PERF_THROTTLE_MS` to compare its visible-update interval (50 ms by default). The screen exposes a `CADisplayLink` interval probe, SwiftUI first-appear time, and the app's `task_vm_info.phys_footprint`. The stream completion label compares the final published reader text with the entire fixture byte for byte.

## Reproduce

Tested on iPhone 17 Pro Simulator, iOS 26.0, Xcode 26.0.1, Debug, 2026-09-28. The project is generated with XcodeGen:

```sh
cd /path/to/ios-smooth-markdown
xcodegen generate --spec Demo/project.yml --project-root Demo
xcodebuild -project Demo/SmoothMarkdownDemo.xcodeproj -scheme SmoothMarkdownDemo -configuration Debug -destination 'platform=iOS Simulator,id=6951A181-8995-494A-81D2-7996A5122A7F' -derivedDataPath "$PWD/DerivedData" PRODUCT_BUNDLE_IDENTIFIER=com.jackcaow.smoothmarkdown.performance.demo CODE_SIGNING_ALLOWED=NO -only-testing:SmoothMarkdownPerformanceUITests/PerformanceUITests test
```

The UI tests launch a fresh app for each case, make 12 upward swipes in the static reader, and record the rapid stream from mode activation through exact completion. The [`PERF_UI` test and Simulator log excerpt](evidence/ios-simulator-ui-tests.log) contains the final run. Screenshots: [static first screen](evidence/ios-static-first-screen.png), [static after scrolling](evidence/ios-static-after-scroll.png), [50 ms stream after completion](evidence/ios-stream-complete-50ms.png). Use `xcrun xcresulttool export attachments --path <xcresult> --output-path <directory>` to export the original XCTest screenshots.

| Scenario | Runs | First appear | Frame interval p95 | Intervals >25 ms | Longest interval | Footprint at stop |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Static, 12 swipes | 3 | 95 / 94 / 90 ms | 16.7 / 16.7 / 16.7 ms | 28 / 23 / 22 | 173.2 / 145.4 / 163.5 ms | 106 / 104 / 103 MiB |
| Rapid stream, 50 ms throttle | 2 | 8 / 7 ms | 16.7 / 16.7 ms | 21 / 19 | 72.7 / 60.6 ms | 60 / 59 MiB |
| Rapid stream, 150 ms throttle | 2 | 10 / 8 ms | 16.7 / 16.7 ms | 24 / 9 | 57.4 / 64.6 ms | 59 / 59 MiB |

All three UI tests passed in the final run. At both stream intervals, the completion callback reported exactly 68,282 bytes matching the input. The final 50 ms run logged `PERF visibleComplete throttleMs=50 bytes=68282 exact=1`; the 150 ms run logged the same with `throttleMs=150`. The existing host benchmark also asserts its buffer's final text equals the fixture.

The static reader had occasional intervals over 100 ms in all three swipe runs. The current data do not locate their cause; README badge images load over the network, and lazy view creation happens during scrolling. The 150 ms stream interval did not improve the repeated frame results consistently, so the library's 50 ms default remains unchanged. No rendering fix was made without a trace-backed cause.

`first appear` is the SwiftUI view's `.onAppear` elapsed time, not a measured first pixel. `CADisplayLink` intervals include idle periods and XCTest waits, so they are a repeatable jank indicator rather than presented frame times or a pure scrolling FPS figure. `phys_footprint` measures this process and does not include all Simulator services. These Debug Simulator results do not establish physical-device performance.
