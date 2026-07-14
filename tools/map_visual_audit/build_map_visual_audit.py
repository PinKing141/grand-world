#!/usr/bin/env python3
"""Build or validate the deterministic MV-0 map-visual asset/render audit."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "tools" / "map_visual_audit" / "map_asset_manifest.json"
OUTPUT_DIRECTORY = ROOT / "docs" / "roadmap" / "map_visual_production" / "mv0"
JSON_OUTPUT = OUTPUT_DIRECTORY / "mv0_asset_render_audit.json"
MARKDOWN_OUTPUT = OUTPUT_DIRECTORY / "MV0_ASSET_RENDER_AUDIT.md"

PROJECT_PATH = ROOT / "project.godot"
SCENE_PATH = ROOT / "scenes" / "main.tscn"
SHADER_PATHS = (
    ROOT / "shaders" / "final_output_political_map.gdshader",
    ROOT / "shaders" / "political_map.gdshader",
    ROOT / "shaders" / "province_sdf.gdshader",
    ROOT / "shaders" / "country_sdf.gdshader",
)

MAP_ASSET_PATHS = (
    "assets/provinces.bmp",
    "assets/definition.csv",
    "assets/biome_map.png",
    "assets/terrain_class_map.png",
    "assets/terrain_base_map.png",
    "assets/heightmap.png",
    "assets/colormap_water.png",
    "assets/color_lookup_map.png",
    "assets/color_map.png",
    "assets/mask_political_map.png",
    "assets/label_territory_map.png",
    "assets/noise.tres",
    "assets/fonts/LibreBaskerville-Variable.ttf",
)

EXPECTED_PRESENTATION_LAYERS = (
    ("normal_map", ("normal",)),
    ("river_data_or_texture", ("river",)),
    ("coastal_shelf_or_foam_mask", ("coast", "bathym", "foam")),
    ("vegetation_mask_or_object_data", ("vegetation", "forest", "tree")),
    ("seasonal_presentation_asset", ("season", "winter", "snow_mask")),
    ("roughness_or_material_parameter_map", ("roughness", "material_map")),
)

DATA_TEXTURES = {
    "assets/provinces.bmp",
    "assets/color_lookup_map.png",
    "assets/color_map.png",
    "assets/mask_political_map.png",
    "assets/terrain_class_map.png",
    "assets/label_territory_map.png",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_scalar(value: str) -> Any:
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    try:
        return int(value)
    except ValueError:
        try:
            return float(value)
        except ValueError:
            return value.strip('"')


def parse_import(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    values: dict[str, Any] = {}
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("[") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.startswith(("compress/", "mipmaps/", "process/", "detect_3d/")):
            values[key] = parse_scalar(value)
    return values


def image_metadata(path: Path) -> dict[str, Any]:
    with Image.open(path) as image:
        return {
            "width": image.width,
            "height": image.height,
            "mode": image.mode,
            "format": image.format,
        }


def load_manifest() -> dict[str, Any]:
    data = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("assets"), dict):
        raise ValueError("map asset manifest must use schema version 1 and contain an assets object")
    return data


def project_settings() -> dict[str, Any]:
    wanted = {
        "config/features",
        "display/window/size/viewport_width",
        "display/window/size/viewport_height",
        "rendering/renderer/rendering_method",
        "rendering/renderer/rendering_method.mobile",
        "rendering/rendering_device/driver.windows",
        "rendering/viewport/hdr_2d",
        "rendering/anti_aliasing/quality/msaa_3d",
        "rendering/anti_aliasing/quality/screen_space_aa",
        "rendering/anti_aliasing/quality/use_taa",
        "rendering/scaling_3d/mode",
        "rendering/scaling_3d/scale",
    }
    section = ""
    found: dict[str, Any] = {}
    for raw_line in PROJECT_PATH.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if not line or line.startswith(";") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        qualified = f"{section}/{key}"
        if qualified in wanted or key in wanted:
            found[qualified if qualified in wanted else key] = parse_scalar(value)
    for key in sorted(wanted):
        found.setdefault(key, "<engine default>")
    return dict(sorted(found.items()))


def scene_render_facts() -> dict[str, Any]:
    text = SCENE_PATH.read_text(encoding="utf-8", errors="replace")
    facts: dict[str, Any] = {}
    patterns = {
        "plane_size": r'\[sub_resource type="PlaneMesh" id="PlaneMesh_terrain"\][\s\S]*?^size = (Vector2\([^\n]+\))',
        "plane_subdivide_width": r'\[sub_resource type="PlaneMesh" id="PlaneMesh_terrain"\][\s\S]*?^subdivide_width = ([^\n]+)',
        "plane_subdivide_depth": r'\[sub_resource type="PlaneMesh" id="PlaneMesh_terrain"\][\s\S]*?^subdivide_depth = ([^\n]+)',
        "camera_controller_transform": r'\[node name="CameraController"[^\]]*\]\s*transform = ([^\n]+)',
        "political_edge_size": r'shader_parameter/edge_size = ([^\n]+)',
        "province_edge_size": r'shader_parameter/province_size_size = ([^\n]+)',
        "province_border_color": r'shader_parameter/province_border_color = ([^\n]+)',
    }
    for key, pattern in patterns.items():
        match = re.search(pattern, text, flags=re.MULTILINE)
        facts[key] = match.group(1).strip() if match else "<not found>"
    facts["subviewport_count"] = len(re.findall(r'\[node name="[^"]+" type="SubViewport"', text))
    facts["shader_parameter_count"] = len(re.findall(r'^shader_parameter/', text, flags=re.MULTILINE))
    return facts


def shader_metadata(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    uniforms = []
    for match in re.finditer(r'^uniform\s+([^\s]+)\s+([^\s:;]+)', text, flags=re.MULTILINE):
        uniforms.append({"type": match.group(1), "name": match.group(2)})
    render_mode = re.search(r'^render_mode\s+([^;]+);', text, flags=re.MULTILINE)
    shader_type = re.search(r'^shader_type\s+([^;]+);', text, flags=re.MULTILINE)
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "sha256": sha256(path),
        "line_count": len(text.splitlines()),
        "shader_type": shader_type.group(1) if shader_type else "<not declared>",
        "render_mode": render_mode.group(1) if render_mode else "<not declared>",
        "uniform_count": len(uniforms),
        "sampler_count": sum(1 for uniform in uniforms if uniform["type"].startswith("sampler")),
        "uniforms": uniforms,
    }


def asset_record(relative: str, manifest_record: dict[str, Any]) -> dict[str, Any]:
    path = ROOT / relative
    record: dict[str, Any] = {
        "path": relative,
        **manifest_record,
        "exists": path.is_file(),
    }
    if not path.is_file():
        return record
    record["bytes"] = path.stat().st_size
    record["sha256"] = sha256(path)
    if path.suffix.lower() in {".png", ".bmp", ".jpg", ".jpeg", ".webp"}:
        record["image"] = image_metadata(path)
        record["import"] = parse_import(Path(f"{path}.import"))
    return record


def build_audit() -> dict[str, Any]:
    manifest = load_manifest()
    manifest_assets = manifest["assets"]
    missing_manifest = sorted(set(MAP_ASSET_PATHS) - set(manifest_assets))
    extra_manifest = sorted(set(manifest_assets) - set(MAP_ASSET_PATHS))
    if missing_manifest or extra_manifest:
        raise ValueError(
            f"manifest mismatch; missing={missing_manifest or 'none'} extra={extra_manifest or 'none'}"
        )

    assets = [asset_record(relative, manifest_assets[relative]) for relative in MAP_ASSET_PATHS]
    all_asset_files = [
        path.relative_to(ROOT).as_posix().lower()
        for path in (ROOT / "assets").rglob("*")
        if path.is_file()
        and not path.name.endswith(".import")
        and path.suffix.lower() in {".png", ".bmp", ".jpg", ".jpeg", ".webp", ".json", ".csv", ".tres"}
    ]
    expected_layers = []
    for layer, tokens in EXPECTED_PRESENTATION_LAYERS:
        matches = sorted(path for path in all_asset_files if any(token in path for token in tokens))
        expected_layers.append({"layer": layer, "present": bool(matches), "matches": matches})

    findings: list[dict[str, str]] = []
    by_path = {asset["path"]: asset for asset in assets}

    for asset in assets:
        if not asset["exists"]:
            findings.append({"priority": "P0", "id": "missing_asset", "message": f"Missing required asset {asset['path']}."})
        if asset.get("licence_status") in {"unverified", "inherits_unverified"}:
            findings.append({
                "priority": "P1",
                "id": "provenance",
                "message": f"{asset['path']} has licence status {asset['licence_status']}: {asset['review_note']}",
            })

    for relative in sorted(DATA_TEXTURES):
        asset = by_path[relative]
        settings = asset.get("import", {})
        if settings.get("compress/mode") not in (None, 0):
            findings.append({
                "priority": "P1",
                "id": "data_texture_compression",
                "message": f"{relative} is categorical/ID data but uses compress/mode={settings.get('compress/mode')}; validate a lossless import path.",
            })
        if settings.get("mipmaps/generate") is True:
            findings.append({
                "priority": "P1",
                "id": "data_texture_mipmaps",
                "message": f"{relative} is categorical/ID data but generates mipmaps; validate that distant sampling cannot blend semantic classes.",
            })

    height_settings = by_path["assets/heightmap.png"].get("import", {})
    if height_settings.get("compress/mode") not in (None, 0):
        findings.append({
            "priority": "P1",
            "id": "height_compression",
            "message": "assets/heightmap.png drives geometry but uses a compressed import path; compare displacement error and memory before locking settings.",
        })

    province_image = by_path["assets/provinces.bmp"].get("image", {})
    province_size = (province_image.get("width", 0), province_image.get("height", 0))
    for relative in ("assets/heightmap.png", "assets/terrain_base_map.png", "assets/colormap_water.png"):
        image = by_path[relative].get("image", {})
        size = (image.get("width", 0), image.get("height", 0))
        if size != province_size:
            findings.append({
                "priority": "P2",
                "id": "resolution_tier",
                "message": f"{relative} is {size[0]}x{size[1]} while province authority is {province_size[0]}x{province_size[1]}; approve this fidelity tier through MV-0 captures.",
            })

    for layer in expected_layers:
        if not layer["present"]:
            findings.append({
                "priority": "P2",
                "id": "missing_presentation_layer",
                "message": f"No candidate asset was found for planned layer {layer['layer']}.",
            })

    settings = project_settings()
    if all(settings[key] == "<engine default>" for key in (
        "rendering/anti_aliasing/quality/msaa_3d",
        "rendering/anti_aliasing/quality/screen_space_aa",
        "rendering/anti_aliasing/quality/use_taa",
    )):
        findings.append({
            "priority": "P1",
            "id": "anti_aliasing_default",
            "message": "No explicit project anti-aliasing policy is recorded; MV-0 must capture and lock the chosen border/terrain/text strategy.",
        })

    findings.append({
        "priority": "P1",
        "id": "hard_coded_geometry",
        "message": "The 56.32x20.48 map extent is duplicated in scene/camera/label code; RP-1.2 and CL-6.1 require one map transform authority.",
    })

    return {
        "schema_version": 1,
        "purpose": "MV-0 deterministic map visual asset and render baseline",
        "assets": assets,
        "expected_presentation_layers": expected_layers,
        "project_settings": settings,
        "scene_render_facts": scene_render_facts(),
        "shaders": [shader_metadata(path) for path in SHADER_PATHS],
        "findings": sorted(findings, key=lambda item: (item["priority"], item["id"], item["message"])),
    }


def markdown(audit: dict[str, Any]) -> str:
    assets = audit["assets"]
    findings = audit["findings"]
    priorities = Counter(finding["priority"] for finding in findings)
    licence_counts = Counter(asset["licence_status"] for asset in assets)
    lines = [
        "# MV-0 Asset and Render Audit",
        "",
        "**Status:** Generated baseline; open findings require milestone decisions  ",
        "**Generator:** `python tools/map_visual_audit/build_map_visual_audit.py`  ",
        "**Stale check:** `python tools/map_visual_audit/build_map_visual_audit.py --check`",
        "",
        "## Executive Summary",
        "",
        f"The audit tracks **{len(assets)}** required map assets, **{len(audit['shaders'])}** active map shaders, and **{len(findings)}** findings. "
        f"Finding distribution: P0={priorities.get('P0', 0)}, P1={priorities.get('P1', 0)}, P2={priorities.get('P2', 0)}.",
        "",
        "This is a technical and provenance baseline, not an approval. It deliberately records risky import settings and missing presentation layers without changing runtime output before the MV-0 comparison spikes.",
        "",
        "## Required Asset Inventory",
        "",
        "| Asset | Role | Dimensions/format | Import summary | Licence/provenance |",
        "|---|---|---|---|---|",
    ]
    for asset in assets:
        image = asset.get("image")
        dimensions = "n/a"
        if image:
            dimensions = f"{image['width']}×{image['height']} {image['format']}/{image['mode']}"
        settings = asset.get("import", {})
        import_summary = "n/a"
        if settings:
            import_summary = (
                f"compression={settings.get('compress/mode', '?')}; "
                f"mipmaps={settings.get('mipmaps/generate', '?')}"
            )
        lines.append(
            f"| `{asset['path']}` | {asset['role']} | {dimensions} | {import_summary} | `{asset['licence_status']}` |"
        )

    lines.extend([
        "",
        "## Provenance Summary",
        "",
        "| Status | Count |",
        "|---|---:|",
    ])
    for status, count in sorted(licence_counts.items()):
        lines.append(f"| `{status}` | {count} |")

    lines.extend([
        "",
        "The imported province topology, definition data, and water texture have no complete repository-level source/licence record. Every generated derivative that inherits those inputs remains unresolved for commercial distribution until the source is approved or replaced.",
        "",
        "## Render Configuration",
        "",
        "### Project settings",
        "",
        "| Setting | Value |",
        "|---|---|",
    ])
    for key, value in audit["project_settings"].items():
        lines.append(f"| `{key}` | `{value}` |")

    lines.extend([
        "",
        "### Scene facts",
        "",
        "| Fact | Value |",
        "|---|---|",
    ])
    for key, value in audit["scene_render_facts"].items():
        lines.append(f"| `{key}` | `{value}` |")

    lines.extend([
        "",
        "### Shader inventory",
        "",
        "| Shader | Type/mode | Lines | Uniforms | Samplers |",
        "|---|---|---:|---:|---:|",
    ])
    for shader in audit["shaders"]:
        lines.append(
            f"| `{shader['path']}` | `{shader['shader_type']}` / `{shader['render_mode']}` | "
            f"{shader['line_count']} | {shader['uniform_count']} | {shader['sampler_count']} |"
        )

    lines.extend([
        "",
        "## Planned Presentation-Layer Gaps",
        "",
        "| Layer | Candidate present | Matches |",
        "|---|---|---|",
    ])
    for layer in audit["expected_presentation_layers"]:
        matches = ", ".join(f"`{match}`" for match in layer["matches"]) or "None"
        lines.append(f"| `{layer['layer']}` | {'Yes' if layer['present'] else '**No**'} | {matches} |")

    lines.extend([
        "",
        "## Findings",
        "",
        "| Priority | Finding |",
        "|---|---|",
    ])
    for finding in findings:
        lines.append(f"| **{finding['priority']}** | {finding['message']} |")

    lines.extend([
        "",
        "## MV-0 Decisions Required",
        "",
        "1. Approve or replace the unverified province, definition, and water sources.",
        "2. Compare lossless categorical/height imports against the current compressed/mipmapped settings before changing them.",
        "3. Lock the anti-aliasing and texture-sampling policy using still and motion captures.",
        "4. Approve the half-resolution terrain/water/height tier or choose a higher/tiled strategy.",
        "5. Decide which missing normal, river, coast, vegetation, season, and material layers are required for 1.0.",
        "6. Replace duplicated map extents with one authoritative map transform during MV-1.",
        "",
        "## Reproduction",
        "",
        "The JSON beside this document contains full hashes, image metadata, import settings, shader uniforms, and deterministic finding records. Do not hand-edit either generated output; update the source manifest/tool and rebuild.",
        "",
    ])
    return "\n".join(lines)


def serialized_outputs(audit: dict[str, Any]) -> tuple[str, str]:
    json_text = json.dumps(audit, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    markdown_text = markdown(audit)
    return json_text, markdown_text


def check_output(path: Path, expected: str) -> bool:
    if not path.is_file():
        print(f"Missing generated audit output: {path.relative_to(ROOT)}", file=sys.stderr)
        return False
    actual = path.read_text(encoding="utf-8")
    if actual != expected:
        print(f"Stale generated audit output: {path.relative_to(ROOT)}", file=sys.stderr)
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if generated reports are missing or stale.")
    args = parser.parse_args()
    try:
        audit = build_audit()
        json_text, markdown_text = serialized_outputs(audit)
        if args.check:
            if check_output(JSON_OUTPUT, json_text) and check_output(MARKDOWN_OUTPUT, markdown_text):
                print("MV-0 map visual asset and render audit is valid and current.")
                return 0
            return 1
        OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
        JSON_OUTPUT.write_text(json_text, encoding="utf-8", newline="\n")
        MARKDOWN_OUTPUT.write_text(markdown_text, encoding="utf-8", newline="\n")
        print(f"Wrote {JSON_OUTPUT.relative_to(ROOT)}")
        print(f"Wrote {MARKDOWN_OUTPUT.relative_to(ROOT)}")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"MV-0 map visual audit failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
