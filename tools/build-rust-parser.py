#!/usr/bin/env python3
"""Build the owned, dependency-free parser for SwiftPM and CocoaPods."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CRATE = ROOT / "rust-core"
TARGET = ROOT / ".build/rust-parser"
OUTPUT = ROOT / "Artifacts/CSmoothMarkdownRust.xcframework"
MANIFEST = ROOT / "Artifacts/CSmoothMarkdownRust.build.json"


def hashes(base, files):
    return {str(path.relative_to(base)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(files) if path.is_file()}


def source_hashes():
    return hashes(CRATE, [CRATE / "Cargo.toml", CRATE / "Cargo.lock"] +
                  list((CRATE / "src").rglob("*.rs")) + list((CRATE / "include").rglob("*.h")))


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True, cwd=CRATE,
                   env={**os.environ, "CARGO_TARGET_DIR": str(TARGET)})


def build(target):
    run("cargo", "build", "--locked", "--release", "--target", target)
    return TARGET / target / "release/libsmooth_markdown_rust.a"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install-targets", action="store_true")
    parser.add_argument("--verify", action="store_true", help="Verify packaged sources and binary checksums without Rust")
    args = parser.parse_args()
    if args.verify:
        metadata = json.loads(MANIFEST.read_text())
        if metadata['sources'] != source_hashes() or metadata['artifact'] != hashes(OUTPUT, OUTPUT.rglob('*')):
            raise SystemExit('Packaged Rust sources or binary changed; rebuild the XCFramework')
        print('Owned Rust source and XCFramework checksums match')
        return
    groups = [
        ("ios", ["aarch64-apple-ios"]),
        ("ios-simulator", ["aarch64-apple-ios-sim", "x86_64-apple-ios"]),
        ("macos", ["aarch64-apple-darwin", "x86_64-apple-darwin"]),
    ]
    if args.install_targets:
        run("rustup", "target", "add", *[t for _, ts in groups for t in ts])
    headers = TARGET / "headers"
    headers.mkdir(parents=True, exist_ok=True)
    shutil.copy2(CRATE / "include/smooth_markdown_rust.h", headers)
    (headers / "module.modulemap").write_text(
        'module CSmoothMarkdownRust {\n  header "smooth_markdown_rust.h"\n  export *\n}\n')
    command = ["xcodebuild", "-create-xcframework"]
    for name, targets in groups:
        libraries = [build(target) for target in targets]
        destination = TARGET / name / "libsmooth_markdown_rust.a"
        destination.parent.mkdir(parents=True, exist_ok=True)
        if len(libraries) == 1:
            shutil.copy2(libraries[0], destination)
        else:
            run("lipo", "-create", *libraries, "-output", destination)
        run("strip", "-S", destination)
        command += ["-library", destination, "-headers", headers]
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    run(*command, "-output", OUTPUT)
    MANIFEST.write_text(json.dumps({
        'rustc': subprocess.check_output(['rustc', '--version'], text=True).strip(),
        'sources': source_hashes(), 'artifact': hashes(OUTPUT, OUTPUT.rglob('*'))
    }, sort_keys=True, indent=2) + '\n')
    print(OUTPUT)


if __name__ == "__main__":
    main()
