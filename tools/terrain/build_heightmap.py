#!/usr/bin/env python3
"""Bake a land heightmap aligned to the strategy map's cropped Mercator projection.

Source: NASA Earth Observatory / GEBCO global elevation raster (public domain),
land elevation encoded as brightness (0..6400 m), equirectangular projection.
The output drives the hillshade relief in final_output_political_map.gdshader.
"""

from __future__ import annotations

import argparse
import math
import urllib.request
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
HEIGHTMAP = ROOT / "assets" / "heightmap.png"
SOURCE_URL = (
    "https://assets.science.nasa.gov/content/dam/science/esd/eo/images/"
    "bmng/topography/gebco_08_rev_elev_5400x2700.jpg"
)
SOURCE_CACHE = Path(__file__).with_name("gebco_08_rev_elev_5400x2700.jpg")

# Calibrated in the geographic audit; shared with build_biome_map.py.
MAP_WIDTH = 5632
MAP_HEIGHT = 2048
MERCATOR_EQUATOR_Y = 1343.856076
MERCATOR_PIXELS_PER_UNIT = 796.164187

# Half the map resolution is plenty for soft relief shading.
OUT_WIDTH = 2816
OUT_HEIGHT = 1024


def map_y_to_latitude(map_y: float) -> float:
    mercator_y = (MERCATOR_EQUATOR_Y - map_y) / MERCATOR_PIXELS_PER_UNIT
    return math.degrees(2.0 * math.atan(math.exp(mercator_y)) - math.pi / 2.0)


def load_source(path: Path | None) -> Image.Image:
    source_path = path or SOURCE_CACHE
    if not source_path.exists():
        print(f"Downloading {SOURCE_URL}")
        request = urllib.request.Request(SOURCE_URL, headers={"User-Agent": "GrandWorldHeightmap/1.0"})
        with urllib.request.urlopen(request, timeout=180) as response:
            source_path.write_bytes(response.read())
    return Image.open(source_path).convert("L")


def bake(source: Image.Image) -> Image.Image:
    src_width, src_height = source.size
    output = Image.new("L", (OUT_WIDTH, OUT_HEIGHT))
    # Longitude maps linearly to x, so each output row is one resampled source
    # row picked by the shared inverse-Mercator latitude transform.
    for out_y in range(OUT_HEIGHT):
        map_y = (out_y + 0.5) * (MAP_HEIGHT / OUT_HEIGHT)
        latitude = map_y_to_latitude(map_y)
        src_y = min(src_height - 1, max(0, int(round((90.0 - latitude) / 180.0 * src_height - 0.5))))
        row = source.crop((0, src_y, src_width, src_y + 1)).resize((OUT_WIDTH, 1), Image.BILINEAR)
        output.paste(row, (0, out_y))
    # Lift low/mid elevations (most of the inhabited world sits under 1000 m)
    # so the shader's slope estimate has usable gradients outside the great
    # ranges, then soften JPEG blocking.
    curve = [min(255, round(255.0 * (value / 255.0) ** 0.6)) for value in range(256)]
    output = output.point(curve)
    return output.filter(ImageFilter.GaussianBlur(0.8))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=None, help="Path to a local copy of the source raster.")
    args = parser.parse_args()
    baked = bake(load_source(args.source))
    baked.save(HEIGHTMAP, optimize=True)
    print(f"Baked {HEIGHTMAP.relative_to(ROOT)} at {baked.size[0]}x{baked.size[1]}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
