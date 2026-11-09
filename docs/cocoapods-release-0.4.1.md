# 0.4.1 Xcode 27.2 compatibility

This patch fixes Swift compilation with Xcode 27.2 without changing the public API, parser ABI, deployment targets or bundled Rust artifacts.

- Assign C hook callbacks directly inside the existing inline/block availability conditions. Absent hooks remain nil.
- Qualify the test helper's `SmoothMarkdown.Document` return type to avoid the new `SwiftUI.Document` protocol collision.

Install SwiftPM tag `0.4.1`, or use `pod 'SmoothMarkdown', '~> 0.4.1'`. SwiftPM supports iOS 17+ and macOS 14+; CocoaPods supports iOS 17+.

## Verification

- Xcode 27.2 (27B52): focused Rust-backed parser/plugin suites passed 32 tests, with three optional/external-fixture skips and no failures.
- The package built for both arm64 and x86_64 iOS Simulator architectures.
- The downstream DimRemote Debug app built with the same callback fix and installed on the iPhone Duo simulator. Authenticated fold/open UI acceptance remains separate from library compilation.
- The full Xcode 27.2 Swift suite ran 635 tests with the checksum-verified CommonMark 0.31.2 fixture and required Rust backend: 631 passed, four opt-in performance benchmarks skipped, zero failures.
- Local `pod lib lint SmoothMarkdown.podspec --allow-warnings --skip-tests` passed for Core and UI on Xcode 27.2. Existing Swift concurrency and unused-value warnings remain warnings.
- [Public CI](https://github.com/JackCaow/ios-smooth-markdown/actions/runs/42590137357) passed all gates, including independent consumers, public API declarations, iOS test compilation, Demo build, CocoaPods validation and 46 platform rendering/runtime tests.

## Publication

- PR #122 is merged as `b9e6f195a29f5216b76a948735cba91ee3c99862`.
- GitHub release and SwiftPM tag `0.4.1` point to `5366d32fba6c171bafaa9838ef02a9fd813dc62a`.
- A clean external SwiftPM consumer resolved exact version `0.4.1` from GitHub with no local override. Its Core consumer and legacy/structured reader/stream consumer built and ran successfully on Xcode 27.2.
- CocoaPods Trunk lists `0.4.1`, registered on 2026-11-09 at 09:26:57 UTC. The official public Specs entry contains version/source tag `0.4.1` and both Core/UI subspecs.
- The remote-tag validation passed during `pod trunk push`. Its post-publication GitHub commit check timed out; no duplicate upload was attempted. Trunk and the official Specs repository independently confirm publication.
