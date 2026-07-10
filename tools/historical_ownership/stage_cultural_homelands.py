#!/usr/bin/env python3
"""Stage medium-confidence cultural-homeland ownership for remaining inhabited land."""

from __future__ import annotations

import csv
import math
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

import build_manifest as ownership


ROOT = Path(__file__).resolve().parents[2]
COUNTRY_FIELD = re.compile(
    r'^\s*(capital|primary_culture|government)\s*=\s*"?([^"\s#{}]+)', re.IGNORECASE
)
ALIASES = {
    "arawak": ["ARW"],
    "maipurean": ["ARW"],
    "miami": ["MMI"],
    "chipewyan": ["DNE"],
}
MANUAL_PROVINCES = {
    574: "OGE",   # Andamanese peoples rather than the imported Filipino label.
    738: "FMC",   # Formosan Indigenous peoples rather than Hawaii.
    978: "DNE",   # Kenai / Dena'ina rather than the imported broad Aleutian label.
    1006: "DNE",  # Province name is Chipewyan despite the imported Inuit culture label.
    1178: "KSN",  # Great Karoo should not be absorbed into the Tswana correction slot.
    1235: "CMR",  # Guam / Chamorro.
    1241: "MIC",  # Kiribati.
    1244: "THT",  # Tahiti.
    1987: "THT",  # Society Islands.
    1988: "RPN",  # Rapa Nui.
    1990: "MIC",  # Tuvalu.
    1991: "MIC",  # Gilbert Islands.
    1992: "MIC",  # Nauru.
    1993: "MIC",  # Marshall Islands.
    1995: "MIC",  # Micronesia.
    1996: "MIC",  # Palau.
    2154: "FMC",  # Kelang, Taiwan.
    2155: "FMC",  # Middag, Taiwan.
    2880: "KSN",  # Griqualand should remain in the Khoisan gameplay umbrella.
    4782: "TSW",  # Correct the imported Khoisan label for Tswana.
    4783: "SWZ",  # Separate Swazi authority.
}
EXCLUDED_UNINHABITED = {
    481: "Bermuda was uninhabited in 1444.",
    1095: "The Falkland Islands had no permanent population in 1444.",
    1096: "Cape Verde was uninhabited before Portuguese settlement.",
    1100: "Mahé was uninhabited in 1444.",
    1101: "Diego Garcia was uninhabited in 1444.",
    1102: "Mauritius was uninhabited in 1444.",
    1103: "Réunion/Bourbon was uninhabited in 1444.",
    1306: "São Tomé was uninhabited before Portuguese settlement.",
    1994: "Wake Island had no permanent population in 1444.",
    1997: "Midway had no permanent population in 1444.",
    1998: "Christmas Island was uninhabited in 1444.",
    1999: "The Cocos Islands were uninhabited in 1444.",
    2002: "The Galápagos Islands had no permanent population in 1444.",
    2025: "South Georgia had no permanent population in 1444.",
}
MANUAL_ONLY_TAGS = {"CMR", "FMC", "MIC", "OGE", "RPN", "SWZ", "THT", "TSW"}
DISALLOWED_CULTURAL_CANDIDATES = {"COM", "ZUL"}
NORTH_AMERICAN_CULTURES = {
    "abenaki", "aleutian", "algonquin", "anishinabe", "apache", "arapaho", "athabascan",
    "blackfoot", "bungi", "caddo", "carib", "catawba", "cherokee", "chichimecan",
    "chickasaw", "chinook", "chipewyan", "choctaw", "cree", "creek", "delaware", "haida",
    "illini", "innu", "inuit", "iroquois", "kiowa", "lipan", "mescalero", "miami", "mikmaq",
    "miskito", "nakota", "natchez", "osage", "pawnee", "piman", "plains_cree", "powhatan",
    "pueblo", "salish", "shawnee", "shoshone", "susquehannock", "tionontate", "wichita",
    "yamasee", "yokuts", "yoron", "yuchi",
}
SOUTH_AMERICAN_CULTURES = {
    "aimara", "arawak", "cara", "chacoan", "charruan", "diaguita", "ge", "guajiro", "guarani",
    "het", "huarpe", "inca", "jivaro", "maipurean", "mapuche", "muisca", "patagonian",
    "tepic", "tupinamba", "wastek",
}
AUSTRALIAN_CULTURES = {"aboriginal", "gamilaraay", "gunwinyguan", "kulin", "nyoongah", "paman", "yura"}


def load_country_metadata() -> dict[str, dict[str, str]]:
    result = {}
    for path in ownership.COUNTRIES.glob("*.txt"):
        match = ownership.COUNTRY_FILE_PATTERN.match(path.name)
        if not match:
            continue
        fields = {}
        depth = 0
        for line in ownership.read_lossless(path).splitlines():
            clean = ownership.strip_comment(line)
            if depth == 0:
                field = COUNTRY_FIELD.match(clean)
                if field:
                    fields.setdefault(field.group(1).lower(), field.group(2))
            depth = max(0, depth + ownership.brace_delta(line))
        fields["tag"] = match.group(1).upper()
        fields["name"] = match.group(2)
        result[fields["tag"]] = fields
    return result


def source_for(culture: str) -> tuple[str, str]:
    if culture in NORTH_AMERICAN_CULTURES:
        return (
            "https://guides.loc.gov/native-american-spaces/cartographic-resources/indian-sites",
            "Library of Congress cartographic guide used as a regional cross-check; exact province borders remain a gameplay abstraction.",
        )
    if culture in SOUTH_AMERICAN_CULTURES:
        return (
            "https://dia.upenn.edu/en/maps/CNT0118/",
            "Smithsonian-derived South American ethnographic mapping used as a regional cross-check; exact province borders remain approximate.",
        )
    if culture in AUSTRALIAN_CULTURES:
        return (
            "https://aiatsis.gov.au/explore/map-indigenous-australia",
            "AIATSIS map used only as a general-location cross-check in accordance with its warning that boundaries are not exact.",
        )
    return (
        "https://seshat-db.com/core/cliopatria/",
        "Seshat Cliopatria used as a global polity cross-check; the assignment is primarily based on imported culture and capital evidence.",
    )


def distance(a: dict[str, str], b: dict[str, str], map_width: float) -> float:
    dx = abs(float(a["centroid_x"]) - float(b["centroid_x"]))
    dx = min(dx, map_width - dx)
    dy = float(a["centroid_y"]) - float(b["centroid_y"])
    return math.hypot(dx, dy)


def main() -> int:
    rows, countries = ownership.build_manifest()
    metadata = load_country_metadata()
    geography = ownership.load_keyed_csv(ownership.GEOGRAPHY, "province_id")
    overrides = ownership.load_keyed_csv(ownership.OVERRIDES, "province_id")
    active_tags = {
        row["proposed_owner"]
        for row in rows
        if row["proposed_owner"] and row["status"] in {"existing", "applied", "ready_to_apply"}
    }
    candidates_by_culture: dict[str, list[dict[str, str]]] = defaultdict(list)
    for tag, fields in metadata.items():
        capital = fields.get("capital", "")
        culture = fields.get("primary_culture", "")
        if not capital.isdigit() or int(capital) not in geography or not culture:
            continue
        if tag in MANUAL_ONLY_TAGS or tag in DISALLOWED_CULTURAL_CANDIDATES:
            continue
        if fields.get("government") not in {"native", "tribal"} and tag not in active_tags:
            continue
        candidate = dict(fields)
        candidate["capital_geography"] = geography[int(capital)]
        candidates_by_culture[culture].append(candidate)

    staged = 0
    today = datetime.now(timezone.utc).date().isoformat()
    map_width = 5632.0
    for province_id, reason in EXCLUDED_UNINHABITED.items():
        existing = overrides.get(province_id, {})
        if existing and existing.get("reviewer") not in {"", "Codex cultural-homeland pass"}:
            continue
        overrides[province_id] = {
            "province_id": str(province_id),
            "assigned_tag": "",
            "status": "excluded",
            "confidence": "high",
            "authority_type": "uninhabited_land",
            "source_url": "https://www.openhistoricalmap.org/",
            "source_note": f"{reason} Retained as non-country land pending a dedicated uninhabited-island terrain layer.",
            "reviewer": "Codex cultural-homeland pass",
            "review_date": today,
        }
    for row in rows:
        existing_override = overrides.get(int(row["province_id"]), {})
        owned_by_this_pass = existing_override.get("reviewer") == "Codex cultural-homeland pass"
        if row["category"] != "inhabited_land_research_required" and not owned_by_this_pass:
            continue
        if not row["culture"] or int(row["province_id"]) in EXCLUDED_UNINHABITED:
            continue
        province_id = int(row["province_id"])
        if province_id in overrides and not owned_by_this_pass:
            continue
        if province_id in MANUAL_PROVINCES:
            tag = MANUAL_PROVINCES[province_id]
            basis = "manual correction of an over-broad imported culture label"
            confidence = "medium"
        else:
            candidates = list(candidates_by_culture.get(row["culture"], []))
            for alias_tag in ALIASES.get(row["culture"], []):
                if alias_tag in metadata:
                    alias = dict(metadata[alias_tag])
                    capital = alias.get("capital", "")
                    if capital.isdigit() and int(capital) in geography:
                        alias["capital_geography"] = geography[int(capital)]
                        candidates.append(alias)
            if not candidates:
                raise ValueError(f"No cultural authority candidate for province {province_id} ({row['culture']})")
            active_candidates = [candidate for candidate in candidates if candidate["tag"] in active_tags]
            if active_candidates:
                candidates = active_candidates
            target_geography = geography[province_id]
            selected = min(
                candidates,
                key=lambda candidate: distance(target_geography, candidate["capital_geography"], map_width),
            )
            tag = selected["tag"]
            basis = f"nearest encoded {row['culture']} authority capital ({selected['name']}, province {selected['capital']})"
            confidence = "medium"
        if tag not in countries:
            raise ValueError(f"Unknown staged country tag {tag} for province {province_id}")
        source_url, regional_note = source_for(row["culture"])
        overrides[province_id] = {
            "province_id": str(province_id),
            "assigned_tag": tag,
            "status": "approved",
            "confidence": confidence,
            "authority_type": "cultural_territorial_authority",
            "source_url": source_url,
            "source_note": (
                f"1444 gameplay territorialization based on imported culture and {basis}. {regional_note} "
                "This is not a claim of a sharply bounded centralized state."
            ),
            "reviewer": "Codex cultural-homeland pass",
            "review_date": today,
        }
        staged += 1

    ownership.write_overrides([overrides[key] for key in sorted(overrides)])
    print(f"Staged {staged} inhabited provinces in ownership_overrides.csv.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
