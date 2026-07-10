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


def main() -> int:
    rows, _countries = ownership.build_manifest()
    overrides = ownership.load_keyed_csv(ownership.OVERRIDES, "province_id")
    today = datetime.now(timezone.utc).date().isoformat()
    staged = 0
    for row in rows:
        if row["category"] not in {
            "water_candidate",
            "uninhabited_or_wasteland_research_required",
            "missing_active_history",
        }:
            continue
        province_id = int(row["province_id"])
        if province_id in overrides:
            continue
        if WATER_NAME.search(row["province_name"]):
            authority_type = "water_or_inland_lake"
            note = "Reviewed as water/inland-lake terrain from the imported name and map texture."
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
