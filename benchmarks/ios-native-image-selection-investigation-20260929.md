# iOS Reader: native selection across an image

Status: **draft implementation, physical acceptance pending**. The earlier
native TextKit drag failed on the iPhone. A revised selection gesture and
multi-image text projection now build and pass model tests, but the iPhone was
unavailable before the new gesture could be run. Keep this branch as a Draft PR.
The branch includes `main` at `dfed3f9` (including natural image sizing,
editor state callbacks, and toolbar slots).

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

## Revised draft and current gate

- One TextKit selection surface now contains multiple bundled SVG/bitmap image
  anchors and their surrounding paragraphs/headings. Hosted SwiftUI image views
  retain image taps and the "Select surrounding content" context menu.
- Safe HTTP(S) bitmap and SVG images now load asynchronously in the selection
  container. While loading, the existing explicit block range shows a progress
  indicator. A failed request or decode keeps that range and shows the existing
  iOS alt-text fallback. Once all remote images in the group decode, the same
  decoded image data supplies both natural sizes and visible image views in the
  continuous native selection surface. The Flutter `Links & Images` shape is
  eligible even though it starts with headings and ends with an image.
- Image slots use `NaturalImageLayout.resolvedSize` for the available width, so
  tall or wide local images follow the Reader's natural-size behavior rather
  than forcing a fixed 320-point cap.
- A simultaneous long-press recognizer extends the native `selectedRange` when
  the drag crosses any image anchor. Copy removes those anchors while retaining
  adjacent text and inline-code space semantics.
- A static follow-up audit preserved the UTF-16 selection when a width or font
  update rebuilds the same text with different attributes. A changed document
  clears the previous range. The drag recognizer does not cancel UIKit touches
  and does not receive touches that begin on the hosted image, leaving its tap
  and context menu to the image view.
- `swift test` passed 250 tests (1 skipped) after the remote-image extension,
  including focused projection and eligibility tests. Generic iOS
  `build-for-testing` compiled the Demo, its UI tests, and the native-image
  XCTest source.
- **Physical gate:** run `ReaderImageRangeUITests.testNativeDragSelectionCrossesBundledImage`
  and `testNativeDragSelectionCrossesTwoBundledImages` on the iPhone 17. Save
  screenshots of the selection handles and verify the system Copy menu puts
  before/middle/after prose in the clipboard. Also drag a handle again after
  selection and check image tap/context-menu behavior. Selection range retention
  in code does not establish that UIKit keeps the visible handles or edit menu.
  Repeat on the Demo `Links & Images` remote bitmap after it loads; verify the
  broken URL still presents its alt fallback and explicit selection. Check a
  loaded remote SVG and orientation/width changes for image alignment.
  The iPhone was unavailable when this revision was prepared.

Custom image builders, non-prose neighbors, failed remote images, and image-only
groups continue to use the existing explicit block range. Do not merge the
native path before its physical drag, Copy, and visual checks pass.
