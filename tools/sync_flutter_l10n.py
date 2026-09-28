#!/usr/bin/env python3
"""Copy Flutter example's six localization dictionaries into the iOS Demo."""

import argparse
import ast
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT.parent / "flutter-smooth-markdown/example/lib/l10n/app_localizations.dart"
DESTINATION = ROOT / "Demo/SmoothMarkdownDemo/Examples/l10n/flutter-localizations.json"
LANGUAGES = ("zh", "en", "ja", "es", "fr", "ko")


def extract(source: Path) -> dict:
    contents = source.read_text(encoding="utf-8")
    translations = {}
    for language in LANGUAGES:
        match = re.search(rf"^    '{language}': \{{\n(.*?)^    \}},", contents, re.M | re.S)
        if match is None:
            raise ValueError(f"Missing Flutter language: {language}")
        values = {}
        for key, literal in re.findall(r"^      '([^']+)': ('(?:\\.|[^'\\])*'),$", match.group(1), re.M):
            values[key] = ast.literal_eval(literal)
        if len(values) < 70 or any(key not in values for key in ("language", "drawer_demos", "theme_default_light")):
            raise ValueError(f"Incomplete Flutter language: {language} ({len(values)} keys)")
        translations[language] = values
    keys = set(translations["zh"])
    if any(set(values) != keys for values in translations.values()):
        raise ValueError("Flutter languages have different localization keys")
    return {
        "source": "flutter-smooth-markdown/example/lib/l10n/app_localizations.dart",
        "sourceSha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "translations": translations,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = json.dumps(extract(args.source), ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not DESTINATION.exists() or DESTINATION.read_text(encoding="utf-8") != expected:
            raise SystemExit("iOS Demo localization fixture differs from Flutter example")
        print("iOS Demo localization fixture matches Flutter example")
    else:
        DESTINATION.parent.mkdir(parents=True, exist_ok=True)
        DESTINATION.write_text(expected, encoding="utf-8")
        print(f"Wrote {DESTINATION}")


if __name__ == "__main__":
    main()
