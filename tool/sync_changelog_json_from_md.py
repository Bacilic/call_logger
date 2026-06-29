#!/usr/bin/env python3
"""Συγχρονισμός assets/changelog.json από CHANGELOG.md (πηγή αλήθειας)."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MD_PATH = ROOT / "CHANGELOG.md"
JSON_PATH = ROOT / "assets" / "changelog.json"

CATEGORY_MAP = {
    "Προστέθηκε": "added",
    "Άλλαξε": "changed",
    "Διορθώθηκε": "fixed",
}


def md_bullet_to_json(text: str) -> str:
    """Μετατροπή bullet Keep a Changelog σε σύντομη γραμμή JSON."""
    out = text.strip()
    out = re.sub(r"\*\*(.+?):\*\*", r"\1:", out)
    out = re.sub(r"\*\*(.+?)\*\*", r"\1", out)
    return out.replace("`", "")


def parse_changelog_md(text: str) -> list[dict]:
    entries: list[dict] = []
    sections = re.split(r"^## \[", text, flags=re.MULTILINE)

    for section in sections[1:]:
        header_line, _, body = section.partition("\n")
        header_match = re.match(
            r"^([^\]]+)\](?: - (\d{4}-\d{2}-\d{2}))?\s*$",
            header_line,
        )
        if not header_match:
            continue

        version = header_match.group(1)
        date = header_match.group(2) or ""

        entry = {
            "version": version,
            "date": date,
            "added": [],
            "changed": [],
            "fixed": [],
        }

        current_key: str | None = None
        for line in body.splitlines():
            stripped = line.strip()
            if stripped.startswith("### "):
                title = stripped[4:].strip()
                current_key = CATEGORY_MAP.get(title)
                continue
            if stripped.startswith("- ") and current_key:
                entry[current_key].append(md_bullet_to_json(stripped[2:]))

        entries.append(entry)

    return entries


def main() -> None:
    md_text = MD_PATH.read_text(encoding="utf-8")
    entries = parse_changelog_md(md_text)
    JSON_PATH.write_text(
        json.dumps(entries, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(entries)} entries to {JSON_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
