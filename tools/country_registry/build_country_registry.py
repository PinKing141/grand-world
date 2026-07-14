#!/usr/bin/env python3
"""Build and validate the canonical Grand World country registry."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
COUNTRIES = ROOT / "assets" / "countries"
COUNTRY_COLORS = ROOT / "assets" / "country_colors"
MANIFEST = ROOT / "docs" / "data" / "1444_ownership_manifest.csv"
PROVINCE_GRAPH = ROOT / "assets" / "province_graph.json"
OUTPUT = ROOT / "assets" / "country_registry.json"

SCHEMA_VERSION = 1
COUNTRY_FILE_PATTERN = re.compile(r"^(?P<tag>[A-Z0-9]{3}) - (?P<name>\S(?:.*\S)?)\.txt$")
COLOR_PATTERN = re.compile(
    r"(?m)^\s*color\s*=\s*\{\s*(?P<red>\d+)\s+(?P<green>\d+)\s+(?P<blue>\d+)\s*\}"
)
OWNER_FIELDS = ("current_owner", "tribal_owner", "dated_1444_owner", "proposed_owner")
MIN_NEIGHBOUR_OKLAB_DISTANCE = 0.04

APPROVED_NAME_COLLISIONS: dict[str, dict[str, Any]] = {}

PSEUDO_COUNTRIES: dict[str, dict[str, Any]] = {
    "No Owner": {
        "display_name": "No Owner",
        "name_key": "country.no_owner.name",
        "adjective_key": "country.no_owner.adjective",
        "adjective": "Unowned",
        "colour_rgba": [0.7, 0.5, 0.1, 1.0],
        "scenario_country": False,
        "selectable": False,
    },
    "Ocean": {
        "display_name": "Ocean",
        "name_key": "country.ocean.name",
        "adjective_key": "country.ocean.adjective",
        "adjective": "Oceanic",
        "colour_rgba": [0.1, 0.4, 0.7, 1.0],
        "scenario_country": False,
        "selectable": False,
    },
}


class RegistryError(RuntimeError):
    """Raised when source country data cannot produce a safe registry."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate all sources and fail if assets/country_registry.json is stale.",
    )
    return parser.parse_args()


def resource_path(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_colour(path: Path) -> list[int]:
    text = path.read_bytes().decode("utf-8", errors="replace")
    match = COLOR_PATTERN.search(text)
    if not match:
        raise RegistryError(f"Missing RGB colour declaration in {path.relative_to(ROOT)}")
    colour = [int(match.group(channel)) for channel in ("red", "green", "blue")]
    if any(component < 0 or component > 255 for component in colour):
        raise RegistryError(f"RGB colour outside 0..255 in {path.relative_to(ROOT)}: {colour}")
    return colour


def load_country_sources() -> dict[str, dict[str, Any]]:
    issues: list[str] = []
    by_tag: dict[str, list[Path]] = defaultdict(list)
    parsed: dict[str, tuple[str, Path]] = {}

    for path in sorted(COUNTRIES.glob("*.txt"), key=lambda item: item.name.casefold()):
        match = COUNTRY_FILE_PATTERN.fullmatch(path.name)
        if not match:
            issues.append(
                f"Malformed country filename `{path.name}`; expected exact `TAG - Name.txt`."
            )
            continue
        tag = match.group("tag")
        name = match.group("name")
        by_tag[tag].append(path)
        parsed[tag] = (name, path)

    for tag, paths in sorted(by_tag.items()):
        if len(paths) > 1:
            rendered = ", ".join(path.name for path in paths)
            issues.append(f"Duplicate country tag `{tag}`: {rendered}")

    if issues:
        raise RegistryError("\n".join(issues))

    colour_paths: dict[str, list[Path]] = defaultdict(list)
    for path in sorted(COUNTRY_COLORS.glob("*.txt"), key=lambda item: item.name.casefold()):
        if path.stem != path.stem.strip() or not path.stem:
            issues.append(f"Malformed country-colour filename `{path.name}`.")
            continue
        colour_paths[path.stem.casefold()].append(path)

    records: dict[str, dict[str, Any]] = {}
    for tag in sorted(parsed):
        name, country_path = parsed[tag]
        matches = colour_paths.get(name.casefold(), [])
        if len(matches) != 1:
            rendered = ", ".join(path.name for path in matches) if matches else "none"
            issues.append(
                f"Country `{tag}` ({name}) requires exactly one matching colour file; found {rendered}."
            )
            continue
        colour_path = matches[0]
        colour_rgb8 = parse_colour(colour_path)
        name_key = f"country.{tag}.name"
        adjective_key = f"country.{tag}.adjective"
        records[tag] = {
            "display_name": name,
            "name_key": name_key,
            "adjective_key": adjective_key,
            "adjective": name,
            "adjective_review_status": "generated_fallback_needs_review",
            "country_history_path": resource_path(country_path),
            "country_history_sha256": sha256(country_path),
            "colour_path": resource_path(colour_path),
            "colour_sha256": sha256(colour_path),
            "colour_rgb8": colour_rgb8,
            "scenario_country": True,
            "selectable": True,
        }

    if issues:
        raise RegistryError("\n".join(issues))
    return records


def load_manifest(records: dict[str, dict[str, Any]]) -> tuple[int, set[str]]:
    issues: list[str] = []
    owners: set[str] = set()
    row_count = 0
    with MANIFEST.open("r", encoding="utf-8-sig", newline="") as handle:
        for row_count, row in enumerate(csv.DictReader(handle), start=1):
            for field in OWNER_FIELDS:
                tag = (row.get(field) or "").strip().upper()
                if not tag:
                    continue
                owners.add(tag)
                if tag not in records:
                    issues.append(
                        f"Manifest row {row_count} field `{field}` references unknown country `{tag}`."
                    )
            proposed_owner = (row.get("proposed_owner") or "").strip().upper()
            manifest_name = (row.get("country_name") or "").strip()
            if proposed_owner in records and manifest_name:
                expected = str(records[proposed_owner]["display_name"])
                if manifest_name != expected:
                    issues.append(
                        f"Manifest row {row_count} names `{proposed_owner}` as `{manifest_name}`; "
                        f"registry source says `{expected}`."
                    )

    if issues:
        preview = issues[:100]
        if len(issues) > len(preview):
            preview.append(f"... and {len(issues) - len(preview)} more manifest errors.")
        raise RegistryError("\n".join(preview))
    return row_count, owners


def validate_name_collisions(records: dict[str, dict[str, Any]]) -> None:
    tags_by_name: dict[str, list[str]] = defaultdict(list)
    for tag, record in records.items():
        tags_by_name[str(record["display_name"])].append(tag)
    actual = {
        name: sorted(tags)
        for name, tags in tags_by_name.items()
        if len(tags) > 1
    }
    approved = {
        name: sorted(str(tag) for tag in definition["tags"])
        for name, definition in APPROVED_NAME_COLLISIONS.items()
    }
    if actual != approved:
        raise RegistryError(
            "Unapproved or stale display-name collision exceptions. "
            f"Actual={actual}; approved={approved}"
        )


def _linear_srgb(component: int) -> float:
    value = component / 255.0
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def _oklab(rgb: list[int]) -> tuple[float, float, float]:
    red, green, blue = (_linear_srgb(component) for component in rgb)
    light = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
    medium = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
    short = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
    light, medium, short = (value ** (1.0 / 3.0) for value in (light, medium, short))
    return (
        0.2104542553 * light + 0.7936177850 * medium - 0.0040720468 * short,
        1.9779984951 * light - 2.4285922050 * medium + 0.4505937099 * short,
        0.0259040371 * light + 0.7827717662 * medium - 0.8086757660 * short,
    )


def _oklab_distance(first: list[int], second: list[int]) -> float:
    first_lab = _oklab(first)
    second_lab = _oklab(second)
    return sum((left - right) ** 2 for left, right in zip(first_lab, second_lab)) ** 0.5


def validate_political_colours(records: dict[str, dict[str, Any]]) -> int:
    by_colour: dict[tuple[int, int, int], list[str]] = defaultdict(list)
    for tag, record in records.items():
        by_colour[tuple(int(value) for value in record["colour_rgb8"])].append(tag)
    duplicates = {
        colour: sorted(tags)
        for colour, tags in by_colour.items()
        if len(tags) > 1
    }
    if duplicates:
        raise RegistryError(f"Exact political-colour collisions are not permitted: {duplicates}")

    province_owners: dict[str, str] = {}
    with MANIFEST.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            province_id = str(int(row["province_id"]))
            owner = (row.get("proposed_owner") or "").strip().upper()
            if owner:
                province_owners[province_id] = owner
    graph = json.loads(PROVINCE_GRAPH.read_text(encoding="utf-8"))
    neighbour_pairs: set[tuple[str, str]] = set()
    for province_id, province in graph.get("provinces", {}).items():
        owner = province_owners.get(str(province_id), "")
        if not owner:
            continue
        for neighbour_id in province.get("land_neighbors", {}):
            neighbour_owner = province_owners.get(str(neighbour_id), "")
            if neighbour_owner and neighbour_owner != owner:
                neighbour_pairs.add(tuple(sorted((owner, neighbour_owner))))

    issues: list[str] = []
    checked = 0
    for first, second in sorted(neighbour_pairs):
        if first not in records or second not in records:
            continue
        checked += 1
        distance = _oklab_distance(records[first]["colour_rgb8"], records[second]["colour_rgb8"])
        if distance < MIN_NEIGHBOUR_OKLAB_DISTANCE:
            issues.append(
                f"{first} {records[first]['display_name']} and {second} {records[second]['display_name']} "
                f"are adjacent with Oklab distance {distance:.4f} below {MIN_NEIGHBOUR_OKLAB_DISTANCE:.4f}."
            )
    if issues:
        raise RegistryError("Political colours fail the neighbour threshold:\n" + "\n".join(issues))
    return checked


def build_registry() -> dict[str, Any]:
    records = load_country_sources()
    validate_name_collisions(records)
    manifest_rows, manifest_owners = load_manifest(records)
    neighbour_pair_count = validate_political_colours(records)

    english: dict[str, str] = {}
    for tag, record in records.items():
        english[str(record["name_key"])] = str(record["display_name"])
        english[str(record["adjective_key"])] = str(record["adjective"])
    for record in PSEUDO_COUNTRIES.values():
        english[str(record["name_key"])] = str(record["display_name"])
        english[str(record["adjective_key"])] = str(record["adjective"])

    return {
        "schema_version": SCHEMA_VERSION,
        "metadata": {
            "generator": "tools/country_registry/build_country_registry.py",
            "country_count": len(records),
            "pseudo_country_count": len(PSEUDO_COUNTRIES),
            "manifest_row_count": manifest_rows,
            "manifest_owner_count": len(manifest_owners),
            "approved_name_collision_count": len(APPROVED_NAME_COLLISIONS),
            "political_colour_policy": {
                "exact_duplicates_allowed": False,
                "neighbour_colour_space": "Oklab",
                "minimum_neighbour_distance": MIN_NEIGHBOUR_OKLAB_DISTANCE,
                "starting_neighbour_pairs_checked": neighbour_pair_count,
            },
            "sources": [
                "assets/countries/*.txt",
                "assets/country_colors/*.txt",
                "docs/data/1444_ownership_manifest.csv",
                "assets/province_graph.json",
            ],
        },
        "approved_name_collisions": APPROVED_NAME_COLLISIONS,
        "pseudo_countries": PSEUDO_COUNTRIES,
        "countries": records,
        "localisation": {"en": english},
    }


def validate_registry(registry: dict[str, Any], *, verify_sources: bool = True) -> list[str]:
    errors: list[str] = []
    if int(registry.get("schema_version", 0)) != SCHEMA_VERSION:
        errors.append(f"Expected schema version {SCHEMA_VERSION}.")

    countries = registry.get("countries")
    localisation = registry.get("localisation", {}).get("en", {})
    pseudo = registry.get("pseudo_countries", {})
    if not isinstance(countries, dict) or not countries:
        return errors + ["`countries` must be a non-empty object."]
    if not isinstance(localisation, dict):
        errors.append("`localisation.en` must be an object.")
        localisation = {}
    if not isinstance(pseudo, dict):
        errors.append("`pseudo_countries` must be an object.")
        pseudo = {}

    metadata_count = int(registry.get("metadata", {}).get("country_count", -1))
    if metadata_count != len(countries):
        errors.append(f"Metadata country count {metadata_count} does not match {len(countries)} records.")

    for tag, raw_record in countries.items():
        if not re.fullmatch(r"[A-Z0-9]{3}", str(tag)):
            errors.append(f"Invalid country tag `{tag}`.")
            continue
        if tag in pseudo:
            errors.append(f"Country `{tag}` also exists as a pseudo-country.")
        if not isinstance(raw_record, dict):
            errors.append(f"Country `{tag}` is not an object.")
            continue
        record = raw_record
        display_name = str(record.get("display_name", ""))
        if not display_name or display_name != display_name.strip():
            errors.append(f"Country `{tag}` has an empty or padded display name.")
        for field in ("name_key", "adjective_key"):
            key = str(record.get(field, ""))
            if not key or key not in localisation or not str(localisation.get(key, "")):
                errors.append(f"Country `{tag}` has unresolved localisation field `{field}`: `{key}`.")
        if not bool(record.get("scenario_country", False)):
            errors.append(f"Country `{tag}` must be a scenario country.")
        colour = record.get("colour_rgb8", [])
        if (
            not isinstance(colour, list)
            or len(colour) != 3
            or any(not isinstance(value, int) or value < 0 or value > 255 for value in colour)
        ):
            errors.append(f"Country `{tag}` has invalid `colour_rgb8`: {colour}.")
        if verify_sources:
            for path_field, hash_field in (
                ("country_history_path", "country_history_sha256"),
                ("colour_path", "colour_sha256"),
            ):
                raw_path = str(record.get(path_field, ""))
                if not raw_path.startswith("res://"):
                    errors.append(f"Country `{tag}` has invalid `{path_field}`: `{raw_path}`.")
                    continue
                path = ROOT / raw_path.removeprefix("res://")
                if not path.is_file():
                    errors.append(f"Country `{tag}` source does not exist: `{raw_path}`.")
                elif str(record.get(hash_field, "")) != sha256(path):
                    errors.append(f"Country `{tag}` source hash is stale for `{raw_path}`.")

    for pseudo_id, raw_record in pseudo.items():
        if pseudo_id in countries:
            errors.append(f"Pseudo-country `{pseudo_id}` is also a scenario country.")
        if not isinstance(raw_record, dict):
            errors.append(f"Pseudo-country `{pseudo_id}` is not an object.")
            continue
        if bool(raw_record.get("scenario_country", True)) or bool(raw_record.get("selectable", True)):
            errors.append(f"Pseudo-country `{pseudo_id}` must be non-scenario and non-selectable.")
        for field in ("name_key", "adjective_key"):
            key = str(raw_record.get(field, ""))
            if not key or key not in localisation:
                errors.append(f"Pseudo-country `{pseudo_id}` has unresolved `{field}`: `{key}`.")

    return errors


def serialize(registry: dict[str, Any]) -> str:
    return json.dumps(registry, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def main() -> int:
    args = parse_args()
    try:
        registry = build_registry()
    except RegistryError as error:
        print(f"Country registry source validation failed:\n{error}", file=sys.stderr)
        return 1

    errors = validate_registry(registry)
    if errors:
        print("Country registry validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    expected = serialize(registry)
    if args.check:
        if not OUTPUT.is_file():
            print(f"Country registry is missing: {OUTPUT.relative_to(ROOT)}", file=sys.stderr)
            return 1
        try:
            existing_data = json.loads(OUTPUT.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"Country registry cannot be read: {error}", file=sys.stderr)
            return 1
        existing_errors = validate_registry(existing_data)
        if existing_errors:
            for error in existing_errors:
                print(f"- {error}", file=sys.stderr)
            return 1
        if OUTPUT.read_text(encoding="utf-8") != expected:
            print(
                "Country registry is stale. Run tools/country_registry/build_country_registry.py.",
                file=sys.stderr,
            )
            return 1
        print(
            "Country registry is valid and current. "
            f"countries={len(registry['countries'])} manifest_owners="
            f"{registry['metadata']['manifest_owner_count']}"
        )
        return 0

    OUTPUT.write_text(expected, encoding="utf-8")
    print(
        f"Wrote {OUTPUT.relative_to(ROOT)} with {len(registry['countries'])} countries."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
