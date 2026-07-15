#!/usr/bin/env python3
"""Validate the renderer-independent province edge-lattice contract."""

from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> int:
    lookup_path = ROOT / "assets" / "color_lookup_map.png"
    lattice_shader_path = ROOT / "shaders" / "province_edge_lattice.gdshader"
    final_shader_path = ROOT / "shaders" / "final_output_political_map.gdshader"
    scene_path = ROOT / "scenes" / "main.tscn"
    lookup = np.asarray(Image.open(lookup_path).convert("RGB"), dtype=np.uint8)[:, :, :2]
    vertical = np.zeros(lookup.shape[:2], dtype=np.bool_)
    horizontal = np.zeros(lookup.shape[:2], dtype=np.bool_)
    vertical[:, 1:] = np.any(lookup[:, 1:] != lookup[:, :-1], axis=2)
    horizontal[1:, :] = np.any(lookup[1:, :] != lookup[:-1, :], axis=2)
    require(not vertical[:, 0].any(), "vertical lattice must not invent a wrapped left-map edge")
    require(not horizontal[0, :].any(), "horizontal lattice must not invent a wrapped top-map edge")
    require(int(vertical.sum()) > 100_000, "vertical lattice must contain representative province adjacencies")
    require(int(horizontal.sum()) > 100_000, "horizontal lattice must contain representative province adjacencies")

    lattice_shader = lattice_shader_path.read_text(encoding="utf-8")
    final_shader = final_shader_path.read_text(encoding="utf-8")
    scene = scene_path.read_text(encoding="utf-8")
    for required in (
        "filter_nearest, repeat_disable",
        "pixel - ivec2(1, 0)",
        "pixel - ivec2(0, 1)",
        "COLOR = vec4(vertical_edge, horizontal_edge",
    ):
        require(required in lattice_shader, f"edge-lattice shader lost required contract: {required}")
    require("canonical_edge_distances_pixels" in final_shader, "final renderer must consume shared edge segments")
    require("province_distance_field" not in final_shader, "province-interior SDF must not return to the live final renderer")
    require("ProvinceEdgeLattice" in scene and "province_edge_lattice" in scene, "main scene must bind the canonical lattice")
    require("ProvinceDistanceField" not in scene, "main scene must not retain the old per-province distance viewport")
    print(
        "Province edge lattice contract passed. "
        f"vertical={int(vertical.sum())} horizontal={int(horizontal.sum())}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
