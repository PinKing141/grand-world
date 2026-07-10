#!/usr/bin/env python3
"""Validate representative terrain classes used by the final map shader."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "historical_ownership"))

import bake_political_textures as baker  # noqa: E402


def main() -> int:
    _definitions, max_id = baker.load_definitions()
    classes = baker.load_terrain_classes(max_id)
    expected = {
        1: baker.TERRAIN_OWNED_LAND,       # Stockholm
        481: baker.TERRAIN_UNOWNED_LAND,  # Bermuda in 1444
        1250: baker.TERRAIN_WATER,         # Vanern
        1252: baker.TERRAIN_WATER,         # Gulf of Bothnia
        1658: baker.TERRAIN_IMPASSABLE,    # Everglades land exception
        1779: baker.TERRAIN_IMPASSABLE,    # Rub' al Khali
        1994: baker.TERRAIN_UNOWNED_LAND,  # Wake
        2953: baker.TERRAIN_WATER,         # Hjalmaren
    }
    for province_id, expected_class in expected.items():
        actual_class = classes[province_id]
        if actual_class != expected_class:
            raise AssertionError(
                f"Province {province_id}: expected terrain class {expected_class}, got {actual_class}"
            )
    print("Terrain classification smoke test passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
