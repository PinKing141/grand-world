# Latest Headless Test Report

- Overall: **PASS**
- Completed: **26/26 checks passed**
- Started: `2026-07-14T13:05:20+01:00`
- Duration: **241.03 seconds**
- Platform: `Windows-11-10.0.26200-SP0`
- Python: `3.14.3`
- Godot: `C:\Users\Favour\Documents\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`

## Results

| Check | Category | Result | Seconds |
|---|---|---:|---:|
| Canonical country registry | Data | **PASS** | 2.64 |
| Conservative country-label territory map | Data | **PASS** | 2.04 |
| Terrain classification | Data | **PASS** | 0.52 |
| Biome classification | Data | **PASS** | 1.15 |
| Baked economy definitions | Data | **PASS** | 2.60 |
| Country registry runtime and ownership integrity | Regression | **PASS** | 13.37 |
| Country label territory, lifecycle, map modes, and performance | Regression | **PASS** | 21.91 |
| Country label projected visual layouts | Regression | **PASS** | 16.11 |
| Phase 1 map interaction | Regression | **PASS** | 10.55 |
| Camera controls | Regression | **PASS** | 10.59 |
| Responsive UI layout | Regression | **PASS** | 10.57 |
| Simulation core and save corruption | Regression | **PASS** | 1.25 |
| Frame-rate determinism | Regression | **PASS** | 3.38 |
| Phase 2 scene integration | Regression | **PASS** | 18.68 |
| Phase 3 graph, route, movement, and save | Regression | **PASS** | 0.96 |
| Phase 4 economy rules and edge cases | Regression | **PASS** | 0.99 |
| Phase 4 UI, heatmap, and save integration | Regression | **PASS** | 18.35 |
| Phase 5 diplomacy, war, battle, siege, peace, and save | Regression | **PASS** | 1.32 |
| Phase 5 UI, overlays, declaration, and active-war save | Regression | **PASS** | 18.06 |
| Phase 6 deterministic economic, diplomatic, and military AI | Regression | **PASS** | 3.33 |
| Phase 6 campaign UI, objectives, overlay, and AI-state save | Regression | **PASS** | 18.20 |
| Phase 7 characters, dynasties, titles, succession, claims, and save | Regression | **PASS** | 1.44 |
| Phase 7 court UI, character AI, claim-war UI, and succession integration | Regression | **PASS** | 18.32 |
| Phase 8 country depth, subjects, events, formation, AI, and save | Regression | **PASS** | 1.45 |
| Phase 8 Country & State UI, map modes, commands, and save | Regression | **PASS** | 17.92 |
| GPU-rendered country label screenshots | Visual | **PASS** | 25.33 |

## Automated scope

This report covers the canonical country registry and ownership integrity, territory-safe country labels, projected overlap/layout baselines, label lifecycle and performance budgets, map selection/search, camera controls, responsive UI containment, deterministic calendar/commands/RNG, save corruption and migrations, graph/pathfinding/movement, economy, construction, recruitment, diplomacy, warfare and peace, utility AI, campaign objectives, characters/dynasties/titles/claims, marriages, commanders, opinions, ruler modifiers, health, birth, death and succession, government, stability, unrest, rebels, control, culture, religion, conversion, technology, ideas, cores, claims, subjects, events, decisions, country formation/release, country-depth AI and UI, deterministic replay through 1700, the hundred-year multi-generation soak, the twenty-year Iberian AI soak, the ten-year global soak, and Windows export startup.

## Human-only checks still required

- Visual polish and readability on the actual display/GPU.
- Mouse feel, tooltip timing, and panel ergonomics.
- Iberian economy scarcity and comparative country balance.
- Whether construction, recruitment, and maintenance choices are enjoyable.
- Combat pacing, siege duration, war-score costs, and diplomatic balance.
- Whether autonomous countries feel coherent, threatening, and distinct across repeated campaigns.
- Campaign-objective clarity and the usefulness of the AI inspector during real play.
- Character-window ergonomics, family-tree clarity, portrait direction, and death/succession feedback.
- Historical review of the representative 1444 Iberian rulers, families, dynasties, claims, and titles.
- Marriage, fertility, mortality, ruler-modifier, claim-war, and succession balance.
- Clarity of battle, occupation, and peace feedback during hands-on play.
- Final release-build signing, installer, and distribution checks.
