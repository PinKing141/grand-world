#!/usr/bin/env python3
"""Run every automated Grand World Phase 1-8 gate and write one report.

Examples:
  python tools/testing/run_all_tests.py
  python tools/testing/run_all_tests.py --quick
  python tools/testing/run_all_tests.py --quick --visual
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
    ("Country registry runtime and ownership integrity", "tests/country_registry_test.gd", "Country registry runtime test passed."),
    ("Country label territory, lifecycle, map modes, and performance", "tests/country_label_layer_test.gd", "Country label layer P1 test passed."),
    ("Country label projected visual layouts", "tests/country_label_visual_regression_test.gd", "Country label visual regression passed."),
    ("Phase 1 map interaction", "tests/phase_1a_smoke.gd", "Phase 1A smoke test passed."),
    ("Camera controls", "tests/camera_controls_smoke.gd", "Camera controls smoke test passed."),
    ("Map semantic lakes, routes, and screen-space hierarchy", "tests/map_semantic_visual_smoke.gd", "Map semantic visual smoke passed."),
    ("Battle and siege marker hierarchy", "tests/conflict_marker_layer_smoke.gd", "Conflict marker layer smoke passed."),
    ("Large-war marker clustering and performance", "tests/conflict_marker_stress_smoke.gd", "Conflict marker stress smoke passed."),
    ("FL1 fleet marker layer clustering and selection", "tests/fleet_marker_layer_smoke.gd", "Fleet marker layer smoke passed."),
    ("FL7.1 naval dense-zone presentation stress", "tests/naval_dense_zone_presentation_stress_test.gd", "Naval dense-zone presentation stress passed."),
    ("FL1 fleet route lifecycle: cancellation, peace, and save/load reconciliation", "tests/fleet_marker_lifecycle_test.gd", "Fleet marker lifecycle test passed."),
	("Unified campaign interface shell and minimap", "tests/campaign_interface_shell_smoke.gd", "Campaign interface shell smoke passed."),
    ("Responsive UI layout", "tests/ui_layout_smoke.gd", "UI layout smoke test passed"),
    ("Simulation core and save corruption", "tests/simulation_core_test.gd", "Simulation core test passed."),
    ("Frame-rate determinism", "tests/simulation_frame_rate_determinism_test.gd", "Frame-rate determinism test passed."),
    ("Phase 2 scene integration", "tests/phase_2_integration_smoke.gd", "Phase 2 integration smoke test passed."),
    ("Phase 3 graph, route, movement, and save", "tests/phase_3_movement_test.gd", "Phase 3 movement test passed."),
    ("Phase 4 economy rules and edge cases", "tests/phase_4_economy_test.gd", "Phase 4 economy test passed."),
    ("Phase 4 UI, heatmap, and save integration", "tests/phase_4_integration_smoke.gd", "Phase 4 integration smoke passed."),
    ("Phase 5 diplomacy, war, battle, siege, peace, and save", "tests/phase_5_warfare_test.gd", "Phase 5 warfare test passed."),
    ("Phase 5 UI, overlays, declaration, and active-war save", "tests/phase_5_integration_smoke.gd", "Phase 5 integration smoke passed."),
    ("Phase 6 deterministic economic, diplomatic, and military AI", "tests/phase_6_ai_test.gd", "Phase 6 AI test passed."),
    ("Phase 6 campaign UI, objectives, overlay, and AI-state save", "tests/phase_6_integration_smoke.gd", "Phase 6 integration smoke passed."),
    ("Phase 7 characters, dynasties, titles, succession, claims, and save", "tests/phase_7_character_test.gd", "Phase 7 character test passed."),
    ("Phase 7 court UI, character AI, claim-war UI, and succession integration", "tests/phase_7_integration_smoke.gd", "Phase 7 integration smoke passed."),
    ("Phase 8 country depth, subjects, events, formation, AI, and save", "tests/phase_8_country_depth_test.gd", "Phase 8 country-depth test passed."),
    ("Phase 8 Country & State UI, map modes, commands, and save", "tests/phase_8_integration_smoke.gd", "Phase 8 integration smoke passed."),
    ("N1.1 naval maritime graph definitions", "tests/naval_definitions_test.gd", "Naval definitions test passed."),
    ("N1.2 maritime graph topology, costs, and route finding", "tests/maritime_graph_test.gd", "Maritime graph test passed."),
    ("N1.3 naval access, basing rights, and supply range", "tests/naval_access_policy_test.gd", "Naval access policy test passed."),
    ("N1.4 maritime graph long-haul, reciprocity, and stress smoke", "tests/maritime_graph_stress_smoke.gd", "Maritime graph stress smoke passed."),
    ("N2.1 ship definitions", "tests/ship_definitions_test.gd", "Ship definitions test passed."),
    ("G1 source-tracked Channel and Iberian starting naval forces", "tests/starting_naval_forces_test.gd", "Starting naval forces test passed."),
    ("N2.1 fleet/ship save state, checksum, and migration", "tests/naval_fleet_state_test.gd", "Naval fleet state test passed."),
    ("N2.2/FL3.2 naval economy, sailors, ship construction, and navy maintenance", "tests/naval_economy_test.gd", "Naval economy test passed."),
    ("N2.3 fleet organisation commands and aggregates", "tests/naval_fleet_organisation_test.gd", "Naval fleet organisation test passed."),
    ("N2.3 fleet movement, blocking, and cancellation", "tests/naval_fleet_movement_test.gd", "Naval fleet movement test passed."),
    ("N2.4 fleet supply, attrition, and repair", "tests/naval_fleet_logistics_test.gd", "Naval fleet logistics test passed."),
    ("N2.4 admiral assignment, exclusivity, and lifecycle", "tests/naval_admiral_test.gd", "Naval admiral test passed."),
    ("N2.5 naval HUD construction, fleet panel, and save integration", "tests/naval_hud_integration_smoke.gd", "Naval HUD integration smoke passed."),
    ("FL2.2 fleet split/transfer/merge HUD integration", "tests/naval_fleet_organisation_hud_test.gd", "Naval fleet organisation HUD test passed."),
    ("FL2.3 fleet home port and targeted return-to-port HUD integration", "tests/naval_fleet_home_port_hud_test.gd", "Naval fleet home port HUD test passed."),
    ("FL2.5 scuttle command validation, cleanup, duplicates, save/load", "tests/naval_fleet_scuttle_test.gd", "Naval fleet scuttle test passed."),
    ("FL2.5 scuttle armed-confirmation HUD integration", "tests/naval_fleet_scuttle_hud_test.gd", "Naval fleet scuttle HUD test passed."),
    ("FL2.1 fleet-summary aggregate queries: class mix, crew readiness, repair, route ETA", "tests/naval_fleet_summary_test.gd", "Naval fleet summary test passed."),
    ("FL2.1 fleet-summary panel HUD integration: resolved names, class mix, repair, route", "tests/naval_fleet_summary_hud_test.gd", "Naval fleet summary HUD test passed."),
    ("FL2.6 transport workflow HUD integration: capacity, route, cancellation, cross-navigation", "tests/naval_transport_workflow_hud_test.gd", "Naval transport workflow HUD test passed."),
    ("FL2.1 fleet-selection fallback on destruction/cascading destruction", "tests/naval_fleet_selection_fallback_hud_test.gd", "Naval fleet selection fallback HUD test passed."),
    ("FL6.2 rapid double-press/duplicate-command safety across naval actions", "tests/naval_hud_duplicate_action_safety_test.gd", "Naval HUD duplicate action safety test passed."),
    ("N2.5 naval fleet-scale stress and performance smoke", "tests/naval_fleet_stress_smoke.gd", "Naval fleet stress smoke passed."),
    ("N3.1/N3.2 transport operation record, reservation, and state machine", "tests/naval_transport_operation_test.gd", "Naval transport operation test passed."),
    ("N3.3 transport capacity shortfall and blocked-fleet recovery", "tests/naval_transport_recovery_test.gd", "Naval transport recovery test passed."),
    ("N3.4 transport save boundaries and Channel repetition gate", "tests/naval_transport_gate_test.gd", "Naval transport gate test passed."),
    ("N4 naval battle engagement, damage, sinking, retreat", "tests/naval_combat_test.gd", "Naval combat test passed."),
    ("N5A blockade eligibility and power query", "tests/naval_blockade_test.gd", "Naval blockade test passed."),
    ("N3.3/N4.3/N5.2 peace/country-extinction naval cleanup", "tests/naval_country_extinction_test.gd", "Naval country extinction test passed."),
    ("N3.3 transport operation orphaned by combat-destroyed carrier fleet", "tests/naval_transport_combat_loss_test.gd", "Naval transport combat loss test passed."),
    ("N4.4/N5.3 naval battle and blockade stress and global-coast smoke", "tests/naval_battle_blockade_stress_smoke.gd", "Naval battle/blockade stress smoke passed."),
    ("FL7.2-FL7.6 global simultaneous naval headless stress", "tests/naval_global_simultaneous_stress_test.gd", "Naval global simultaneous stress passed."),
    ("N6A fleet mission state machine (return_to_port, repair)", "tests/fleet_mission_system_test.gd", "Fleet mission system test passed."),
    ("N6A naval AI posture, construction, organisation, tactical, determinism", "tests/naval_ai_test.gd", "Naval AI test passed."),
    ("N6A naval AI sea-zone threat query, evasion, blockade-duty assignment", "tests/naval_ai_threat_test.gd", "Naval AI threat test passed."),
    ("N6A naval AI transport-objective planning and land-AI handoff", "tests/naval_ai_transport_test.gd", "Naval AI transport test passed."),
    ("N6A/FL3.3 naval AI fleet organisation, task-fleet merging, and transport-run fleet splitting", "tests/naval_ai_organisation_test.gd", "Naval AI organisation test passed."),
    ("FL3.1 threat/opportunity cache: revision invalidation, inputs, determinism", "tests/naval_threat_map_test.gd", "Naval threat map test passed."),
    ("FL3.2 strategic posture spectrum, ship mix, sailor reserve", "tests/naval_ai_strategic_posture_test.gd", "Naval AI strategic posture test passed."),
    ("FL3.4 tactical missions: escort, intercept, protect_coast, patrol, stand-down", "tests/naval_ai_tactical_missions_test.gd", "Naval AI tactical missions test passed."),
    ("FL3.3/FL3.5: reinforcement, home-port reassignment, danger-aware transport", "tests/naval_ai_reinforcement_homeport_transport_test.gd", "Naval AI reinforcement/home-port/transport test passed."),
    ("FL3.6 explainability: structured targets/constraints/posture/next-planning-day, candidates-evaluated counter", "tests/naval_ai_explainability_test.gd", "Naval AI explainability test passed."),
    ("FL3.2 correctness fix: ship technology gate (command contract, AI family fallback)", "tests/naval_ship_technology_gate_test.gd", "Naval ship technology gate test passed."),
    ("FL3 verification 1/4: same-zone player/AI battle arbitration produces one authoritative battle", "tests/naval_ai_player_battle_arbitration_test.gd", "Naval AI/player battle arbitration test passed."),
    ("FL3 verification 2/4: full AI recovery matrix (destroyed fleets, debt, sailors, peace, captured ports)", "tests/naval_ai_recovery_matrix_test.gd", "Naval AI recovery matrix test passed."),
    ("FL3 verification 3/4: trace production does not change authoritative results", "tests/naval_ai_trace_neutrality_test.gd", "Naval AI trace neutrality test passed."),
    ("FL3.4 event-triggered replanning: off-schedule tactical reconsideration on battle start/fleet arrival", "tests/naval_ai_event_replan_test.gd", "Naval AI event replan test passed."),
    ("FL3.5 escort lifecycle: proactive reservation, follows-the-voyage, survives temporary separation", "tests/naval_ai_escort_lifecycle_test.gd", "Naval AI escort lifecycle test passed."),
    ("FL3 verification 4/4: global naval AI planning performance budget across 20 countries", "tests/naval_ai_performance_smoke.gd", "Naval AI performance smoke passed."),
    ("FL5.1 trade-protection output: eligibility, damage scaling, contested/unsupplied, pure query", "tests/naval_trade_protection_test.gd", "Naval trade protection test passed."),
    ("FL5.2 blockade/coastal contract: same-day release on peace and on annexation", "tests/naval_blockade_peace_annexation_test.gd", "Naval blockade peace/annexation test passed."),
    ("N6.3 naval save schema migration (7/8/full chain)", "tests/naval_save_schema_migration_test.gd", "Naval save schema migration test passed."),
    ("G1 England-France Channel final release gate", "tests/naval_channel_release_gate_test.gd", "Naval Channel release gate passed."),
    ("G1 destructive naval lifecycle final release gate", "tests/naval_destructive_edge_gate_test.gd", "Naval destructive edge gate passed."),
)

PYTHON_TESTS = (
    ("Canonical country registry", "tools/country_registry/build_country_registry.py", "Country registry is valid and current."),
    ("FL4.2 starting naval content report", "tools/naval/build_naval_forces_report.py", "no unresolved starting naval content rows."),
	("Runtime history profile cache", "tests/runtime_history_profile_cache_smoke.py", "Runtime history profile cache smoke test passed."),
    ("1444 neighbour-colour contrast analysis", "tools/country_registry/analyse_neighbour_colours.py", "Neighbour-colour analysis is valid and current."),
	("Generated historical placeholder marker assets", "tools/marker_art/build_marker_assets.py", "Marker assets are valid and current."),
	("Historical placeholder shields and marker asset contract", "tests/marker_asset_contract_smoke.py", "Marker asset contract smoke passed."),
    ("Conservative country-label territory map", "tools/map_labels/build_label_territory_map.py", "Label territory map is valid and current."),
	("MV-0 map visual asset and render audit", "tools/map_visual_audit/build_map_visual_audit.py", "MV-0 map visual asset and render audit is valid and current."),
	("Canonical province edge lattice", "tests/province_edge_lattice_contract_smoke.py", "Province edge lattice contract passed."),
	("Canonical generated lake mask", "tools/map_visual_audit/build_lake_mask.py", "Lake mask is valid and current."),
    ("Lake, island, and shoreline topology", "tests/map_hydrography_topology_smoke.py", "Map hydrography topology smoke passed."),
    ("River source ingestion contract", "tests/river_data_contract_smoke.py", "River data contract smoke passed."),
    ("Terrain classification", "tests/terrain_classification_smoke.py", "Terrain classification smoke test passed."),
    ("Biome classification", "tests/biome_classification_smoke.py", "Biome classification smoke test passed."),
    ("Baked economy definitions", "tools/economy/build_economy_data.py", "Economy definitions are current."),
    ("Baked N1.1 naval maritime graph definitions", "tools/naval/build_naval_graph_data.py", "Naval graph definitions are current."),
    ("N1.4 naval graph malformed-data rejection", "tests/naval_graph_malformed_data_smoke.py", "Naval graph malformed data smoke passed."),
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
    parser.add_argument("--quick", action="store_true", help="Skip long campaign soaks and Windows export.")
    parser.add_argument("--skip-export", action="store_true", help="Run all gameplay tests but skip packaging.")
    parser.add_argument("--no-report", action="store_true", help="Do not update the Markdown report.")
    parser.add_argument("--visual", action="store_true", help="Open a rendering window and compare GPU country-label screenshots.")
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
    process: subprocess.Popen[str] | None = None
    try:
        process = subprocess.Popen(
            spec.command,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        stdout, stderr = process.communicate(timeout=spec.timeout)
        output = "\n".join(part.strip() for part in (stdout, stderr) if part.strip())
        lowered = output.lower()
        failure_marker = next((marker for marker in FAILURE_MARKERS if marker.lower() in lowered), "")
        passed = process.returncode == 0 and spec.success_marker in output and not failure_marker
        reason = ""
        if process.returncode != 0:
            reason = f"exit code {process.returncode}"
        elif failure_marker:
            reason = f"output contains `{failure_marker}`"
        elif spec.success_marker not in output:
            reason = f"missing success marker `{spec.success_marker}`"
        return TestResult(spec.name, spec.category, passed, time.perf_counter() - started, int(process.returncode or 0), output, reason)
    except subprocess.TimeoutExpired:
        # Godot's Windows console executable can launch an engine child. Kill
        # the entire test tree so a timeout cannot contaminate later timings.
        if process is not None:
            if os.name == "nt":
                subprocess.run(("taskkill", "/PID", str(process.pid), "/T", "/F"), capture_output=True, check=False)
            else:
                process.kill()
            stdout, stderr = process.communicate()
        else:
            stdout, stderr = "", ""
        output = "\n".join(part.strip() for part in (stdout, stderr) if part.strip())
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
                "res://assets/country_registry.json",
                "res://assets/generated/history_profiles.json",
                "res://assets/label_territory_map.json",
                "res://assets/label_territory_map.png",
                "res://assets/fonts/LibreBaskerville-Variable.ttf",
                "res://assets/economy_definitions.json",
                "res://assets/ai_definitions.json",
                "res://assets/character_definitions.json",
                "res://assets/country_depth_definitions.json",
				"res://assets/grand_world_1444_naval_forces.json",
				"res://assets/marker_art/generated/country_shield_atlas.png",
				"res://assets/marker_art/generated/marker_icon_atlas.png",
				"res://assets/marker_art/generated/marker_asset_manifest.json",
                "res://assets/province_graph.json",
                "res://scenes/ui/economy_hud.tscn",
                "res://scenes/ui/war_hud.tscn",
                "res://scenes/ui/ai_debug_hud.tscn",
                "res://scenes/ui/character_hud.tscn",
                "res://scenes/ui/country_depth_hud.tscn",
                "res://scenes/ui/naval_hud.tscn",
                "res://assets/ship_definitions.json",
                "res://assets/naval_definitions.json",
                "res://scripts/simulation/fleet_movement_system.gd",
                "res://scripts/simulation/fleet_logistics_system.gd",
                "res://scripts/simulation/warfare_system.gd",
                "res://scripts/simulation/strategic_ai_system.gd",
                "res://scripts/simulation/character_system.gd",
                "res://scripts/simulation/country_depth_system.gd",
                "res://scripts/simulation/country_depth_ai_system.gd",
                "res://scripts/simulation/country_registry.gd",
                "res://scripts/ui/country_label_layer.gd",
				"res://scripts/ui/conflict_marker_layer.gd",
				"res://shaders/army_flag_marker.gdshader",
				"res://shaders/cartographic_marker_icon.gdshader",
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

        # Launch the actual packaged binary. The small console wrapper can hide
        # an early Windows/engine crash by returning success with only the
        # engine banner, which made the startup gate report an unhelpful set of
        # missing data markers.
        startup_exe = export_exe
        startup_log = export_dir / "startup.log"
        startup_spec = TestSpec(
            "Exported build startup",
            (str(startup_exe), "--headless", "--script", "res://tests/export_startup_smoke.gd", "--log-file", str(startup_log)),
            "Export startup smoke passed.",
            timeout=60,
            category="Packaging",
        )
        startup_result = execute(startup_spec)
        if not startup_result.passed:
            pack_path = export_dir / "Grand World.pck"
            pack_spec = TestSpec(
                "Windows PCK export for policy-safe startup",
                (str(godot), "--headless", "--path", str(ROOT), "--export-pack", "Windows Desktop", str(pack_path)),
                "Storing File: res://project.binary",
                timeout=240,
                category="Packaging",
            )
            pack_result = execute(pack_spec)
            if pack_result.passed and pack_path.exists():
                fallback_spec = TestSpec(
                    "Exported build startup (trusted-host PCK fallback)",
                    (str(godot), "--headless", "--main-pack", str(pack_path), "--script", "res://tests/export_startup_smoke.gd", "--log-file", str(startup_log)),
                    "Export startup smoke passed.",
                    timeout=60,
                    category="Packaging",
                )
                fallback_result = execute(fallback_spec)
                fallback_result.output = "\n".join(
                    value for value in (
                        "Direct exported executable startup failed on this host; validating the same exported resources through the trusted Godot host and PCK fallback.",
                        pack_result.output,
                        fallback_result.output,
                    ) if value
                )
                startup_result = fallback_result
            else:
                startup_result.output = "\n".join(
                    value for value in (startup_result.output, pack_result.output) if value
                )
                startup_result.reason = "direct executable startup failed and PCK fallback export failed"
        log_text = startup_log.read_text(encoding="utf-8", errors="replace") if startup_log.exists() else ""
        startup_result.output = "\n".join(value for value in (startup_result.output, log_text) if value)
        required_startup = (
            "Parsed Provinces:3924",
            "Parsed Country Colors:1009",
            "Parsed Countries:1009",
            "Marker Assets:shield=true icons=true",
        )
        missing = [item for item in required_startup if item not in startup_result.output]
        fatal = any(marker in startup_result.output for marker in ("SCRIPT ERROR:", "Failed to open directory", "requires valid Phase 4 economy definitions", "requires valid Phase 6 AI definitions", "requires valid Phase 7 character definitions", "requires valid Phase 8 country-depth definitions"))
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
        "This report covers the canonical country registry and ownership integrity, 1444 neighbour-colour contrast analysis, provenance-aware historical placeholder shield coverage, the complete marker-icon family, territory-safe country labels, projected overlap/layout baselines, label lifecycle and performance budgets, map selection/search, camera controls, clickable deterministic conflict-marker clustering, the 720-marker large-war stress budget, responsive UI containment, deterministic calendar/commands/RNG, save corruption and migrations, graph/pathfinding/movement, economy, construction, recruitment, diplomacy, warfare and peace, utility AI, campaign objectives, characters/dynasties/titles/claims, marriages, commanders, opinions, ruler modifiers, health, birth, death and succession, government, stability, unrest, rebels, control, culture, religion, conversion, technology, ideas, cores, claims, subjects, events, decisions, country formation/release, country-depth AI and UI, deterministic replay through 1700, the hundred-year multi-generation soak, the twenty-year Iberian AI soak, the ten-year global soak, and Windows export startup.",
        "",
        "## Human-only checks still required",
        "",
        "- Visual polish and readability on the actual display/GPU.",
		"- Hands-on political-palette and semantic-state review with colour-vision-deficient players.",
        "- Mouse feel, tooltip timing, and panel ergonomics.",
        "- Iberian economy scarcity and comparative country balance.",
        "- Whether construction, recruitment, and maintenance choices are enjoyable.",
        "- Combat pacing, siege duration, war-score costs, and diplomatic balance.",
        "- Whether autonomous countries feel coherent, threatening, and distinct across repeated campaigns.",
        "- Campaign-objective clarity and the usefulness of the AI inspector during real play.",
        "- Character-window ergonomics, family-tree clarity, portrait direction, and death/succession feedback.",
        "- Historical review of the representative 1444 Iberian rulers, families, dynasties, claims, and titles.",
        "- Marriage, fertility, mortality, ruler-modifier, claim-war, and succession balance.",
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
        extra = ("--check",) if path.endswith(("build_economy_data.py", "build_country_registry.py", "analyse_neighbour_colours.py", "build_marker_assets.py", "build_label_territory_map.py", "build_map_visual_audit.py", "build_lake_mask.py", "build_naval_graph_data.py", "build_naval_forces_report.py")) else ()
        specs.append(TestSpec(name, (sys.executable, str(ROOT / path), *extra), marker, timeout=60, category="Data"))
    for name, path, marker in GODOT_TESTS:
        timeout = 2400 if path.endswith("naval_channel_release_gate_test.gd") else 120
        specs.append(TestSpec(name, (str(godot), "--headless", "--path", str(ROOT), "--script", f"res://{path}"), marker, timeout=timeout))
    if args.visual:
        specs.append(TestSpec(
            "GPU-rendered country label screenshots",
            (sys.executable, str(ROOT / "tools/map_labels/run_visual_regression.py"), "--godot", str(godot)),
            "Country label rendered visual regression passed.",
            timeout=240,
            category="Visual",
        ))
    if not args.quick:
        specs.append(TestSpec(
            "Phase 8 deterministic 1444-1700 Alpha campaign",
            (str(godot), "--headless", "--path", str(ROOT), "--script", "res://tests/phase_8_1444_1700_soak.gd"),
            "Phase 8 1444-1700 soak passed",
            timeout=120,
            category="Performance",
        ))
        specs.append(TestSpec(
            "Hundred-year multi-generation character soak",
            (str(godot), "--headless", "--path", str(ROOT), "--script", "res://tests/phase_7_multigeneration_soak.gd"),
            "Phase 7 hundred-year multi-generation soak passed",
            timeout=120,
            category="Performance",
        ))
        specs.append(TestSpec(
            "Twenty-year Iberian AI soak",
            (str(godot), "--headless", "--path", str(ROOT), "--script", "res://tests/phase_6_regional_soak.gd"),
            "Phase 6 twenty-year regional soak passed",
            timeout=120,
            category="Performance",
        ))
        specs.append(TestSpec(
            "Ten-year full-world soak",
            (str(godot), "--headless", "--path", str(ROOT), "--script", "res://tests/phase_2_global_soak.gd"),
            "Global Phase 5 ten-year soak passed",
            timeout=120,
            category="Performance",
        ))
        specs.append(TestSpec(
            "N6.3 100-seed England-France Channel acceptance",
            (str(godot), "--headless", "--path", str(ROOT), "--script", "res://tests/naval_channel_100_seed_acceptance_test.gd"),
            "Naval Channel 100-seed acceptance test passed.",
            timeout=300,
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
