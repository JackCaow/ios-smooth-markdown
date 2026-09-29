#!/usr/bin/env python3
"""Sync Flutter's 12 sample conversations and message Markdown into native demos."""

import argparse
import hashlib
import json
import re
from pathlib import Path


STRING = r"'((?:\\.|[^'\\])*)'"
MESSAGE = re.compile(
    r"ChatMsg\(\s*content:\s*" + STRING +
    r"\s*,\s*isMe:\s*(true|false)\s*,\s*timestamp:\s*"
    r"DateTime\.now\(\)\.subtract\(const Duration\((.*?)\)\)\s*\)", re.S,
)
ESCAPES = {"n": "\n", "'": "'", "\\": "\\", "$": "$"}


def dart_string(raw: str) -> str:
    if re.search(r"(?<!\\)\$\{", raw):
        raise ValueError("Interpolated conversation fixture needs manual extraction")

    def replace(match: re.Match[str]) -> str:
        code = match.group(1)
        if code not in ESCAPES:
            raise ValueError(f"Unexpected Dart escape: \\{code}")
        return ESCAPES[code]

    return re.sub(r"\\(.)", replace, raw, flags=re.S)


def constructor_blocks(source: str) -> list[str]:
    start = source.index("static final List<Conversation> _sampleConversations")
    end = source.index("static Conversation _makeConv", start)
    section = source[start:end]
    blocks = []
    position = 0
    while (found := section.find("_makeConv(", position)) >= 0:
        cursor = found + len("_makeConv(")
        depth = 1
        quoted = False
        escaped = False
        while depth and cursor < len(section):
            char = section[cursor]
            if quoted:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == "'":
                    quoted = False
            elif char == "'":
                quoted = True
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            cursor += 1
        if depth:
            raise ValueError("Unclosed _makeConv constructor")
        blocks.append(section[found:cursor])
        position = cursor
    return blocks


def field(block: str, name: str) -> str:
    match = re.search(r"\b" + re.escape(name) + r"\s*:\s*" + STRING, block)
    if not match:
        raise ValueError(f"Missing {name} in conversation")
    return dart_string(match.group(1))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source_path = args.source or root.parent / "flutter-smooth-markdown/example/lib/conversation_list_demo.dart"
    data = source_path.read_bytes()
    conversations = []
    for block in constructor_blocks(data.decode("utf-8")):
        color = re.search(r"\bavatarColor:\s*const Color\(0x([0-9A-Fa-f]{8})\)", block)
        if not color:
            raise ValueError("Missing avatar color")
        unread = re.search(r"\bunreadCount:\s*(\d+)", block)
        messages = []
        for raw, is_me, duration in MESSAGE.findall(block):
            amounts = {unit: int(value) for unit, value in re.findall(r"(days|hours|minutes|seconds):\s*(\d+)", duration)}
            seconds_ago = (amounts.get("days", 0) * 86400 + amounts.get("hours", 0) * 3600 +
                           amounts.get("minutes", 0) * 60 + amounts.get("seconds", 0))
            messages.append({"content": dart_string(raw), "isMe": is_me == "true", "secondsAgo": seconds_ago})
        if not messages:
            raise ValueError("Conversation has no messages")
        conversations.append({"id": field(block, "id"), "name": field(block, "name"),
                              "avatar": field(block, "avatar"), "avatarColorARGB": color.group(1).upper(),
                              "unreadCount": int(unread.group(1)) if unread else 0,
                              "lastMessage": field(block, "lastMsg"), "messages": messages})
    if [item["id"] for item in conversations] != [str(index) for index in range(1, 13)]:
        raise ValueError("Flutter conversation ids changed")
    if sum(len(item["messages"]) for item in conversations) != 29:
        raise ValueError("Flutter conversation message count changed")
    fixture = {"source": "flutter-smooth-markdown/example/lib/conversation_list_demo.dart",
               "sourceSha256": hashlib.sha256(data).hexdigest(), "conversations": conversations}
    output = root / ("Demo/SmoothMarkdownDemo/Examples/Conversations/conversations.json"
                     if (root / "Package.swift").exists()
                     else "app/src/main/assets/examples/conversations/conversations.json")
    expected = (json.dumps(fixture, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if args.check:
        if not output.exists() or output.read_bytes() != expected:
            raise SystemExit(f"Out-of-date Flutter conversation fixture: {output}")
        print(f"Verified {len(conversations)} Flutter conversations and 29 messages")
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(expected)
    print(f"Synced {len(conversations)} Flutter conversations to {output}")


if __name__ == "__main__":
    main()
