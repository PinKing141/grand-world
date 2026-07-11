#!/usr/bin/env python3
"""Bake deterministic Phase 4 economy definitions from province histories."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROVINCES = ROOT / "assets" / "provinces"
GRAPH = ROOT / "assets" / "province_graph.json"
OUTPUT = ROOT / "assets" / "economy_definitions.json"
REPORT = ROOT / "docs" / "data" / "economy_validation.md"

TRADE_GOOD_PRICES = {
    "unknown": 2000, "grain": 2000, "fish": 2200, "wool": 2200,
    "naval_supplies": 2500, "livestock": 2500, "salt": 3200,
    "wine": 3200, "iron": 3500, "copper": 3800, "cloth": 4000,
    "glass": 4200, "paper": 4200, "silk": 5000, "spices": 5200,
    "tea": 4500, "coffee": 4500, "sugar": 4500, "tobacco": 4500,
    "cotton": 3500, "dyes": 4000, "gems": 5500, "gold": 6000,
    "ivory": 4800, "chinaware": 4800, "cloves": 5500, "fur": 3500, "slaves": 2800,
    "incense": 3500, "cocoa": 4000, "tropical_wood": 3000,
}

BUILDINGS = {
    "tax_office": {
        "name": "Tax Office", "cost": 50000, "construction_days": 180,
        "tax_modifier_bp": 2000, "production_modifier_bp": 0,
        "manpower_modifier_bp": 0, "refund_bp": 5000,
    },
    "workshop": {
        "name": "Workshop", "cost": 60000, "construction_days": 240,
        "tax_modifier_bp": 0, "production_modifier_bp": 2000,
        "manpower_modifier_bp": 0, "refund_bp": 5000,
    },
    "barracks": {
        "name": "Barracks", "cost": 50000, "construction_days": 180,
        "tax_modifier_bp": 0, "production_modifier_bp": 0,
        "manpower_modifier_bp": 2500, "refund_bp": 5000,
    },
}

UNITS = {
    "infantry_regiment": {
        "name": "Infantry Regiment", "cost": 10000, "manpower_cost": 1000,
        "recruitment_days": 90, "monthly_maintenance": 500,
        "maximum_strength": 1000,
    }
}

TOP_LEVEL_VALUE = re.compile(r"^\s*([a-zA-Z0-9_]+)\s*=\s*([^#{}]+)")
DATED_BLOCK = re.compile(r"^\s*\d{3,4}\.\d{1,2}\.\d{1,2}\s*=")


def province_id(path: Path) -> int:
    match = re.match(r"(\d+)", path.name)
    return int(match.group(1)) if match else -1


def parse_history(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    text = path.read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines():
        if DATED_BLOCK.match(line):
            break
        match = TOP_LEVEL_VALUE.match(line)
        if not match:
            continue
        key, value = match.groups()
        values.setdefault(key, value.strip().strip('"'))
    return values


def as_nonnegative_int(value: str | None) -> int:
    try:
        return max(0, int(float(value or "0")))
    except ValueError:
        return 0


def main(check_only: bool = False) -> None:
    graph = json.loads(GRAPH.read_text(encoding="utf-8"))
    graph_provinces = graph["provinces"]
    histories = {}
    duplicate_ids = []
    for path in sorted(PROVINCES.glob("*.txt"), key=lambda p: (province_id(p), p.name)):
        pid = province_id(path)
        if pid <= 0:
            continue
        if pid in histories:
            duplicate_ids.append(pid)
            continue
        histories[pid] = parse_history(path)

    provinces = {}
    goods = Counter()
    missing_history = []
    unknown_goods = Counter()
    playable_count = 0
    for raw_id in sorted(graph_provinces, key=int):
        pid = int(raw_id)
        geography = graph_provinces[raw_id]
        history = histories.get(pid, {})
        classification = geography.get("classification", "impassable")
        owner = history.get("owner", "")
        playable = classification == "land" and bool(owner)
        if playable:
            playable_count += 1
        if not history:
            missing_history.append(pid)
        base_tax = as_nonnegative_int(history.get("base_tax")) if playable else 0
        base_production = as_nonnegative_int(history.get("base_production")) if playable else 0
        base_manpower = as_nonnegative_int(history.get("base_manpower")) if playable else 0
        trade_good = history.get("trade_goods", "unknown").lower() if playable else "unknown"
        if trade_good not in TRADE_GOOD_PRICES:
            unknown_goods[trade_good] += 1
            trade_good = "unknown"
        goods[trade_good] += 1
        development = base_tax + base_production + base_manpower
        provinces[str(pid)] = {
            "base_tax": base_tax,
            "base_production": base_production,
            "base_manpower": base_manpower,
            "development": development,
            "control_bp": 10000,
            "unrest_bp": 0,
            "devastation_bp": 0,
            "trade_good": trade_good,
            "terrain": geography.get("move_class", "plains"),
            "classification": classification,
            "coastal": bool(geography.get("coastal", False)),
            "center_of_trade": as_nonnegative_int(history.get("center_of_trade")),
            "building_slots": max(1, min(4, 1 + development // 10)) if playable else 0,
            "economic_eligible": playable,
        }

    payload = {
        "version": 1,
        "money_scale": 1000,
        "basis_points": 10000,
        "trade_goods": {
            key: {"name": key.replace("_", " ").title(), "base_price": value}
            for key, value in sorted(TRADE_GOOD_PRICES.items())
        },
        "buildings": {key: BUILDINGS[key] for key in sorted(BUILDINGS)},
        "units": {key: UNITS[key] for key in sorted(UNITS)},
        "provinces": provinces,
    }
    output_text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))

    total_tax = sum(p["base_tax"] for p in provinces.values())
    total_production = sum(p["base_production"] for p in provinces.values())
    total_manpower = sum(p["base_manpower"] for p in provinces.values())
    lines = [
        "# Phase 4 Economy Data Validation", "",
        f"- Graph provinces: **{len(provinces)}**",
        f"- Economically eligible provinces: **{playable_count}**",
        f"- Province histories found: **{len(histories)}**",
        f"- Missing history records: **{len(missing_history)}**",
        f"- Duplicate numeric history IDs: **{len(duplicate_ids)}**",
        f"- Unknown trade-good names mapped to `unknown`: **{sum(unknown_goods.values())}**",
        f"- Total base tax: **{total_tax}**",
        f"- Total base production: **{total_production}**",
        f"- Total base manpower: **{total_manpower}**", "",
        "## Trade-good counts", "",
    ]
    lines.extend(f"- `{good}`: {count}" for good, count in sorted(goods.items()))
    if unknown_goods:
        lines.extend(["", "## Unknown source trade goods", ""])
        lines.extend(f"- `{good}`: {count}" for good, count in sorted(unknown_goods.items()))
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
            raise SystemExit("Stale generated economy data: %s. Run the baker without --check." % ", ".join(stale))
        print("Economy definitions are current.")
        return
    OUTPUT.write_text(output_text, encoding="utf-8")
    REPORT.write_text(report_text, encoding="utf-8")
    print(f"Baked {len(provinces)} province economies to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if committed generated data differs from source inputs.")
    main(parser.parse_args().check)
