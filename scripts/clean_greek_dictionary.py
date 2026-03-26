from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

import geonamescache
import pycountry
from wordfreq import zipf_frequency


DICT_PATH = Path("assets/dictionaries/greek_core_60k.txt")
REPORT_PATH = Path("assets/dictionaries/greek_core_60k.clean_report.json")
BACKUP_PATH = Path("assets/dictionaries/greek_core_60k.bak.txt")


LATIN_TO_GREEK = {
    "A": "Α",
    "B": "Β",
    "E": "Ε",
    "H": "Η",
    "I": "Ι",
    "K": "Κ",
    "M": "Μ",
    "N": "Ν",
    "O": "Ο",
    "P": "Ρ",
    "T": "Τ",
    "X": "Χ",
    "Y": "Υ",
    "Z": "Ζ",
    "a": "α",
    "b": "β",
    "e": "ε",
    "h": "η",
    "i": "ι",
    "k": "κ",
    "m": "μ",
    "n": "ν",
    "o": "ο",
    "p": "ρ",
    "t": "τ",
    "x": "χ",
    "y": "υ",
    "z": "ζ",
}

GREEK_TO_LATIN = {
    "Α": "A",
    "Β": "B",
    "Ε": "E",
    "Η": "H",
    "Ι": "I",
    "Κ": "K",
    "Μ": "M",
    "Ν": "N",
    "Ο": "O",
    "Ρ": "P",
    "Τ": "T",
    "Χ": "X",
    "Υ": "Y",
    "Ζ": "Z",
    "α": "a",
    "β": "b",
    "ε": "e",
    "η": "h",
    "ι": "i",
    "κ": "k",
    "μ": "m",
    "ν": "v",
    "ο": "o",
    "ρ": "p",
    "τ": "t",
    "χ": "x",
    "υ": "y",
    "ζ": "z",
}


def has_script(name: str, needle: str) -> bool:
    return needle in name


def is_greek_letter(ch: str) -> bool:
    if not ch.isalpha():
        return False
    name = unicodedata.name(ch, "")
    return has_script(name, "GREEK")


def is_latin_letter(ch: str) -> bool:
    if not ch.isalpha():
        return False
    name = unicodedata.name(ch, "")
    return has_script(name, "LATIN")


def script_counts(word: str) -> tuple[int, int]:
    greek = sum(1 for ch in word if is_greek_letter(ch))
    latin = sum(1 for ch in word if is_latin_letter(ch))
    return greek, latin


def normalize_display_word(word: str) -> str:
    return unicodedata.normalize("NFC", word).strip()


def fix_mixed_script(word: str) -> tuple[str, bool]:
    greek, latin = script_counts(word)
    if greek == 0 or latin == 0:
        return word, False

    target_greek = greek >= latin
    fixed = []
    changed = False

    for ch in word:
        if target_greek and is_latin_letter(ch) and ch in LATIN_TO_GREEK:
            fixed.append(LATIN_TO_GREEK[ch])
            changed = True
        elif (not target_greek) and is_greek_letter(ch) and ch in GREEK_TO_LATIN:
            fixed.append(GREEK_TO_LATIN[ch])
            changed = True
        else:
            fixed.append(ch)

    return "".join(fixed), changed


def is_word_shape_allowed(word: str) -> bool:
    if not word:
        return False
    allowed_punct = {"-", "'", "."}
    for ch in word:
        if ch.isalpha() or ch.isdigit():
            continue
        if ch in allowed_punct:
            continue
        return False
    return True


def build_proper_noun_set() -> set[str]:
    proper: set[str] = set()

    def add(name: str | None) -> None:
        if not name:
            return
        cleaned = name.strip()
        if not cleaned:
            return
        if re.search(r"[\s\-_'.]", cleaned):
            return
        proper.add(cleaned.lower())

    for country in pycountry.countries:
        add(getattr(country, "name", None))
        add(getattr(country, "official_name", None))
        add(getattr(country, "common_name", None))

    for subdiv in pycountry.subdivisions:
        add(getattr(subdiv, "name", None))

    gc = geonamescache.GeonamesCache()
    for country in gc.get_countries().values():
        add(country.get("name"))
        add(country.get("capital"))

    for city in gc.get_cities().values():
        add(city.get("name"))

    # Common Greek proper nouns that should stay title-cased.
    for greek_name in (
        "Αθήνα",
        "Θεσσαλονίκη",
        "Πειραιάς",
        "Πάτρα",
        "Ηράκλειο",
        "Λάρισα",
        "Βόλος",
        "Ιωάννινα",
        "Ελλάδα",
        "Κύπρος",
    ):
        add(greek_name)

    return proper


def score_el(word: str) -> float:
    return zipf_frequency(word, "el")


def score_en(word: str) -> float:
    return zipf_frequency(word, "en")


def maybe_capitalize_proper(word: str, proper_nouns: set[str]) -> tuple[str, bool]:
    if not word or not word.isalpha():
        return word, False

    if not word.islower():
        return word, False

    if word.lower() in proper_nouns:
        return word[:1].upper() + word[1:], True

    return word, False


def is_valid_word(word: str, proper_nouns: set[str]) -> bool:
    if not is_word_shape_allowed(word):
        return False

    greek, latin = script_counts(word)
    lower = word.lower()

    if lower in proper_nouns:
        return True

    # Keep common short forms/acronyms (wifi, vpn, etc.) while dropping random noise.
    if 2 <= len(word) <= 8 and word.isalnum():
        if word.isupper():
            return True
        if word.isdigit():
            return True
        if any(ch.isdigit() for ch in word) and any(ch.isalpha() for ch in word):
            return True

    if greek > 0 and latin == 0:
        return max(score_el(lower), score_el(word)) >= 1.2

    if latin > 0 and greek == 0:
        en_ok = max(score_en(lower), score_en(word), score_en(word.title())) >= 1.35
        return en_ok

    # For mixed scripts, validity should have been evaluated after a repair attempt.
    return False


def clean_dictionary() -> dict:
    source_path = BACKUP_PATH if BACKUP_PATH.exists() else DICT_PATH
    raw_lines = source_path.read_text(encoding="utf-8").splitlines()

    if not BACKUP_PATH.exists():
        BACKUP_PATH.write_text("\n".join(raw_lines) + "\n", encoding="utf-8")

    proper_nouns = build_proper_noun_set()

    output_lines: list[str] = []
    seen: set[str] = set()

    report = {
        "total_input_lines": len(raw_lines),
        "comment_lines_kept": 0,
        "blank_lines_skipped": 0,
        "normalized_unicode": 0,
        "mixed_script_fixed": 0,
        "proper_nouns_capitalized": 0,
        "invalid_removed": 0,
        "duplicates_removed": 0,
        "words_changed_total": 0,
        "total_output_lines": 0,
    }

    for idx, line in enumerate(raw_lines):
        if line.startswith("#"):
            output_lines.append(line)
            report["comment_lines_kept"] += 1
            continue

        word = normalize_display_word(line)
        if not word:
            report["blank_lines_skipped"] += 1
            continue

        changed = False
        if word != line:
            report["normalized_unicode"] += 1
            changed = True

        repaired, mixed_changed = fix_mixed_script(word)
        if mixed_changed:
            report["mixed_script_fixed"] += 1
            word = repaired
            changed = True

        greek, latin = script_counts(word)
        if greek > 0 and latin == 0:
            cap_word, cap_changed = maybe_capitalize_proper(word, proper_nouns=proper_nouns)
        elif latin > 0 and greek == 0:
            cap_word, cap_changed = maybe_capitalize_proper(word, proper_nouns=proper_nouns)
        else:
            cap_word, cap_changed = word, False

        if cap_changed:
            report["proper_nouns_capitalized"] += 1
            word = cap_word
            changed = True

        if not is_valid_word(word, proper_nouns=proper_nouns):
            report["invalid_removed"] += 1
            continue

        if word in seen:
            report["duplicates_removed"] += 1
            continue

        seen.add(word)
        output_lines.append(word)

        if changed:
            report["words_changed_total"] += 1

    if len(output_lines) >= 2 and output_lines[1].startswith("# Γραμμές λεξικού"):
        lexical_count = len(output_lines) - report["comment_lines_kept"]
        output_lines[1] = f"# Γραμμές λεξικού (display forms): {lexical_count}"

    report["total_output_lines"] = len(output_lines)

    DICT_PATH.write_text("\n".join(output_lines) + "\n", encoding="utf-8")
    REPORT_PATH.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return report


if __name__ == "__main__":
    result = clean_dictionary()
    print(json.dumps(result, ensure_ascii=False, indent=2))
