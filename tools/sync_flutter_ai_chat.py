#!/usr/bin/env python3
"""Sync Flutter AI Chat's offline welcome, quick prompts, and mock replies."""

import argparse
import hashlib
import json
import re
from pathlib import Path


PROMPT = re.compile(
    r"QuickPrompt\(\s*label: '([^']*)',\s*description: '([^']*)',\s*"
    r"prompt: '([^']*)',\s*mockResponse: _getMock([A-Za-z]+)Response\(\),\s*\)", re.S,
)
KINDS = ("Thinking", "Artifact", "ToolCall", "AllInOne", "Code", "Table")


def triple_string(source: str, pattern: str) -> str:
    match = re.search(pattern, source, re.S)
    if not match:
        raise ValueError(f"Missing Flutter AI Chat fixture: {pattern}")
    content = match.group(1)
    if re.search(r"\\.|(?<!\\)\$\{", content):
        raise ValueError("AI Chat fixture acquired Dart escapes/interpolation; update extractor")
    return content


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source_path = args.source or root.parent / "flutter-smooth-markdown/example/lib/ai_chat_demo.dart"
    data = source_path.read_bytes()
    source = data.decode("utf-8")
    welcome = triple_string(source, r"void _loadWelcomeMessage\(\) \{.*?content:\s*'''(.*?)'''")
    raw_prompts = PROMPT.findall(source)
    if tuple(item[3] for item in raw_prompts) != KINDS:
        raise ValueError("Flutter AI Chat quick prompts changed")
    prompts = []
    for label, description, prompt, kind in raw_prompts:
        response = triple_string(source, rf"String _getMock{kind}Response\(\) \{{\s*return '''(.*?)''';")
        prompts.append({"id": kind[0].lower() + kind[1:], "label": label,
                        "description": description, "prompt": prompt, "response": response,
                        "responseSha256": hashlib.sha256(response.encode("utf-8")).hexdigest()})
    generic = triple_string(source, r"String _getGenericResponse\(String prompt\) \{\s*return '''(.*?)''';")
    if generic.count("$prompt") != 2:
        raise ValueError("Flutter AI Chat generic response interpolation changed")
    if "const chunkSize = 5;" not in source or "Duration(milliseconds: 20)" not in source:
        raise ValueError("Flutter AI Chat mock streaming cadence changed")
    fixture = {"source": "flutter-smooth-markdown/example/lib/ai_chat_demo.dart",
               "sourceSha256": hashlib.sha256(data).hexdigest(),
               "chunkSizeUTF16": 5, "delayMillis": 20,
               "welcome": welcome, "welcomeSha256": hashlib.sha256(welcome.encode("utf-8")).hexdigest(),
               "quickPrompts": prompts, "genericResponseTemplate": generic.replace("$prompt", "{{prompt}}")}
    output = root / ("Demo/SmoothMarkdownDemo/Examples/AIChat/ai-chat.json"
                     if (root / "Package.swift").exists()
                     else "app/src/main/assets/examples/ai-chat/ai-chat.json")
    expected = (json.dumps(fixture, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if args.check:
        if not output.exists() or output.read_bytes() != expected:
            raise SystemExit(f"Out-of-date Flutter AI Chat fixture: {output}")
        print(f"Verified {len(prompts)} Flutter AI Chat quick prompts")
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(expected)
    print(f"Synced {len(prompts)} Flutter AI Chat quick prompts to {output}")


if __name__ == "__main__":
    main()
