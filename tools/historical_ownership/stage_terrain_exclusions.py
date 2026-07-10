#!/usr/bin/env python3
"""Document water, impassable wasteland, and missing terrain definitions as non-country."""

from __future__ import annotations

import re
from datetime import datetime, timezone

import build_manifest as ownership


WATER_NAME = re.compile(
    r"(?:sea|ocean|gulf|lake|strait|channel|bay|bight|coast|basin|lagoon|reef|bank|sound|hav|approach|delta|archipelago|shelf|trench|current|gap|river|firth|chott)",
    re.IGNORECASE,
)

# The imported province set retains the classic contiguous sea-zone block.
# Two later map revisions reuse IDs in that range for land and must not be
# folded into the water class.
SEA_ZONE_ID_RANGE = range(1250, 1742)
SEA_ZONE_LAND_EXCEPTIONS = {1306, 1658}  # Sao Tome, Everglades
KNOWN_INLAND_WATER_IDS = {
    1886, 1887, 1890, 1891, 1897,
    1904, 1905, 1906, 1907, 1908, 1909, 1910,
    1977, 2953,
    4132, 4133, 4134, 4136, 4137, 4138, 4139, 4140,
}


def is_water_definition(province_id: int, province_name: str) -> bool:
    if province_id in SEA_ZONE_ID_RANGE and province_id not in SEA_ZONE_LAND_EXCEPTIONS:
        return True
    if province_id in KNOWN_INLAND_WATER_IDS:
        return True
    return WATER_NAME.search(province_name) is not None


def main() -> int:
    rows, _countries = ownership.build_manifest()
    overrides = ownership.load_keyed_csv(ownership.OVERRIDES, "province_id")
    today = datetime.now(timezone.utc).date().isoformat()
    staged = 0
    for row in rows:
        province_id = int(row["province_id"])
        existing_override = overrides.get(province_id)
        owns_existing_override = (
            existing_override is not None
            and existing_override.get("reviewer") == "Codex terrain-exclusion pass"
        )
        if row["category"] not in {
            "water_candidate",
            "uninhabited_or_wasteland_research_required",
            "missing_active_history",
        } and not owns_existing_override:
            continue
        if existing_override is not None and not owns_existing_override:
            continue
        if is_water_definition(province_id, row["province_name"]):
            authority_type = "water_or_inland_lake"
            note = "Reviewed as water/inland-lake terrain from the imported sea-zone block, name, and map texture."
            confidence = "high"
        else:
            authority_type = "impassable_or_non_playable_terrain"
            note = (
                "Retained as non-country terrain because the imported history has no owner, culture, religion, or population signal. "
                "This is a gameplay exclusion and does not claim the geographic area was literally uninhabited."
            )
            confidence = "medium"
        if row["category"] == "missing_active_history":
            note = (
                "Active definition has no history file and represents the Central Africa wasteland block. "
                "Retained as non-country terrain until that block is replaced with playable provinces."
            )
        overrides[province_id] = {
            "province_id": str(province_id),
            "assigned_tag": "",
            "status": "excluded",
            "confidence": confidence,
            "authority_type": authority_type,
            "source_url": "",
            "source_note": note,
            "reviewer": "Codex terrain-exclusion pass",
            "review_date": today,
        }
        staged += 1
    ownership.write_overrides([overrides[key] for key in sorted(overrides)])
    print(f"Documented {staged} water/wasteland definitions as non-country terrain.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
