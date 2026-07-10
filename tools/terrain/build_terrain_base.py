#!/usr/bin/env python3
"""Bake the physical terrain base texture that sits under every colour mapmode.

Combines the province biome colours with the baked elevation texture into a
natural-looking ground layer: lush lowlands, rocky highlands, snow above the
snowline, soft ecotone transitions, and a little hand-painted variation. The
political (or any future religion/ideology) overlay is blended on top of this
texture by final_output_political_map.gdshader, so mapmodes can change without
touching the terrain underneath.
"""

from __future__ import annotations

import numpy as np
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
BIOME_MAP = ROOT / "assets" / "biome_map.png"
HEIGHTMAP = ROOT / "assets" / "heightmap.png"
TERRAIN_CLASS = ROOT / "assets" / "terrain_class_map.png"
OUTPUT = ROOT / "assets" / "terrain_base_map.png"

WIDTH, HEIGHT = 2816, 1024
STRIP = 128  # process in strips to keep peak memory low

ROCK_COLOR = np.array([0.50, 0.45, 0.40], dtype=np.float32)
SNOW_COLOR = np.array([0.93, 0.95, 0.97], dtype=np.float32)
WATER_FILL = np.array([0.05, 0.11, 0.18], dtype=np.float32)

ROCK_START, ROCK_FULL = 0.45, 0.80  # elevation band blending toward bare rock
SNOW_START = 0.80                   # elevation where snow begins


def masked_blur(biome: Image.Image, land_mask: Image.Image, radius: float) -> Image.Image:
    """Blur biome colours without bleeding the black water pixels into coasts."""
    weighted = Image.merge("RGB", [
        Image.composite(channel, Image.new("L", biome.size, 0), land_mask)
        for channel in biome.split()
    ]).filter(ImageFilter.GaussianBlur(radius))
    weight = land_mask.filter(ImageFilter.GaussianBlur(radius))
    return weighted, weight


def main() -> int:
    size = (WIDTH, HEIGHT)
    biome = Image.open(BIOME_MAP).convert("RGB").resize(size, Image.NEAREST)
    height = Image.open(HEIGHTMAP).convert("L").resize(size, Image.BILINEAR)
    # The class texture encodes water/owned/unowned/impassable in the RED
    # channel (0, 85, 170, 255); convert("L") would crush those values.
    terrain_class = Image.open(TERRAIN_CLASS).convert("RGB").getchannel(0).resize(size, Image.NEAREST)
    land_mask = terrain_class.point(lambda v: 255 if v >= 43 else 0)

    blurred, weight = masked_blur(biome, land_mask, radius=2.5)

    # Low-frequency hand-painted blotches plus fine grain, deterministic.
    rng = np.random.default_rng(1444)
    blotches = rng.uniform(-1.0, 1.0, (HEIGHT // 16, WIDTH // 16)).astype(np.float32)
    blotches = np.asarray(
        Image.fromarray(((blotches + 1.0) * 127.5).astype(np.uint8)).resize(size, Image.BILINEAR),
        dtype=np.float32) / 127.5 - 1.0

    output = Image.new("RGB", size)
    for top in range(0, HEIGHT, STRIP):
        box = (0, top, WIDTH, min(top + STRIP, HEIGHT))
        soft = np.asarray(blurred.crop(box), dtype=np.float32) / 255.0
        wgt = np.asarray(weight.crop(box), dtype=np.float32)[..., None] / 255.0
        soft = soft / np.maximum(wgt, 1e-3)
        hard = np.asarray(biome.crop(box), dtype=np.float32) / 255.0
        land = (np.asarray(land_mask.crop(box), dtype=np.float32) / 255.0)[..., None]
        elevation = (np.asarray(height.crop(box), dtype=np.float32) / 255.0)[..., None]
        noise = blotches[box[1]:box[3], :][..., None]

        # Soften province-edge ecotones, keep some of the crisp biome identity.
        ground = hard * 0.35 + np.clip(soft, 0, 1) * 0.65
        # Lowlands read slightly lusher, highlands blend to rock, peaks to snow.
        ground = ground * (1.0 - 0.06 * np.clip(1.0 - elevation / 0.25, 0, 1))
        rock_amount = np.clip((elevation - ROCK_START) / (ROCK_FULL - ROCK_START), 0, 1) * 0.65
        ground = ground * (1 - rock_amount) + ROCK_COLOR * rock_amount
        snow_amount = np.clip((elevation - SNOW_START) / (1.0 - SNOW_START), 0, 1)
        ground = ground * (1 - snow_amount) + SNOW_COLOR * snow_amount
        # Hand-painted variation: gentle blotches, none on snow.
        ground = ground * (1.0 + 0.05 * noise * (1.0 - snow_amount))

        ground = ground * land + WATER_FILL * (1.0 - land)
        strip_img = Image.fromarray((np.clip(ground, 0, 1) * 255).astype(np.uint8))
        output.paste(strip_img, (0, top))

    output.save(OUTPUT, optimize=True)
    print(f"Baked {OUTPUT.relative_to(ROOT)} at {WIDTH}x{HEIGHT}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
