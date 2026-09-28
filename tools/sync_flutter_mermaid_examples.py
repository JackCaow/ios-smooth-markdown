#!/usr/bin/env python3
"""Copy the Flutter Mermaid gallery's 40 examples into the native demo."""

import argparse
import hashlib
import json
import re
from pathlib import Path


PATTERN = re.compile(
    r"MermaidExample\(\s*title: '([^']+)',\s*description: '([^']+)',\s*code: '''(.*?)''',\s*\)",
    re.S,
)
GROUPS = (
    ("flowchart", 7), ("sequence", 4), ("pie", 4), ("gantt", 4),
    ("timeline", 5), ("kanban", 6), ("complex", 3), ("radar", 3), ("xy", 4),
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source = args.source or root.parent / "flutter-smooth-markdown/example/lib/mermaid_demo.dart"
    output = root / ("Demo/SmoothMarkdownDemo/Examples/Mermaid" if (root / "Package.swift").exists()
                     else "app/src/main/assets/examples/mermaid")
    data = source.read_bytes()
    examples = PATTERN.findall(data.decode("utf-8"))
    if len(examples) != 40 or examples[0][0] != "基础流程图 (TD)" or examples[-1][0] != "XY图 - 年度营收":
        raise SystemExit("Flutter Mermaid gallery changed; update the extractor before syncing")
    categories = [category for category, count in GROUPS for _ in range(count)]
    entries = []
    files: dict[Path, bytes] = {}
    for index, ((title, description, code), category) in enumerate(zip(examples, categories), start=1):
        # Dart uses \$ for a literal dollar sign inside a non-raw triple-quoted string.
        content = code.replace(r"\$", "$").encode("utf-8")
        filename = f"mermaid-{index:02d}.mmd"
        files[output / filename] = content
        entries.append({"index": index, "category": category, "title": title,
                        "description": description, "file": filename,
                        "sha256": hashlib.sha256(content).hexdigest()})
    manifest = {"source": "flutter-smooth-markdown/example/lib/mermaid_demo.dart",
                "sourceSha256": hashlib.sha256(data).hexdigest(), "examples": entries}
    files[output / "manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if args.check:
        stale = [str(path) for path, expected in files.items() if not path.exists() or path.read_bytes() != expected]
        if stale:
            raise SystemExit("Out-of-date Mermaid gallery fixtures:\n" + "\n".join(stale))
        print(f"Verified {len(entries)} Flutter Mermaid fixtures")
        return
    output.mkdir(parents=True, exist_ok=True)
    for path, content in files.items():
        path.write_bytes(content)
    print(f"Synced {len(entries)} Flutter Mermaid fixtures to {output}")


if __name__ == "__main__":
    main()
