#!/usr/bin/env python3
"""Sync static Flutter demo-page Markdown, preserving Dart string semantics."""

import argparse
import hashlib
import json
import re
from pathlib import Path


PAGES = (
    ("math", "Math", "math_demo.dart", "_mathContent"),
    ("footnote", "Footnotes", "footnote_demo.dart", "_footnoteContent"),
    ("plugin", "Plugin System", "plugin_demo.dart", "_demoMarkdown"),
    ("editor", "Markdown Editor", "editor_demo.dart", "_initialMarkdown"),
    ("html", "HTML Tags Demo", "html_demo.dart", "_htmlContent"),
)
ESCAPES = {"$": "$", "\\": "\\", "n": "\n"}


def extract(source: str, name: str) -> str:
    match = re.search(r"\b" + name + r"\s*=\s*'''(.*?)'''\s*;", source, re.S)
    if not match:
        raise ValueError(f"Missing Dart fixture: {name}")

    def unescape(escape: re.Match[str]) -> str:
        code = escape.group(1)
        if code not in ESCAPES:
            raise ValueError(f"Unexpected Dart escape in {name}: \\{code}")
        return ESCAPES[code]

    content = re.sub(r"\\(.)", unescape, match.group(1), flags=re.S)
    if "${" in content:
        raise ValueError(f"Interpolated Dart fixture requires manual extraction: {name}")
    return content


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source_dir = args.source_dir or root.parent / "flutter-smooth-markdown/example/lib"
    output = root / ("Demo/SmoothMarkdownDemo/Examples/Pages" if (root / "Package.swift").exists()
                     else "app/src/main/assets/examples/pages")
    entries = []
    files: dict[Path, bytes] = {}
    for identifier, title, filename, symbol in PAGES:
        source = (source_dir / filename).read_bytes()
        content = extract(source.decode("utf-8"), symbol).encode("utf-8")
        target = identifier + ".md"
        files[output / target] = content
        entries.append({"id": identifier, "title": title, "file": target,
                        "source": f"flutter-smooth-markdown/example/lib/{filename}",
                        "sourceSha256": hashlib.sha256(source).hexdigest(),
                        "sha256": hashlib.sha256(content).hexdigest()})
    files[output / "pages.json"] = (json.dumps({"pages": entries}, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if args.check:
        stale = [str(path) for path, expected in files.items() if not path.exists() or path.read_bytes() != expected]
        if stale:
            raise SystemExit("Out-of-date Flutter demo-page fixtures:\n" + "\n".join(stale))
        print(f"Verified {len(entries)} Flutter demo-page fixtures")
        return
    output.mkdir(parents=True, exist_ok=True)
    for path, content in files.items():
        path.write_bytes(content)
    print(f"Synced {len(entries)} Flutter demo-page fixtures to {output}")


if __name__ == "__main__":
    main()
