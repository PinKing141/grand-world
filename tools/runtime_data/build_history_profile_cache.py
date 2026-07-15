#!/usr/bin/env python3
"""Bake compact country and province history fields needed at runtime.

The raw history directories are intentionally hidden from Godot with .gdignore.
This builder mirrors the bounded parsers formerly used by the UI and emits the
small, deterministic subset that runtime code is allowed to consume.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[2]
COUNTRIES = ROOT / "assets" / "countries"
PROVINCES = ROOT / "assets" / "provinces"
OUTPUT = ROOT / "assets" / "generated" / "history_profiles.json"

COUNTRY_FIELDS = ("government", "primary_culture", "religion")
PROVINCE_FIELDS = ("capital", "culture", "religion", "trade_goods")
COUNTRY_HEADER_LIMIT = 4096
LEADING_INTEGER = re.compile(r"^[+-]?\d+")


def _trim_wrapping_quotes(value: str) -> str:
    """Match GDScript's trim_prefix/trim_suffix quote handling."""
    if value.startswith('"'):
        value = value[1:]
    if value.endswith('"'):
        value = value[:-1]
    return value


def parse_country_profile(path: Path) -> dict[str, str]:
    """Parse the same bounded, pre-timeline fields as the selection UI."""
    content = path.read_bytes()[:COUNTRY_HEADER_LIMIT].decode("latin-1")
    profile: dict[str, str] = {}
    for raw_line in content.split("\n"):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line[0].isdigit():
            break
        for field in COUNTRY_FIELDS:
            prefix = f"{field} ="
            if line.startswith(prefix):
                value = line[len(prefix) :].strip()
                profile[field] = _trim_wrapping_quotes(value)
    return profile


def parse_province_profile(path: Path) -> dict[str, str]:
    """Parse the first non-empty base value for each province UI field."""
    details = {field: "" for field in PROVINCE_FIELDS}
    content = path.read_bytes().decode("latin-1")
    for raw_line in content.split("\n"):
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line[0].isdigit() and "." in line:
            break
        slices = line.split("=")
        key = slices[0].strip()
        if key not in details or details[key]:
            continue
        value = slices[1].split("#", 1)[0].strip()
        details[key] = _trim_wrapping_quotes(value).strip()
    return details


def _country_history_paths(directory: Path) -> dict[str, Path]:
    paths: dict[str, Path] = {}
    for path in sorted(directory.iterdir(), key=lambda candidate: candidate.name):
        filename = path.name
        if not path.is_file() or not filename.endswith(".txt") or len(filename) < 7:
            continue
        tag = filename[:3].upper()
        if filename.startswith(f"{tag} - "):
            paths[tag] = path
    return paths


def _province_history_paths(directory: Path) -> dict[int, Path]:
    paths: dict[int, Path] = {}
    for path in sorted(directory.iterdir(), key=lambda candidate: candidate.name):
        if not path.is_file() or not path.name.lower().endswith(".txt"):
            continue
        match = LEADING_INTEGER.match(path.name)
        province_id = int(match.group(0)) if match else 0
        if province_id > 0:
            paths[province_id] = path
    return paths


def build_payload(countries_dir: Path = COUNTRIES, provinces_dir: Path = PROVINCES) -> dict:
    country_paths = _country_history_paths(countries_dir)
    province_paths = _province_history_paths(provinces_dir)
    countries = {
        tag: parse_country_profile(country_paths[tag])
        for tag in sorted(country_paths)
    }
    provinces = {
        str(province_id): parse_province_profile(province_paths[province_id])
        for province_id in sorted(province_paths)
    }
    return {"schema_version": 1, "countries": countries, "provinces": provinces}


def serialize(payload: dict) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail when the committed runtime cache differs from the raw histories.",
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    payload = build_payload()
    expected = serialize(payload)
    if args.check:
        if not OUTPUT.is_file() or OUTPUT.read_text(encoding="utf-8") != expected:
            raise SystemExit(
                f"Stale runtime history cache: {OUTPUT}. Run this builder without --check."
            )
        print(
            "Runtime history profile cache is current: "
            f"{len(payload['countries'])} countries, {len(payload['provinces'])} provinces."
        )
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(expected, encoding="utf-8", newline="\n")
    print(
        f"Built {OUTPUT}: {len(payload['countries'])} countries, "
        f"{len(payload['provinces'])} provinces."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
