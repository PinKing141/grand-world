#!/usr/bin/env python3
"""Bake the compact per-province metadata the runtime HUD reads.

Combines the geographic audit (map-pixel centroids for search focus), the
biome manifest (terrain display name), and a coastal flag computed from the
province bitmap (a land province is coastal when it borders a water-class
province) into assets/province_metadata.csv. The docs/data sources are
gdignored, so the runtime gets this baked copy instead.
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "historical_ownership"))

import bake_political_textures as baker  # noqa: E402

GEOGRAPHY = ROOT / "docs" / "data" / "province_geography.csv"
BIOMES = ROOT / "docs" / "data" / "1444_biome_manifest.csv"
OUTPUT = ROOT / "assets" / "province_metadata.csv"
STRIP_ROWS = 128


def neighbour_province_pairs() -> set[tuple[int, int]]:
    definition_colors, _max_id = baker.load_definitions()
    bmp = baker.PROVINCE_BITMAP.read_bytes()
    pixel_offset, width, signed_height, row_stride = baker.read_bmp_header(bmp)
    height = abs(signed_height)
    pair_keys: set[tuple[int, int]] = set()
    previous_last_row = None
    for strip_top in range(0, height, STRIP_ROWS):
        strip_height = min(STRIP_ROWS, height - strip_top)
        rows = np.frombuffer(
            bmp, dtype=np.uint8, count=strip_height * row_stride, offset=pixel_offset + strip_top * row_stride
        ).reshape(strip_height, row_stride)[:, : width * 3].reshape(strip_height, width, 3)
        keys = (rows[..., 2].astype(np.uint32) << 16) | (rows[..., 1].astype(np.uint32) << 8) | rows[..., 0]
        for y, x in zip(*np.nonzero(keys[:, 1:] != keys[:, :-1])):
            pair_keys.add((int(keys[y, x]), int(keys[y, x + 1])))
        if previous_last_row is not None:
            for x in np.nonzero(keys[0] != previous_last_row)[0]:
                pair_keys.add((int(previous_last_row[x]), int(keys[0, x])))
        for y, x in zip(*np.nonzero(keys[1:] != keys[:-1])):
            pair_keys.add((int(keys[y, x]), int(keys[y + 1, x])))
        previous_last_row = keys[-1].copy()

    id_pairs: set[tuple[int, int]] = set()
    for key_a, key_b in pair_keys:
        id_a = definition_colors.get((key_a >> 16 & 255, key_a >> 8 & 255, key_a & 255), -1)
        id_b = definition_colors.get((key_b >> 16 & 255, key_b >> 8 & 255, key_b & 255), -1)
        if id_a >= 0 and id_b >= 0 and id_a != id_b:
            id_pairs.add((id_a, id_b))
    return id_pairs


def main() -> int:
    _definition_colors, max_id = baker.load_definitions()
    terrain_classes = baker.load_terrain_classes(max_id)
    coastal: set[int] = set()
    for id_a, id_b in neighbour_province_pairs():
        class_a, class_b = terrain_classes[id_a], terrain_classes[id_b]
        if class_a != baker.TERRAIN_WATER and class_b == baker.TERRAIN_WATER:
            coastal.add(id_a)
        if class_b != baker.TERRAIN_WATER and class_a == baker.TERRAIN_WATER:
            coastal.add(id_b)

    biomes: dict[int, str] = {}
    with BIOMES.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            biomes[int(row["province_id"])] = row["biome_name"]

    rows_out = []
    with GEOGRAPHY.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            province_id = int(row["province_id"])
            rows_out.append({
                "province_id": province_id,
                "centroid_x": f"{float(row['centroid_x']):.1f}",
                "centroid_y": f"{float(row['centroid_y']):.1f}",
                "pixel_count": row["pixel_count"],
                "biome": biomes.get(province_id, ""),
                "coastal": 1 if province_id in coastal else 0,
            })

    with OUTPUT.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["province_id", "centroid_x", "centroid_y", "pixel_count", "biome", "coastal"],
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows_out)
    import_path = OUTPUT.with_suffix(".csv.import")
    if not import_path.exists():
        import_path.write_text('[remap]\n\nimporter="keep"\n', encoding="utf-8")
    print(f"Baked {OUTPUT.relative_to(ROOT)}: {len(rows_out)} provinces, {len(coastal)} coastal.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
