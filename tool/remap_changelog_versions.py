#!/usr/bin/env python3
"""Αναδιαμόρφωση ιστορικού εκδόσεων σε αυστηρό SemVer (κύκλοι minor + patches)."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# old_version -> (new_version, date)  date="" για ανοιχτό κύκλο minor
VERSION_MAP: dict[str, tuple[str, str]] = {
    "0.1.0": ("0.1.0", "2026-03-12"),  # αφετηρία
    "0.2.0": ("0.2.0", "2026-04-07"),
    "0.3.0": ("0.2.1", "2026-04-07"),
    "0.4.0": ("0.2.2", "2026-04-07"),
    "0.5.0": ("0.2.3", "2026-04-07"),
    "0.6.0": ("0.2.4", "2026-04-07"),
    "0.7.0": ("0.3.0", "2026-04-22"),
    "0.8.0": ("0.3.1", "2026-04-22"),
    "0.9.0": ("0.3.2", "2026-04-22"),
    "0.10.0": ("0.4.0", "2026-04-27"),
    "0.11.0": ("0.4.1", "2026-04-27"),
    "0.12.0": ("0.4.2", "2026-04-27"),
    "0.13.0": ("0.5.0", "2026-05-03"),
    "0.14.0": ("0.5.1", "2026-05-03"),
    "0.15.0": ("0.5.2", "2026-05-03"),
    "0.16.0": ("0.6.0", "2026-05-18"),
    "0.16.1": ("0.6.1", "2026-05-18"),
    "0.17.0": ("0.7.0", "2026-05-19"),
    "0.18.0": ("0.7.1", "2026-05-19"),
    "0.19.0": ("0.8.0", "2026-05-24"),
    "0.19.1": ("0.8.1", "2026-05-24"),
    "0.19.2": ("0.8.2", "2026-05-24"),
    "0.20.0": ("0.9.0", "2026-06-01"),
    "0.20.1": ("0.9.1", "2026-06-01"),
    "0.20.2": ("0.9.2", "2026-06-01"),
    "0.21.0": ("0.10.0", "2026-06-06"),
    "0.22.0": ("0.10.1", "2026-06-06"),
    "0.23.0": ("0.10.2", "2026-06-06"),
    "0.24.0": ("0.10.3", "2026-06-06"),
    "0.25.0": ("0.11.0", "2026-06-09"),
    "0.26.0": ("0.11.1", "2026-06-09"),
    "0.27.0": ("0.11.2", "2026-06-09"),
    "0.28.0": ("0.12.0", ""),
}

NEW_CURRENT = "0.12.0"


def remap_json() -> None:
    path = ROOT / "assets" / "changelog.json"
    entries = json.loads(path.read_text(encoding="utf-8-sig"))
    for entry in entries:
        old = entry["version"]
        if old not in VERSION_MAP:
            raise KeyError(f"Unmapped version: {old}")
        new_ver, new_date = VERSION_MAP[old]
        entry["version"] = new_ver
        entry["date"] = new_date
    path.write_text(
        json.dumps(entries, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8-sig",
    )


def remap_changelog_md() -> None:
    path = ROOT / "CHANGELOG.md"
    text = path.read_text(encoding="utf-8")

    # Δύο περάσματα με placeholder ώστε 0.28→0.12 να μην ξανα-αντιστοιχιστεί ως παλιό 0.12→0.4.2.
    sorted_old = sorted(VERSION_MAP.keys(), key=lambda v: [int(x) for x in v.split(".")], reverse=True)
    for i, old in enumerate(sorted_old):
        text = re.sub(
            rf"^## \[{re.escape(old)}\](?: - \d{{4}}-\d{{2}}-\d{{2}})?\s*$",
            f"## @@VER_{i}@@",
            text,
            flags=re.MULTILINE,
        )
    for i, old in enumerate(sorted_old):
        new_ver, new_date = VERSION_MAP[old]
        replacement = f"## [{new_ver}] - {new_date}" if new_date else f"## [{new_ver}]"
        text = text.replace(f"## @@VER_{i}@@", replacement)

    path.write_text(text, encoding="utf-8")


def remap_pubspec() -> None:
    path = ROOT / "pubspec.yaml"
    text = path.read_text(encoding="utf-8")
    text = re.sub(
        r"^version: \d+\.\d+\.\d+\+(\d+)\s*$",
        rf"version: {NEW_CURRENT}+\1",
        text,
        flags=re.MULTILINE,
    )
    path.write_text(text, encoding="utf-8")


def main(md_only: bool = False) -> None:
    if not md_only:
        remap_json()
        remap_pubspec()
    remap_changelog_md()
    print(f"Remapped to {NEW_CURRENT} (open minor cycle, no date on top entry)")


if __name__ == "__main__":
    import sys

    main(md_only="--md-only" in sys.argv)
