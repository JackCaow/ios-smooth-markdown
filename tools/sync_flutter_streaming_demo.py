#!/usr/bin/env python3
"""Preserve each Dart _responseChunks element as an iOS demo fixture."""

import argparse
import hashlib
import json
import re
from pathlib import Path


def extract_chunks(source: str) -> list[str]:
    match = re.search(r"\b_responseChunks\s*=\s*\[(.*?)\];", source, re.S)
    if not match:
        raise ValueError("Missing Flutter _responseChunks array")
    body = match.group(1)
    chunks: list[str] = []
    position = 0
    pattern = re.compile(r"\s*'((?:\\.|[^'\\])*)'\s*,", re.S)
    while position < len(body):
        if not body[position:].strip():
            break
        item = pattern.match(body, position)
        if not item:
            raise ValueError(f"Unsupported Dart chunk at offset {position}")
        raw = item.group(1)
        chunks.append(re.sub(r"\\(.)", lambda escape: {"n": "\n", "'": "'", "\\": "\\"}[escape.group(1)], raw))
        position = item.end()
    if not chunks:
        raise ValueError("Empty Flutter _responseChunks array")
    return chunks


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source_path = args.source or root.parent / "flutter-smooth-markdown/example/lib/streaming_demo.dart"
    source = source_path.read_bytes()
    chunks = extract_chunks(source.decode("utf-8"))
    joined = "".join(chunks).encode("utf-8")
    fixture = {
        "source": "flutter-smooth-markdown/example/lib/streaming_demo.dart",
        "sourceSha256": hashlib.sha256(source).hexdigest(),
        "markdownSha256": hashlib.sha256(joined).hexdigest(),
        "delayMillis": 50,
        "chunks": chunks,
    }
    output = root / "Demo/SmoothMarkdownDemo/Examples/Streaming/streaming.json"
    expected = (json.dumps(fixture, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if args.check:
        if not output.exists() or output.read_bytes() != expected:
            raise SystemExit(f"Out-of-date Flutter streaming fixture: {output}")
        print(f"Verified {len(chunks)} Flutter streaming chunks")
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(expected)
    print(f"Synced {len(chunks)} Flutter streaming chunks to {output}")


if __name__ == "__main__":
    main()
