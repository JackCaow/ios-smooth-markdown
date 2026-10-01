# Smooth Markdown Rust core

Owned CommonMark/GFM AST parser for the native Smooth Markdown libraries. The crate has **no Cargo dependencies**. Android uses a small C JNI shim; Apple platforms use the same C ABI in a static XCFramework. Both bindings preserve the existing public Kotlin and Swift API.

## Verify

```sh
cargo test --locked
cargo test --release --test block_contract parser_and_c_abi_baseline -- --ignored --nocapture
```

The gate compares exact HTML and original UTF-16 source ranges for all 652 CommonMark 0.31.2 examples and 24 GFM extension examples. Additional tests cover CR/LF/CRLF, Unicode, unfinished streaming prefixes, extension boundaries, recursion limits and C allocation ownership. Fixture attribution is in `tests/fixtures/NOTICE.md`; fixtures are not runtime code.

## C ABI version 1

`smr_parse_utf16` copies UTF-16 input and returns an owned batch AST buffer. The caller copies/decodes it and calls `smr_buffer_free` exactly once. Buffers contain no borrowed pointers. Cleared buffers may be freed again. Input is limited to 8 Mi UTF-16 units, output to 64 MiB and one million nodes. Container recursion is bounded to 64 (inline nesting to 128); the wire decoder rejects trees deeper than 256. The C API returns an explicit status when a limit is exceeded.

The wire format is little endian: `SMR1`, node count, preorder node records. Each record contains seven u32 fields (kind, UTF-16 start/length, heading level, flags, ordered-list start, child count), six length-prefixed UTF-16 strings (source, info, destination, title, literal, label), then alignment count and nullable strings. Length `0xffffffff` is nil. The source field uses `0xfffffffe` to reference the original input by the node's source range. Semantic text is separate, so transient isolated surrogates remain in the caller's original source.

Native readers, standard editor syntax recognition, source ranges and HTML export use this shared engine. Rendering, lossless source patches, image loading, SVG and formula layout remain platform components. Android's standalone JVM Core retains its owned Kotlin fallback when no JNI binary is loaded.

The additional ABI entry points preserve the original version-1 parse/free contract:

- `smr_parse_with_hooks_utf16`: full-document parse with synchronous host extensions. Custom nodes carry opaque positive IDs; host payloads stay in the binding.
- `smr_parse_inline_utf16`: fragment grammar plus optional `SMF1` reference definitions, without promoting a heading or list fragment into block syntax.
- `smr_render_ast_utf16`: HTML from the caller's current mutable AST, with explicit source strings. It accepts subtree roots and never reparses a fabricated source document.
- `smr_export_html_utf16`: parse and HTML export in one call.

HTML buffers contain raw little-endian UTF16 and use the same allocation/free contract. `SMR_ESCAPE_HTML` escapes raw HTML; the binding compatibility flag `SMR_TRANSPARENT_TABLE_PARTS` retains Swift's standalone table-row/cell output. Mutable AST records can use private wire kinds for custom nodes, table head/body and task markers, flag 64 for header cells, and flag 128 with a signed-decimal label for mutable heading/list numeric values. HTML preflight rejects conservative output estimates over the transport limit before escaping or allocating UTF16 output. Parsing still returns original-source sentinels; host render input must use explicit strings.

Inline matches consume UTF16 units; block matches consume lines. Hooks run after escape/code protection and before built-in syntax at eligible positions, including projected quote/list context. `SMR_HOST_FENCED_BLOCKS` lets a binding explicitly claim a complete fenced extension at its opening line (for example a host Mermaid block); ordinary fence bodies remain protected. Invalid spans are ignored, negative callback statuses abort with `SMR_CALLBACK_ERROR`. Optional nested context notifications let JNI/Swift reuse immutable strings and line arrays for a scan; borrowed pointers never escape a callback scope. `SMF1` is a count followed by UTF16 label/destination/nullable-title triples.

The local canonical crate is mirrored into each native repository's `rust-core` directory for self-contained builds. `tools/sync-native-sources.py` copies the owned files and creates the same SHA-256 manifest. Normal library consumers require no Rust toolchain. Changes must be synchronized and both bindings verified before release.

The Rust benchmark includes C input copying, parsing, serialization and freeing; it excludes JNI/Swift transitions, host AST decoding and rendering. It is not evidence of faster mobile rendering.

## Stream sessions

`smr_stream_new`, `smr_stream_update_utf16` and `smr_stream_free` provide a single-owner session without host hooks. Update receives the exact complete UTF-16 prefix and returns ordinary SMR1 tail nodes plus the number of old top-level children to retain. The root span covers the complete current source. Keep the final two top-level blocks mutable: an unfinished interrupt marker can become ordinary paragraph text. Containers are reparsed as complete blocks.

Any `]:` sequence conservatively invalidates the full tree because reference definitions can change earlier inline nodes. Non-append edits reset the retained prefix. Failed updates also invalidate session state. Node and cumulative wire limits match the batch parser, even when each individual delta is small. Platform adapters preserve their existing whole-document hook paths for unsupported incremental features.

Run `cargo test --locked` for every-character prefix equality against all CommonMark/GFM fixtures. Run `cargo test --locked --release --test stream_benchmark -- --ignored --nocapture` for observational same-input FFI comparisons. In the 2026-10-01 arm64 macOS host run, 58,500 UTF-16 units across 115 publications took 251.137 ms batch versus 4.955 ms incremental, with aggregate wire bytes reduced from 34,508,720 to 653,666. A single 60,000-unit paragraph and an early global definition showed no improvement. These timings exclude host AST adaptation and UI layout/drawing; full-prefix identity checks still have linear cost.
