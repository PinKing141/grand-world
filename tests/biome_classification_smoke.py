#!/usr/bin/env python3
"""Validate representative biome assignments across the world map."""

from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs" / "data" / "1444_biome_manifest.csv"


def main() -> int:
    with MANIFEST.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = {int(row["province_id"]): row for row in csv.DictReader(handle)}
    expected = {
        1: "Temperate Broadleaf & Mixed Forests",            # Stockholm
        1128: "Deserts & Xeric Shrublands",                  # Taodeni / Sahara
        1252: "Water",                                       # Gulf of Bothnia
        1779: "Deserts & Xeric Shrublands",                  # Rub' al Khali
        1787: "Montane Grasslands & Shrublands",             # Himalaya
        1790: "Deserts & Xeric Shrublands",                  # Western Australia
        1796: "Tropical & Subtropical Moist Broadleaf Forests",  # Central Africa
        1802: "Tropical & Subtropical Moist Broadleaf Forests",  # Amazon
        1804: "Rock and Ice",                                # Greenland interior
        2425: "Boreal Forests/Taiga",                        # Naryan-Mar
    }
    for province_id, expected_biome in expected.items():
        actual_biome = rows.get(province_id, {}).get("biome_name")
        if actual_biome != expected_biome:
            raise AssertionError(
                f"Province {province_id}: expected {expected_biome!r}, got {actual_biome!r}"
            )
    methods = {row["assignment_method"] for row in rows.values()}
    required_methods = {"terrain_water_class", "wwf_biome_centroid", "historical_gameplay_override"}
    if not required_methods.issubset(methods):
        raise AssertionError(f"Biome manifest is missing assignment methods: {required_methods - methods}")
    print("Biome classification smoke test passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
