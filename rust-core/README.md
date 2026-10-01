# Smooth Markdown Rust core

Owned CommonMark/GFM AST parser for the native Smooth Markdown libraries. The crate has **no Cargo dependencies**. Android uses a small C JNI shim; Apple platforms use the same C ABI in a static XCFramework. Both bindings preserve the existing public Kotlin and Swift API.

## Verify

```sh
cargo test --locked
cargo test --release --test block_contract parser_and_c_abi_baseline -- --ignored --nocapture
```

The gate compares exact HTML and original UTF-16 source ranges for all 652 CommonMark 0.31.2 examples and 24 GFM extension examples. Additional tests cover CR/LF/CRLF, Unicode, unfinished streaming prefixes, extension boundaries, recursion limits and C allocation ownership. Fixture attribution is in `tests/fixtures/NOTICE.md`; fixtures are not runtime code.

## C ABI version 1

`smr_parse_utf16` copies UTF-16 input and returns an owned batch AST buffer. The caller copies/decodes it and calls `smr_buffer_free` exactly once. Buffers contain no borrowed pointers. Cleared buffers may be freed again. Input is limited to 8 Mi UTF-16 units, output to 64 MiB and one million nodes. Container recursion is bounded to 128; the wire decoder rejects trees deeper than 256. The C API returns an explicit status when a limit is exceeded.

The wire format is little endian: `SMR1`, node count, preorder node records. Each record contains seven u32 fields (kind, UTF-16 start/length, heading level, flags, ordered-list start, child count), six length-prefixed UTF-16 strings (source, info, destination, title, literal, label), then alignment count and nullable strings. Length `0xffffffff` is nil. The source field uses `0xfffffffe` to reference the original input by the node's source range. Semantic text is separate, so transient isolated surrogates remain in the caller's original source.

This is the first migration batch. Default native readers use Rust, including math and footnote block boundaries. Host-provided Kotlin parser hooks and details compatibility use the existing owned Kotlin implementation. The pure JVM core keeps its owned JVM parser when no JNI binary is loaded. Rendering, image loading, SVG, formula layout and editing remain platform components.

The local canonical crate is mirrored into each native repository's `rust-core` directory for self-contained builds. `tools/sync-native-sources.py` copies the owned files and creates the same SHA-256 manifest. Normal library consumers require no Rust toolchain. Changes must be synchronized and both bindings verified before release.

The Rust benchmark includes C input copying, parsing, serialization and freeing; it excludes JNI/Swift transitions, host AST decoding and rendering. It is not evidence of faster mobile rendering.
