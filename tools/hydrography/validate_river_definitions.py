#!/usr/bin/env python3
"""Validate authored river vectors before they can enter the runtime map."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PATH = ROOT / "assets" / "river_definitions.json"
VALID_WIDTHS = {"major", "secondary", "minor"}
VALID_ZOOM_BANDS = {"strategic", "regional", "close"}
VALID_MOUTHS = {"ocean", "lake", "river"}
VALID_REVIEW = {"approved", "unresolved", "rejected"}
ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


def validate(data: dict, *, allow_empty: bool = False, allow_unapproved: bool = False) -> list[str]:
    errors: list[str] = []
    if data.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    if data.get("coordinate_space") != "map_pixels":
        errors.append("coordinate_space must be map_pixels")
    map_size = data.get("map_size")
    if not isinstance(map_size, list) or len(map_size) != 2 or any(not isinstance(value, int) or value <= 0 for value in map_size):
        errors.append("map_size must contain two positive integers")
        map_size = [5632, 2048]

    source = data.get("source")
    if not isinstance(source, dict):
        errors.append("source provenance object is required")
        source = {}
    for field in ("title", "uri", "license", "attribution", "review_status"):
        if not str(source.get(field, "")).strip():
            errors.append(f"source.{field} is required")
    review_status = str(source.get("review_status", ""))
    if review_status and review_status not in VALID_REVIEW:
        errors.append(f"source.review_status must be one of {sorted(VALID_REVIEW)}")
    if not allow_unapproved and review_status != "approved":
        errors.append("source.review_status must be approved for a production river asset")

    rivers = data.get("rivers")
    if not isinstance(rivers, list):
        errors.append("rivers must be an array")
        rivers = []
    if not rivers and not allow_empty:
        errors.append("a production river asset cannot be empty")

    ids: set[str] = set()
    river_records: dict[str, dict] = {}
    for index, raw_record in enumerate(rivers):
        prefix = f"rivers[{index}]"
        if not isinstance(raw_record, dict):
            errors.append(f"{prefix} must be an object")
            continue
        river_id = str(raw_record.get("id", ""))
        if not ID_PATTERN.fullmatch(river_id):
            errors.append(f"{prefix}.id must be stable lowercase snake_case")
        elif river_id in ids:
            errors.append(f"duplicate river id {river_id}")
        ids.add(river_id)
        river_records[river_id] = raw_record
        if not str(raw_record.get("name", "")).strip():
            errors.append(f"{prefix}.name is required")
        if raw_record.get("width_class") not in VALID_WIDTHS:
            errors.append(f"{prefix}.width_class must be one of {sorted(VALID_WIDTHS)}")
        if raw_record.get("minimum_zoom_band") not in VALID_ZOOM_BANDS:
            errors.append(f"{prefix}.minimum_zoom_band must be one of {sorted(VALID_ZOOM_BANDS)}")
        if not isinstance(raw_record.get("navigable"), bool):
            errors.append(f"{prefix}.navigable must be boolean")
        points = raw_record.get("points")
        if not isinstance(points, list) or len(points) < 2:
            errors.append(f"{prefix}.points must contain at least two map-pixel coordinates")
            continue
        previous: tuple[float, float] | None = None
        for point_index, point in enumerate(points):
            if not isinstance(point, list) or len(point) != 2 or any(not isinstance(value, (int, float)) for value in point):
                errors.append(f"{prefix}.points[{point_index}] must contain two numbers")
                continue
            coordinate = (float(point[0]), float(point[1]))
            if not (0.0 <= coordinate[0] < map_size[0] and 0.0 <= coordinate[1] < map_size[1]):
                errors.append(f"{prefix}.points[{point_index}] lies outside the map")
            if previous == coordinate:
                errors.append(f"{prefix}.points[{point_index}] duplicates the previous point")
            previous = coordinate
        mouth = raw_record.get("mouth")
        if not isinstance(mouth, dict) or mouth.get("type") not in VALID_MOUTHS:
            errors.append(f"{prefix}.mouth.type must be one of {sorted(VALID_MOUTHS)}")
        elif mouth.get("type") in {"lake", "river"} and mouth.get("target_id") in (None, ""):
            errors.append(f"{prefix}.mouth.target_id is required for lake/river mouths")

    for river_id, record in river_records.items():
        mouth = record.get("mouth", {})
        if mouth.get("type") == "river" and str(mouth.get("target_id")) not in ids:
            errors.append(f"river {river_id} drains into unknown river {mouth.get('target_id')}")
        if mouth.get("type") == "river" and str(mouth.get("target_id")) == river_id:
            errors.append(f"river {river_id} cannot drain into itself")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", type=Path, default=DEFAULT_PATH)
    parser.add_argument("--allow-empty", action="store_true", help="Allow a schema/tooling template with no rivers.")
    parser.add_argument("--allow-unapproved", action="store_true", help="Allow unresolved provenance during a non-shipping spike.")
    args = parser.parse_args()
    path = args.path.expanduser().resolve()
    if not path.is_file():
        print(f"River definition file is missing: {path}", file=sys.stderr)
        return 1
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"River definition parse failed: {error}", file=sys.stderr)
        return 1
    errors = validate(data, allow_empty=args.allow_empty, allow_unapproved=args.allow_unapproved)
    if errors:
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"River definitions are valid: {len(data.get('rivers', []))} rivers.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
