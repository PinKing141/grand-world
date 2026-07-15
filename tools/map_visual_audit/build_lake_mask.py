#!/usr/bin/env python3
"""Build the deterministic lake-only mask used by the final map shader.

The province graph remains authoritative. A water province is classified as a
lake only when its canonical name contains the standalone word "Lake" or
"Lakes". This deliberately excludes names such as "Blake Plataeu".
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
GRAPH_PATH = ROOT / "assets" / "province_graph.json"
LOOKUP_PATH = ROOT / "assets" / "color_lookup_map.png"
TERRAIN_CLASS_PATH = ROOT / "assets" / "terrain_class_map.png"
OUTPUT_PATH = ROOT / "assets" / "lake_mask.png"
METADATA_PATH = ROOT / "assets" / "lake_mask_metadata.json"
LAKE_WORD = re.compile(r"\blakes?\b", re.IGNORECASE)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build() -> tuple[np.ndarray, dict]:
    graph = json.loads(GRAPH_PATH.read_text(encoding="utf-8"))
    provinces = graph.get("provinces", {})
    lakes: list[dict] = []
    for raw_id, raw_record in provinces.items():
        record = raw_record if isinstance(raw_record, dict) else {}
        name = str(record.get("name", ""))
        if record.get("classification") == "water" and LAKE_WORD.search(name):
            lakes.append({"province_id": int(raw_id), "name": name, "area": int(record.get("area", 0))})
    lakes.sort(key=lambda item: item["province_id"])
    if not lakes:
        raise ValueError("province graph contains no named lake provinces")

    lookup = np.asarray(Image.open(LOOKUP_PATH).convert("RGB"), dtype=np.uint16)
    province_ids = lookup[:, :, 0] + lookup[:, :, 1] * 256
    lake_ids = np.asarray([item["province_id"] for item in lakes], dtype=np.uint16)
    mask = np.isin(province_ids, lake_ids).astype(np.uint8) * 255

    terrain_class = np.asarray(Image.open(TERRAIN_CLASS_PATH).convert("L"), dtype=np.uint8)
    if terrain_class.shape != mask.shape:
        raise ValueError(f"terrain class size {terrain_class.shape[::-1]} does not match lookup {mask.shape[::-1]}")
    if np.any(terrain_class[mask > 0] >= 43):
        raise ValueError("a canonical lake province is not classified as water in terrain_class_map.png")

    pixel_counts = dict(zip(*np.unique(province_ids[mask > 0], return_counts=True), strict=True))
    for item in lakes:
        province_id = item["province_id"]
        count = int(pixel_counts.get(province_id, 0))
        if count != item["area"]:
            raise ValueError(f"lake {province_id} ({item['name']}) has {count} pixels; graph records {item['area']}")

    metadata = {
        "schema_version": 1,
        "authority": "assets/province_graph.json water classification plus canonical standalone Lake/Lakes name",
        "derived_asset": "assets/lake_mask.png",
        "size": [int(mask.shape[1]), int(mask.shape[0])],
        "lake_count": len(lakes),
        "lake_pixel_count": int(np.count_nonzero(mask)),
        "sources": {
            "province_graph_sha256": sha256(GRAPH_PATH),
            "color_lookup_map_sha256": sha256(LOOKUP_PATH),
            "terrain_class_map_sha256": sha256(TERRAIN_CLASS_PATH),
        },
        "lakes": lakes,
    }
    return mask, metadata


def canonical_metadata_text(metadata: dict) -> str:
    return json.dumps(metadata, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def check(mask: np.ndarray, metadata: dict) -> bool:
    if not OUTPUT_PATH.is_file() or not METADATA_PATH.is_file():
        return False
    actual = np.asarray(Image.open(OUTPUT_PATH).convert("L"), dtype=np.uint8)
    if actual.shape != mask.shape or not np.array_equal(actual, mask):
        return False
    return METADATA_PATH.read_text(encoding="utf-8") == canonical_metadata_text(metadata)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the generated mask or metadata is stale.")
    args = parser.parse_args()
    try:
        mask, metadata = build()
        if args.check:
            if not check(mask, metadata):
                print("Lake mask or metadata is missing or stale.", file=sys.stderr)
                return 1
            print("Lake mask is valid and current.")
            return 0
        Image.fromarray(mask, mode="L").save(OUTPUT_PATH, format="PNG", compress_level=9, optimize=False)
        METADATA_PATH.write_text(canonical_metadata_text(metadata), encoding="utf-8")
        print(f"Wrote {OUTPUT_PATH.relative_to(ROOT)} with {metadata['lake_count']} canonical lakes.")
        print(f"Wrote {METADATA_PATH.relative_to(ROOT)}")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Lake mask build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
