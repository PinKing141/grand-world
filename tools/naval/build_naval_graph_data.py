#!/usr/bin/env python3
"""Bake N1.1 naval maritime graph data: sea-zone classification and port candidates.

This is the data-audit stage of the naval roadmap (docs/roadmap/naval/01_N1_MARITIME_GRAPH_AUTHORITY.md,
work packet N1A). It does not add any runtime pathfinding, access, or fleet
logic - it only inventories the existing province_graph.json water/coastal
records into a versioned, overridable naval definitions file plus a
validation report, per docs/roadmap/naval/00_SCOPE_AND_ARCHITECTURE_LOCK.md:
water province IDs are sea-zone IDs, and ports use their land province ID -
naval never mints a second ID namespace.

Sea-zone classification (default heuristic, overridable):
  closed_water  water record not connected (via sea_neighbors) to the largest
                connected water component - i.e. an inland lake or otherwise
                non-navigable body. Never assigned from country ownership.
  coastal_sea   member of the main navigable component with at least one
                land neighbour (touches a coastline).
  open_ocean    member of the main navigable component with no land neighbour.
  inland_sea    authored-only; the default heuristic never assigns it.

Port candidates are every land province that is coastal, not impassable, and
has at least one sea neighbour - the baseline eligibility rule from N1's
"Port Derivation" section. All candidates get baseline placeholder capability
values; only the Channel/Iberian fixture region (tools/naval/port_overrides.csv)
carries a human-reviewed override in this pass.

Overrides (tools/naval/sea_zone_overrides.csv, tools/naval/port_overrides.csv):
  sea_zone_overrides.csv  province_id, classification, note, source, reviewer,
                          review_date, confidence
  port_overrides.csv      province_id, enabled, primary_exit, harbour_level,
                          shipyard, repair_capacity_bp, basing_capacity,
                          supply_range_bp, note, source, reviewer,
                          review_date, confidence
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GRAPH = ROOT / "assets" / "province_graph.json"
SEA_ZONE_OVERRIDES = Path(__file__).with_name("sea_zone_overrides.csv")
PORT_OVERRIDES = Path(__file__).with_name("port_overrides.csv")
OUTPUT = ROOT / "assets" / "naval_definitions.json"
REPORT = ROOT / "docs" / "data" / "naval_graph_validation.md"

VALID_CLASSIFICATIONS = ("coastal_sea", "inland_sea", "open_ocean", "closed_water")
CLOSED_WATER_CLASSIFICATION = "closed_water"


def content_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def load_graph() -> dict:
    return json.loads(GRAPH.read_text(encoding="utf-8"))


def water_connected_components(provinces: dict) -> tuple[dict[int, int], list[int]]:
    """Return {province_id: component_id} and component sizes indexed by component_id."""
    water_ids = [int(pid) for pid, record in provinces.items() if record.get("classification") == "water"]
    water_set = set(water_ids)
    component_of: dict[int, int] = {}
    sizes: list[int] = []
    for start in sorted(water_ids):
        if start in component_of:
            continue
        component_id = len(sizes)
        queue = deque([start])
        component_of[start] = component_id
        size = 0
        while queue:
            current = queue.popleft()
            size += 1
            neighbours = provinces[str(current)].get("sea_neighbors", {})
            for raw_neighbour in neighbours:
                neighbour = int(raw_neighbour)
                if neighbour in water_set and neighbour not in component_of:
                    component_of[neighbour] = component_id
                    queue.append(neighbour)
        sizes.append(size)
    return component_of, sizes


def classify_sea_zones(provinces: dict) -> dict[int, dict]:
    component_of, sizes = water_connected_components(provinces)
    main_component = max(range(len(sizes)), key=lambda i: sizes[i]) if sizes else -1
    zones: dict[int, dict] = {}
    for pid, record in provinces.items():
        if record.get("classification") != "water":
            continue
        province_id = int(pid)
        land_neighbour_count = len(record.get("land_neighbors", {}))
        sea_neighbour_count = len(record.get("sea_neighbors", {}))
        in_main_component = component_of.get(province_id) == main_component
        if not in_main_component:
            classification = "closed_water"
        elif land_neighbour_count > 0:
            classification = "coastal_sea"
        else:
            classification = "open_ocean"
        zones[province_id] = {
            "classification": classification,
            "default_classification": classification,
            "land_neighbor_count": land_neighbour_count,
            "sea_neighbor_count": sea_neighbour_count,
            "component_size": sizes[component_of[province_id]] if province_id in component_of else 0,
            "provenance": {"source": "derived", "confidence": "derived"},
        }
    return zones


def candidate_ports(provinces: dict, ownership: dict[int, str], zones: dict[int, dict]) -> dict[int, dict]:
    ports: dict[int, dict] = {}
    for pid, record in provinces.items():
        if record.get("classification") != "land" or not record.get("coastal", False):
            continue
        all_sea_neighbors = sorted(int(x) for x in record.get("sea_neighbors", {}))
        # A lake-shore province touching only closed_water is not a naval port:
        # closed water is excluded from ordinary fleets entirely (01_N1
        # "Sea-Zone Classification"). Filtering here, not just at the
        # MaritimeGraph runtime layer, keeps "port candidate" meaning "has at
        # least one real navigable exit" rather than merely "touches water."
        sea_exits = [zone_id for zone_id in all_sea_neighbors if zones.get(zone_id, {}).get("classification") != CLOSED_WATER_CLASSIFICATION]
        if not sea_exits:
            continue
        province_id = int(pid)
        ports[province_id] = {
            "enabled": True,
            "primary_exit": sea_exits[0],
            "sea_exits": sea_exits,
            "harbour_level": 0,
            "shipyard": False,
            "repair_capacity_bp": 0,
            "basing_capacity": 0,
            "supply_range_bp": 0,
            "owner_1444": ownership.get(province_id, ""),
            "provenance": {"source": "derived", "confidence": "candidate"},
        }
    return ports


def load_ownership() -> dict[int, str]:
    manifest = ROOT / "docs" / "data" / "1444_ownership_manifest.csv"
    ownership: dict[int, str] = {}
    if not manifest.exists():
        return ownership
    with manifest.open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            owner = row.get("dated_1444_owner") or row.get("current_owner") or ""
            if owner:
                ownership[int(row["province_id"])] = owner
    return ownership


def apply_sea_zone_overrides(zones: dict[int, dict], provinces: dict, issues: list[str], overrides_path: Path = SEA_ZONE_OVERRIDES) -> int:
    if not overrides_path.exists():
        return 0
    applied = 0
    with overrides_path.open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            province_id = int(row["province_id"])
            classification = row["classification"].strip()
            if province_id not in zones:
                issues.append(f"sea_zone_overrides.csv: {province_id} is not a water province - rejected.")
                continue
            if classification not in VALID_CLASSIFICATIONS:
                issues.append(f"sea_zone_overrides.csv: {province_id} has unknown classification '{classification}' - rejected.")
                continue
            zones[province_id]["classification"] = classification
            zones[province_id]["provenance"] = {
                "source": row.get("source", ""),
                "note": row.get("note", ""),
                "reviewer": row.get("reviewer", ""),
                "review_date": row.get("review_date", ""),
                "confidence": row.get("confidence", "reviewed"),
            }
            applied += 1
    return applied


def apply_port_overrides(ports: dict[int, dict], provinces: dict, issues: list[str], overrides_path: Path = PORT_OVERRIDES) -> int:
    if not overrides_path.exists():
        return 0
    applied = 0
    with overrides_path.open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            province_id = int(row["province_id"])
            if province_id not in ports:
                issues.append(f"port_overrides.csv: {province_id} is not a coastal-land port candidate - rejected.")
                continue
            port = ports[province_id]
            primary_exit = int(row["primary_exit"])
            if primary_exit not in port["sea_exits"]:
                issues.append(
                    f"port_overrides.csv: {province_id} primary_exit {primary_exit} is not one of its sea exits {port['sea_exits']} - rejected."
                )
                continue
            port["enabled"] = row["enabled"].strip().lower() == "true"
            port["primary_exit"] = primary_exit
            port["harbour_level"] = int(row["harbour_level"])
            port["shipyard"] = row["shipyard"].strip().lower() == "true"
            port["repair_capacity_bp"] = int(row["repair_capacity_bp"])
            port["basing_capacity"] = int(row["basing_capacity"])
            port["supply_range_bp"] = int(row["supply_range_bp"])
            port["provenance"] = {
                "source": row.get("source", ""),
                "note": row.get("note", ""),
                "reviewer": row.get("reviewer", ""),
                "review_date": row.get("review_date", ""),
                "confidence": row.get("confidence", "reviewed"),
            }
            applied += 1
    return applied


def check_reciprocity(provinces: dict) -> list[str]:
    """Verify sea_neighbors edges are reciprocal, accounting for the graph's
    asymmetric field convention: a water record's water-to-water neighbours
    live in its own sea_neighbors, but a land record's water exits are only
    reciprocated on the water side's land_neighbors, not its sea_neighbors."""
    issues: list[str] = []
    for pid, record in provinces.items():
        province_id = int(pid)
        is_water = record.get("classification") == "water"
        for raw_neighbour in record.get("sea_neighbors", {}):
            neighbour = int(raw_neighbour)
            neighbour_record = provinces.get(str(neighbour))
            if neighbour_record is None:
                issues.append(f"{province_id} has sea_neighbor {neighbour} which does not exist.")
                continue
            if is_water and neighbour_record.get("classification") == "water":
                reverse = neighbour_record.get("sea_neighbors", {})
                if str(province_id) not in reverse:
                    issues.append(f"Asymmetric water-water sea_neighbors: {province_id} -> {neighbour} has no reciprocal edge.")
            elif is_water and neighbour_record.get("classification") != "water":
                issues.append(f"Water province {province_id} lists non-water sea_neighbor {neighbour} (expected in land_neighbors).")
            else:
                # Land province's sea exit; reciprocal side is the water record's land_neighbors.
                if neighbour_record.get("classification") != "water":
                    issues.append(f"Land province {province_id} has non-water sea_neighbor {neighbour}.")
                    continue
                reverse = neighbour_record.get("land_neighbors", {})
                if str(province_id) not in reverse:
                    issues.append(f"Asymmetric land-water edge: land {province_id} exits to sea zone {neighbour}, but {neighbour}'s land_neighbors does not list {province_id}.")
    return issues


def main(check_only: bool) -> None:
    graph = load_graph()
    provinces: dict = graph["provinces"]
    graph_text = GRAPH.read_text(encoding="utf-8")
    graph_hash = content_hash(graph_text)

    ownership = load_ownership()
    zones = classify_sea_zones(provinces)
    ports = candidate_ports(provinces, ownership, zones)

    issues: list[str] = []
    sea_zone_overrides_applied = apply_sea_zone_overrides(zones, provinces, issues)
    port_overrides_applied = apply_port_overrides(ports, provinces, issues)
    reciprocity_issues = check_reciprocity(provinces)

    ports_without_exits = [pid for pid, record in provinces.items()
                            if record.get("classification") == "land" and record.get("coastal")
                            and not record.get("sea_neighbors")]
    lake_only_excluded = [pid for pid, record in provinces.items()
                           if record.get("classification") == "land" and record.get("coastal")
                           and record.get("sea_neighbors")
                           and all(zones.get(int(z), {}).get("classification") == CLOSED_WATER_CLASSIFICATION for z in record.get("sea_neighbors", {}))]

    payload = {
        "version": 1,
        "graph_content_hash": graph_hash,
        "sea_zones": {str(pid): zones[pid] for pid in sorted(zones)},
        "ports": {str(pid): ports[pid] for pid in sorted(ports)},
    }
    output_text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=False)

    classification_counts = Counter(zone["classification"] for zone in zones.values())
    default_vs_override = sum(1 for zone in zones.values() if zone["classification"] != zone["default_classification"])
    reviewed_ports = sum(1 for port in ports.values() if port["provenance"]["confidence"] != "candidate")

    lines = [
        "# N1.1 Naval Maritime Graph Data Validation", "",
        f"- Source graph content hash: **{graph_hash}**",
        f"- Total water records: **{sum(1 for r in provinces.values() if r.get('classification') == 'water')}**",
        f"- Total coastal land records: **{sum(1 for r in provinces.values() if r.get('coastal'))}**",
        f"- Sea zones classified: **{len(zones)}**",
        f"- Port candidates derived: **{len(ports)}**",
        f"- Ports with a human-reviewed override: **{reviewed_ports}**",
        f"- Sea-zone overrides applied: **{sea_zone_overrides_applied}**",
        f"- Port overrides applied: **{port_overrides_applied}**",
        f"- Sea zones reclassified away from their derived default: **{default_vs_override}**",
        f"- Ports without any sea exit (should be zero by construction): **{len(ports_without_exits)}**",
        f"- Coastal land excluded as port candidates (touches only closed_water/lake zones, no real naval exit): **{len(lake_only_excluded)}**",
        f"- Asymmetric sea-neighbour edges found: **{len(reciprocity_issues)}**",
        "",
        "## Sea-zone classification counts", "",
    ]
    lines.extend(f"- `{classification}`: {classification_counts.get(classification, 0)}" for classification in VALID_CLASSIFICATIONS)
    lines.extend(["", "## Rejected or malformed override rows", ""])
    if issues:
        lines.extend(f"- {issue}" for issue in issues)
    else:
        lines.append("- None.")
    lines.extend(["", "## Reciprocity issues", ""])
    if reciprocity_issues:
        lines.extend(f"- {issue}" for issue in reciprocity_issues[:50])
        if len(reciprocity_issues) > 50:
            lines.append(f"- ... and {len(reciprocity_issues) - 50} more.")
    else:
        lines.append("- None. Every sea-neighbour edge is reciprocal.")
    lines.extend(["", "## Channel/Iberian fixture ports (N0.3)", ""])
    fixture_ids = sorted(pid for pid in ports if ports[pid]["provenance"]["confidence"] != "candidate")
    for pid in fixture_ids:
        port = ports[pid]
        name = provinces[str(pid)].get("name", "")
        lines.append(f"- `{pid}` {name}: enabled={port['enabled']}, primary_exit={port['primary_exit']}, {port['provenance'].get('note', '')}")
    report_text = "\n".join(lines) + "\n"

    if check_only:
        output_matches = OUTPUT.exists() and OUTPUT.read_text(encoding="utf-8") == output_text
        report_matches = REPORT.exists() and REPORT.read_text(encoding="utf-8") == report_text
        if not output_matches or not report_matches:
            stale = []
            if not output_matches:
                stale.append(str(OUTPUT.relative_to(ROOT)))
            if not report_matches:
                stale.append(str(REPORT.relative_to(ROOT)))
            raise SystemExit("Stale generated naval data: %s. Run the baker without --check." % ", ".join(stale))
        print("Naval graph definitions are current.")
        return

    OUTPUT.write_text(output_text, encoding="utf-8")
    REPORT.write_text(report_text, encoding="utf-8")
    print(f"Baked {len(zones)} sea zones and {len(ports)} port candidates to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if committed generated data differs from source inputs.")
    main(parser.parse_args().check)
