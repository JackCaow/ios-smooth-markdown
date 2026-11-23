# 0.6.1 · Unified diff highlighting

When a unified diff contains a missing-newline annotation between a removed line and its replacement, `CodeSyntaxHighlighter.diffRows` preserves the changed word range on each side and carries multiline syntax colors across the annotation. Notes retain their original position and text. The existing Swift API and minimum OS versions are unchanged.

This patch includes the shared core at [7ecb0fc](https://github.com/JackCaow/smooth-rust-core/commit/7ecb0fc97efbde39c37165829234b69f583f428f). The XCFramework includes iPhone arm64, iOS Simulator arm64 and x86_64, and macOS arm64 and x86_64.

The same public API regression ran on a physical iPhone 17 with iOS 27.2.1. The previous library passed 9 of 12 assertions. This build passed all 12, including both change ranges and the added line’s comment color. [Fix and verification](https://github.com/JackCaow/ios-smooth-markdown/pull/125) · [CI](https://github.com/JackCaow/ios-smooth-markdown/actions/runs/45105175214)
