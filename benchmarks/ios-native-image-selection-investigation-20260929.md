# iOS Reader: native selection across an image

Status: **not implemented**. This is a record of a failed isolated prototype. The
production Reader still uses its explicit block range selection for images.

## Acceptance case

Render `Before image.`, a bundled SVG, and `After image.` in the selectable
Reader. On a physical iPhone, drag a native selection from the first paragraph
through the image into the final paragraph, then use the system Copy menu.
Expected plain text: `Before image.\nAfter image.`. The image must still render,
respond to taps, and offer its surrounding-content menu.

## Physical device evidence

- Device: iPhone 17, iOS 26.6.1, UDID `00008150-001C18E426F8401C`.
- Base: `main` at `4bb79e1`; all experiments were confined to
  `codex/ios-reader-image-drag` in this separate worktree.
- A TextKit 1 `UITextView` with one reserved image line did render the actual
  SwiftUI SVG; tapping it incremented `Image taps` to 1. The native selection
  handles and Copy menu appeared.
- The drag stopped at the image line. Copy returned only `Before image.`.
  [Physical screenshot](evidence/ios-native-image-selection-failed-iphone17-20260929.png)
  shows the lower native selection handle at the image boundary, with
  `After image.` still unselected.
- The text view's XCTest frame was `(16, 147, 370, 153)` points and its
  accessibility value contained all three lines. The drag endpoint was inside
  the final paragraph, so this was not merely a separate SwiftUI text view.
- Repeating with a later endpoint, disabling interaction on the hosted image,
  and replacing `NSTextAttachment` with an ordinary invisible glyph all yielded
  the same clipboard result. The corresponding local result bundles are
  `/tmp/smoothmarkdown-image-drag-physical.xcresult`,
  `/tmp/smoothmarkdown-image-drag-physical-2.xcresult`,
  `/tmp/smoothmarkdown-image-drag-physical-3.xcresult`, and
  `/tmp/smoothmarkdown-image-drag-physical-5.xcresult`.
- An initial prototype subclassed `QuoteTextView` and crashed while drawing
  `quoteFrames()`; the crash report is
  `/Users/cver/Library/Logs/DiagnosticReports/SmoothMarkdownDemo-2026-09-29-190337.ips`.
  Using a plain `UITextView` removed that crash, but not the selection limit.

## Next implementation direction

Keep the image as an independently hosted SwiftUI view, but own the selection
gesture across the complete text and image geometry. Map drag locations into
the before/after UTF-16 offsets and update one `UITextView.selectedRange` while
retaining UIKit's visible selection handles and Copy menu. Verify the system
handle can be dragged again after the initial selection. Preserve image tap,
context menu, Dynamic Type, links, and multiline layout. Cover bundled,
remote, and custom image-builder content before making this the default path.

Do not merge the current prototype source: its physical UI test fails the core
copy requirement. The existing click-based range remains the safe production
behavior until a replacement passes physical-device visual and clipboard tests.
