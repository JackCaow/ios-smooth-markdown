# Background stream scheduling validation — 2026-10-01

Eligible `StreamMarkdownView` streams parse and decode owned native AST on a serial queue. The worker keeps one pending complete prefix. Chunks are accumulated before coalescing, so skipped requests do not discard source fragments. The worker commits every processed native tree; UI publication validates generation, version, configuration and exact UTF-16 source. If the UI skipped a base version, it adapts the complete owned tree rather than applying an incompatible delta.

Markup adaptation, source maps, UI state and plugin callbacks stay on MainActor. Formula, footnote, HTML, details and custom plugin paths retain their existing parser behavior. A native rejection uses the original owned parser fallback on MainActor.

A finite stream awaits its final source publication before invoking `onComplete`. Reset, cancellation and configuration changes invalidate stale tickets; pending finish waiters are resolved. The final publication drops the worker and its native session storage. The standalone public accumulator retains its synchronous behavior.

Validation: 602 Swift tests, 27 focused streaming tests after final cleanup (7 new background cases), 18 hosted simulator/runtime UI tests, independent Core/Reader consumers and unchanged public API baseline. The hosted test checks final header/body via OCR and completion once on the main thread. See [runtime evidence](evidence/stream-background-runtime-2026-10-01.json).

Existing parser timing measurements were captured before this scheduling change. No device timing, frame-rate or additional speedup is claimed here.
