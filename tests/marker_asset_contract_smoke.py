#!/usr/bin/env python3
"""Validate generated country shields, marker icons, provenance, and runtime bindings."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets" / "marker_art" / "generated" / "marker_asset_manifest.json"
SOURCE_MANIFEST = ROOT / "assets" / "marker_art" / "source_flags" / "source_manifest.json"
RESEARCH_REGISTER = ROOT / "docs" / "roadmap" / "map_visual_production" / "HISTORICAL_SHIELD_RESEARCH_REGISTER.md"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"Marker asset contract smoke failed: {message}")


def main() -> int:
    registry = json.loads((ROOT / "assets" / "country_registry.json").read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    sources = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))
    countries = manifest["countries"]
    require(set(countries) == set(registry["countries"]), "every registry country must own exactly one shield slot")
    indices = sorted(int(record["atlas_index"]) for record in countries.values())
    require(indices == list(range(len(countries))), "country shield atlas indices must be unique and contiguous")

    active: set[str] = set()
    with (ROOT / "docs" / "data" / "1444_ownership_manifest.csv").open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            if tag := (row.get("proposed_owner") or "").strip().upper():
                active.add(tag)
    require(int(manifest["active_1444_country_count"]) == len(active) == 703, "active 1444 coverage must remain complete")
    require(all(bool(countries[tag]["active_in_1444_manifest"]) for tag in active), "every starting owner must be marked active")
    require(int(manifest["sourced_historical_placeholder_count"]) == len(sources["sources"]) >= 30, "the initial openly licensed historical source pack must remain present")
    require(int(manifest["generated_fallback_count"]) == 0, "invented country-specific shields must not be generated")
    require(int(manifest["unassigned_research_required_count"]) == len(countries) - len(sources["sources"]), "every unsourced country must be explicitly queued for research")
    for tag, source in sources["sources"].items():
        path = ROOT / source["asset_path"].removeprefix("res://")
        require(path.is_file(), f"source image missing for {tag}")
        require(hashlib.sha256(path.read_bytes()).hexdigest() == source["sha256"], f"source image hash stale for {tag}")
        require(bool(source["description_url"]) and bool(source["license"]), f"source provenance incomplete for {tag}")
        require(countries[tag]["status"] == "sourced_open_historical_placeholder", f"sourced status missing for {tag}")
    for tag in ("ENG", "FRA", "CAS", "ARA", "POR", "SCO", "LIT", "HUN", "BYZ", "TIM"):
        require(tag in sources["sources"], f"priority historical identity missing for {tag}")

    shield_info = manifest["shield_atlas"]
    require(int(shield_info["tile_size"]) >= 128, "country shields must retain the high-resolution 128px-or-better tile contract")
    require(int(shield_info.get("render_supersample", 1)) >= 2, "country shields must be supersampled before atlas assembly")
    shield = Image.open(ROOT / shield_info["path"].removeprefix("res://"))
    require(shield.size == (int(shield_info["columns"]) * int(shield_info["tile_size"]), int(shield_info["rows"]) * int(shield_info["tile_size"])), "shield atlas dimensions must match metadata")
    tile_size = int(shield_info["tile_size"])
    columns = int(shield_info["columns"])
    for tag, record in countries.items():
        index = int(record["atlas_index"])
        left = (index % columns) * tile_size
        top = (index // columns) * tile_size
        alpha = shield.crop((left, top, left + tile_size, top + tile_size)).getchannel("A")
        if tag in sources["sources"]:
            require(alpha.getbbox() is not None, f"source-backed shield must contain visible pixels for {tag}")
        else:
            require(record["status"] == "unassigned_requires_historical_research", f"unsourced status must require research for {tag}")
            require(alpha.getbbox() is None, f"unsourced atlas slot must remain transparent for {tag}")
    register_text = RESEARCH_REGISTER.read_text(encoding="utf-8")
    require("Source-backed shield identities: **39**" in register_text, "research register must report the current sourced count")
    require("Active 1444 countries still requiring research: **664**" in register_text, "research register must expose the complete active research queue")
    icon_info = manifest["icon_atlas"]
    icons = Image.open(ROOT / icon_info["path"].removeprefix("res://"))
    require(icons.size == (int(icon_info["columns"]) * int(icon_info["tile_size"]), int(icon_info["rows"]) * int(icon_info["tile_size"])), "icon atlas dimensions must match metadata")
    require(set(manifest["icons"]) == {"army", "navy", "battle", "siege", "capital", "fort", "port", "cluster", "destination", "invalid"}, "complete marker family must remain generated")

    army_script = (ROOT / "scripts" / "ui" / "army_layer.gd").read_text(encoding="utf-8")
    conflict_script = (ROOT / "scripts" / "ui" / "conflict_marker_layer.gd").read_text(encoding="utf-8")
    require("army_flag_marker.gdshader" in army_script and "set_instance_custom_data" in army_script, "army runtime must bind country shield atlas slots")
    require("cartographic_marker_icon.gdshader" in conflict_script and "set_instance_custom_data" in conflict_script, "conflict runtime must bind icon art and cluster counts")
    print(f"Marker asset contract smoke passed. countries={len(countries)} active={len(active)} sourced={len(sources['sources'])} icons={len(manifest['icons'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
