#!/usr/bin/env python3
"""Rank 1444 neighbouring-country colour risks and propose review candidates."""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

from build_country_registry import (
    MANIFEST,
    MIN_NEIGHBOUR_OKLAB_DISTANCE,
    PROVINCE_GRAPH,
    ROOT,
    _linear_srgb,
    _oklab,
    _oklab_distance,
    build_registry,
)

JSON_OUTPUT = ROOT / "docs" / "data" / "1444_neighbour_colour_analysis.json"
MARKDOWN_OUTPUT = ROOT / "docs" / "roadmap" / "map_visual_production" / "MV1_NEIGHBOUR_COLOUR_REPORT.md"
TARGET_NORMAL_DISTANCE = 0.075
TARGET_SIMULATED_DISTANCE = 0.035

# Linear-RGB deficiency approximations are an automated warning aid, not a
# substitute for the hands-on review explicitly retained in the roadmap.
SIMULATION_MATRICES: dict[str, tuple[tuple[float, float, float], ...]] = {
    "protanopia": (
        (0.152286, 1.052583, -0.204868),
        (0.114503, 0.786281, 0.099216),
        (-0.003882, -0.048116, 1.051998),
    ),
    "deuteranopia": (
        (0.367322, 0.860646, -0.227968),
        (0.280085, 0.672501, 0.047413),
        (-0.011820, 0.042940, 0.968881),
    ),
    "tritanopia": (
        (1.255528, -0.076749, -0.178779),
        (-0.078411, 0.930809, 0.147602),
        (0.004733, 0.691367, 0.303900),
    ),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if either generated report is stale.")
    return parser.parse_args()


def _srgb_component(linear: float) -> int:
    linear = max(0.0, min(1.0, linear))
    value = linear * 12.92 if linear <= 0.0031308 else 1.055 * linear ** (1.0 / 2.4) - 0.055
    return round(max(0.0, min(1.0, value)) * 255.0)


def simulate_colour(rgb: list[int], matrix: tuple[tuple[float, float, float], ...]) -> list[int]:
    linear = tuple(_linear_srgb(component) for component in rgb)
    transformed = tuple(sum(row[index] * linear[index] for index in range(3)) for row in matrix)
    return [_srgb_component(component) for component in transformed]


def load_owners() -> dict[int, str]:
    owners: dict[int, str] = {}
    with MANIFEST.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            owner = (row.get("proposed_owner") or "").strip().upper()
            if owner:
                owners[int(row["province_id"])] = owner
    return owners


def adjacency_contacts(owners: dict[int, str]) -> dict[tuple[str, str], dict[str, int]]:
    graph = json.loads(PROVINCE_GRAPH.read_text(encoding="utf-8"))
    contacts: dict[tuple[str, str], dict[str, int]] = defaultdict(lambda: {"province_contacts": 0, "shared_border_pixels": 0})
    for raw_province_id, province in graph.get("provinces", {}).items():
        province_id = int(raw_province_id)
        owner = owners.get(province_id, "")
        if not owner:
            continue
        for raw_neighbour_id, raw_border_pixels in province.get("land_neighbors", {}).items():
            neighbour_id = int(raw_neighbour_id)
            if province_id >= neighbour_id:
                continue
            neighbour_owner = owners.get(neighbour_id, "")
            if not neighbour_owner or neighbour_owner == owner:
                continue
            pair = tuple(sorted((owner, neighbour_owner)))
            contacts[pair]["province_contacts"] += 1
            contacts[pair]["shared_border_pixels"] += max(0, int(raw_border_pixels))
    return dict(contacts)


def severity(normal: float, simulated: float) -> str:
    if normal < MIN_NEIGHBOUR_OKLAB_DISTANCE:
        return "blocker"
    if normal < 0.055 or simulated < 0.025:
        return "high"
    if normal < 0.075 or simulated < 0.045:
        return "medium"
    if normal < 0.100 or simulated < 0.065:
        return "low"
    return "pass"


def candidate_colours(current: list[int]) -> list[list[int]]:
    offsets = (-96, -64, -40, -24, 0, 24, 40, 64, 96)
    candidates = {
        tuple(max(16, min(239, current[channel] + offset)) for channel, offset in enumerate((red, green, blue)))
        for red in offsets
        for green in offsets
        for blue in offsets
    }
    candidates.discard(tuple(current))
    return [list(candidate) for candidate in sorted(candidates)]


def lab_distance(first: tuple[float, float, float], second: tuple[float, float, float]) -> float:
    return math.sqrt(sum((left - right) ** 2 for left, right in zip(first, second)))


def propose_colour(
    tag: str,
    colours: dict[str, list[int]],
    neighbours: dict[str, set[str]],
    normal_labs: dict[str, tuple[float, float, float]],
    simulated_labs: dict[str, dict[str, tuple[float, float, float]]],
) -> dict[str, Any] | None:
    current = colours[tag]
    neighbour_tags = sorted(neighbours[tag])
    best: tuple[float, list[int], float, float] | None = None
    for candidate in candidate_colours(current):
        candidate_lab = _oklab(candidate)
        normal_min = min(lab_distance(candidate_lab, normal_labs[other]) for other in neighbour_tags)
        if normal_min < TARGET_NORMAL_DISTANCE:
            continue
        candidate_simulated = {
            profile: _oklab(simulate_colour(candidate, matrix))
            for profile, matrix in SIMULATION_MATRICES.items()
        }
        simulated_min = min(lab_distance(candidate_simulated[profile], simulated_labs[profile][other]) for other in neighbour_tags for profile in SIMULATION_MATRICES)
        if simulated_min < TARGET_SIMULATED_DISTANCE:
            continue
        change = _oklab_distance(candidate, current)
        score = change - normal_min * 0.08 - simulated_min * 0.04
        if best is None or score < best[0]:
            best = (score, candidate, normal_min, simulated_min)
    if best is None:
        return None
    return {
        "country": tag,
        "current_rgb8": current,
        "suggested_rgb8": best[1],
        "oklab_change": round(_oklab_distance(current, best[1]), 6),
        "minimum_normal_distance_after": round(best[2], 6),
        "minimum_simulated_distance_after": round(best[3], 6),
        "status": "advisory_only_review_in_context",
    }


def build_analysis() -> dict[str, Any]:
    registry = build_registry()
    records: dict[str, dict[str, Any]] = registry["countries"]
    colours = {tag: [int(value) for value in record["colour_rgb8"]] for tag, record in records.items()}
    normal_labs = {tag: _oklab(colour) for tag, colour in colours.items()}
    simulated_labs = {
        profile: {tag: _oklab(simulate_colour(colour, matrix)) for tag, colour in colours.items()}
        for profile, matrix in SIMULATION_MATRICES.items()
    }
    contacts = adjacency_contacts(load_owners())
    neighbours: dict[str, set[str]] = defaultdict(set)
    risks: list[dict[str, Any]] = []
    for (first, second), contact in sorted(contacts.items()):
        if first not in colours or second not in colours:
            continue
        neighbours[first].add(second)
        neighbours[second].add(first)
        normal = _oklab_distance(colours[first], colours[second])
        profile_distances = {
            profile: _oklab_distance(simulate_colour(colours[first], matrix), simulate_colour(colours[second], matrix))
            for profile, matrix in SIMULATION_MATRICES.items()
        }
        minimum_profile = min(profile_distances, key=profile_distances.get)
        minimum_simulated = profile_distances[minimum_profile]
        risks.append({
            "first": first,
            "first_name": records[first]["display_name"],
            "first_rgb8": colours[first],
            "second": second,
            "second_name": records[second]["display_name"],
            "second_rgb8": colours[second],
            "normal_oklab_distance": round(normal, 6),
            "simulated_oklab_distances": {key: round(value, 6) for key, value in sorted(profile_distances.items())},
            "minimum_simulated_profile": minimum_profile,
            "minimum_simulated_distance": round(minimum_simulated, 6),
            "severity": severity(normal, minimum_simulated),
            **contact,
        })
    severity_order = {"blocker": 0, "high": 1, "medium": 2, "low": 3, "pass": 4}
    risks.sort(key=lambda item: (severity_order[item["severity"]], item["normal_oklab_distance"], -item["shared_border_pixels"], item["first"], item["second"]))
    risky_countries = sorted({item[key] for item in risks if item["severity"] in {"blocker", "high", "medium"} for key in ("first", "second")})
    suggestions = [
        proposal
        for tag in risky_countries
        if (proposal := propose_colour(tag, colours, neighbours, normal_labs, simulated_labs)) is not None
    ]
    counts = {label: sum(item["severity"] == label for item in risks) for label in severity_order}
    return {
        "schema_version": 1,
        "metadata": {
            "generator": "tools/country_registry/analyse_neighbour_colours.py",
            "scenario": "11 November 1444",
            "colour_space": "Oklab",
            "normal_blocking_threshold": MIN_NEIGHBOUR_OKLAB_DISTANCE,
            "candidate_normal_target": TARGET_NORMAL_DISTANCE,
            "candidate_simulated_target": TARGET_SIMULATED_DISTANCE,
            "pair_count": len(risks),
            "severity_counts": counts,
            "warning": "Colour-vision simulation is a heuristic screening aid; hands-on review remains required.",
        },
        "risks": risks,
        "suggestions": suggestions,
    }


def markdown(analysis: dict[str, Any]) -> str:
    metadata = analysis["metadata"]
    counts = metadata["severity_counts"]
    lines = [
        "# MV1 Neighbour-Colour Production Report",
        "",
        "This deterministic report ranks every pair of countries sharing a land adjacency in the 11 November 1444 scenario. It measures the authored political colours in Oklab and screens them through protanopia, deuteranopia, and tritanopia approximations.",
        "",
        f"- Pairs checked: **{metadata['pair_count']}**",
        f"- Blockers: **{counts['blocker']}** · high: **{counts['high']}** · medium: **{counts['medium']}** · low: **{counts['low']}** · pass: **{counts['pass']}**",
        f"- Hard normal-vision threshold: **{metadata['normal_blocking_threshold']:.3f} Oklab**",
        "- Generated replacement colours are advisory and must be reviewed with realm identity, map modes, labels, borders, subjects, and historical associations visible.",
        "- Simulations are screening aids, not evidence that the hands-on accessibility gate has passed.",
        "",
        "## Highest-priority neighbour pairs",
        "",
        "| Priority | Countries | Normal | Worst simulation | Shared border px | Province contacts |",
        "|---|---|---:|---:|---:|---:|",
    ]
    for item in analysis["risks"][:100]:
        lines.append(
            f"| {item['severity'].upper()} | {item['first_name']} ({item['first']}) / {item['second_name']} ({item['second']}) | "
            f"{item['normal_oklab_distance']:.4f} | {item['minimum_simulated_profile']} {item['minimum_simulated_distance']:.4f} | "
            f"{item['shared_border_pixels']} | {item['province_contacts']} |"
        )
    lines.extend([
        "",
        "## Advisory country-colour candidates",
        "",
        "These are one-country-at-a-time starting points. Applying several suggestions together requires regenerating this report because simultaneous changes alter the neighbour constraints.",
        "",
        "| Country | Current RGB | Candidate RGB | Oklab change | New normal minimum | New simulated minimum |",
        "|---|---:|---:|---:|---:|---:|",
    ])
    for item in analysis["suggestions"]:
        lines.append(
            f"| {item['country']} | {','.join(map(str, item['current_rgb8']))} | {','.join(map(str, item['suggested_rgb8']))} | "
            f"{item['oklab_change']:.4f} | {item['minimum_normal_distance_after']:.4f} | {item['minimum_simulated_distance_after']:.4f} |"
        )
    lines.extend([
        "",
        "## Art-review workflow",
        "",
        "1. Start with blocker and high pairs that also have long shared borders.",
        "2. Test only one proposed country colour at a time and regenerate both the registry and this report.",
        "3. Capture political, diplomatic, war, subject-realm, occupation, and selected/hovered states at strategic and regional zoom.",
        "4. Reject candidates that damage national identity or collide with reserved semantic colours even if their numerical distance improves.",
        "5. Complete the final decision with colour-vision-deficient players; automated simulation cannot close that gate.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    analysis = build_analysis()
    expected_json = json.dumps(analysis, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    expected_markdown = markdown(analysis)
    if args.check:
        stale = []
        if not JSON_OUTPUT.is_file() or JSON_OUTPUT.read_text(encoding="utf-8") != expected_json:
            stale.append(str(JSON_OUTPUT.relative_to(ROOT)))
        if not MARKDOWN_OUTPUT.is_file() or MARKDOWN_OUTPUT.read_text(encoding="utf-8") != expected_markdown:
            stale.append(str(MARKDOWN_OUTPUT.relative_to(ROOT)))
        if stale:
            print("Neighbour-colour analysis is stale: " + ", ".join(stale), file=sys.stderr)
            return 1
        print(f"Neighbour-colour analysis is valid and current. pairs={analysis['metadata']['pair_count']} suggestions={len(analysis['suggestions'])}")
        return 0
    JSON_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    MARKDOWN_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    JSON_OUTPUT.write_text(expected_json, encoding="utf-8")
    MARKDOWN_OUTPUT.write_text(expected_markdown, encoding="utf-8")
    print(f"Wrote neighbour-colour analysis. pairs={analysis['metadata']['pair_count']} suggestions={len(analysis['suggestions'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
