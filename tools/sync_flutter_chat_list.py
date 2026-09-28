#!/usr/bin/env python3
"""Sync Flutter Chat List welcome and four response Markdown fixtures."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from sync_flutter_examples import dart_string_value

PATTERNS = {
    "welcome": r"void _loadWelcomeMessage\(\).*?content: '''(.*?)'''",
    "code": r"String _getCodeExampleResponse\(\).*?return '''(.*?)'''",
    "markdown": r"String _getMarkdownFeaturesResponse\(\).*?return '''(.*?)'''",
    "performance": r"String _getPerformanceResponse\(\).*?return '''(.*?)'''",
    "table": r"String _getTableResponse\(\).*?return '''(.*?)'''",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source = args.source or root.parent / "flutter-smooth-markdown/example/lib/chat_list_demo.dart"
    output = root / "Demo/SmoothMarkdownDemo/Examples/ChatList"
    source_bytes = source.read_bytes()
    text = source_bytes.decode("utf-8")
    files = {}
    hashes = {}
    for name, pattern in PATTERNS.items():
        match = re.search(pattern, text, re.S)
        if not match:
            raise SystemExit(f"Flutter chat fixture changed: {name}")
        content = dart_string_value(match.group(1)).encode("utf-8")
        files[output / f"{name}.md"] = content
        hashes[name] = hashlib.sha256(content).hexdigest()
    manifest = {
        "source": "example/lib/chat_list_demo.dart",
        "sourceSha256": hashlib.sha256(source_bytes).hexdigest(),
        "sha256": hashes,
    }
    files[output / "manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    if args.check:
        stale = [str(path) for path, expected in files.items()
                 if not path.exists() or path.read_bytes() != expected]
        if stale:
            raise SystemExit("Out-of-date chat fixtures:\n" + "\n".join(stale))
        print("Verified Flutter Chat List welcome and four responses")
        return
    output.mkdir(parents=True, exist_ok=True)
    for path, data in files.items():
        path.write_bytes(data)
    print("Synced Flutter Chat List welcome and four responses")


if __name__ == "__main__":
    main()
