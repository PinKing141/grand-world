#!/usr/bin/env python3
"""Build complete original marker atlases and a provenance-aware country shield atlas."""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import io
import json
import math
import re
import sys
import time
import urllib.parse
import urllib.request
from urllib.error import HTTPError
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(__file__).with_name("historical_flag_sources.json")
REGISTRY = ROOT / "assets" / "country_registry.json"
OWNERSHIP = ROOT / "docs" / "data" / "1444_ownership_manifest.csv"
SOURCE_DIR = ROOT / "assets" / "marker_art" / "source_flags"
GENERATED_DIR = ROOT / "assets" / "marker_art" / "generated"
SOURCE_MANIFEST = SOURCE_DIR / "source_manifest.json"
ASSET_MANIFEST = GENERATED_DIR / "marker_asset_manifest.json"
SHIELD_ATLAS = GENERATED_DIR / "country_shield_atlas.png"
ICON_ATLAS = GENERATED_DIR / "marker_icon_atlas.png"
CONTACT_SHEET = ROOT / "docs" / "roadmap" / "map_visual_production" / "marker_placeholder_contact_sheet.png"
THIRD_PARTY_NOTICES = ROOT / "assets" / "marker_art" / "THIRD_PARTY_NOTICES.md"
RESEARCH_REGISTER = ROOT / "docs" / "roadmap" / "map_visual_production" / "HISTORICAL_SHIELD_RESEARCH_REGISTER.md"
RESEARCH_REVIEWS = ROOT / "tools" / "marker_art" / "shield_research_reviews.json"

SHIELD_TILE = 128
SHIELD_COLUMNS = 32
SHIELD_RENDER_SUPERSAMPLE = 2
ICON_TILE = 128
ICON_COLUMNS = 4
ICON_NAMES = ("army", "navy", "battle", "siege", "capital", "fort", "port", "cluster", "destination", "invalid")
USER_AGENT = "GrandWorldHistoricalMarkerPipeline/1.0 (local game asset pipeline)"


def urlopen_with_retry(request: urllib.request.Request, timeout: int = 60):
    for attempt in range(7):
        try:
            return urllib.request.urlopen(request, timeout=timeout)
        except HTTPError as error:
            if error.code != 429 or attempt == 6:
                raise
            retry_after = int(error.headers.get("Retry-After", "0") or 0)
            time.sleep(max(retry_after, 2 ** attempt))
    raise RuntimeError("unreachable retry state")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch-sources", action="store_true", help="Fetch configured openly licensed Wikimedia thumbnails and metadata.")
    parser.add_argument("--check", action="store_true", help="Fail when generated atlases/manifests are stale.")
    return parser.parse_args()


def stable_json(data: Any) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def third_party_notices(source_manifest: dict[str, Any]) -> str:
    lines = [
        "# Historical Placeholder Flag Notices",
        "",
        "The files in `source_flags/` and the corresponding clipped/resized portions of `generated/country_shield_atlas.png` use the openly licensed or public-domain works listed below. The gold shield frame, marker icons, atlas layout, shaders, and runtime code are project-original placeholders. Unsourced country slots are transparent and contain no invented heraldry.",
        "",
        "These visuals identify historical research leads; their inclusion does not certify that modern national-flag conventions or the exact depicted design existed on 11 November 1444. See each entry's evidence class and review note in `source_flags/source_manifest.json`.",
        "",
        "Adaptation applied: download thumbnail normalisation, centre crop/resize, clipping to an original shield silhouette, and a restrained highlight/shade overlay.",
        "",
    ]
    for tag, source in sorted(source_manifest["sources"].items()):
        attribution = source.get("attribution") or source.get("artist") or source.get("credit") or "See source page"
        lines.extend([
            f"## {tag} — {source['commons_file']}",
            "",
            f"- Source: {source['description_url']}",
            f"- Creator/attribution: {attribution}",
            f"- Licence: {source['license']}" + (f" — {source['license_url']}" if source.get("license_url") else ""),
            f"- Evidence: `{source['evidence']}`",
            f"- Review note: {source['review_note']}",
            "",
        ])
    return "\n".join(lines)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def plain_metadata(value: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", value or "")).strip()


def fetch_sources(config: dict[str, Any]) -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    entries: dict[str, dict[str, Any]] = config["sources"]
    titles = ["File:" + entry["commons_file"] for entry in entries.values()]
    params = urllib.parse.urlencode({
        "action": "query",
        "titles": "|".join(titles),
        "prop": "imageinfo",
        "iiprop": "url|extmetadata",
        "iiurlwidth": 512,
        "format": "json",
    })
    request = urllib.request.Request("https://commons.wikimedia.org/w/api.php?" + params, headers={"User-Agent": USER_AGENT})
    with urlopen_with_retry(request, timeout=60) as response:
        payload = json.load(response)
    aliases: dict[str, str] = {}
    for group in ("normalized", "redirects"):
        for item in payload.get("query", {}).get(group, []):
            aliases[item["from"]] = item["to"]
    pages = {page["title"]: page for page in payload["query"]["pages"].values()}

    def resolve(title: str) -> str:
        seen: set[str] = set()
        while title in aliases and title not in seen:
            seen.add(title)
            title = aliases[title]
        return title

    manifest_sources: dict[str, Any] = {}
    for tag, entry in sorted(entries.items()):
        requested = "File:" + entry["commons_file"]
        page = pages.get(resolve(requested)) or pages.get(requested)
        if page is None or "missing" in page or not page.get("imageinfo"):
            raise RuntimeError(f"Wikimedia source is missing for {tag}: {requested}")
        info = page["imageinfo"][0]
        metadata = info.get("extmetadata", {})
        download_url = info.get("thumburl", info["url"])
        output_path = SOURCE_DIR / f"{tag}.png"
        if not output_path.is_file():
            image_request = urllib.request.Request(download_url, headers={"User-Agent": USER_AGENT})
            with urlopen_with_retry(image_request, timeout=60) as response:
                downloaded_bytes = response.read()
            image = Image.open(io.BytesIO(downloaded_bytes)).convert("RGBA")
            image.save(output_path, format="PNG", optimize=True)
            time.sleep(0.35)
        normalized_bytes = output_path.read_bytes()
        manifest_sources[tag] = {
            "asset_path": f"res://assets/marker_art/source_flags/{tag}.png",
            "commons_file": page["title"].removeprefix("File:"),
            "description_url": info["descriptionurl"],
            "original_url": info["url"],
            "thumbnail_url": download_url,
            "artist": plain_metadata(metadata.get("Artist", {}).get("value", "")),
            "credit": plain_metadata(metadata.get("Credit", {}).get("value", "")),
            "attribution": plain_metadata(metadata.get("Attribution", {}).get("value", "")),
            "license": plain_metadata(metadata.get("LicenseShortName", {}).get("value", "")),
            "license_url": metadata.get("LicenseUrl", {}).get("value", ""),
            "usage_terms": plain_metadata(metadata.get("UsageTerms", {}).get("value", "")),
            "sha256": sha256_bytes(normalized_bytes),
            "evidence": entry["evidence"],
            "review_note": entry["note"],
        }
    SOURCE_MANIFEST.write_text(stable_json({
        "schema_version": 1,
        "generator": "tools/marker_art/build_marker_assets.py --fetch-sources",
        "policy": config["policy"],
        "source_count": len(manifest_sources),
        "sources": manifest_sources,
    }), encoding="utf-8")
    print(f"Fetched {len(manifest_sources)} openly licensed historical source images.")


def active_1444_tags() -> set[str]:
    tags: set[str] = set()
    with OWNERSHIP.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            tag = (row.get("proposed_owner") or "").strip().upper()
            if tag:
                tags.add(tag)
    return tags


def markdown_cell(value: Any) -> str:
    return " ".join(str(value or "").split()).replace("|", "\\|")


def shield_research_register(manifest: dict[str, Any], source_manifest: dict[str, Any]) -> str:
    countries: dict[str, dict[str, Any]] = manifest["countries"]
    sources: dict[str, dict[str, Any]] = source_manifest.get("sources", {})
    registry: dict[str, dict[str, Any]] = json.loads(REGISTRY.read_text(encoding="utf-8"))["countries"]
    review_data = json.loads(RESEARCH_REVIEWS.read_text(encoding="utf-8"))
    review_entries: dict[str, dict[str, Any]] = review_data.get("entries", {})
    allowed_statuses = set(review_data.get("allowed_statuses", []))
    unknown_review_tags = sorted(set(review_entries) - set(countries))
    if unknown_review_tags:
        raise RuntimeError("Shield research review tracker contains unknown tags: " + ", ".join(unknown_review_tags))

    authority_counts: dict[str, dict[str, int]] = {}
    with OWNERSHIP.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            tag = (row.get("proposed_owner") or "").strip().upper()
            authority = (row.get("authority_type") or "").strip()
            if tag and authority:
                tag_counts = authority_counts.setdefault(tag, {})
                tag_counts[authority] = tag_counts.get(authority, 0) + 1

    def history_context(tag: str) -> dict[str, str]:
        registry_record = registry[tag]
        relative = str(registry_record.get("country_history_path", "")).removeprefix("res://")
        path = ROOT / relative
        text = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""

        def first_value(key: str) -> str:
            match = re.search(rf"^\s*{re.escape(key)}\s*=\s*([^\s#]+)", text, flags=re.MULTILINE)
            return match.group(1).strip('"') if match else "unknown"

        counts = authority_counts.get(tag, {})
        authority = max(counts, key=counts.get) if counts else "not_in_starting_ownership_manifest"
        return {
            "government": first_value("government"),
            "technology_group": first_value("technology_group"),
            "culture": first_value("primary_culture"),
            "religion": first_value("religion"),
            "authority": authority,
        }

    contexts = {tag: history_context(tag) for tag in countries}

    def research_lane(tag: str) -> str:
        context = contexts[tag]
        government = context["government"]
        authority = context["authority"]
        if government == "native" or authority in {"cultural_territorial_authority", "indigenous_or_tribal_authority"}:
            return "Community or indigenous identity"
        if government in {"tribal", "nomad"}:
            return "Tribal, clan or nomadic polity"
        if government == "republic":
            return "Republic or civic polity"
        if government == "theocracy":
            return "Religious institution or order"
        if government == "monarchy":
            return "Monarchy or dynastic territory"
        return "Unclassified political identity"

    def required_deliverable(tag: str, active: bool) -> str:
        lane = research_lane(tag)
        targets = {
            "Monarchy or dynastic territory": "Identify the 1444 ruler/dynasty and find dated royal or dynastic arms, a standard, banner, seal, or polity emblem; record the bearer and valid date range.",
            "Republic or civic polity": "Find a civic/state banner, municipal arms, official seal, coin, or government emblem used by the republic near the relevant date; record the issuing authority.",
            "Religious institution or order": "Find the governing church/order/institution's banner, cross, arms, seal, or office emblem; prove that it represents the ruling institution rather than the modern territory.",
            "Tribal, clan or nomadic polity": "Find a ruler, dynasty, clan, tamga, war banner, seal, coin, or manuscript emblem linked to this polity and period; do not substitute a modern national flag.",
            "Community or indigenous identity": "First decide with culturally appropriate evidence whether a shield is suitable. Then approve a documented community symbol, material-culture motif, seal/banner, or an explicit no-shield presentation.",
            "Unclassified political identity": "Confirm what political entity this tag represents and when it can exist, then select the matching state, dynastic, civic, institutional, or community evidence path.",
        }
        prefix = "" if active else "Define the tag's intended formation/release era before selecting artwork. "
        return prefix + targets[lane]

    def current_status(tag: str) -> str:
        default = "CANDIDATE_IMPORTED" if tag in sources else ("CULTURAL_REVIEW_REQUIRED" if research_lane(tag) == "Community or indigenous identity" else "NOT_STARTED")
        status = str(review_entries.get(tag, {}).get("status", default))
        if status not in allowed_statuses:
            raise RuntimeError(f"Invalid shield research status for {tag}: {status}")
        return status

    sourced_tags = sorted(sources, key=lambda tag: (countries[tag]["display_name"].casefold(), tag))
    missing_active = sorted(
        (tag for tag, record in countries.items() if record["active_in_1444_manifest"] and tag not in sources),
        key=lambda tag: (countries[tag]["display_name"].casefold(), tag),
    )
    missing_inactive = sorted(
        (tag for tag, record in countries.items() if not record["active_in_1444_manifest"] and tag not in sources),
        key=lambda tag: (countries[tag]["display_name"].casefold(), tag),
    )
    lane_order = (
        "Monarchy or dynastic territory",
        "Republic or civic polity",
        "Religious institution or order",
        "Tribal, clan or nomadic polity",
        "Community or indigenous identity",
        "Unclassified political identity",
    )
    lines = [
        "# Historical Shield Research Register",
        "",
        "Generated by `tools/marker_art/build_marker_assets.py`. Do not edit the tables manually.",
        "",
        "## Do all countries require research?",
        "",
        "**Yes, every country tag that can appear in a released campaign requires a completed identity decision.** That does not mean every tag needs a European-style national flag. A tag is complete only when it has one approved outcome: period shield/banner, representative arms or seal, culturally appropriate non-shield marker, an intentional no-marker decision, or removal/deprecation of an unused tag.",
        "",
        "Research active 1444 tags first. Non-starting tags can wait, but must be resolved before they are allowed to form, release, revolt, or appear through events in a complete game.",
        "",
        "## Permanent status vocabulary",
        "",
        "| Status | Exact meaning |",
        "|---|---|",
        "| `NOT_STARTED` | No candidate source or approved presentation decision exists. |",
        "| `RESEARCH_IN_PROGRESS` | A researcher, target identity, and working references have been recorded, but no candidate is selected. |",
        "| `CANDIDATE_SELECTED` | A specific visual source has been selected and is awaiting licence/evidence review or import. |",
        "| `CANDIDATE_IMPORTED` | Openly licensed artwork is integrated, but historical applicability and final art are not approved. |",
        "| `EVIDENCE_REVIEWED` | The object, date, bearer, polity relationship, and source reliability have been reviewed. |",
        "| `CULTURAL_REVIEW_REQUIRED` | A flag/shield may be inappropriate; consult suitable scholarship or cultural reviewers before choosing the visual form. |",
        "| `ART_APPROVED` | Historical identity, crop, silhouette, legibility, and licence are approved. |",
        "| `RUNTIME_VERIFIED` | The approved asset passes atlas, map, accessibility, performance, credit, and export tests. |",
        "| `COMPLETE` | Evidence, art, runtime, attribution, reviewer, and review date are all recorded. |",
        "| `APPROVED_NO_MARKER` | Review concluded that no country shield should be displayed; the alternative presentation is documented. |",
        "| `DEPRECATED_TAG` | The tag cannot appear in release content and therefore requires no player-facing shield. |",
        "",
        "## Durable record locations",
        "",
        "This generated Markdown is the readable report, not the editable source of truth. After a year away, rebuild it and it will recover the current registry, scenario state, research lanes, and reviewed sources from:",
        "",
        "- `tools/marker_art/historical_flag_sources.json` — selected source artwork, evidence class, and research warning.",
        "- `tools/marker_art/shield_research_reviews.json` — manual progress, researcher, dates, candidate links, decision outcome, and notes.",
        "- `assets/marker_art/source_flags/source_manifest.json` — downloaded source, licence, attribution, URLs, and content hash.",
        "- `assets/country_registry.json`, country history files, and `docs/data/1444_ownership_manifest.csv` — tag identity, active status, government, culture, religion, technology group, and starting authority.",
        "",
        "Never record progress only by editing this generated Markdown; the next rebuild will replace it. Update the review tracker or source configuration, then regenerate the report.",
        "",
        "## Definition of complete for one country",
        "",
        "A country is not complete merely because an image was found. Its record must contain:",
        "",
        "1. The represented object: flag, banner, arms, seal, coin, tamga, standard, civic emblem, or approved non-shield identity.",
        "2. The historical bearer: ruler, dynasty, polity, city, order, office, clan, confederation, or community.",
        "3. A date or defensible date range and an explanation of its relationship to the game's relevant start/formation date.",
        "4. At least one source page and, for final approval, a reliable historical reference beyond an unattributed modern flag gallery.",
        "5. Licence, creator/attribution, redistribution requirements, and a local content hash.",
        "6. A written uncertainty note distinguishing contemporary evidence, reconstruction, tradition, or later representative arms.",
        "7. Historian/content-reviewer name and review date.",
        "8. Final art approval and an in-engine screenshot at strategic and regional zoom.",
        "9. Runtime atlas, accessibility, performance, export, and third-party-notice verification.",
        "",
        "## Meaning of ‘real’ in this register",
        "",
        "The sourced list contains openly licensed historical banners, royal standards, civic flags, dynastic arms, manuscript details, or explicit reconstructions. It does **not** mean every image is proven to be the exact flag flown on 11 November 1444. Read the evidence class and review note before treating an entry as final.",
        "",
        f"- Canonical country tags: **{len(countries)}**",
        f"- Source-backed shield identities: **{len(sourced_tags)}**",
        f"- Active 1444 countries still requiring research: **{len(missing_active)}**",
        f"- Inactive, releasable, formable, or otherwise non-starting tags still requiring research: **{len(missing_inactive)}**",
        "- Unsourced atlas slots are transparent; the game does not display invented country heraldry.",
        "",
        "## Research-lane summary",
        "",
        "| Research lane | Active missing | Non-starting missing | Required identity family |",
        "|---|---:|---:|---|",
    ]
    for lane in lane_order:
        active_count = sum(research_lane(tag) == lane for tag in missing_active)
        inactive_count = sum(research_lane(tag) == lane for tag in missing_inactive)
        example = next((tag for tag in (*missing_active, *missing_inactive) if research_lane(tag) == lane), None)
        target = required_deliverable(example, bool(example and countries[example]["active_in_1444_manifest"])) if example else "No unresolved tags."
        lines.append(f"| {lane} | {active_count} | {inactive_count} | {markdown_cell(target)} |")
    lines.extend([
        "",
        "## Source-backed shields currently available — status `CANDIDATE_IMPORTED`",
        "",
        "These 39 entries are usable research candidates, not automatically final. Every one still needs the complete approval checklist above.",
        "",
        "| Tag | Country | Government | Evidence class | Source artwork | Licence | Current status | Review note |",
        "|---|---|---|---|---|---|---|---|",
    ])
    for tag in sourced_tags:
        record = countries[tag]
        source = sources[tag]
        context = contexts[tag]
        source_link = f"[{markdown_cell(source['commons_file'])}]({source['description_url']})"
        lines.append(
            f"| `{tag}` | {markdown_cell(record['display_name'])} | `{markdown_cell(context['government'])}` | "
            f"`{markdown_cell(source['evidence'])}` | {source_link} | {markdown_cell(source['license'])} | `{current_status(tag)}` | {markdown_cell(source['review_note'])} |"
        )
    lines.extend([
        "",
        "## Priority 1 — active 1444 countries missing identity decisions",
        "",
        "These affect the starting map and must be resolved first. They are split by the type of evidence or cultural decision required.",
    ])
    for lane in lane_order:
        lane_tags = [tag for tag in missing_active if research_lane(tag) == lane]
        if not lane_tags:
            continue
        lines.extend([
            "",
            f"### {lane} — {len(lane_tags)} active tags",
            "",
            "| Tag | Country | Government | Tech group | Culture | Religion | Starting authority | Current status | Exact research deliverable |",
            "|---|---|---|---|---|---|---|---|---|",
        ])
        for tag in lane_tags:
            context = contexts[tag]
            lines.append(
                f"| `{tag}` | {markdown_cell(countries[tag]['display_name'])} | `{markdown_cell(context['government'])}` | "
                f"`{markdown_cell(context['technology_group'])}` | `{markdown_cell(context['culture'])}` | `{markdown_cell(context['religion'])}` | "
                f"`{markdown_cell(context['authority'])}` | `{current_status(tag)}` | {markdown_cell(required_deliverable(tag, True))} |"
            )
    lines.extend([
        "",
        "## Priority 2 — non-starting, releasable, and formable tags",
        "",
        "These are not excused from research in a complete game. They are scheduled second because their correct visual identity may depend on the date and conditions under which the tag forms or is released.",
    ])
    for lane in lane_order:
        lane_tags = [tag for tag in missing_inactive if research_lane(tag) == lane]
        if not lane_tags:
            continue
        lines.extend([
            "",
            f"### {lane} — {len(lane_tags)} non-starting tags",
            "",
            "| Tag | Country | Government | Tech group | Culture | Religion | Current status | Exact research deliverable |",
            "|---|---|---|---|---|---|---|---|",
        ])
        for tag in lane_tags:
            context = contexts[tag]
            lines.append(
                f"| `{tag}` | {markdown_cell(countries[tag]['display_name'])} | `{markdown_cell(context['government'])}` | "
                f"`{markdown_cell(context['technology_group'])}` | `{markdown_cell(context['culture'])}` | `{markdown_cell(context['religion'])}` | "
                f"`{current_status(tag)}` | {markdown_cell(required_deliverable(tag, False))} |"
            )
    lines.extend([
        "",
        "## Advancing a country from research to complete",
        "",
        "1. Start with the exact deliverable in that country's row.",
        "2. Record status, candidate links, represented object, bearer, dates, evidence quality, uncertainty, researcher, and research date in `tools/marker_art/shield_research_reviews.json`.",
        "3. Add the selected Commons filename, evidence class, and review note to `tools/marker_art/historical_flag_sources.json`.",
        "4. Run `python tools/marker_art/build_marker_assets.py --fetch-sources` to move it to `CANDIDATE_IMPORTED`.",
        "5. Complete historical/cultural review, final art approval, runtime verification, attribution, reviewer, and review date before marking it `COMPLETE` in production tracking.",
        "6. Run `python tools/marker_art/build_marker_assets.py`, the marker contract, live visual tests, performance probe, and export gate.",
        "",
    ])
    return "\n".join(lines)


def contrasting_colour(rgb: tuple[int, int, int], seed: bytes) -> tuple[int, int, int]:
    channel_shift = seed[0] % 3
    values = list(rgb)
    for index in range(3):
        source = values[(index + channel_shift) % 3]
        values[index] = max(24, min(232, 255 - source + (seed[index + 1] % 35) - 17))
    return tuple(values)


def draw_fallback_flag(tag: str, name: str, political: tuple[int, int, int]) -> Image.Image:
    seed = hashlib.sha256(f"{tag}:{name}".encode("utf-8")).digest()
    scale = 4
    image = Image.new("RGBA", (96 * scale, 72 * scale), (*political, 255))
    draw = ImageDraw.Draw(image)

    def box(values: tuple[float, float, float, float]) -> tuple[int, int, int, int]:
        return tuple(round(value * scale) for value in values)

    def polygon(values: tuple[tuple[float, float], ...]) -> tuple[tuple[int, int], ...]:
        return tuple((round(x * scale), round(y * scale)) for x, y in values)

    secondary = contrasting_colour(political, seed)
    tertiary = tuple((left + right) // 2 for left, right in zip(political, secondary))
    pattern = seed[4] % 7
    if pattern == 0:
        draw.rectangle(box((0, 0, 95, 35)), fill=(*secondary, 255))
    elif pattern == 1:
        draw.rectangle(box((0, 0, 31, 71)), fill=(*secondary, 255))
        draw.rectangle(box((64, 0, 95, 71)), fill=(*tertiary, 255))
    elif pattern == 2:
        draw.rectangle(box((41, 0, 54, 71)), fill=(*secondary, 255))
        draw.rectangle(box((0, 29, 95, 42)), fill=(*secondary, 255))
        draw.rectangle(box((45, 0, 50, 71)), fill=(242, 226, 177, 210))
        draw.rectangle(box((0, 33, 95, 38)), fill=(242, 226, 177, 210))
    elif pattern == 3:
        draw.polygon(polygon(((0, 0), (26, 0), (96, 54), (96, 72), (70, 72), (0, 18))), fill=(*secondary, 255))
        draw.polygon(polygon(((70, 0), (96, 0), (96, 18), (26, 72), (0, 72), (0, 54))), fill=(*secondary, 255))
    elif pattern == 4:
        draw.rectangle(box((0, 0, 47, 35)), fill=(*secondary, 255))
        draw.rectangle(box((48, 36, 95, 71)), fill=(*secondary, 255))
    elif pattern == 5:
        draw.polygon(polygon(((0, 0), (48, 36), (0, 72))), fill=(*secondary, 255))
    else:
        draw.rectangle(box((0, 24, 95, 47)), fill=(*secondary, 255))
    charge = seed[5] % 5
    outline = (28, 24, 20, 235)
    fill = (242, 220, 152, 255)
    if charge == 0:
        draw.ellipse(box((34, 22, 62, 50)), fill=fill, outline=outline, width=4 * scale)
    elif charge == 1:
        draw.polygon(polygon(((48, 16), (61, 35), (48, 56), (35, 35))), fill=fill, outline=outline)
    elif charge == 2:
        points = []
        for point in range(10):
            angle = -math.pi / 2 + point * math.pi / 5
            radius = 19 if point % 2 == 0 else 8
            points.append((round((48 + math.cos(angle) * radius) * scale), round((36 + math.sin(angle) * radius) * scale)))
        draw.polygon(points, fill=fill, outline=outline)
    elif charge == 3:
        draw.ellipse(box((30, 27, 46, 43)), fill=fill, outline=outline, width=3 * scale)
        draw.ellipse(box((50, 27, 66, 43)), fill=fill, outline=outline, width=3 * scale)
    else:
        draw.polygon(polygon(((48, 15), (67, 52), (29, 52))), fill=fill, outline=outline)
    return image


def shield_from_flag(flag: Image.Image) -> Image.Image:
    render_size = SHIELD_TILE * SHIELD_RENDER_SUPERSAMPLE
    scale = render_size / 64.0

    def point(x: float, y: float) -> tuple[int, int]:
        return round(x * scale), round(y * scale)

    tile = Image.new("RGBA", (render_size, render_size), (0, 0, 0, 0))
    outer_points = tuple(point(x, y) for x, y in ((6, 5), (58, 5), (58, 38), (32, 61), (6, 38)))
    inner_points = tuple(point(x, y) for x, y in ((10, 9), (54, 9), (54, 36), (32, 56), (10, 36)))
    shadow = Image.new("L", tile.size, 0)
    shadow_offset = round(2 * scale)
    ImageDraw.Draw(shadow).polygon(tuple((x + shadow_offset, y + shadow_offset) for x, y in outer_points), fill=190)
    shadow = shadow.filter(ImageFilter.GaussianBlur(2.0 * scale))
    shadow_layer = Image.new("RGBA", tile.size, (0, 0, 0, 150))
    shadow_layer.putalpha(shadow)
    tile.alpha_composite(shadow_layer)
    draw = ImageDraw.Draw(tile)
    draw.polygon(outer_points, fill=(37, 29, 22, 255))
    draw.line((*outer_points, outer_points[0]), fill=(210, 174, 88, 255), width=max(1, round(2 * scale)), joint="curve")
    mask = Image.new("L", tile.size, 0)
    ImageDraw.Draw(mask).polygon(inner_points, fill=255)
    fitted = ImageOps.fit(flag.convert("RGBA"), (round(44 * scale), round(47 * scale)), method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))
    flag_layer = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    flag_layer.alpha_composite(fitted, point(10, 9))
    flag_layer.putalpha(mask)
    tile.alpha_composite(flag_layer)
    # Restrained painted highlight and lower-edge shade keep the placeholder
    # readable without copying another game's proprietary shield material.
    sheen = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    sheen_draw = ImageDraw.Draw(sheen)
    sheen_draw.polygon(tuple(point(x, y) for x, y in ((11, 10), (53, 10), (53, 21), (11, 30))), fill=(255, 255, 255, 28))
    sheen_draw.polygon(tuple(point(x, y) for x, y in ((10, 35), (32, 55), (54, 35), (54, 42), (32, 58), (10, 42))), fill=(0, 0, 0, 30))
    sheen.putalpha(ImageChops.multiply(sheen.getchannel("A"), mask))
    tile.alpha_composite(sheen)
    return tile.resize((SHIELD_TILE, SHIELD_TILE), Image.Resampling.LANCZOS)


def line(draw: ImageDraw.ImageDraw, points: list[tuple[float, float]], fill: tuple[int, int, int, int], width: int) -> None:
    draw.line(points, fill=fill, width=width, joint="curve")


def marker_icon(name: str) -> Image.Image:
    image = Image.new("RGBA", (ICON_TILE, ICON_TILE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    dark = (25, 21, 18, 255)
    light = (245, 232, 194, 255)
    gold = (217, 170, 67, 255)

    def stroked_line(points: list[tuple[float, float]], width: int = 12) -> None:
        line(draw, points, dark, width + 8)
        line(draw, points, light, width)

    if name == "battle":
        stroked_line([(31, 96), (93, 28)], 13)
        stroked_line([(35, 28), (97, 96)], 13)
        draw.ellipse((49, 49, 79, 79), fill=gold, outline=dark, width=6)
    elif name == "siege":
        draw.rounded_rectangle((25, 45, 103, 101), radius=7, fill=dark)
        draw.rectangle((33, 53, 95, 93), fill=light)
        for x in (29, 52, 75, 98):
            draw.rectangle((x - 8, 30, x + 8, 58), fill=dark)
            draw.rectangle((x - 4, 35, x + 4, 55), fill=light)
        draw.rounded_rectangle((54, 69, 74, 101), radius=8, fill=dark)
    elif name == "army":
        draw.polygon(((24, 29), (104, 29), (96, 86), (64, 108), (32, 86)), fill=dark)
        draw.polygon(((33, 38), (95, 38), (88, 80), (64, 98), (40, 80)), fill=light)
        stroked_line([(64, 46), (64, 85)], 7)
        stroked_line([(48, 62), (80, 62)], 7)
    elif name == "navy":
        draw.polygon(((20, 76), (108, 76), (91, 101), (37, 101)), fill=dark)
        draw.polygon(((31, 82), (97, 82), (85, 94), (43, 94)), fill=light)
        stroked_line([(64, 26), (64, 80)], 7)
        draw.polygon(((66, 30), (99, 58), (66, 58)), fill=gold, outline=dark)
    elif name == "capital":
        draw.polygon(((20, 55), (36, 30), (55, 53), (68, 24), (85, 53), (104, 31), (108, 92), (20, 92)), fill=dark)
        draw.polygon(((29, 58), (38, 44), (57, 65), (68, 41), (84, 65), (98, 46), (99, 83), (29, 83)), fill=gold)
    elif name == "fort":
        draw.rectangle((32, 42, 96, 102), fill=dark)
        draw.rectangle((41, 51, 87, 94), fill=light)
        for x in (35, 64, 93):
            draw.rectangle((x - 10, 26, x + 10, 55), fill=dark)
            draw.rectangle((x - 5, 33, x + 5, 51), fill=light)
    elif name == "port":
        stroked_line([(64, 23), (64, 96)], 8)
        draw.ellipse((52, 18, 76, 42), fill=light, outline=dark, width=6)
        stroked_line([(28, 66), (36, 89), (64, 104), (92, 89), (100, 66)], 8)
        stroked_line([(35, 65), (93, 65)], 8)
    elif name == "cluster":
        for x, y in ((48, 47), (80, 47), (64, 79)):
            draw.ellipse((x - 20, y - 20, x + 20, y + 20), fill=dark)
            draw.ellipse((x - 13, y - 13, x + 13, y + 13), fill=gold)
    elif name == "destination":
        draw.ellipse((25, 25, 103, 103), fill=dark)
        draw.ellipse((36, 36, 92, 92), fill=gold)
        draw.ellipse((51, 51, 77, 77), fill=dark)
    elif name == "invalid":
        stroked_line([(30, 30), (98, 98)], 14)
        stroked_line([(98, 30), (30, 98)], 14)
    return image


def build_outputs() -> tuple[dict[str, Any], Image.Image, Image.Image, Image.Image]:
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    countries: dict[str, dict[str, Any]] = registry["countries"]
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    source_manifest = json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8")) if SOURCE_MANIFEST.is_file() else {"sources": {}}
    sources: dict[str, dict[str, Any]] = source_manifest.get("sources", {})
    active = active_1444_tags()
    tags = sorted(countries)
    shield_rows = math.ceil(len(tags) / SHIELD_COLUMNS)
    shield_atlas = Image.new("RGBA", (SHIELD_COLUMNS * SHIELD_TILE, shield_rows * SHIELD_TILE), (0, 0, 0, 0))
    output_countries: dict[str, Any] = {}
    for index, tag in enumerate(tags):
        record = countries[tag]
        source = sources.get(tag)
        if source:
            source_path = ROOT / source["asset_path"].removeprefix("res://")
            data = source_path.read_bytes()
            if sha256_bytes(data) != source["sha256"]:
                raise RuntimeError(f"Historical flag source hash is stale for {tag}")
            flag = Image.open(io.BytesIO(data)).convert("RGBA")
            shield = shield_from_flag(flag)
            status = "sourced_open_historical_placeholder"
        else:
            # Preserve the stable atlas coordinate without displaying invented
            # country heraldry. A reviewed source can fill this slot later.
            shield = Image.new("RGBA", (SHIELD_TILE, SHIELD_TILE), (0, 0, 0, 0))
            status = "unassigned_requires_historical_research"
        x = (index % SHIELD_COLUMNS) * SHIELD_TILE
        y = (index // SHIELD_COLUMNS) * SHIELD_TILE
        shield_atlas.alpha_composite(shield, (x, y))
        output_countries[tag] = {
            "atlas_index": index,
            "atlas_cell": [index % SHIELD_COLUMNS, index // SHIELD_COLUMNS],
            "display_name": record["display_name"],
            "active_in_1444_manifest": tag in active,
            "status": status,
            "source": source or {
                "evidence": "none_configured",
                "review_note": "Transparent atlas slot. No invented shield is displayed; historical research is required.",
            },
        }

    icon_rows = math.ceil(len(ICON_NAMES) / ICON_COLUMNS)
    icon_atlas = Image.new("RGBA", (ICON_COLUMNS * ICON_TILE, icon_rows * ICON_TILE), (0, 0, 0, 0))
    icons: dict[str, Any] = {}
    icon_images: dict[str, Image.Image] = {}
    for index, name in enumerate(ICON_NAMES):
        icon = marker_icon(name)
        icon_images[name] = icon
        x = (index % ICON_COLUMNS) * ICON_TILE
        y = (index // ICON_COLUMNS) * ICON_TILE
        icon_atlas.alpha_composite(icon, (x, y))
        icons[name] = {"atlas_index": index, "atlas_cell": [index % ICON_COLUMNS, index // ICON_COLUMNS]}

    sample_tags = [tag for tag in ("ENG", "FRA", "CAS", "ARA", "POR", "SCO", "BUR", "HAB", "POL", "LIT", "HUN", "BOH", "BYZ", "TIM", "MAM", "MLO", "LAN", "SIE", "TEU", "SER", "WAL", "MOL", "CRI", "MOS", "NOV", "ORL", "VEN", "PAP", "GRA", "QAR", "SWE") if tag in output_countries]
    sheet = Image.new("RGBA", (1024, 800), (28, 31, 34, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((28, 18), "GRAND WORLD - HISTORICAL PLACEHOLDER SHIELDS", fill=(238, 225, 191, 255))
    for sample_index, tag in enumerate(sample_tags):
        atlas_index = output_countries[tag]["atlas_index"]
        source_box = ((atlas_index % SHIELD_COLUMNS) * SHIELD_TILE, (atlas_index // SHIELD_COLUMNS) * SHIELD_TILE, (atlas_index % SHIELD_COLUMNS + 1) * SHIELD_TILE, (atlas_index // SHIELD_COLUMNS + 1) * SHIELD_TILE)
        shield = shield_atlas.crop(source_box).resize((96, 96), Image.Resampling.LANCZOS)
        col, row = sample_index % 9, sample_index // 9
        px, py = 24 + col * 110, 56 + row * 142
        sheet.alpha_composite(shield, (px, py))
        draw.text((px + 30, py + 99), tag, fill=(238, 225, 191, 255))
    icon_y = 670
    for index, name in enumerate(ICON_NAMES):
        icon = icon_images[name].resize((72, 72), Image.Resampling.LANCZOS)
        px = 22 + index * 98
        sheet.alpha_composite(icon, (px, icon_y))
        draw.text((px + 3, icon_y + 76), name, fill=(211, 199, 168, 255))

    manifest = {
        "schema_version": 1,
        "generator": "tools/marker_art/build_marker_assets.py",
        "art_direction": "Original early-modern painted cartographic placeholders inspired by grand-strategy information hierarchy; no proprietary game assets used.",
        "replacement_policy": "Only source-backed country shields are displayed. Unsourced slots remain transparent until reviewed historical artwork is added. Preserve atlas indices or regenerate the manifest when final art arrives.",
        "country_count": len(output_countries),
        "active_1444_country_count": len(active),
        "sourced_historical_placeholder_count": sum(record["status"].startswith("sourced") for record in output_countries.values()),
        "generated_fallback_count": 0,
        "unassigned_research_required_count": sum(record["status"].startswith("unassigned") for record in output_countries.values()),
        "shield_atlas": {"path": "res://assets/marker_art/generated/country_shield_atlas.png", "tile_size": SHIELD_TILE, "columns": SHIELD_COLUMNS, "rows": shield_rows, "render_supersample": SHIELD_RENDER_SUPERSAMPLE},
        "icon_atlas": {"path": "res://assets/marker_art/generated/marker_icon_atlas.png", "tile_size": ICON_TILE, "columns": ICON_COLUMNS, "rows": icon_rows},
        "icons": icons,
        "countries": output_countries,
    }
    return manifest, shield_atlas, icon_atlas, sheet


def image_bytes(image: Image.Image) -> bytes:
    stream = io.BytesIO()
    image.save(stream, format="PNG", optimize=True)
    return stream.getvalue()


def main() -> int:
    args = parse_args()
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    if args.fetch_sources:
        fetch_sources(config)
    if not SOURCE_MANIFEST.is_file():
        print("Historical source manifest is missing; run with --fetch-sources.", file=sys.stderr)
        return 1
    manifest, shield_atlas, icon_atlas, contact_sheet = build_outputs()
    expected = {
        ASSET_MANIFEST: stable_json(manifest).encode("utf-8"),
        SHIELD_ATLAS: image_bytes(shield_atlas),
        ICON_ATLAS: image_bytes(icon_atlas),
        CONTACT_SHEET: image_bytes(contact_sheet),
        THIRD_PARTY_NOTICES: third_party_notices(json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))).encode("utf-8"),
        RESEARCH_REGISTER: shield_research_register(manifest, json.loads(SOURCE_MANIFEST.read_text(encoding="utf-8"))).encode("utf-8"),
    }
    for name in ICON_NAMES:
        expected[GENERATED_DIR / "icons" / f"{name}.png"] = image_bytes(marker_icon(name))
    if args.check:
        stale = [str(path.relative_to(ROOT)) for path, data in expected.items() if not path.is_file() or path.read_bytes() != data]
        if stale:
            print("Marker assets are stale: " + ", ".join(stale), file=sys.stderr)
            return 1
        print(f"Marker assets are valid and current. countries={manifest['country_count']} sourced={manifest['sourced_historical_placeholder_count']} transparent={manifest['unassigned_research_required_count']}")
        return 0
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)
    CONTACT_SHEET.parent.mkdir(parents=True, exist_ok=True)
    for path, data in expected.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(f"Wrote marker assets. countries={manifest['country_count']} sourced={manifest['sourced_historical_placeholder_count']} transparent={manifest['unassigned_research_required_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
