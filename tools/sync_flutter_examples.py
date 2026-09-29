#!/usr/bin/env python3
"""Copy the Flutter example's ten main Markdown samples into the native demo."""

import argparse
import hashlib
import json
import re
from pathlib import Path


TITLES = (
    "Basic Formatting", "Headers", "Lists", "Code Blocks", "Quotes & Rules",
    "Links & Images", "Enhanced UI", "Theme Showcase", "Details & Summary", "Complex Example",
)
IDS = (
    "basic-formatting", "headers", "lists", "code-blocks", "quotes-rules",
    "links-images", "enhanced-ui", "theme-showcase", "details-summary", "complex-example",
)
PATTERN = re.compile(r"MarkdownExample\(\s*title: '([^']+)',\s*markdown: '''(.*?)''',\s*\)", re.S)
ESCAPES = {"$": "$", "\\": "\\"}


def dart_string_value(source: str) -> str:
    """Convert escapes used by Flutter's non-raw triple-quoted samples."""
    if re.search(r"(?<!\\)\$\{", source):
        raise ValueError("Interpolated Flutter example requires manual extraction")

    def unescape(match: re.Match[str]) -> str:
        code = match.group(1)
        if code not in ESCAPES:
            raise ValueError(f"Unexpected Dart escape in example: \\{code}")
        return ESCAPES[code]

    return re.sub(r"\\(.)", unescape, source, flags=re.S)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source = args.source or root.parent / "flutter-smooth-markdown/example/lib/main.dart"
    output = root / ("Demo/SmoothMarkdownDemo/Examples" if (root / "Package.swift").exists()
                     else "app/src/main/assets/examples")
    data = source.read_bytes()
    examples = PATTERN.findall(data.decode("utf-8"))
    if tuple(title for title, _ in examples) != TITLES:
        raise SystemExit("Flutter example titles/format changed; update the extractor before syncing")
    entries = []
    files: dict[Path, bytes] = {}
    for identifier, (title, markdown) in zip(IDS, examples):
        content = dart_string_value(markdown).encode("utf-8")
        filename = identifier + ".md"
        files[output / filename] = content
        entries.append({"id": identifier, "title": title, "file": filename,
                        "sha256": hashlib.sha256(content).hexdigest()})
    manifest = {"source": "flutter-smooth-markdown/example/lib/main.dart",
                "sourceSha256": hashlib.sha256(data).hexdigest(), "examples": entries}
    files[output / "manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if args.check:
        stale = [str(path) for path, expected in files.items() if not path.exists() or path.read_bytes() != expected]
        if stale:
            raise SystemExit("Out-of-date demo fixtures:\n" + "\n".join(stale))
        print(f"Verified {len(entries)} Flutter example fixtures")
        return
    output.mkdir(parents=True, exist_ok=True)
    for path, content in files.items():
        path.write_bytes(content)
    print(f"Synced {len(entries)} Flutter example fixtures to {output}")


if __name__ == "__main__":
    main()
