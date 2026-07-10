#!/usr/bin/env python3
"""Bake political and terrain-class textures on CPU without Godot compute shaders."""

from __future__ import annotations

import binascii
import csv
import re
import struct
import zlib
from collections import Counter
from pathlib import Path

import build_manifest as ownership


ROOT = Path(__file__).resolve().parents[2]
PROVINCE_BITMAP = ROOT / "assets" / "provinces.bmp"
COLOR_MAP = ROOT / "assets" / "color_map.png"
POLITICAL_MASK = ROOT / "assets" / "mask_political_map.png"
TERRAIN_CLASS_MAP = ROOT / "assets" / "terrain_class_map.png"
COLOR_PATTERN = re.compile(r"color\s*=\s*\{\s*(\d+)\s+(\d+)\s+(\d+)\s*\}")
WATER_NAME_PATTERN = re.compile(
    r"(?:sea|ocean|gulf|lake|strait|channel|bay|bight|coast|basin|lagoon|reef|bank|sound|hav|approach|delta|archipelago|shelf|trench|current|gap|river|firth|chott)",
    re.IGNORECASE,
)

TERRAIN_WATER = 0
TERRAIN_OWNED_LAND = 85
TERRAIN_UNOWNED_LAND = 170
TERRAIN_IMPASSABLE = 255


def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    checksum = binascii.crc32(chunk_type)
    checksum = binascii.crc32(data, checksum) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", checksum)


def write_rgba_png(path: Path, width: int, height: int, rows) -> None:
    compressor = zlib.compressobj(level=9)
    compressed_parts = []
    row_count = 0
    for row in rows:
        if len(row) != width * 4:
            raise ValueError(f"Invalid row width while writing {path.name}")
        compressed_parts.append(compressor.compress(b"\x00" + bytes(row)))
        row_count += 1
    if row_count != height:
        raise ValueError(f"Expected {height} rows for {path.name}, received {row_count}")
    compressed_parts.append(compressor.flush())
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    payload = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", b"".join(compressed_parts))
        + png_chunk(b"IEND", b"")
    )
    path.write_bytes(payload)


def load_definitions() -> tuple[dict[tuple[int, int, int], int], int]:
    colors = {}
    max_id = 0
    with ownership.DEFINITIONS.open("r", encoding="utf-8-sig", errors="replace", newline="") as handle:
        reader = csv.reader(handle, delimiter=";")
        next(reader, None)
        for row in reader:
            if len(row) < 4 or not row[0].strip().isdigit():
                continue
            province_id = int(row[0])
            colors[(int(row[1]), int(row[2]), int(row[3]))] = province_id
            max_id = max(max_id, province_id)
    return colors, max_id


def load_country_colors() -> dict[str, tuple[int, int, int]]:
    result = {}
    countries = ownership.load_countries()
    for tag, country in countries.items():
        color_path = ownership.COUNTRY_COLORS / f"{country.name}.txt"
        if not color_path.exists():
            continue
        match = COLOR_PATTERN.search(color_path.read_text(encoding="utf-8", errors="replace"))
        if match:
            result[tag] = tuple(int(match.group(part)) for part in (1, 2, 3))
    return result


def load_province_colors(country_colors: dict[str, tuple[int, int, int]], max_id: int) -> list[tuple[int, int, int, int]]:
    colors = [(0, 0, 0, 0) for _ in range(max_id + 1)]
    for province_id, (_path, fields) in ownership.load_histories().items():
        owner = fields.get("owner", "").upper()
        if owner in country_colors and province_id <= max_id:
            red, green, blue = country_colors[owner]
            colors[province_id] = (red, green, blue, 255)
    return colors


def load_terrain_classes(max_id: int) -> list[int]:
    classes = [TERRAIN_WATER for _ in range(max_id + 1)]
    if not ownership.MANIFEST.exists():
        raise FileNotFoundError("Build docs/data/1444_ownership_manifest.csv before baking terrain classes")
    with ownership.MANIFEST.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            raw_id = (row.get("province_id") or "").strip()
            if not raw_id.isdigit():
                continue
            province_id = int(raw_id)
            if province_id > max_id:
                continue
            status = (row.get("status") or "").strip()
            authority_type = (row.get("authority_type") or "").strip()
            province_name = (row.get("province_name") or "").strip()
            if status in {"existing", "applied"}:
                terrain_class = TERRAIN_OWNED_LAND
            elif authority_type == "uninhabited_land":
                terrain_class = TERRAIN_UNOWNED_LAND
            elif authority_type == "water_or_inland_lake" or WATER_NAME_PATTERN.search(province_name):
                terrain_class = TERRAIN_WATER
            elif authority_type in {"impassable_or_non_playable_terrain", "non_playable_definition"}:
                terrain_class = TERRAIN_IMPASSABLE
            elif province_name.casefold().startswith("unusedwater") or province_name.casefold().startswith("unusedsea"):
                terrain_class = TERRAIN_WATER
            elif province_name.casefold().startswith("unused"):
                terrain_class = TERRAIN_IMPASSABLE
            else:
                terrain_class = TERRAIN_UNOWNED_LAND
            classes[province_id] = terrain_class
    return classes


def read_bmp_header(data: bytes) -> tuple[int, int, int, int]:
    if data[:2] != b"BM":
        raise ValueError("Province bitmap is not a BMP file")
    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    width = struct.unpack_from("<i", data, 18)[0]
    height = struct.unpack_from("<i", data, 22)[0]
    bits_per_pixel = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]
    if width <= 0 or height == 0 or bits_per_pixel != 24 or compression != 0:
        raise ValueError("CPU baker currently requires an uncompressed 24-bit BMP")
    return pixel_offset, width, height, ((width * 3 + 3) // 4) * 4


def color_map_rows(province_colors: list[tuple[int, int, int, int]]):
    for y in range(256):
        row = bytearray(256 * 4)
        for x in range(256):
            province_id = x + y * 256
            if province_id < len(province_colors):
                row[x * 4:x * 4 + 4] = bytes(province_colors[province_id])
        yield row


def political_mask_rows(
    bmp: bytes,
    pixel_offset: int,
    width: int,
    signed_height: int,
    row_stride: int,
    definition_colors: dict[tuple[int, int, int], int],
    province_colors: list[tuple[int, int, int, int]],
):
    height = abs(signed_height)
    bottom_up = signed_height > 0
    transparent = (0, 0, 0, 0)
    for output_y in range(height):
        source_y = height - 1 - output_y if bottom_up else output_y
        source_start = pixel_offset + source_y * row_stride
        row = bytearray(width * 4)
        for x in range(width):
            source = source_start + x * 3
            blue, green, red = bmp[source:source + 3]
            province_id = definition_colors.get((red, green, blue), -1)
            color = province_colors[province_id] if 0 <= province_id < len(province_colors) else transparent
            row[x * 4:x * 4 + 4] = bytes(color)
        yield row


def terrain_class_rows(
    bmp: bytes,
    pixel_offset: int,
    width: int,
    signed_height: int,
    row_stride: int,
    definition_colors: dict[tuple[int, int, int], int],
    terrain_classes: list[int],
):
    height = abs(signed_height)
    bottom_up = signed_height > 0
    for output_y in range(height):
        source_y = height - 1 - output_y if bottom_up else output_y
        source_start = pixel_offset + source_y * row_stride
        row = bytearray(width * 4)
        for x in range(width):
            source = source_start + x * 3
            blue, green, red = bmp[source:source + 3]
            province_id = definition_colors.get((red, green, blue), -1)
            terrain_class = terrain_classes[province_id] if 0 <= province_id < len(terrain_classes) else TERRAIN_WATER
            row[x * 4:x * 4 + 4] = bytes((terrain_class, 0, 0, 255))
        yield row


def main() -> int:
    definition_colors, max_id = load_definitions()
    country_colors = load_country_colors()
    province_colors = load_province_colors(country_colors, max_id)
    terrain_classes = load_terrain_classes(max_id)
    missing_colored = [province_id for province_id, color in enumerate(province_colors) if color[3] and color[:3] == (0, 0, 0)]
    if missing_colored:
        raise ValueError(f"Invalid opaque-black province colors: {missing_colored[:20]}")

    bmp = PROVINCE_BITMAP.read_bytes()
    pixel_offset, width, signed_height, row_stride = read_bmp_header(bmp)
    height = abs(signed_height)
    write_rgba_png(COLOR_MAP, 256, 256, color_map_rows(province_colors))
    write_rgba_png(
        POLITICAL_MASK,
        width,
        height,
        political_mask_rows(
            bmp,
            pixel_offset,
            width,
            signed_height,
            row_stride,
            definition_colors,
            province_colors,
        ),
    )
    write_rgba_png(
        TERRAIN_CLASS_MAP,
        width,
        height,
        terrain_class_rows(
            bmp,
            pixel_offset,
            width,
            signed_height,
            row_stride,
            definition_colors,
            terrain_classes,
        ),
    )
    owned = sum(1 for color in province_colors if color[3])
    class_counts = Counter(terrain_classes)
    print(f"Baked political textures for {owned} owned provinces at {width}x{height}.")
    print(
        "Terrain definitions: "
        f"water={class_counts[TERRAIN_WATER]}, "
        f"owned={class_counts[TERRAIN_OWNED_LAND]}, "
        f"unowned={class_counts[TERRAIN_UNOWNED_LAND]}, "
        f"impassable={class_counts[TERRAIN_IMPASSABLE]}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
