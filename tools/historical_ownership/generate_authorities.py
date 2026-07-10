#!/usr/bin/env python3
"""Generate reproducible country/color files for documented cultural authority slots."""

from __future__ import annotations

import colorsys
import csv
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(__file__).with_name("cultural_authorities.csv")
COUNTRIES = ROOT / "assets" / "countries"
COLORS = ROOT / "assets" / "country_colors"
LEDGER = Path(__file__).with_name("generated_authorities.json")
TAG_PATTERN = re.compile(r"^(.{3})\s+-\s+(.+)\.txt$", re.IGNORECASE)
COLOR_PATTERN = re.compile(r"color\s*=\s*\{\s*(\d+)\s+(\d+)\s+(\d+)\s*\}")


def existing_tags() -> set[str]:
    tags = set()
    for path in COUNTRIES.glob("*.txt"):
        match = TAG_PATTERN.match(path.name)
        if match:
            tags.add(match.group(1).upper())
    return tags


def existing_colors() -> set[tuple[int, int, int]]:
    colors = set()
    for path in COLORS.glob("*.txt"):
        match = COLOR_PATTERN.search(path.read_text(encoding="utf-8", errors="replace"))
        if match:
            colors.add(tuple(int(match.group(part)) for part in (1, 2, 3)))
    return colors


def allocate_color(tag: str, used: set[tuple[int, int, int]]) -> tuple[int, int, int]:
    digest = hashlib.sha256(tag.encode("ascii")).digest()
    hue = int.from_bytes(digest[:2], "big") / 65535.0
    for attempt in range(64):
        saturation = 0.52 + ((digest[2] + attempt * 17) % 30) / 100.0
        value = 0.68 + ((digest[3] + attempt * 11) % 25) / 100.0
        rgb_float = colorsys.hsv_to_rgb((hue + attempt * 0.071) % 1.0, min(saturation, 0.82), min(value, 0.90))
        rgb = tuple(round(channel * 255) for channel in rgb_float)
        if rgb not in used and min(rgb) >= 24:
            used.add(rgb)
            return rgb
    raise RuntimeError(f"Could not allocate a unique colour for {tag}")


def country_text(row: dict[str, str]) -> str:
    return f'''# Generated cultural-territorial authority for the 1444 scenario.
# {row["scope_note"]}
government = {row["government"]}
add_government_reform = {row["reform"]}
government_rank = 1
primary_culture = {row["primary_culture"]}
religion = {row["religion"]}
technology_group = {row["technology_group"]}
capital = {row["capital"]}

1444.11.11 = {{
\tmonarch = {{
\t\tname = "Community Council"
\t\tadm = 3
\t\tdip = 3
\t\tmil = 3
\t\tregent = yes
\t}}
}}
'''


def color_text(row: dict[str, str], rgb: tuple[int, int, int]) -> str:
    red, green, blue = rgb
    return f'''# Generated cultural-territorial authority for the 1444 scenario.
# {row["scope_note"]}
graphical_culture = {row["graphical_culture"]}

color = {{ {red} {green} {blue} }}

revolutionary_colors = {{ 8 5 8 }}

monarch_names = {{
\t"Community Council #0" = 100
}}
'''


def main() -> int:
    tags = existing_tags()
    used_colors = existing_colors()
    generated = []
    with CONFIG.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    for row in rows:
        tag = row["tag"].upper()
        country_path = COUNTRIES / f'{tag} - {row["name"]}.txt'
        color_path = COLORS / f'{row["name"]}.txt'
        if tag in tags and not country_path.exists():
            raise ValueError(f"Configured tag {tag} is already used by another country")
        if country_path.exists() and color_path.exists():
            color_match = COLOR_PATTERN.search(color_path.read_text(encoding="utf-8", errors="replace"))
            rgb = tuple(int(color_match.group(part)) for part in (1, 2, 3)) if color_match else None
            generated.append({"tag": tag, "name": row["name"], "color": rgb, "status": "existing"})
            tags.add(tag)
            continue
        rgb = allocate_color(tag, used_colors)
        country_path.write_text(country_text(row), encoding="utf-8", newline="")
        color_path.write_text(color_text(row, rgb), encoding="utf-8", newline="")
        tags.add(tag)
        generated.append({"tag": tag, "name": row["name"], "color": rgb, "status": "generated"})
    LEDGER.write_text(json.dumps(generated, indent=2) + "\n", encoding="utf-8")
    print(f"Generated/validated {len(generated)} cultural authority definitions.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
