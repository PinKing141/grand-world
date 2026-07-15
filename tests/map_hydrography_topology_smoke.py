#!/usr/bin/env python3
"""Validate lake, island, and shoreline topology against canonical map data."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> int:
    print(f"Map hydrography topology smoke failed: {message}", file=sys.stderr)
    return 1


def main() -> int:
    graph = json.loads((ROOT / "assets/province_graph.json").read_text(encoding="utf-8"))
    provinces: dict = graph["provinces"]
    lookup_rgb = np.asarray(Image.open(ROOT / "assets/color_lookup_map.png").convert("RGB"), dtype=np.uint16)
    lookup = lookup_rgb[:, :, 0] + lookup_rgb[:, :, 1] * 256
    lake_mask = np.asarray(Image.open(ROOT / "assets/lake_mask.png").convert("L"), dtype=np.uint8)
    terrain = np.asarray(Image.open(ROOT / "assets/terrain_class_map.png").convert("L"), dtype=np.uint8)
    metadata = json.loads((ROOT / "assets/lake_mask_metadata.json").read_text(encoding="utf-8"))

    if lookup.shape != lake_mask.shape or lookup.shape != terrain.shape:
        return fail("lookup, lake mask, and terrain class dimensions must agree")
    expected_ids = {int(item["province_id"]) for item in metadata["lakes"]}
    actual_ids = {int(value) for value in np.unique(lookup[lake_mask > 0])}
    if actual_ids != expected_ids:
        return fail("lake mask province IDs differ from generated metadata")
    if 1889 not in actual_ids or 1659 not in actual_ids or 4940 not in actual_ids:
        return fail("Lake Geneva, Lake Ontario, and tiny Lake Tulare must be represented")
    if 1571 in actual_ids:
        return fail("Blake Plataeu must not be misclassified by substring matching")
    if np.any(terrain[lake_mask > 0] >= 43):
        return fail("lake pixels must remain water in the categorical terrain authority")
    if np.any(lake_mask[0, :]) or np.any(lake_mask[-1, :]) or np.any(lake_mask[:, 0]) or np.any(lake_mask[:, -1]):
        return fail("an inland lake mask must never touch the wrapped world boundary")

    for province_id in expected_ids:
        record: dict = provinces[str(province_id)]
        pixel_count = int(np.count_nonzero(lookup == province_id))
        if pixel_count != int(record["area"]):
            return fail(f"lake {province_id} raster area differs from the graph")
        if not record.get("land_neighbors"):
            return fail(f"lake {province_id} must retain at least one enclosing land shoreline")

    # Tiny island fixtures protect against smoothing or masks deleting islands.
    for island_id in (4934, 4935, 4936):  # Maui, Oahu, Kauai
        record = provinces[str(island_id)]
        if record["classification"] != "land" or not record["coastal"]:
            return fail(f"island fixture {island_id} lost its land/coastal classification")
        if int(np.count_nonzero(lookup == island_id)) != int(record["area"]):
            return fail(f"island fixture {island_id} lost raster pixels")
        if np.any(lake_mask[lookup == island_id]):
            return fail(f"island fixture {island_id} leaked into the lake mask")

    print(
        "Map hydrography topology smoke passed. "
        f"lakes={len(expected_ids)} lake_pixels={int(np.count_nonzero(lake_mask))} islands=3"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
