#!/usr/bin/env python3
"""Assign a physical biome to every province and bake an aligned world texture.

The political owner map and the physical biome map are deliberately separate.
WWF-derived generalized terrestrial biome polygons provide the baseline. A
small, explicit override layer handles map-specific wastelands and mountain
blocks whose province centroids are not sufficiently representative.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "historical_ownership"))

import bake_political_textures as baker  # noqa: E402


GEOGRAPHY = ROOT / "docs" / "data" / "province_geography.csv"
BIOME_MANIFEST = ROOT / "docs" / "data" / "1444_biome_manifest.csv"
BIOME_MAP = ROOT / "assets" / "biome_map.png"
SOURCE_LAYER = (
    "https://services.arcgis.com/BG6nSlhZSAWtExvp/arcgis/rest/services/"
    "GlobalBiomes/FeatureServer/0"
)
MERCATOR_EQUATOR_Y = 1343.856076
MERCATOR_PIXELS_PER_UNIT = 796.164187

# Muted strategy-map colours. These are visual design colours, not colours
# supplied by the source dataset.
BIOMES = {
    "Water": (0, (0, 0, 0)),
    "Boreal Forests/Taiga": (1, (57, 88, 64)),
    "Deserts & Xeric Shrublands": (2, (194, 157, 96)),
    "Flooded Grasslands & Savannas": (3, (89, 126, 92)),
    "Lake": (4, (45, 105, 143)),
    "Mangroves": (5, (43, 103, 82)),
    "Mediterranean Forests, Woodlands & Scrub": (6, (119, 132, 72)),
    "Montane Grasslands & Shrublands": (7, (124, 119, 103)),
    "Rock and Ice": (8, (196, 211, 216)),
    "Temperate Broadleaf & Mixed Forests": (9, (81, 119, 70)),
    "Temperate Conifer Forests": (10, (61, 103, 70)),
    "Temperate Grasslands, Savannas & Shrublands": (11, (139, 148, 78)),
    "Tropical & Subtropical Coniferous Forests": (12, (54, 113, 72)),
    "Tropical & Subtropical Dry Broadleaf Forests": (13, (126, 143, 76)),
    "Tropical & Subtropical Grasslands, Savannas & Shrublands": (14, (157, 145, 70)),
    "Tropical & Subtropical Moist Broadleaf Forests": (15, (42, 107, 61)),
    "Tundra": (16, (132, 139, 112)),
}

MOUNTAIN_PATTERN = re.compile(
    r"(?:mountain|highland|range|himalaya|karakoram|kunlun|tian shan|tiam shan|"
    r"alps|pyrenees|carpathian|caucasus|zagros|elburz|scandes|atlas|jotenheim|"
    r"chagai|arunachal|maoke|changtang|aqenganggyai|gaoligong|hengduan|changbai)",
    re.IGNORECASE,
)
DESERT_PATTERN = re.compile(
    r"(?:sahara|kalahari|namib|rub.? al khali|takla makan|el djouf|badia|badiyat|"
    r"eastern desert|western australia|central australia|chagai)",
    re.IGNORECASE,
)
ICE_PATTERN = re.compile(r"(?:greenland|ice cap|ice sheet)", re.IGNORECASE)

# Map-specific large terrain blocks. Explicit IDs make the historical-gameplay
# reconstruction reviewable instead of burying exceptions in shader code.
BIOME_OVERRIDES = {
    1779: "Deserts & Xeric Shrublands",  # Rub' al Khali
    1784: "Montane Grasslands & Shrublands",  # Tian Shan
    1785: "Montane Grasslands & Shrublands",  # Karakoram
    1786: "Deserts & Xeric Shrublands",  # Takla Makan
    1787: "Montane Grasslands & Shrublands",  # Himalaya
    1788: "Montane Grasslands & Shrublands",  # Arunachal
    1789: "Montane Grasslands & Shrublands",  # Maoke
    1790: "Deserts & Xeric Shrublands",  # Western Australia
    1791: "Deserts & Xeric Shrublands",  # Central Australia
    1793: "Deserts & Xeric Shrublands",  # El Djouf
    1794: "Deserts & Xeric Shrublands",  # Central Sahara
    1795: "Deserts & Xeric Shrublands",  # East Sahara
    1796: "Tropical & Subtropical Moist Broadleaf Forests",  # Central Africa
    1797: "Tropical & Subtropical Moist Broadleaf Forests",  # Inner Kongo
    1801: "Deserts & Xeric Shrublands",  # Kalahari
    1802: "Tropical & Subtropical Moist Broadleaf Forests",  # Northern Amazonas
    1803: "Tropical & Subtropical Moist Broadleaf Forests",  # Southern Amazonas
    1804: "Rock and Ice",  # Greenland
    1924: "Rock and Ice",  # Greenland tip
}


def fetch_source_features() -> list[dict]:
    query = urllib.parse.urlencode(
        {
            "where": "1=1",
            "outFields": "OBJECTID,BIOME_DESC",
            "returnGeometry": "true",
            "outSR": "4326",
            "f": "geojson",
        }
    )
    request = urllib.request.Request(
        f"{SOURCE_LAYER}/query?{query}",
        headers={"User-Agent": "GrandWorldBiomeBuilder/1.0"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = json.load(response)
    features = payload.get("features") or []
    if len(features) < 14:
        raise ValueError(f"Expected the global biome layer, received only {len(features)} features")
    return features


def point_on_segment(point: tuple[float, float], start: list[float], end: list[float]) -> bool:
    px, py = point
    ax, ay = start[:2]
    bx, by = end[:2]
    cross = (px - ax) * (by - ay) - (py - ay) * (bx - ax)
    if abs(cross) > 1.0e-9:
        return False
    return min(ax, bx) - 1.0e-9 <= px <= max(ax, bx) + 1.0e-9 and min(ay, by) - 1.0e-9 <= py <= max(ay, by) + 1.0e-9


def point_in_ring(point: tuple[float, float], ring: list[list[float]]) -> bool:
    px, py = point
    inside = False
    previous = ring[-1]
    for current in ring:
        if point_on_segment(point, previous, current):
            return True
        x1, y1 = previous[:2]
        x2, y2 = current[:2]
        if (y1 > py) != (y2 > py):
            crossing_x = (x2 - x1) * (py - y1) / (y2 - y1) + x1
            if px < crossing_x:
                inside = not inside
        previous = current
    return inside


def polygon_parts(features: list[dict]) -> list[tuple[str, tuple[float, float, float, float], list[list[list[float]]]]]:
    parts = []
    for feature in features:
        biome_name = (feature.get("properties") or {}).get("BIOME_DESC", "")
        if biome_name not in BIOMES:
            continue
        geometry = feature.get("geometry") or {}
        geometry_type = geometry.get("type")
        coordinates = geometry.get("coordinates") or []
        polygons = [coordinates] if geometry_type == "Polygon" else coordinates if geometry_type == "MultiPolygon" else []
        for polygon in polygons:
            if not polygon or not polygon[0]:
                continue
            exterior = polygon[0]
            xs = [coordinate[0] for coordinate in exterior]
            ys = [coordinate[1] for coordinate in exterior]
            parts.append((biome_name, (min(xs), min(ys), max(xs), max(ys)), polygon))
    return parts


def source_biome_at(longitude: float, latitude: float, parts) -> str:
    point = (longitude, latitude)
    for biome_name, bounds, polygon in parts:
        min_x, min_y, max_x, max_y = bounds
        if not (min_x <= longitude <= max_x and min_y <= latitude <= max_y):
            continue
        if not point_in_ring(point, polygon[0]):
            continue
        if any(point_in_ring(point, hole) for hole in polygon[1:]):
            continue
        return biome_name
    return ""


def gameplay_override(province_id: int, province_name: str) -> str:
    if province_id in BIOME_OVERRIDES:
        return BIOME_OVERRIDES[province_id]
    if ICE_PATTERN.search(province_name):
        return "Rock and Ice"
    if DESERT_PATTERN.search(province_name):
        return "Deserts & Xeric Shrublands"
    if MOUNTAIN_PATTERN.search(province_name):
        return "Montane Grasslands & Shrublands"
    return ""


def fallback_biome(latitude: float) -> str:
    absolute_latitude = abs(latitude)
    if absolute_latitude >= 80.0:
        return "Rock and Ice"
    if absolute_latitude >= 67.0:
        return "Tundra"
    if absolute_latitude >= 56.0:
        return "Boreal Forests/Taiga"
    if absolute_latitude >= 32.0:
        return "Temperate Broadleaf & Mixed Forests"
    if absolute_latitude >= 18.0:
        return "Tropical & Subtropical Grasslands, Savannas & Shrublands"
    return "Tropical & Subtropical Moist Broadleaf Forests"


def map_y_to_latitude(centroid_y: float) -> float:
    mercator_y = (MERCATOR_EQUATOR_Y - centroid_y) / MERCATOR_PIXELS_PER_UNIT
    return math.degrees(2.0 * math.atan(math.exp(mercator_y)) - math.pi / 2.0)


def build_assignments(features: list[dict]) -> dict[int, dict[str, str]]:
    parts = polygon_parts(features)
    terrain_classes = baker.load_terrain_classes(baker.load_definitions()[1])
    assignments = {}
    with GEOGRAPHY.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            province_id = int(row["province_id"])
            province_name = row["province_name"]
            longitude = float(row["longitude"])
            # Recalculate from the authoritative map coordinate so this tool
            # remains correct even if geography.csv predates the projection fix.
            latitude = map_y_to_latitude(float(row["centroid_y"]))
            if terrain_classes[province_id] == baker.TERRAIN_WATER:
                biome_name = "Water"
                method = "terrain_water_class"
            else:
                biome_name = gameplay_override(province_id, province_name)
                method = "historical_gameplay_override" if biome_name else ""
                if not biome_name:
                    biome_name = source_biome_at(longitude, latitude, parts)
                    method = "wwf_biome_centroid" if biome_name else ""
                if biome_name == "Lake":
                    biome_name = ""
                    method = ""
                if not biome_name:
                    biome_name = fallback_biome(latitude)
                    method = "latitude_fallback"
            biome_id, color = BIOMES[biome_name]
            assignments[province_id] = {
                "province_id": str(province_id),
                "province_name": province_name,
                "longitude": f"{longitude:.5f}",
                "latitude": f"{latitude:.5f}",
                "biome_id": str(biome_id),
                "biome_name": biome_name,
                "red": str(color[0]),
                "green": str(color[1]),
                "blue": str(color[2]),
                "assignment_method": method,
                "source_url": SOURCE_LAYER if method == "wwf_biome_centroid" else "",
            }
    return assignments


def write_manifest(assignments: dict[int, dict[str, str]]) -> None:
    fieldnames = [
        "province_id", "province_name", "longitude", "latitude", "biome_id", "biome_name",
        "red", "green", "blue", "assignment_method", "source_url",
    ]
    BIOME_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with BIOME_MANIFEST.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(assignments[key] for key in sorted(assignments))


def load_manifest() -> dict[int, dict[str, str]]:
    assignments = {}
    with BIOME_MANIFEST.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            assignments[int(row["province_id"])] = row
    return assignments


def biome_map_rows(bmp, pixel_offset, width, signed_height, row_stride, definitions, colors):
    height = abs(signed_height)
    bottom_up = signed_height > 0
    for output_y in range(height):
        source_y = height - 1 - output_y if bottom_up else output_y
        source_start = pixel_offset + source_y * row_stride
        row = bytearray(width * 4)
        for x in range(width):
            source = source_start + x * 3
            blue, green, red = bmp[source:source + 3]
            province_id = definitions.get((red, green, blue), -1)
            color = colors.get(province_id, (0, 0, 0))
            row[x * 4:x * 4 + 4] = bytes((*color, 255))
        yield row


def bake_map(assignments: dict[int, dict[str, str]]) -> tuple[int, int]:
    definitions, _max_id = baker.load_definitions()
    colors = {
        province_id: (int(row["red"]), int(row["green"]), int(row["blue"]))
        for province_id, row in assignments.items()
    }
    bmp = baker.PROVINCE_BITMAP.read_bytes()
    pixel_offset, width, signed_height, row_stride = baker.read_bmp_header(bmp)
    height = abs(signed_height)
    baker.write_rgba_png(
        BIOME_MAP,
        width,
        height,
        biome_map_rows(bmp, pixel_offset, width, signed_height, row_stride, definitions, colors),
    )
    return width, height


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--refresh", action="store_true", help="Refresh assignments from the WWF-derived ArcGIS layer")
    args = parser.parse_args()

    if args.refresh or not BIOME_MANIFEST.exists():
        assignments = build_assignments(fetch_source_features())
        write_manifest(assignments)
    else:
        assignments = load_manifest()
    width, height = bake_map(assignments)
    counts = Counter(row["biome_name"] for row in assignments.values())
    print(f"Baked {len(assignments)} province biome assignments at {width}x{height}.")
    for biome_name, count in sorted(counts.items()):
        print(f"  {biome_name}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
