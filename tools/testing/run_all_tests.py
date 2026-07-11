#!/usr/bin/env python3
"""Run every automated Grand World Phase 1-5 gate and write one report.

Examples:
  python tools/testing/run_all_tests.py
  python tools/testing/run_all_tests.py --quick
  python tools/testing/run_all_tests.py --skip-export
  python tools/testing/run_all_tests.py --godot C:/Godot/Godot_console.exe
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPORT_DIR = ROOT / "docs" / "test_reports"
REPORT_PATH = REPORT_DIR / "latest_headless_report.md"


@dataclass(frozen=True)
class TestSpec:
    name: str
    command: tuple[str, ...]
    success_marker: str
    timeout: int = 120
    category: str = "Regression"


@dataclass
class TestResult:
    name: str
    category: str
    passed: bool
    duration: float
    returncode: int
    output: str
    reason: str = ""


GODOT_TESTS = (
    ("Phase 1 map interaction", "tests/phase_1a_smoke.gd", "Phase 1A smoke test passed."),
    ("Camera controls", "tests/camera_controls_smoke.gd", "Camera controls smoke test passed."),
    ("Responsive UI layout", "tests/ui_layout_smoke.gd", "UI layout smoke test passed"),
    ("Simulation core and save corruption", "tests/simulation_core_test.gd", "Simulation core test passed."),
    ("Frame-rate determinism", "tests/simulation_frame_rate_determinism_test.gd", "Frame-rate determinism test passed."),
    ("Phase 2 scene integration", "tests/phase_2_integration_smoke.gd", "Phase 2 integration smoke test passed."),
    ("Phase 3 graph, route, movement, and save", "tests/phase_3_movement_test.gd", "Phase 3 movement test passed."),
    ("Phase 4 economy rules and edge cases", "tests/phase_4_economy_test.gd", "Phase 4 economy test passed."),
    ("Phase 4 UI, heatmap, and save integration", "tests/phase_4_integration_smoke.gd", "Phase 4 integration smoke passed."),
    ("Phase 5 diplomacy, war, battle, siege, peace, and save", "tests/phase_5_warfare_test.gd", "Phase 5 warfare test passed."),
    ("Phase 5 UI, overlays, declaration, and active-war save", "tests/phase_5_integration_smoke.gd", "Phase 5 integration smoke passed."),
)

PYTHON_TESTS = (
    ("Terrain classification", "tests/terrain_classification_smoke.py", "Terrain classification smoke test passed."),
    ("Biome classification", "tests/biome_classification_smoke.py", "Biome classification smoke test passed."),
    ("Baked economy definitions", "tools/economy/build_economy_data.py", "Economy definitions are current."),
)

FAILURE_MARKERS = (
    "SCRIPT ERROR:",
    "Parse Error:",
    "Compile Error:",
    "test failed:",
    "smoke failed:",
    "soak failed:",
    "Failed to load script",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, help="Path to the Godot console executable.")
    parser.add_argument("--quick", action="store_true", help="Skip the ten-year soak and Windows export.")
    parser.add_argument("--skip-export", action="store_true", help="Run all gameplay tests but skip packaging.")
    parser.add_argument("--no-report", action="store_true", help="Do not update the Markdown report.")
    return parser.parse_args()


def find_godot(explicit: Path | None) -> Path:
    candidates: list[Path] = []
    if explicit:
        candidates.append(explicit.expanduser())
    if os.environ.get("GODOT_BIN"):
        candidates.append(Path(os.environ["GODOT_BIN"]).expanduser())
    for executable in (
        "godot", "godot4", "Godot", "Godot_v4.7-stable_mono_win64_console.exe",
    ):
        found = shutil.which(executable)
        if found:
            candidates.append(Path(found))
    documents = Path.home() / "Documents"
    if documents.exists():
        candidates.extend(sorted(documents.glob("Godot_v*-stable*_win64/Godot*_console.exe"), reverse=True))
        candidates.extend(sorted(documents.glob("Godot_v*-stable*_win64/Godot*.exe"), reverse=True))
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved.is_file():
            return resolved
    raise FileNotFoundError("Godot was not found. Pass --godot or set GODOT_BIN.")


def combined_output(completed: subprocess.CompletedProcess[str]) -> str:
    return "\n".join(part.strip() for part in (completed.stdout, completed.stderr) if part.strip())


def execute(spec: TestSpec) -> TestResult:
    started = time.perf_counter()
    try:
        completed = subprocess.run(
            spec.command,
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=spec.timeout,
            check=False,
        )
        output = combined_output(completed)
        lowered = output.lower()
        failure_marker = next((marker for marker in FAILURE_MARKERS if marker.lower() in lowered), "")
        passed = completed.returncode == 0 and spec.success_marker in output and not failure_marker
        reason = ""
        if completed.returncode != 0:
            reason = f"exit code {completed.returncode}"
        elif failure_marker:
            reason = f"output contains `{failure_marker}`"
        elif spec.success_marker not in output:
            reason = f"missing success marker `{spec.success_marker}`"
        return TestResult(spec.name, spec.category, passed, time.perf_counter() - started, completed.returncode, output, reason)
    except subprocess.TimeoutExpired as error:
        output = "\n".join(
            value.decode("utf-8", "replace") if isinstance(value, bytes) else (value or "")
            for value in (error.stdout, error.stderr)
        ).strip()
        return TestResult(spec.name, spec.category, False, time.perf_counter() - started, 124, output, f"timed out after {spec.timeout}s")


def export_and_start(godot: Path) -> list[TestResult]:
    results: list[TestResult] = []
    with tempfile.TemporaryDirectory(prefix="grand-world-export-test-") as raw_temp:
        export_dir = Path(raw_temp)
        export_exe = export_dir / "Grand World.exe"
        export_spec = TestSpec(
            "Windows debug export",
            (str(godot), "--headless", "--path", str(ROOT), "--export-debug", "Windows Desktop", str(export_exe)),
            "Storing File: res://project.binary",
            timeout=240,
            category="Packaging",
        )
        export_result = execute(export_spec)
        if export_result.passed:
            required_export_log = (
                "res://assets/economy_definitions.json",
                "res://assets/province_graph.json",
                "res://scenes/ui/economy_hud.tscn",
                "res://scenes/ui/war_hud.tscn",
                "res://scripts/simulation/warfare_system.gd",
            )
            missing = [item for item in required_export_log if item not in export_result.output]
            if missing:
                export_result.passed = False
                export_result.reason = "export log omitted: " + ", ".join(missing)
        if export_result.passed and not export_exe.exists():
            export_result.passed = False
            export_result.reason = "export command passed but no executable was created"
        results.append(export_result)
        if not export_result.passed:
            return results

        console_exe = export_dir / "Grand World.console.exe"
        startup_exe = console_exe if console_exe.exists() else export_exe
        startup_log = export_dir / "startup.log"
        startup_spec = TestSpec(
            "Exported build startup",
            (str(startup_exe), "--headless", "--quit-after", "10", "--log-file", str(startup_log)),
            "Parsed Countries:1010",
            timeout=60,
            category="Packaging",
        )
        startup_result = execute(startup_spec)
        log_text = startup_log.read_text(encoding="utf-8", errors="replace") if startup_log.exists() else ""
        startup_result.output = "\n".join(value for value in (startup_result.output, log_text) if value)
        required_startup = ("Parsed Provinces:3924", "Parsed Country Colors:1022", "Parsed Countries:1010")
        missing = [item for item in required_startup if item not in startup_result.output]
        fatal = any(marker in startup_result.output for marker in ("SCRIPT ERROR:", "Failed to open directory", "requires valid Phase 4 economy definitions", "Phase 5 warfare test failed"))
        if missing or fatal:
            startup_result.passed = False
            startup_result.reason = "startup data validation failed" + (": " + ", ".join(missing) if missing else "")
        results.append(startup_result)
    return results


def output_tail(output: str, line_count: int = 14) -> str:
    lines = [line.rstrip() for line in output.splitlines() if line.strip()]
    return "\n".join(lines[-line_count:])


def write_report(results: list[TestResult], godot: Path, started_at: dt.datetime, elapsed: float) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    passed = sum(result.passed for result in results)
    status = "PASS" if passed == len(results) else "FAIL"
    lines = [
        "# Latest Headless Test Report",
        "",
        f"- Overall: **{status}**",
        f"- Completed: **{passed}/{len(results)} checks passed**",
        f"- Started: `{started_at.astimezone().isoformat(timespec='seconds')}`",
        f"- Duration: **{elapsed:.2f} seconds**",
        f"- Platform: `{platform.platform()}`",
        f"- Python: `{platform.python_version()}`",
        f"- Godot: `{godot}`",
        "",
        "## Results",
        "",
        "| Check | Category | Result | Seconds |",
        "|---|---|---:|---:|",
    ]
    for result in results:
        label = "PASS" if result.passed else "FAIL"
        lines.append(f"| {result.name} | {result.category} | **{label}** | {result.duration:.2f} |")
    failures = [result for result in results if not result.passed]
    if failures:
        lines.extend(["", "## Failures", ""])
        for result in failures:
            lines.extend([
                f"### {result.name}", "",
                f"Reason: {result.reason or 'unknown failure'}", "",
                "~~~text", output_tail(result.output, 30), "~~~", "",
            ])
    lines.extend([
        "",
        "## Automated scope",
        "",
        "This report covers map selection/search, camera controls, responsive UI containment, deterministic calendar/commands/RNG, save corruption and migrations, graph/pathfinding/movement, economy formulas and edge cases, construction, recruitment, maintenance, loans/debt, diplomacy, access, alliances, war declarations, deterministic battles, reinforcement, retreats, sieges, occupation, war score, peace terms, truces, strategy overlays, scene integration, frame-rate determinism, the ten-year global soak, and Windows export startup.",
        "",
        "## Human-only checks still required",
        "",
        "- Visual polish and readability on the actual display/GPU.",
        "- Mouse feel, tooltip timing, and panel ergonomics.",
        "- Iberian economy scarcity and comparative country balance.",
        "- Whether construction, recruitment, and maintenance choices are enjoyable.",
        "- Combat pacing, siege duration, war-score costs, and diplomatic balance.",
        "- Clarity of battle, occupation, and peace feedback during hands-on play.",
        "- Final release-build signing, installer, and distribution checks.",
        "",
    ])
    REPORT_PATH.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    started_at = dt.datetime.now().astimezone()
    suite_started = time.perf_counter()
    try:
        godot = find_godot(args.godot)
    except FileNotFoundError as error:
        print(error, file=sys.stderr)
        return 2

    specs: list[TestSpec] = []
    for name, path, marker in PYTHON_TESTS:
        extra = ("--check",) if path.endswith("build_economy_data.py") else ()
        specs.append(TestSpec(name, (sys.executable, str(ROOT / path), *extra), marker, timeout=60, category="Data"))
    for name, path, marker in GODOT_TESTS:
        specs.append(TestSpec(name, (str(godot), "--headless", "--path", str(ROOT), "--script", f"res://{path}"), marker))
    if not args.quick:
        specs.append(TestSpec(
            "Ten-year full-world soak",
            (str(godot), "--headless", "--path", str(ROOT), "--script", "res://tests/phase_2_global_soak.gd"),
            "Global Phase 5 ten-year soak passed",
            timeout=120,
            category="Performance",
        ))

    results: list[TestResult] = []
    for index, spec in enumerate(specs, start=1):
        print(f"[{index}/{len(specs)}] {spec.name} ...", flush=True)
        result = execute(spec)
        results.append(result)
        print(f"  {'PASS' if result.passed else 'FAIL'} ({result.duration:.2f}s)", flush=True)

    if not args.quick and not args.skip_export:
        print("[export] Windows package and startup ...", flush=True)
        export_results = export_and_start(godot)
        results.extend(export_results)
        for result in export_results:
            print(f"  {result.name}: {'PASS' if result.passed else 'FAIL'} ({result.duration:.2f}s)", flush=True)

    elapsed = time.perf_counter() - suite_started
    if not args.no_report:
        write_report(results, godot, started_at, elapsed)
        print(f"Report: {REPORT_PATH.relative_to(ROOT)}", flush=True)
    failed = [result for result in results if not result.passed]
    print(f"Result: {len(results) - len(failed)}/{len(results)} checks passed in {elapsed:.2f}s", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
