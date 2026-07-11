# Latest Headless Test Report

- Overall: **PASS**
- Completed: **17/17 checks passed**
- Started: `2026-07-11T19:19:41+01:00`
- Duration: **160.68 seconds**
- Platform: `Windows-11-10.0.26200-SP0`
- Python: `3.14.3`
- Godot: `C:\Users\Favour\Documents\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`

## Results

| Check | Category | Result | Seconds |
|---|---|---:|---:|
| Terrain classification | Data | **PASS** | 0.50 |
| Biome classification | Data | **PASS** | 1.16 |
| Baked economy definitions | Data | **PASS** | 2.13 |
| Phase 1 map interaction | Regression | **PASS** | 15.16 |
| Camera controls | Regression | **PASS** | 10.40 |
| Responsive UI layout | Regression | **PASS** | 10.32 |
| Simulation core and save corruption | Regression | **PASS** | 1.96 |
| Frame-rate determinism | Regression | **PASS** | 1.21 |
| Phase 2 scene integration | Regression | **PASS** | 14.24 |
| Phase 3 graph, route, movement, and save | Regression | **PASS** | 0.99 |
| Phase 4 economy rules and edge cases | Regression | **PASS** | 0.95 |
| Phase 4 UI, heatmap, and save integration | Regression | **PASS** | 13.69 |
| Phase 5 diplomacy, war, battle, siege, peace, and save | Regression | **PASS** | 1.21 |
| Phase 5 UI, overlays, declaration, and active-war save | Regression | **PASS** | 14.15 |
| Ten-year full-world soak | Performance | **PASS** | 26.42 |
| Windows debug export | Packaging | **PASS** | 30.21 |
| Exported build startup | Packaging | **PASS** | 15.89 |

## Automated scope

This report covers map selection/search, camera controls, responsive UI containment, deterministic calendar/commands/RNG, save corruption and migrations, graph/pathfinding/movement, economy formulas and edge cases, construction, recruitment, maintenance, loans/debt, diplomacy, access, alliances, war declarations, deterministic battles, reinforcement, retreats, sieges, occupation, war score, peace terms, truces, strategy overlays, scene integration, frame-rate determinism, the ten-year global soak, and Windows export startup.

## Human-only checks still required

- Visual polish and readability on the actual display/GPU.
- Mouse feel, tooltip timing, and panel ergonomics.
- Iberian economy scarcity and comparative country balance.
- Whether construction, recruitment, and maintenance choices are enjoyable.
- Combat pacing, siege duration, war-score costs, and diplomatic balance.
- Clarity of battle, occupation, and peace feedback during hands-on play.
- Final release-build signing, installer, and distribution checks.
