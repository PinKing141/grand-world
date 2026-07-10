#!/usr/bin/env python3
"""Audit and safely migrate Grand World's 1444 province ownership data."""

from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
PROVINCES = ASSETS / "provinces"
COUNTRIES = ASSETS / "countries"
COUNTRY_COLORS = ASSETS / "country_colors"
DEFINITIONS = ASSETS / "definition.csv"
GEOGRAPHY = ROOT / "docs" / "data" / "province_geography.csv"
MANIFEST = ROOT / "docs" / "data" / "1444_ownership_manifest.csv"
SUMMARY = ROOT / "docs" / "data" / "1444_ownership_summary.json"
OVERRIDES = Path(__file__).with_name("ownership_overrides.csv")
BACKUPS = Path(__file__).with_name("backups")

OVERRIDE_FIELDS = [
    "province_id",
    "assigned_tag",
    "status",
    "confidence",
    "authority_type",
    "source_url",
    "source_note",
    "reviewer",
    "review_date",
]

MANIFEST_FIELDS = [
    "province_id",
    "province_name",
    "history_file",
    "definition_status",
    "current_owner",
    "tribal_owner",
    "dated_1444_owner",
    "dated_owner_date",
    "proposed_owner",
    "country_name",
    "category",
    "status",
    "confidence",
    "authority_type",
    "culture",
    "religion",
    "native_size",
    "longitude",
    "latitude",
    "land_luma_ratio",
    "source_url",
    "source_note",
    "reviewer",
    "review_date",
]

FIELD_PATTERN = re.compile(
    r'^\s*(owner|tribal_owner|culture|religion|native_size)\s*=\s*"?([^"\s#{}]+)',
    re.IGNORECASE,
)
PROVINCE_FILE_PATTERN = re.compile(r"^(\d+)(?:\s*-\s*|\s+)(.+)\.txt$", re.IGNORECASE)
COUNTRY_FILE_PATTERN = re.compile(r"^(.{3})\s+-\s+(.+)\.txt$", re.IGNORECASE)
DATE_PATTERN = re.compile(r"(?m)^[ \t]*(\d{1,4})\.(\d{1,2})\.(\d{1,2})\s*=\s*\{")
EVENT_OWNER_PATTERN = re.compile(r"owner\s*=\s*([A-Za-z0-9_-]+)", re.IGNORECASE)
START_DATE = (1444, 11, 11)


@dataclass(frozen=True)
class Country:
    tag: str
    name: str
    has_color: bool


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply-explicit-tribal",
        action="store_true",
        help="Promote only existing top-level tribal_owner evidence to owner.",
    )
    parser.add_argument(
        "--apply-approved",
        action="store_true",
        help="Apply rows marked approved in ownership_overrides.csv.",
    )
    parser.add_argument(
        "--apply-dated-1444",
        action="store_true",
        help="Promote the latest owner event on or before 1444-11-11 to the top-level runtime owner.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit non-zero if the manifest contains invalid owner tags or files.",
    )
    return parser.parse_args()


def strip_comment(line: str) -> str:
    in_quote = False
    escaped = False
    for index, character in enumerate(line):
        if character == "\\" and in_quote and not escaped:
            escaped = True
            continue
        if character == '"' and not escaped:
            in_quote = not in_quote
        elif character == "#" and not in_quote:
            return line[:index]
        escaped = False
    return line


def brace_delta(line: str) -> int:
    content = strip_comment(line)
    in_quote = False
    delta = 0
    for character in content:
        if character == '"':
            in_quote = not in_quote
        elif not in_quote and character == "{":
            delta += 1
        elif not in_quote and character == "}":
            delta -= 1
    return delta


def read_lossless(path: Path) -> str:
    return path.read_bytes().decode("utf-8", errors="surrogateescape")


def parse_top_level_fields(path: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    depth = 0
    for line in read_lossless(path).splitlines(keepends=True):
        if depth == 0:
            match = FIELD_PATTERN.match(strip_comment(line))
            if match:
                fields.setdefault(match.group(1).lower(), match.group(2))
        depth = max(0, depth + brace_delta(line))
    return fields


def matching_brace(text: str, opening_index: int) -> int:
    depth = 0
    in_quote = False
    in_comment = False
    escaped = False
    for index in range(opening_index, len(text)):
        character = text[index]
        if in_comment:
            if character in "\r\n":
                in_comment = False
            continue
        if character == "#" and not in_quote:
            in_comment = True
            continue
        if character == "\\" and in_quote and not escaped:
            escaped = True
            continue
        if character == '"' and not escaped:
            in_quote = not in_quote
        elif not in_quote and character == "{":
            depth += 1
        elif not in_quote and character == "}":
            depth -= 1
            if depth == 0:
                return index
        escaped = False
    return -1


def direct_event_owner(block: str) -> str:
    depth = 0
    in_quote = False
    in_comment = False
    escaped = False
    index = 0
    while index < len(block):
        character = block[index]
        if in_comment:
            if character in "\r\n":
                in_comment = False
            index += 1
            continue
        if character == "#" and not in_quote:
            in_comment = True
            index += 1
            continue
        if character == "\\" and in_quote and not escaped:
            escaped = True
            index += 1
            continue
        if character == '"' and not escaped:
            in_quote = not in_quote
        elif not in_quote and character == "{":
            depth += 1
        elif not in_quote and character == "}":
            depth = max(0, depth - 1)
        elif depth == 0 and not in_quote and (index == 0 or not (block[index - 1].isalnum() or block[index - 1] == "_")):
            match = EVENT_OWNER_PATTERN.match(block, index)
            if match:
                return match.group(1).upper()
        escaped = False
        index += 1
    return ""


def parse_dated_owner(path: Path) -> tuple[str, str]:
    text = read_lossless(path)
    latest_date: tuple[int, int, int] | None = None
    latest_owner = ""
    for match in DATE_PATTERN.finditer(text):
        event_date = tuple(int(match.group(part)) for part in (1, 2, 3))
        if event_date > START_DATE:
            continue
        opening_index = text.find("{", match.start(), match.end())
        closing_index = matching_brace(text, opening_index)
        if opening_index < 0 or closing_index < 0:
            continue
        owner = direct_event_owner(text[opening_index + 1:closing_index])
        if owner and (latest_date is None or event_date >= latest_date):
            latest_date = event_date
            latest_owner = owner
    if latest_date is None:
        return "", ""
    return latest_owner, ".".join(str(part) for part in latest_date)


def normalise_name(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.casefold())


def load_definitions() -> dict[int, dict[str, str]]:
    definitions: dict[int, dict[str, str]] = {}
    with DEFINITIONS.open("r", encoding="utf-8-sig", errors="replace", newline="") as handle:
        reader = csv.reader(handle, delimiter=";")
        next(reader, None)
        for row in reader:
            if len(row) < 5 or not row[0].strip().isdigit():
                continue
            province_id = int(row[0])
            definitions[province_id] = {
                "name": row[4].strip(),
                "status": row[5].strip() if len(row) > 5 else "",
            }
    return definitions


def load_countries() -> dict[str, Country]:
    color_names = {path.stem.casefold() for path in COUNTRY_COLORS.glob("*.txt")}
    countries: dict[str, Country] = {}
    for path in COUNTRIES.glob("*.txt"):
        match = COUNTRY_FILE_PATTERN.match(path.name)
        if not match:
            continue
        tag = match.group(1).upper()
        name = match.group(2).strip()
        countries[tag] = Country(tag=tag, name=name, has_color=name.casefold() in color_names)
    return countries


def load_histories() -> dict[int, tuple[Path, dict[str, str]]]:
    histories: dict[int, tuple[Path, dict[str, str]]] = {}
    for path in PROVINCES.glob("*.txt"):
        match = PROVINCE_FILE_PATTERN.match(path.name)
        if not match:
            continue
        province_id = int(match.group(1))
        fields = parse_top_level_fields(path)
        dated_owner, dated_owner_date = parse_dated_owner(path)
        fields["dated_1444_owner"] = dated_owner
        fields["dated_owner_date"] = dated_owner_date
        histories[province_id] = (path, fields)
    return histories


def load_keyed_csv(path: Path, key: str) -> dict[int, dict[str, str]]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = csv.DictReader(handle)
        result = {}
        for row in rows:
            value = (row.get(key) or "").strip()
            if value.isdigit():
                result[int(value)] = {name: (content or "").strip() for name, content in row.items()}
        return result


def classify_row(
    province_id: int,
    definition: dict[str, str],
    history: tuple[Path, dict[str, str]] | None,
    countries: dict[str, Country],
    geography: dict[str, str],
    override: dict[str, str] | None,
) -> dict[str, str]:
    path, fields = history if history else (None, {})
    current_owner = fields.get("owner", "").upper()
    tribal_owner = fields.get("tribal_owner", "").upper()
    dated_owner = fields.get("dated_1444_owner", "").upper()
    dated_owner_date = fields.get("dated_owner_date", "")
    proposed_owner = ""
    country_name = ""
    category = "research_required"
    status = "unresolved"
    confidence = "unresolved"
    authority_type = ""
    source_url = ""
    source_note = ""
    reviewer = ""
    review_date = ""

    if dated_owner and dated_owner != current_owner:
        proposed_owner = dated_owner
        category = "dated_1444_owner"
        status = "ready_to_apply"
        confidence = "source_explicit"
        authority_type = "state_or_polity"
        source_note = "Latest direct owner event on or before 1444-11-11 in the imported province history."
    elif override:
        proposed_owner = override.get("assigned_tag", "").upper()
        status = override.get("status", "unresolved")
        confidence = override.get("confidence", "unresolved")
        authority_type = override.get("authority_type", "")
        source_url = override.get("source_url", "")
        source_note = override.get("source_note", "")
        reviewer = override.get("reviewer", "")
        review_date = override.get("review_date", "")
        if current_owner and current_owner == proposed_owner:
            category = "applied_documented_assignment"
            status = "applied"
        else:
            category = "reviewed_override"
    elif current_owner:
        proposed_owner = current_owner
        category = "existing_owner"
        status = "existing"
        confidence = "source_explicit"
        authority_type = "state_or_polity"
        source_note = "Existing top-level owner in the imported province history."
    elif tribal_owner:
        proposed_owner = tribal_owner
        category = "explicit_tribal_authority"
        status = "ready_to_apply"
        confidence = "source_explicit"
        authority_type = "indigenous_or_tribal_authority"
        source_note = "Existing top-level tribal_owner in the imported province history."
    elif history is None:
        if definition["name"].casefold().startswith("unused") or definition["status"].casefold() != "x":
            category = "unused_definition"
            status = "excluded"
            confidence = "high"
            authority_type = "non_playable_definition"
            source_note = "Definition is reserved/unused and has no province history file."
        else:
            category = "missing_active_history"
            source_note = "Active definition has no matching province history file."
    elif fields.get("culture") or int(fields.get("native_size") or 0) > 0:
        category = "inhabited_land_research_required"
        source_note = "Culture and/or native population data exists, but no 1444 authority is encoded."
    else:
        luma_ratio = float(geography.get("luma_100_ratio") or 0.0)
        if geography and luma_ratio < 0.15:
            category = "water_candidate"
            status = "candidate_exclusion"
            confidence = "medium"
            authority_type = "water"
            source_note = "Geography texture is predominantly water; verify before excluding."
        else:
            category = "uninhabited_or_wasteland_research_required"
            source_note = "No owner, culture, or native population signal exists."

    if proposed_owner in countries:
        country_name = countries[proposed_owner].name

    return {
        "province_id": str(province_id),
        "province_name": definition["name"],
        "history_file": path.name if path else "",
        "definition_status": definition["status"],
        "current_owner": current_owner,
        "tribal_owner": tribal_owner,
        "dated_1444_owner": dated_owner,
        "dated_owner_date": dated_owner_date,
        "proposed_owner": proposed_owner,
        "country_name": country_name,
        "category": category,
        "status": status,
        "confidence": confidence,
        "authority_type": authority_type,
        "culture": fields.get("culture", ""),
        "religion": fields.get("religion", ""),
        "native_size": fields.get("native_size", ""),
        "longitude": geography.get("longitude", ""),
        "latitude": geography.get("latitude", ""),
        "land_luma_ratio": geography.get("luma_100_ratio", ""),
        "source_url": source_url,
        "source_note": source_note,
        "reviewer": reviewer,
        "review_date": review_date,
    }


def build_manifest() -> tuple[list[dict[str, str]], dict[str, Country]]:
    definitions = load_definitions()
    countries = load_countries()
    histories = load_histories()
    geography = load_keyed_csv(GEOGRAPHY, "province_id")
    overrides = load_keyed_csv(OVERRIDES, "province_id")
    rows = [
        classify_row(
            province_id,
            definition,
            histories.get(province_id),
            countries,
            geography.get(province_id, {}),
            overrides.get(province_id),
        )
        for province_id, definition in sorted(definitions.items())
    ]
    return rows, countries


def write_manifest(rows: list[dict[str, str]]) -> None:
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with MANIFEST.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=MANIFEST_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    summary = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "province_count": len(rows),
        "categories": dict(sorted(Counter(row["category"] for row in rows).items())),
        "statuses": dict(sorted(Counter(row["status"] for row in rows).items())),
        "invalid_proposed_tags": sorted(
            {
                row["proposed_owner"]
                for row in rows
                if row["proposed_owner"] and not row["country_name"]
            }
        ),
    }
    SUMMARY.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


def write_overrides(rows: list[dict[str, str]]) -> None:
    with OVERRIDES.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=OVERRIDE_FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def promote_tribal_line(path: Path, expected_tag: str) -> None:
    content = read_lossless(path)
    lines = content.splitlines(keepends=True)
    depth = 0
    replaced = False
    pattern = re.compile(r"^(\s*)tribal_owner(\s*=\s*)[A-Za-z0-9_-]+(.*)$", re.IGNORECASE)
    for index, line in enumerate(lines):
        if depth == 0:
            line_without_ending = line.rstrip("\r\n")
            ending = line[len(line_without_ending):]
            match = pattern.match(line_without_ending)
            if match:
                existing_tag = re.search(r"=\s*([A-Za-z0-9_-]+)", line_without_ending)
                if not existing_tag or existing_tag.group(1).upper() != expected_tag.upper():
                    raise ValueError(f"Unexpected tribal owner in {path.name}")
                lines[index] = f"{match.group(1)}owner{match.group(2)}{expected_tag}{match.group(3)}{ending}"
                replaced = True
                break
        depth = max(0, depth + brace_delta(line))
    if not replaced:
        raise ValueError(f"No top-level tribal_owner found in {path.name}")
    path.write_bytes("".join(lines).encode("utf-8", errors="surrogateescape"))


def prepend_owner(path: Path, tag: str) -> None:
    content = read_lossless(path)
    if parse_top_level_fields(path).get("owner"):
        raise ValueError(f"{path.name} already has a top-level owner")
    newline = "\r\n" if "\r\n" in content else "\n"
    path.write_bytes((f"owner = {tag}{newline}" + content).encode("utf-8", errors="surrogateescape"))


def set_top_level_owner(path: Path, tag: str) -> None:
    content = read_lossless(path)
    lines = content.splitlines(keepends=True)
    depth = 0
    owner_pattern = re.compile(r"^(\s*)owner(\s*=\s*)[A-Za-z0-9_-]+(.*)$", re.IGNORECASE)
    tribal_pattern = re.compile(r"^(\s*)tribal_owner(\s*=\s*)[A-Za-z0-9_-]+(.*)$", re.IGNORECASE)
    for index, line in enumerate(lines):
        if depth == 0:
            line_without_ending = line.rstrip("\r\n")
            ending = line[len(line_without_ending):]
            match = owner_pattern.match(line_without_ending) or tribal_pattern.match(line_without_ending)
            if match:
                lines[index] = f"{match.group(1)}owner{match.group(2)}{tag}{match.group(3)}{ending}"
                path.write_bytes("".join(lines).encode("utf-8", errors="surrogateescape"))
                return
        depth = max(0, depth + brace_delta(line))
    prepend_owner(path, tag)


def apply_assignments(rows: list[dict[str, str]], mode: str) -> int:
    histories = load_histories()
    overrides = load_keyed_csv(OVERRIDES, "province_id")
    selected = []
    for row in rows:
        if mode == "explicit_tribal":
            should_apply = row["category"] == "explicit_tribal_authority"
        elif mode == "dated_1444":
            should_apply = row["category"] == "dated_1444_owner"
        else:
            should_apply = row["status"] == "approved" and bool(row["proposed_owner"])
        if should_apply:
            selected.append(row)
    if not selected:
        print("No ownership assignments matched the requested apply mode.")
        return 0

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = BACKUPS / stamp
    backup_dir.mkdir(parents=True, exist_ok=False)
    applied_log = []
    today = datetime.now(timezone.utc).date().isoformat()

    for row in selected:
        province_id = int(row["province_id"])
        if province_id not in histories:
            raise ValueError(f"No history file for province {province_id}")
        path, fields = histories[province_id]
        tag = row["proposed_owner"]
        shutil.copy2(path, backup_dir / path.name)
        if row["category"] == "explicit_tribal_authority":
            promote_tribal_line(path, tag)
            overrides[province_id] = {
                "province_id": str(province_id),
                "assigned_tag": tag,
                "status": "approved",
                "confidence": "source_explicit",
                "authority_type": "indigenous_or_tribal_authority",
                "source_url": "",
                "source_note": "Promoted from the imported top-level tribal_owner field; original file is in the migration backup.",
                "reviewer": "Codex data migration",
                "review_date": today,
            }
        elif row["category"] == "dated_1444_owner":
            set_top_level_owner(path, tag)
            existing_override = overrides.get(province_id, {})
            previous_note = existing_override.get("source_note", "")
            dated_note = f"Promoted from the imported {row['dated_owner_date']} owner event for the 1444-11-11 scenario."
            overrides[province_id] = {
                "province_id": str(province_id),
                "assigned_tag": tag,
                "status": "approved",
                "confidence": "source_explicit",
                "authority_type": existing_override.get("authority_type", "state_or_polity"),
                "source_url": existing_override.get("source_url", ""),
                "source_note": f"{previous_note} {dated_note}".strip(),
                "reviewer": "Codex data migration",
                "review_date": today,
            }
        else:
            set_top_level_owner(path, tag)
        applied_log.append({"province_id": province_id, "file": path.name, "owner": tag})

    write_overrides([overrides[key] for key in sorted(overrides)])
    (backup_dir / "applied.json").write_text(
        json.dumps({"created_at_utc": datetime.now(timezone.utc).isoformat(), "changes": applied_log}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Applied {len(selected)} assignments. Safety copies: {backup_dir.relative_to(ROOT)}")
    return len(selected)


def validate(rows: list[dict[str, str]], countries: dict[str, Country]) -> list[str]:
    errors = []
    for row in rows:
        tag = row["proposed_owner"]
        if tag and tag not in countries:
            errors.append(f"Province {row['province_id']} proposes unknown country tag {tag}")
        elif tag and not countries[tag].has_color:
            errors.append(f"Country {tag} ({countries[tag].name}) has no matching colour file")
        if row["category"] == "missing_active_history":
            errors.append(f"Active province {row['province_id']} has no history file")
    return errors


def main() -> int:
    args = parse_args()
    rows, countries = build_manifest()
    write_manifest(rows)
    if args.apply_explicit_tribal or args.apply_dated_1444 or args.apply_approved:
        mode = "explicit_tribal" if args.apply_explicit_tribal else "dated_1444" if args.apply_dated_1444 else "approved"
        apply_assignments(rows, mode=mode)
        rows, countries = build_manifest()
        write_manifest(rows)
    errors = validate(rows, countries)
    print(f"Wrote {len(rows)} ownership records to {MANIFEST.relative_to(ROOT)}")
    for category, count in sorted(Counter(row["category"] for row in rows).items()):
        print(f"  {category}: {count}")
    if errors:
        print("Validation findings:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
    return 1 if args.check and errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
