#!/usr/bin/env python3
"""Bake the canonical province graph the simulation moves armies on.

This is the single authority for province adjacency. It scans the province
bitmap once at build time and emits assets/province_graph.json plus a
validation report; the campaign runtime only ever loads the baked file.

Border rules: two provinces are adjacent when their pixels touch horizontally
or vertically. Diagonal corner contact never creates a border. The map edge
does not wrap; any future wrap connection must be authored as an override.

Overrides (tools/map_graph/graph_overrides.csv) support:
  add_connection      province_a, province_b
  remove_connection   province_a, province_b
  mark_strait         province_a, province_b  (adds the connection if absent)
  override_anchor     province_a, x, y
  mark_impassable     province_a
"""

from __future__ import annotations

import csv
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "historical_ownership"))

import bake_political_textures as baker  # noqa: E402

OVERRIDES = Path(__file__).with_name("graph_overrides.csv")
BIOMES = ROOT / "docs" / "data" / "1444_biome_manifest.csv"
OUTPUT = ROOT / "assets" / "province_graph.json"
REPORT = ROOT / "docs" / "data" / "province_graph_validation.md"
STRIP_ROWS = 128
INVALID_ID = 0xFFFF

# Data-driven movement model: whole days to enter a province of each class.
TERRAIN_COSTS = {
    "plains": 5,
    "forest": 7,
    "hills": 8,
    "desert": 8,
    "tundra": 8,
    "marsh": 10,
    "mountains": 12,
    "strait_crossing": 4,
}

BIOME_MOVE_CLASS = {
    "Deserts & Xeric Shrublands": "desert",
    "Tropical & Subtropical Moist Broadleaf Forests": "forest",
    "Tropical & Subtropical Dry Broadleaf Forests": "forest",
    "Tropical & Subtropical Coniferous Forests": "forest",
    "Temperate Broadleaf & Mixed Forests": "forest",
    "Temperate Conifer Forests": "forest",
    "Boreal Forests/Taiga": "forest",
    "Mediterranean Forests, Woodlands & Scrub": "hills",
    "Montane Grasslands & Shrublands": "mountains",
    "Rock and Ice": "mountains",
    "Tundra": "tundra",
    "Flooded Grasslands & Savannas": "marsh",
    "Mangroves": "marsh",
    "Temperate Grasslands, Savannas & Shrublands": "plains",
    "Tropical & Subtropical Grasslands, Savannas & Shrublands": "plains",
}


def build_id_map(definition_colors: dict[tuple[int, int, int], int]) -> np.ndarray:
    bmp = baker.PROVINCE_BITMAP.read_bytes()
    pixel_offset, width, signed_height, row_stride = baker.read_bmp_header(bmp)
    height = abs(signed_height)
    key_to_id = {
        (red << 16) | (green << 8) | blue: province_id
        for (red, green, blue), province_id in definition_colors.items()
    }
    id_map = np.full((height, width), INVALID_ID, dtype=np.uint16)
    for strip_top in range(0, height, STRIP_ROWS):
        strip_height = min(STRIP_ROWS, height - strip_top)
        rows = np.frombuffer(
            bmp, dtype=np.uint8, count=strip_height * row_stride, offset=pixel_offset + strip_top * row_stride
        ).reshape(strip_height, row_stride)[:, : width * 3].reshape(strip_height, width, 3)
        keys = (rows[..., 2].astype(np.uint32) << 16) | (rows[..., 1].astype(np.uint32) << 8) | rows[..., 0]
        unique_keys = np.unique(keys)
        lut_ids = np.array([key_to_id.get(int(key), INVALID_ID) for key in unique_keys], dtype=np.uint16)
        id_map[strip_top:strip_top + strip_height] = lut_ids[np.searchsorted(unique_keys, keys)]
    if signed_height > 0:
        # Bottom-up BMP: flip so row 0 is the top of the map, matching every
        # other baked texture and the geography audit's coordinate space.
        id_map = np.flipud(id_map).copy()
    return id_map


def scan_adjacency(id_map: np.ndarray) -> Counter:
    borders: Counter = Counter()
    height = id_map.shape[0]
    for strip_top in range(0, height, STRIP_ROWS):
        strip = id_map[strip_top:min(strip_top + STRIP_ROWS + 1, height)]
        horizontal_a = strip[: STRIP_ROWS, :-1]
        horizontal_b = strip[: STRIP_ROWS, 1:]
        mask = horizontal_a != horizontal_b
        pair_keys = (horizontal_a[mask].astype(np.uint32) << 16) | horizontal_b[mask].astype(np.uint32)
        unique_pairs, counts = np.unique(pair_keys, return_counts=True)
        for pair, count in zip(unique_pairs.tolist(), counts.tolist()):
            borders[pair] += count
        vertical_a = strip[:-1]
        vertical_b = strip[1:]
        mask = vertical_a != vertical_b
        pair_keys = (vertical_a[mask].astype(np.uint32) << 16) | vertical_b[mask].astype(np.uint32)
        unique_pairs, counts = np.unique(pair_keys, return_counts=True)
        for pair, count in zip(unique_pairs.tolist(), counts.tolist()):
            borders[pair] += count
    merged: Counter = Counter()
    for pair, count in borders.items():
        id_a, id_b = pair >> 16, pair & 0xFFFF
        if id_a == INVALID_ID or id_b == INVALID_ID:
            continue
        merged[(min(id_a, id_b), max(id_a, id_b))] += count
    return merged


def per_province_stats(id_map: np.ndarray, max_id: int):
    height, width = id_map.shape
    area = np.zeros(INVALID_ID + 1, dtype=np.int64)
    sum_x = np.zeros(INVALID_ID + 1, dtype=np.float64)
    sum_y = np.zeros(INVALID_ID + 1, dtype=np.float64)
    min_x = np.full(max_id + 1, width, dtype=np.int64)
    min_y = np.full(max_id + 1, height, dtype=np.int64)
    max_x = np.full(max_id + 1, -1, dtype=np.int64)
    max_y = np.full(max_id + 1, -1, dtype=np.int64)
    column_index = np.arange(width, dtype=np.int64)
    for strip_top in range(0, height, STRIP_ROWS):
        strip = id_map[strip_top:strip_top + STRIP_ROWS]
        flat = strip.reshape(-1).astype(np.int64)
        strip_height = strip.shape[0]
        xs = np.tile(column_index, strip_height)
        ys = np.repeat(np.arange(strip_top, strip_top + strip_height, dtype=np.int64), width)
        area += np.bincount(flat, minlength=INVALID_ID + 1)
        sum_x += np.bincount(flat, weights=xs, minlength=INVALID_ID + 1)
        sum_y += np.bincount(flat, weights=ys, minlength=INVALID_ID + 1)
        keep = flat <= max_id
        kept_ids = flat[keep]
        np.minimum.at(min_x, kept_ids, xs[keep])
        np.minimum.at(min_y, kept_ids, ys[keep])
        np.maximum.at(max_x, kept_ids, xs[keep])
        np.maximum.at(max_y, kept_ids, ys[keep])
    return area[: max_id + 1], sum_x[: max_id + 1], sum_y[: max_id + 1], min_x, min_y, max_x, max_y


def interior_mask(id_map: np.ndarray, source: np.ndarray) -> np.ndarray:
    # One full-map temporary at a time to stay inside the memory budget.
    same = np.zeros(id_map.shape, dtype=bool)
    view = same[1:-1, 1:-1]
    center = id_map[1:-1, 1:-1]
    np.copyto(view, source[1:-1, 1:-1])
    view &= source[:-2, 1:-1]
    view &= source[2:, 1:-1]
    view &= source[1:-1, :-2]
    view &= source[1:-1, 2:]
    view &= center == id_map[:-2, 1:-1]
    view &= center == id_map[2:, 1:-1]
    view &= center == id_map[1:-1, :-2]
    view &= center == id_map[1:-1, 2:]
    return same


def best_pixels(id_map: np.ndarray, mask: np.ndarray, centroid_x, centroid_y, max_id: int) -> np.ndarray:
    """Per-province stable pick: nearest to centroid, ties by lowest y then x."""
    best = np.full(max_id + 1, np.iinfo(np.int64).max, dtype=np.int64)
    height, width = id_map.shape
    for strip_top in range(0, height, STRIP_ROWS):
        strip_mask = mask[strip_top:strip_top + STRIP_ROWS]
        ys, xs = np.nonzero(strip_mask)
        if ys.size == 0:
            continue
        ys = ys + strip_top
        ids = id_map[ys, xs].astype(np.int64)
        keep = ids <= max_id
        ys, xs, ids = ys[keep], xs[keep], ids[keep]
        dx = xs - centroid_x[ids]
        dy = ys - centroid_y[ids]
        distance = (dx * dx + dy * dy).astype(np.int64)
        key = distance * (1 << 25) + ys * width + xs
        np.minimum.at(best, ids, key)
    return best


def decode_anchor(key: int, width: int) -> tuple[int, int] | None:
    if key == np.iinfo(np.int64).max:
        return None
    position = key % (1 << 25)
    return (int(position % width), int(position // width))


def load_overrides() -> list[dict]:
    if not OVERRIDES.exists():
        return []
    with OVERRIDES.open("r", encoding="utf-8-sig", newline="") as handle:
        return [row for row in csv.DictReader(handle) if (row.get("operation") or "").strip()]


def main() -> int:
    definition_colors, max_id = baker.load_definitions()
    definitions_by_id = {}
    with baker.ownership.DEFINITIONS.open("r", encoding="utf-8-sig", errors="replace", newline="") as handle:
        reader = csv.reader(handle, delimiter=";")
        next(reader, None)
        for row in reader:
            if len(row) > 4 and row[0].strip().isdigit():
                definitions_by_id[int(row[0])] = row[4].strip()
    terrain_classes = baker.load_terrain_classes(max_id)
    biomes: dict[int, str] = {}
    with BIOMES.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            biomes[int(row["province_id"])] = row["biome_name"]

    print("Building province ID map...")
    id_map = build_id_map(definition_colors)
    width = id_map.shape[1]
    print("Scanning adjacency (horizontal + vertical, no wrap)...")
    borders = scan_adjacency(id_map)
    print(f"  {len(borders)} raw adjacent pairs.")

    print("Computing per-province statistics...")
    area, sum_x, sum_y, min_x, min_y, max_x, max_y = per_province_stats(id_map, max_id)
    centroid_x = np.zeros(max_id + 1, dtype=np.int64)
    centroid_y = np.zeros(max_id + 1, dtype=np.int64)
    present = area > 0
    centroid_x[present] = (sum_x[present] / area[present]).astype(np.int64)
    centroid_y[present] = (sum_y[present] / area[present]).astype(np.int64)

    print("Computing anchors (eroded interior, nearest to centroid)...")
    own = id_map != INVALID_ID
    level_1 = interior_mask(id_map, own)
    level_2 = interior_mask(id_map, level_1)
    level_3 = interior_mask(id_map, level_2)
    best_3 = best_pixels(id_map, level_3, centroid_x, centroid_y, max_id)
    best_1 = best_pixels(id_map, level_1, centroid_x, centroid_y, max_id)
    best_0 = best_pixels(id_map, own, centroid_x, centroid_y, max_id)
    del level_1, level_2, level_3, own

    overrides = load_overrides()
    forced_impassable = {int(row["province_a"]) for row in overrides if row["operation"] == "mark_impassable"}
    anchor_overrides = {
        int(row["province_a"]): (int(row["x"]), int(row["y"]))
        for row in overrides if row["operation"] == "override_anchor"
    }

    provinces: dict[int, dict] = {}
    for province_id in range(1, max_id + 1):
        if area[province_id] == 0:
            continue
        terrain = terrain_classes[province_id]
        if terrain == baker.TERRAIN_WATER:
            classification = "water"
        elif terrain == baker.TERRAIN_IMPASSABLE or province_id in forced_impassable:
            classification = "impassable"
        else:
            classification = "land"
        anchor = anchor_overrides.get(province_id)
        if anchor is None:
            for best in (best_3, best_1, best_0):
                anchor = decode_anchor(int(best[province_id]), width)
                if anchor is not None:
                    break
        move_class = BIOME_MOVE_CLASS.get(biomes.get(province_id, ""), "plains")
        provinces[province_id] = {
            "name": definitions_by_id.get(province_id, ""),
            "classification": classification,
            "move_class": move_class,
            "coastal": False,
            "area": int(area[province_id]),
            "bbox": [int(min_x[province_id]), int(min_y[province_id]), int(max_x[province_id]), int(max_y[province_id])],
            "anchor": [int(anchor[0]), int(anchor[1])] if anchor else None,
            "land_neighbors": {},
            "sea_neighbors": {},
            "straits": [],
        }

    for (id_a, id_b), border_pixels in sorted(borders.items()):
        province_a, province_b = provinces.get(id_a), provinces.get(id_b)
        if province_a is None or province_b is None:
            continue
        a_water = province_a["classification"] == "water"
        b_water = province_b["classification"] == "water"
        if a_water and b_water:
            province_a["sea_neighbors"][str(id_b)] = border_pixels
            province_b["sea_neighbors"][str(id_a)] = border_pixels
        elif a_water != b_water:
            land, sea = (province_b, province_a) if a_water else (province_a, province_b)
            land_id, sea_id = (id_b, id_a) if a_water else (id_a, id_b)
            land["coastal"] = True
            land["sea_neighbors"][str(sea_id)] = border_pixels
            sea["land_neighbors"][str(land_id)] = border_pixels
        else:
            province_a["land_neighbors"][str(id_b)] = border_pixels
            province_b["land_neighbors"][str(id_a)] = border_pixels

    report_lines = ["# Province graph validation", ""]
    problems = 0

    def check(condition: bool, message: str) -> None:
        nonlocal problems
        if not condition:
            problems += 1
            report_lines.append(f"- **PROBLEM** {message}")

    strait_pairs: set[tuple[int, int]] = set()
    for row in overrides:
        operation = row["operation"].strip()
        note = (row.get("note") or "").strip()
        if operation in {"add_connection", "remove_connection", "mark_strait"}:
            id_a, id_b = int(row["province_a"]), int(row["province_b"])
            check(id_a != id_b, f"{operation} connects province {id_a} to itself ({note}).")
            check(id_a in provinces and id_b in provinces, f"{operation} references unknown province ({id_a}, {id_b}).")
            if id_a not in provinces or id_b not in provinces or id_a == id_b:
                continue
            key_a, key_b = str(id_a), str(id_b)
            if operation == "remove_connection":
                provinces[id_a]["land_neighbors"].pop(key_b, None)
                provinces[id_b]["land_neighbors"].pop(key_a, None)
            else:
                provinces[id_a]["land_neighbors"].setdefault(key_b, 0)
                provinces[id_b]["land_neighbors"].setdefault(key_a, 0)
                if operation == "mark_strait":
                    pair = (min(id_a, id_b), max(id_a, id_b))
                    check(pair not in strait_pairs, f"Duplicate strait between {id_a} and {id_b} ({note}).")
                    strait_pairs.add(pair)
                    if key_b not in provinces[id_a]["straits"]:
                        provinces[id_a]["straits"].append(key_b)
                    if key_a not in provinces[id_b]["straits"]:
                        provinces[id_b]["straits"].append(key_a)
        elif operation == "override_anchor":
            id_a = int(row["province_a"])
            check(id_a in provinces, f"override_anchor references unknown province {id_a} ({note}).")
        elif operation == "mark_impassable":
            check(int(row["province_a"]) in provinces, f"mark_impassable references unknown province ({note}).")
        else:
            check(False, f"Unknown override operation '{operation}' ({note}).")

    # Symmetry, self-connection, anchor containment, isolation, components.
    # A connection is symmetric when the reverse edge exists in either list:
    # land provinces keep sea neighbours in sea_neighbors while sea provinces
    # keep their coastal land in land_neighbors.
    for province_id, province in provinces.items():
        key_self = str(province_id)
        check(key_self not in province["land_neighbors"], f"Province {province_id} connects to itself.")
        check(key_self not in province["sea_neighbors"], f"Province {province_id} connects to itself by sea.")
        for neighbor_key in list(province["land_neighbors"]) + list(province["sea_neighbors"]):
            neighbor = provinces.get(int(neighbor_key))
            check(
                neighbor is not None
                and (key_self in neighbor["land_neighbors"] or key_self in neighbor["sea_neighbors"]),
                f"Asymmetric connection {province_id} -> {neighbor_key}.",
            )
        anchor = province["anchor"]
        check(anchor is not None, f"Province {province_id} ({province['name']}) has no anchor.")
        if anchor is not None:
            check(
                int(id_map[anchor[1], anchor[0]]) == province_id,
                f"Anchor of province {province_id} ({province['name']}) is outside the province.",
            )

    land_ids = sorted(pid for pid, p in provinces.items() if p["classification"] == "land")
    isolated = [
        pid for pid in land_ids
        if not any(provinces.get(int(k), {}).get("classification") == "land" for k in provinces[pid]["land_neighbors"])
    ]
    report_lines.append("")
    report_lines.append(f"Isolated land provinces (islands without crossings): {len(isolated)}")
    for pid in isolated[:40]:
        report_lines.append(f"  - {pid} {provinces[pid]['name']}")
    if len(isolated) > 40:
        report_lines.append(f"  - ... and {len(isolated) - 40} more")

    # Connected components over land movement edges.
    component_of: dict[int, int] = {}
    component_sizes: Counter = Counter()
    for start in land_ids:
        if start in component_of:
            continue
        component = len(component_sizes)
        stack = [start]
        component_of[start] = component
        while stack:
            current = stack.pop()
            component_sizes[component] += 1
            for neighbor_key in provinces[current]["land_neighbors"]:
                neighbor_id = int(neighbor_key)
                neighbor = provinces.get(neighbor_id)
                if neighbor is None or neighbor["classification"] != "land" or neighbor_id in component_of:
                    continue
                component_of[neighbor_id] = component
                stack.append(neighbor_id)
    report_lines.append("")
    report_lines.append(f"Land movement components: {len(component_sizes)}")
    for component, size in component_sizes.most_common(8):
        report_lines.append(f"  - component {component}: {size} provinces")

    output = {
        "version": 1,
        "map_size": [int(id_map.shape[1]), int(id_map.shape[0])],
        "terrain_costs": TERRAIN_COSTS,
        "provinces": {str(pid): provinces[pid] for pid in sorted(provinces)},
    }
    OUTPUT.write_text(json.dumps(output, separators=(",", ":")), encoding="utf-8")
    import_path = OUTPUT.with_suffix(".json.import")
    if not import_path.exists():
        import_path.write_text('[remap]\n\nimporter="keep"\n', encoding="utf-8")

    report_lines.insert(1, "")
    report_lines.insert(2, f"Provinces: {len(provinces)} (land {len(land_ids)}), border pairs: {len(borders)}, straits: {len(strait_pairs)}, problems: {problems}.")
    REPORT.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)} and {REPORT.relative_to(ROOT)} ({problems} problems).")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
