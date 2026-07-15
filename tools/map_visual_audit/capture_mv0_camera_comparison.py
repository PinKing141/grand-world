#!/usr/bin/env python3
"""Capture and validate the MV-0 perspective/orthographic comparison."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from capture_mv0_baselines import ROOT, find_godot
from PIL import Image

DEFAULT_OUTPUT = ROOT / "tests" / "baselines" / "map_visual_mv0" / "camera_comparison"
SCRIPT = "res://tests/map_visual_mv0_camera_comparison.gd"
EXPECTED = ("france_perspective_75deg.png", "france_orthographic_matched.png")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    try:
        godot = find_godot(args.godot)
        output = args.output_dir.expanduser().resolve()
        output.mkdir(parents=True, exist_ok=True)
        completed = subprocess.run(
            (str(godot), "--path", str(ROOT), "--script", SCRIPT, "--", f"--output-dir={output}"),
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,
            check=False,
        )
        combined = "\n".join(value for value in (completed.stdout, completed.stderr) if value)
        if completed.returncode != 0 or "MV-0 camera comparison completed." not in combined:
            raise RuntimeError(f"Godot comparison failed ({completed.returncode}):\n{combined[-8000:]}")
        for name in EXPECTED:
            with Image.open(output / name) as image:
                if image.size != (1920, 1080):
                    raise RuntimeError(f"{name} is {image.size}, expected 1920x1080")
        report = json.loads((output / "camera_comparison.json").read_text(encoding="utf-8"))
        views = report.get("views", [])
        if [view.get("projection") for view in views] != ["perspective", "orthographic"]:
            raise RuntimeError("comparison report is incomplete")
        perspective, orthographic = views
        mismatch = abs(orthographic["measured_map_vertical_span"] - perspective["measured_map_vertical_span"])
        if mismatch > 0.02:
            raise RuntimeError(f"camera framing mismatch is {mismatch:.4f} world units")
        print(
            "MV-0 camera comparison passed: "
            f"perspective P95={perspective['frame_interval_p95_ms']:.3f} ms, "
            f"orthographic P95={orthographic['frame_interval_p95_ms']:.3f} ms, "
            f"span mismatch={mismatch:.4f}."
        )
        return 0
    except (FileNotFoundError, RuntimeError, OSError, json.JSONDecodeError, subprocess.TimeoutExpired) as error:
        print(f"MV-0 camera comparison failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
