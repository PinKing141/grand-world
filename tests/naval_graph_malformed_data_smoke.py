#!/usr/bin/env python3
"""N1.4 malformed-data coverage for the naval maritime graph baker.

Exercises tools/naval/build_naval_graph_data.py's override-rejection paths
directly against synthetic CSVs, so a malformed sea-zone or port override row
is provably rejected with a reason and never mutates the baked data - rather
than only trusting that the checked-in override CSVs happen to be clean.
"""

from __future__ import annotations

import csv
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "naval"))

import build_naval_graph_data as builder  # noqa: E402


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"Naval graph malformed data smoke failed: {message}")


def write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main() -> int:
    graph = builder.load_graph()
    provinces: dict = graph["provinces"]
    zones = builder.classify_sea_zones(provinces)
    ports = builder.candidate_ports(provinces, {}, zones)

    # A real water ID (Straits of Dover) and a real coastal-land ID (Calais)
    # to prove the rejection is about the row content, not a missing fixture.
    dover_id = 1271
    calais_id = 87
    require(dover_id in zones, "fixture assumption: 1271 must be a water province")
    require(calais_id in ports, "fixture assumption: 87 must be a port candidate")
    original_dover_classification = zones[dover_id]["classification"]
    original_calais_primary_exit = ports[calais_id]["primary_exit"]

    with tempfile.TemporaryDirectory(prefix="naval-malformed-smoke-") as raw_temp:
        temp_dir = Path(raw_temp)

        sea_zone_rows = [
            {"province_id": "99999999", "classification": "coastal_sea", "note": "unknown province", "source": "", "reviewer": "", "review_date": "", "confidence": ""},
            {"province_id": str(calais_id), "classification": "coastal_sea", "note": "land province used as a sea zone", "source": "", "reviewer": "", "review_date": "", "confidence": ""},
            {"province_id": str(dover_id), "classification": "lava_sea", "note": "invalid classification enum", "source": "", "reviewer": "", "review_date": "", "confidence": ""},
        ]
        sea_zone_path = temp_dir / "sea_zone_overrides.csv"
        write_csv(sea_zone_path, ["province_id", "classification", "note", "source", "reviewer", "review_date", "confidence"], sea_zone_rows)

        port_rows = [
            {"province_id": "99999999", "enabled": "true", "primary_exit": "1271", "harbour_level": "1", "shipyard": "false", "repair_capacity_bp": "10000", "basing_capacity": "1", "supply_range_bp": "10000", "note": "unknown province", "source": "", "reviewer": "", "review_date": "", "confidence": ""},
            {"province_id": str(dover_id), "enabled": "true", "primary_exit": "1271", "harbour_level": "1", "shipyard": "false", "repair_capacity_bp": "10000", "basing_capacity": "1", "supply_range_bp": "10000", "note": "water province used as a port", "source": "", "reviewer": "", "review_date": "", "confidence": ""},
            {"province_id": str(calais_id), "enabled": "true", "primary_exit": "4999999", "harbour_level": "1", "shipyard": "false", "repair_capacity_bp": "10000", "basing_capacity": "1", "supply_range_bp": "10000", "note": "primary_exit not among this port's own sea exits", "source": "", "reviewer": "", "review_date": "", "confidence": ""},
        ]
        port_path = temp_dir / "port_overrides.csv"
        write_csv(port_path, ["province_id", "enabled", "primary_exit", "harbour_level", "shipyard", "repair_capacity_bp", "basing_capacity", "supply_range_bp", "note", "source", "reviewer", "review_date", "confidence"], port_rows)

        sea_zone_issues: list[str] = []
        applied_zones = builder.apply_sea_zone_overrides(zones, provinces, sea_zone_issues, overrides_path=sea_zone_path)
        require(applied_zones == 0, f"every malformed sea-zone override row must be rejected, not applied (applied={applied_zones})")
        require(len(sea_zone_issues) == len(sea_zone_rows), f"every malformed sea-zone row must produce exactly one issue (got {len(sea_zone_issues)} for {len(sea_zone_rows)} rows)")
        require(any("99999999" in issue and "not a water province" in issue for issue in sea_zone_issues), "an unknown province override must be rejected with a specific reason")
        require(any(str(calais_id) in issue and "not a water province" in issue for issue in sea_zone_issues), "a land province used as a sea-zone override must be rejected")
        require(any(str(dover_id) in issue and "unknown classification" in issue for issue in sea_zone_issues), "an invalid classification enum must be rejected")
        require(zones[dover_id]["classification"] == original_dover_classification, "a rejected override must never mutate the baked classification")

        port_issues: list[str] = []
        applied_ports = builder.apply_port_overrides(ports, provinces, port_issues, overrides_path=port_path)
        require(applied_ports == 0, f"every malformed port override row must be rejected, not applied (applied={applied_ports})")
        require(len(port_issues) == len(port_rows), f"every malformed port row must produce exactly one issue (got {len(port_issues)} for {len(port_rows)} rows)")
        require(any("99999999" in issue and "not a coastal-land port candidate" in issue for issue in port_issues), "an unknown province port override must be rejected")
        require(any(str(dover_id) in issue and "not a coastal-land port candidate" in issue for issue in port_issues), "a water province used as a port override must be rejected")
        require(any(str(calais_id) in issue and "is not one of its sea exits" in issue for issue in port_issues), "a primary_exit outside the port's own sea exits must be rejected")
        require(ports[calais_id]["primary_exit"] == original_calais_primary_exit, "a rejected override must never mutate the baked primary_exit")

    print(f"Naval graph malformed data smoke passed. sea_zone_issues={len(sea_zone_issues)} port_issues={len(port_issues)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
