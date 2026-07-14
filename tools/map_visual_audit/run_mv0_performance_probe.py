#!/usr/bin/env python3
"""Run the rendered MV-0 layer-isolation performance probe."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "tests" / "baselines" / "map_visual_mv0" / "current"
SCRIPT = "res://tests/map_visual_mv0_performance_probe.gd"
OUTPUT_FILE = "mv0_performance_probe.json"


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
    candidates.extend(sorted((Path.home() / "Documents").glob("Godot_v4.7-stable*_win64/Godot*_console.exe"), reverse=True))
    for candidate in candidates:
        resolved = candidate.expanduser().resolve()
        if resolved.is_file():
            return resolved
    raise FileNotFoundError("Godot 4.7 console executable not found; pass --godot or set GODOT_BIN")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    try:
        godot = find_godot(args.godot)
        output = args.output_dir.expanduser().resolve()
        output.mkdir(parents=True, exist_ok=True)
        command = (
            str(godot), "--path", str(ROOT), "--script", SCRIPT,
            "--", f"--output-dir={output}",
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
        if completed.returncode != 0 or "MV-0 layer performance probe completed." not in combined:
            raise RuntimeError(f"Godot probe failed ({completed.returncode}):\n{combined[-8000:]}")
        report_path = output / OUTPUT_FILE
        report = json.loads(report_path.read_text(encoding="utf-8"))
        profiles = report.get("profiles", [])
        if len(profiles) != 15 or any(not profile for profile in profiles):
            raise RuntimeError("performance probe report is incomplete")
        for profile in profiles:
            print(
                f"{profile['name']}: P50={profile['frame_interval_ms_p50']:.3f} ms "
                f"P95={profile['frame_interval_ms_p95']:.3f} ms "
                f"max={profile['frame_interval_ms_max']:.3f} ms "
                f">50 ms={profile['frames_over_50_ms']} draws={profile['draw_calls_p95']:.0f}"
            )
        print("MV-0 layer performance probe passed.")
        return 0
    except (FileNotFoundError, RuntimeError, OSError, json.JSONDecodeError, subprocess.TimeoutExpired) as error:
        print(f"MV-0 layer performance probe failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
