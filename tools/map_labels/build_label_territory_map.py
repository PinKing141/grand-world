#!/usr/bin/env python3
"""Bake and validate a conservative province-ID raster for country-label fitting."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets" / "provinces.bmp"
DEFINITIONS = ROOT / "assets" / "definition.csv"
OUTPUT = ROOT / "assets" / "label_territory_map.png"
METADATA = ROOT / "assets" / "label_territory_map.json"
SCALE = 4
SCHEMA_VERSION = 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail when the baked map is missing or stale.")
    return parser.parse_args()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def definition_lookup() -> tuple[np.ndarray, np.ndarray]:
    by_colour: dict[int, tuple[int, str]] = {}
    with DEFINITIONS.open("r", encoding="utf-8", errors="replace") as handle:
        next(handle, None)
        for row_number, line in enumerate(handle, start=2):
            row = line.strip().strip('"').split(";")
            if len(row) < 4:
                raise ValueError(f"definition.csv row {row_number} has fewer than four columns")
            province_id = int(row[0])
            red, green, blue = (int(row[index]) for index in range(1, 4))
            packed = (red << 16) | (green << 8) | blue
            province_name = row[4].strip('"') if len(row) > 4 else ""
            if packed in by_colour:
                previous_id, previous_name = by_colour[packed]
                if province_name != "RNW" or previous_name != "RNW":
                    raise ValueError(
                        f"definition.csv colour {red},{green},{blue} is shared by "
                        f"{previous_id} ({previous_name}) and {province_id} ({province_name})"
                    )
                by_colour[packed] = (min(previous_id, province_id), "RNW")
            else:
                by_colour[packed] = (province_id, province_name)
    pairs = sorted((packed, value[0]) for packed, value in by_colour.items())
    colours = np.asarray([pair[0] for pair in pairs], dtype=np.uint32)
    ids = np.asarray([pair[1] for pair in pairs], dtype=np.uint32)
    return colours, ids


def build_image() -> Image.Image:
    source = np.asarray(Image.open(SOURCE).convert("RGB"), dtype=np.uint8)
    height, width, channels = source.shape
    if channels != 3 or width % SCALE or height % SCALE:
        raise ValueError(f"province map dimensions {width}x{height} are not divisible by scale {SCALE}")

    blocks = source.reshape(height // SCALE, SCALE, width // SCALE, SCALE, 3)
    reference = blocks[:, 0, :, 0, :]
    conservative = np.all(blocks == reference[:, None, :, None, :], axis=(1, 3, 4))
    packed = (
        reference[:, :, 0].astype(np.uint32) << 16
        | reference[:, :, 1].astype(np.uint32) << 8
        | reference[:, :, 2].astype(np.uint32)
    )

    colour_keys, province_ids = definition_lookup()
    positions = np.searchsorted(colour_keys, packed)
    in_range = positions < colour_keys.size
    matched = np.zeros_like(in_range)
    matched[in_range] = colour_keys[positions[in_range]] == packed[in_range]
    valid = conservative & matched
    encoded_ids = np.zeros(packed.shape, dtype=np.uint32)
    encoded_ids[valid] = province_ids[positions[valid]]

    encoded = np.empty((*encoded_ids.shape, 3), dtype=np.uint8)
    encoded[:, :, 0] = (encoded_ids >> 16) & 0xFF
    encoded[:, :, 1] = (encoded_ids >> 8) & 0xFF
    encoded[:, :, 2] = encoded_ids & 0xFF
    return Image.fromarray(encoded, mode="RGB")


def png_bytes(image: Image.Image) -> bytes:
    import io

    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def expected_metadata(image: Image.Image, output_bytes: bytes) -> dict[str, object]:
    return {
        "schema_version": SCHEMA_VERSION,
        "generator": "tools/map_labels/build_label_territory_map.py",
        "source": "assets/provinces.bmp",
        "source_sha256": sha256_file(SOURCE),
        "definition_source": "assets/definition.csv",
        "definition_sha256": sha256_file(DEFINITIONS),
        "scale": SCALE,
        "map_size": list(image.size),
        "source_size": [image.width * SCALE, image.height * SCALE],
        "encoding": "RGB24 big-endian province ID; 0 means unsafe/mixed block",
        "conservative_rule": f"all pixels in each {SCALE}x{SCALE} source block must share one province colour",
        "png_sha256": sha256_bytes(output_bytes),
    }


def serialize_metadata(data: dict[str, object]) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main() -> int:
    args = parse_args()
    try:
        image = build_image()
        output_bytes = png_bytes(image)
        metadata_text = serialize_metadata(expected_metadata(image, output_bytes))
    except (OSError, ValueError) as error:
        print(f"Label territory bake failed: {error}", file=sys.stderr)
        return 1

    if args.check:
        if not OUTPUT.is_file() or not METADATA.is_file():
            print("Label territory map or metadata is missing.", file=sys.stderr)
            return 1
        if OUTPUT.read_bytes() != output_bytes:
            print("Label territory map is stale; rebuild it with build_label_territory_map.py.", file=sys.stderr)
            return 1
        if METADATA.read_text(encoding="utf-8") != metadata_text:
            print("Label territory metadata is stale; rebuild it with build_label_territory_map.py.", file=sys.stderr)
            return 1
        print(f"Label territory map is valid and current. size={image.width}x{image.height} scale={SCALE}")
        return 0

    OUTPUT.write_bytes(output_bytes)
    METADATA.write_text(metadata_text, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)} ({image.width}x{image.height}, scale {SCALE}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
