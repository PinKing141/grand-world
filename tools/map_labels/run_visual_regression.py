#!/usr/bin/env python3
"""Capture and compare the GPU-rendered country-label reference views."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / "tests" / "baselines" / "country_label_renders"
CAPTURE_SCRIPT = "res://tests/country_label_render_capture.gd"
EXPECTED = (
    "default_1700x960.png",
    "dense_europe_1700x960.png",
    "island_southeast_asia_1152x648.png",
    "scandinavia_shape_1152x648.png",
    "italian_peninsula_shape_1152x648.png",
)
MAX_MEAN_CHANNEL_ERROR = 2.0
MAX_CHANGED_PIXEL_RATIO = 0.025
CHANGED_PIXEL_THRESHOLD = 12


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, help="Godot console executable")
    parser.add_argument("--update", action="store_true", help="Replace the rendered baselines")
    return parser.parse_args()


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
    candidates.extend(sorted(documents.glob("Godot_v*-stable*_win64/Godot*_console.exe"), reverse=True))
    for candidate in candidates:
        resolved = candidate.expanduser().resolve()
        if resolved.is_file():
            return resolved
    raise FileNotFoundError("Godot not found; pass --godot or set GODOT_BIN")


def capture(godot: Path, output: Path) -> None:
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
        timeout=180,
        check=False,
    )
    combined = "\n".join(value for value in (completed.stdout, completed.stderr) if value)
    if completed.returncode != 0 or "Country label rendered captures completed." not in combined:
        raise RuntimeError(f"Godot capture failed ({completed.returncode}):\n{combined[-5000:]}")
    for name in EXPECTED:
        if not (output / name).is_file():
            raise RuntimeError(f"Godot capture omitted {name}")


def compare(expected_path: Path, actual_path: Path) -> tuple[float, float]:
    expected = np.asarray(Image.open(expected_path).convert("RGB"), dtype=np.int16)
    actual = np.asarray(Image.open(actual_path).convert("RGB"), dtype=np.int16)
    if expected.shape != actual.shape:
        raise RuntimeError(f"{expected_path.name} changed size: {expected.shape} -> {actual.shape}")
    difference = np.abs(expected - actual)
    mean_error = float(difference.mean())
    changed_ratio = float(np.mean(np.max(difference, axis=2) > CHANGED_PIXEL_THRESHOLD))
    return mean_error, changed_ratio


def main() -> int:
    args = parse_args()
    try:
        godot = find_godot(args.godot)
        if args.update:
            BASELINE.mkdir(parents=True, exist_ok=True)
            capture(godot, BASELINE)
            print(f"Updated country label render baselines in {BASELINE.relative_to(ROOT)}")
            return 0
        if any(not (BASELINE / name).is_file() for name in EXPECTED):
            raise RuntimeError("render baselines are missing; run this tool with --update")
        with tempfile.TemporaryDirectory(prefix="grand-world-label-render-") as raw_temp:
            output = Path(raw_temp)
            capture(godot, output)
            for name in EXPECTED:
                mean_error, changed_ratio = compare(BASELINE / name, output / name)
                if mean_error > MAX_MEAN_CHANNEL_ERROR or changed_ratio > MAX_CHANGED_PIXEL_RATIO:
                    raise RuntimeError(
                        f"{name} differs: mean channel error={mean_error:.3f} "
                        f"changed pixels={changed_ratio:.3%}"
                    )
                print(f"{name}: mean={mean_error:.3f}, changed={changed_ratio:.3%}")
        print("Country label rendered visual regression passed.")
        return 0
    except (FileNotFoundError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"Country label rendered visual regression failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
