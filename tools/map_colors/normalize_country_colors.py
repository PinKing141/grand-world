#!/usr/bin/env python3
"""Normalize country map colours: tame neon values, separate adjacent look-alikes.

Two deterministic passes over assets/country_colors/*.txt:

1. Taming. Colours keep their hue identity but extremes are clamped in HSV:
   neon (high saturation x brightness), near-white pastels, and near-black
   values all pull toward a readable strategy-map band.
2. Separation. Countries that border each other on the 1444 map and whose
   colours are perceptually close get pushed apart. Larger countries keep
   their colour; the smaller neighbour is nudged in hue/value until every
   processed neighbour is distinct.

Only the `color = { R G B }` line of each affected file is rewritten. Run
tools/historical_ownership/bake_political_textures.py afterwards.
"""

from __future__ import annotations

import colorsys
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "historical_ownership"))

import bake_political_textures as baker  # noqa: E402
import build_manifest as ownership  # noqa: E402

COLOR_LINE = re.compile(r"(?<![A-Za-z_])color\s*=\s*\{\s*\d+\s+\d+\s+\d+\s*\}")
DISTANCE_THRESHOLD = 60.0
STRIP_ROWS = 128


def redmean_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    mean_red = (a[0] + b[0]) / 2.0
    dr, dg, db = (a[0] - b[0]), (a[1] - b[1]), (a[2] - b[2])
    return ((2.0 + mean_red / 256.0) * dr * dr + 4.0 * dg * dg + (2.0 + (255.0 - mean_red) / 256.0) * db * db) ** 0.5


def tame(color: tuple[int, int, int]) -> tuple[int, int, int]:
    hue, saturation, value = colorsys.rgb_to_hsv(*(part / 255.0 for part in color))
    saturation = min(saturation, 0.92)
    if saturation * value > 0.70:
        value = 0.70 / max(saturation, 1e-4)
    value = min(value, 0.88)
    value = max(value, 0.22)
    if value > 0.70 and saturation < 0.12:
        saturation = 0.12
    red, green, blue = colorsys.hsv_to_rgb(hue, saturation, value)
    return (round(red * 255), round(green * 255), round(blue * 255))


def candidates(color: tuple[int, int, int]):
    hue, saturation, value = colorsys.rgb_to_hsv(*(part / 255.0 for part in color))
    for hue_shift in (0.0, 0.05, -0.05, 0.10, -0.10, 0.15, -0.15):
        for value_shift in (0.0, -0.14, 0.14, -0.24):
            for saturation_shift in (0.0, -0.18, 0.15):
                candidate = colorsys.hsv_to_rgb(
                    (hue + hue_shift) % 1.0,
                    min(max(saturation + saturation_shift, 0.10), 0.92),
                    min(max(value + value_shift, 0.22), 0.88),
                )
                yield tame(tuple(round(part * 255) for part in candidate))


def build_adjacency(province_owner: dict[int, str]) -> set[tuple[str, str]]:
    definition_colors, _max_id = baker.load_definitions()
    bmp = baker.PROVINCE_BITMAP.read_bytes()
    pixel_offset, width, signed_height, row_stride = baker.read_bmp_header(bmp)
    height = abs(signed_height)

    def owner_of(key: int) -> str:
        return province_owner.get(definition_colors.get((key >> 16 & 255, key >> 8 & 255, key & 255), -1), "")

    pair_keys: set[tuple[int, int]] = set()
    previous_last_row = None
    for strip_top in range(0, height, STRIP_ROWS):
        strip_height = min(STRIP_ROWS, height - strip_top)
        rows = np.frombuffer(
            bmp, dtype=np.uint8, count=strip_height * row_stride, offset=pixel_offset + strip_top * row_stride
        ).reshape(strip_height, row_stride)[:, : width * 3].reshape(strip_height, width, 3)
        keys = (rows[..., 2].astype(np.uint32) << 16) | (rows[..., 1].astype(np.uint32) << 8) | rows[..., 0]
        horizontal = keys[:, 1:] != keys[:, :-1]
        for y, x in zip(*np.nonzero(horizontal)):
            pair_keys.add((int(keys[y, x]), int(keys[y, x + 1])))
        if previous_last_row is not None:
            vertical = keys[0] != previous_last_row
            for x in np.nonzero(vertical)[0]:
                pair_keys.add((int(previous_last_row[x]), int(keys[0, x])))
        vertical = keys[1:] != keys[:-1]
        for y, x in zip(*np.nonzero(vertical)):
            pair_keys.add((int(keys[y, x]), int(keys[y + 1, x])))
        previous_last_row = keys[-1].copy()

    adjacency: set[tuple[str, str]] = set()
    owner_cache: dict[int, str] = {}
    for key_a, key_b in pair_keys:
        for key in (key_a, key_b):
            if key not in owner_cache:
                owner_cache[key] = owner_of(key)
        tag_a, tag_b = owner_cache[key_a], owner_cache[key_b]
        if tag_a and tag_b and tag_a != tag_b:
            adjacency.add((min(tag_a, tag_b), max(tag_a, tag_b)))
    return adjacency


def main() -> int:
    countries = ownership.load_countries()
    colors = baker.load_country_colors()
    province_owner = {
        province_id: fields.get("owner", "").upper()
        for province_id, (_path, fields) in ownership.load_histories().items()
        if fields.get("owner")
    }
    sizes = Counter(province_owner.values())
    adjacency = build_adjacency(province_owner)
    neighbours: dict[str, set[str]] = defaultdict(set)
    for tag_a, tag_b in adjacency:
        neighbours[tag_a].add(tag_b)
        neighbours[tag_b].add(tag_a)

    used_tags = sorted(sizes, key=lambda tag: (-sizes[tag], tag))
    result: dict[str, tuple[int, int, int]] = {}
    tamed_count = 0
    separated_count = 0
    for tag in used_tags:
        if tag not in colors:
            continue
        color = tame(colors[tag])
        if color != colors[tag]:
            tamed_count += 1
        fixed_neighbours = [result[other] for other in sorted(neighbours[tag]) if other in result]
        if fixed_neighbours and min(redmean_distance(color, other) for other in fixed_neighbours) < DISTANCE_THRESHOLD:
            best, best_score = color, min(redmean_distance(color, other) for other in fixed_neighbours)
            for candidate in candidates(color):
                score = min(redmean_distance(candidate, other) for other in fixed_neighbours)
                if score > best_score:
                    best, best_score = candidate, score
                    if score >= DISTANCE_THRESHOLD:
                        break
            if best != color:
                separated_count += 1
            color = best
        result[tag] = color

    rewritten = 0
    for tag, color in sorted(result.items()):
        if color == colors[tag]:
            continue
        path = ownership.COUNTRY_COLORS / f"{countries[tag].name}.txt"
        content = path.read_bytes().decode("utf-8", errors="surrogateescape")
        new_content, count = COLOR_LINE.subn(
            f"color = {{ {color[0]} {color[1]} {color[2]} }}", content, count=1
        )
        if count != 1:
            raise ValueError(f"Could not rewrite colour line in {path.name}")
        path.write_bytes(new_content.encode("utf-8", errors="surrogateescape"))
        rewritten += 1

    print(f"Tags in 1444 use: {len(used_tags)}; adjacency pairs: {len(adjacency)}.")
    print(f"Tamed {tamed_count} colours, separated {separated_count} adjacent collisions, rewrote {rewritten} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
