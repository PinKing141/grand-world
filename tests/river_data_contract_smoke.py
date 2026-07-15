#!/usr/bin/env python3
"""Exercise the river ingestion contract without pretending source data exists."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/hydrography/validate_river_definitions.py"
SPEC = importlib.util.spec_from_file_location("river_validator", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def main() -> int:
    valid = {
        "schema_version": 1,
        "coordinate_space": "map_pixels",
        "map_size": [5632, 2048],
        "source": {
            "title": "Synthetic contract fixture",
            "uri": "test://river-fixture",
            "license": "test-only",
            "attribution": "Automated test",
            "review_status": "approved",
        },
        "rivers": [
            {
                "id": "fixture_major",
                "name": "Fixture Major River",
                "width_class": "major",
                "minimum_zoom_band": "strategic",
                "navigable": True,
                "points": [[100, 100], [120, 130], [150, 160]],
                "mouth": {"type": "ocean"},
            }
        ],
    }
    errors = MODULE.validate(valid)
    if errors:
        print(f"River data contract smoke failed: valid fixture rejected: {errors}", file=sys.stderr)
        return 1
    invalid = {**valid, "rivers": [{**valid["rivers"][0], "id": "Bad ID", "points": [[-1, 0], [-1, 0]], "mouth": {"type": "river", "target_id": "missing"}}]}
    errors = MODULE.validate(invalid)
    required_fragments = ("stable lowercase", "outside the map", "duplicates the previous", "unknown river")
    if any(not any(fragment in error for error in errors) for fragment in required_fragments):
        print(f"River data contract smoke failed: malformed fixture was not fully rejected: {errors}", file=sys.stderr)
        return 1
    print("River data contract smoke passed. production source remains intentionally unresolved.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
