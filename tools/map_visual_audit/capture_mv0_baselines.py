#!/usr/bin/env python3
"""Capture the current MV-0 map-only benchmark views through Forward+."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "tests" / "baselines" / "map_visual_mv0" / "current"
CAPTURE_SCRIPT = "res://tests/map_visual_mv0_capture.gd"
EXPECTED = {
    "current_world_political_1920x1080.png": (1920, 1080),
    "current_france_low_countries_political_1920x1080.png": (1920, 1080),
    "current_france_low_countries_terrain_1920x1080.png": (1920, 1080),
    "current_france_low_countries_ids_1920x1080.png": (1920, 1080),
    "current_italy_alps_political_1152x648.png": (1152, 648),
    "current_scandinavia_baltic_terrain_1152x648.png": (1152, 648),
    "current_sahara_nile_terrain_1700x960.png": (1700, 960),
    "current_maritime_southeast_asia_political_1152x648.png": (1152, 648),
    "current_andes_terrain_1152x648.png": (1152, 648),
    "current_north_america_political_1152x648.png": (1152, 648),
}


def find_godot(explicit: Path | None) -> Path:
    candidates: list[Path] = []
    if explicit:
        candidates.append(explicit)
    if os.environ.get("GODOT_BIN"):
        candidates.append(Path(os.environ["GODOT_BIN"]))
    for name in ("godot", "godot4", "Godot_v4.7-stable_mono_win64_console.exe"):
        found = shutil.which(name)
        if found:
            candidates.append(Path(found))
    documents = Path.home() / "Documents"
    candidates.extend(sorted(documents.glob("Godot_v4.7-stable*_win64/Godot*_console.exe"), reverse=True))
    for candidate in candidates:
        resolved = candidate.expanduser().resolve()
        if resolved.is_file():
            return resolved
    raise FileNotFoundError("Godot 4.7 console executable not found; pass --godot or set GODOT_BIN")


def validate_output(output: Path) -> dict:
    for file_name, expected_size in EXPECTED.items():
        path = output / file_name
        if not path.is_file():
            raise RuntimeError(f"capture omitted {file_name}")
        with Image.open(path) as image:
            if image.size != expected_size:
                raise RuntimeError(f"{file_name} has size {image.size}; expected {expected_size}")
    manifest_path = output / "mv0_capture_manifest.json"
    if not manifest_path.is_file():
        raise RuntimeError("capture omitted mv0_capture_manifest.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1 or len(manifest.get("views", [])) != len(EXPECTED):
        raise RuntimeError("capture manifest is invalid or incomplete")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, help="Godot 4.7 console executable")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    try:
        godot = find_godot(args.godot)
        output = args.output_dir.expanduser().resolve()
        output.mkdir(parents=True, exist_ok=True)
        command = (
            str(godot),
            "--path",
            str(ROOT),
            "--script",
            CAPTURE_SCRIPT,
            "--",
            f"--output-dir={output}",
        )
        completed = subprocess.run(
            command,
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,
            check=False,
        )
        combined = "\n".join(value for value in (completed.stdout, completed.stderr) if value)
        if completed.returncode != 0 or "MV-0 map visual captures completed." not in combined:
            raise RuntimeError(f"Godot capture failed ({completed.returncode}):\n{combined[-8000:]}")
        manifest = validate_output(output)
        profile = manifest["camera_motion_profile"]
        print(f"Captured {len(EXPECTED)} MV-0 views in {output.relative_to(ROOT)}")
        print(
            "Camera motion: "
            f"frame interval P95={profile['frame_interval_ms_p95']:.3f} ms, "
            f"P99={profile['frame_interval_ms_p99']:.3f} ms, "
            f"max={profile['frame_interval_ms_max']:.3f} ms, "
            f"FPS P05={profile['fps_p05']:.1f}, "
            f">50 ms={profile['frames_over_50_ms']}/{profile['frames']}"
        )
        print("MV-0 map visual baseline capture passed.")
        return 0
    except (FileNotFoundError, RuntimeError, OSError, json.JSONDecodeError, subprocess.TimeoutExpired) as error:
        print(f"MV-0 map visual baseline capture failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
