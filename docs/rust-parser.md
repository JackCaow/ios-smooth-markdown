# Owned parser and binary distribution

The default parser uses the library's owned Rust AST engine through a C ABI. The parser and bridge add **zero external code dependencies**. The existing Swift APIs, custom builders, resources and design tokens keep their contracts.

SwiftPM and CocoaPods include `Artifacts/CSmoothMarkdownRust.xcframework`. Applications need no Cargo or Rust installation. The static archive contains device arm64, simulator arm64/x86_64 and macOS arm64/x86_64 slices. Device and simulator binaries are packaged separately. `SmoothMarkdown/Core` includes the same engine as the UI subspec.

## Source development

The complete parser source, C header, license and pinned fixtures are in `rust-core`. Install the stable Rust toolchain and rebuild with:

```sh
python3 tools/build-rust-parser.py --install-targets
(cd rust-core && cargo test --locked)
COMMONMARK_SPEC_JSON=/path/to/commonmark-0.31.2-spec.json \
  SMOOTH_MARKDOWN_RUST_REQUIRED=1 swift test
```

Commit the updated parser source, source checksum and XCFramework together. Normal users do not run these commands. The framework is compiled from owned source, not downloaded from a third-party binary vendor.

## Compatibility and limits

UTF-16 ranges match `NSRange`. Source is retrieved from the caller's original input using a range reference, while decoded semantic text is separate. Reader math and footnote segmentation uses the same AST. Swift-specific rendering, images, formulas, SVG and editor behavior remain in their existing components.

The bridge batches the whole tree into one FFI result and releases Rust ownership after copying. A missing binary or rejected parse retains the existing owned Swift fallback; strict integration tests prove the backend was actually invoked. Source and wire limits are described in `rust-core/README.md`. This migration does not change the public backend configuration API.

Both exact HTML output and source ranges are checked for 652 CommonMark examples and 24 GFM extension fixtures. Builds and package consumers are additional gates. Rust-only timing excludes Swift AST decoding and UI rendering; no mobile speed improvement is claimed from that timing.
