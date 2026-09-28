#!/usr/bin/env python3
"""Verify every bundled iOS Demo fixture against the Flutter example source."""

import argparse
from pathlib import Path
import subprocess
import sys


SOURCES = (
    ("sync_flutter_examples.py", "main.dart"),
    ("sync_flutter_demo_pages.py", None),
    ("sync_flutter_mermaid_examples.py", "mermaid_demo.dart"),
    ("sync_flutter_streaming_demo.py", "streaming_demo.dart"),
    ("sync_flutter_ai_chat.py", "ai_chat_demo.dart"),
    ("sync_flutter_chat_list.py", "chat_list_demo.dart"),
    ("sync_flutter_conversations.py", "conversation_list_demo.dart"),
    ("sync_flutter_l10n.py", "l10n/app_localizations.dart"),
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--flutter-example-lib",
        type=Path,
        help="Flutter example/lib directory (default: sibling flutter-smooth-markdown/example/lib)",
    )
    args = parser.parse_args()
    tools = Path(__file__).resolve().parent
    source_dir = args.flutter_example_lib or tools.parent.parent / "flutter-smooth-markdown/example/lib"
    if not source_dir.is_dir():
        parser.error(f"Flutter example directory does not exist: {source_dir}")

    for script, source_file in SOURCES:
        source_flag = ["--source", str(source_dir / source_file)] if source_file else ["--source-dir", str(source_dir)]
        print(f"Checking {script}...", flush=True)
        subprocess.run([sys.executable, str(tools / script), "--check", *source_flag], check=True)
    print("All eight iOS Demo fixture groups match the Flutter example.")


if __name__ == "__main__":
    main()
