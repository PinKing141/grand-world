# Latest Headless Test Report

- Overall: **PASS**
- Completed: **26/26 checks passed**
- Started: `2026-07-12T23:58:39+01:00`
- Duration: **335.90 seconds**
- Platform: `Windows-11-10.0.26200-SP0`
- Python: `3.14.3`
- Godot: `C:\Users\Favour\Documents\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`

## Results

| Check | Category | Result | Seconds |
|---|---|---:|---:|
| Terrain classification | Data | **PASS** | 0.60 |
| Biome classification | Data | **PASS** | 1.14 |
| Baked economy definitions | Data | **PASS** | 1.24 |
| Phase 1 map interaction | Regression | **PASS** | 11.14 |
| Camera controls | Regression | **PASS** | 10.20 |
| Responsive UI layout | Regression | **PASS** | 10.00 |
| Simulation core and save corruption | Regression | **PASS** | 1.11 |
| Frame-rate determinism | Regression | **PASS** | 1.65 |
| Phase 2 scene integration | Regression | **PASS** | 17.22 |
| Phase 3 graph, route, movement, and save | Regression | **PASS** | 0.92 |
| Phase 4 economy rules and edge cases | Regression | **PASS** | 0.91 |
| Phase 4 UI, heatmap, and save integration | Regression | **PASS** | 16.10 |
| Phase 5 diplomacy, war, battle, siege, peace, and save | Regression | **PASS** | 1.23 |
| Phase 5 UI, overlays, declaration, and active-war save | Regression | **PASS** | 16.71 |
| Phase 6 deterministic economic, diplomatic, and military AI | Regression | **PASS** | 3.78 |
| Phase 6 campaign UI, objectives, overlay, and AI-state save | Regression | **PASS** | 18.78 |
| Phase 7 characters, dynasties, titles, succession, claims, and save | Regression | **PASS** | 1.47 |
| Phase 7 court UI, character AI, claim-war UI, and succession integration | Regression | **PASS** | 17.65 |
| Phase 8 country depth, subjects, events, formation, AI, and save | Regression | **PASS** | 1.48 |
| Phase 8 Country & State UI, map modes, commands, and save | Regression | **PASS** | 17.88 |
| Phase 8 deterministic 1444-1700 Alpha campaign | Performance | **PASS** | 47.60 |
| Hundred-year multi-generation character soak | Performance | **PASS** | 20.24 |
| Twenty-year Iberian AI soak | Performance | **PASS** | 9.68 |
| Ten-year full-world soak | Performance | **PASS** | 66.62 |
| Windows debug export | Packaging | **PASS** | 26.06 |
| Exported build startup | Packaging | **PASS** | 14.41 |

## Automated scope

This report covers map selection/search, camera controls, responsive UI containment, deterministic calendar/commands/RNG, save corruption and migrations, graph/pathfinding/movement, economy, construction, recruitment, diplomacy, warfare and peace, utility AI, campaign objectives, characters/dynasties/titles/claims, marriages, commanders, opinions, ruler modifiers, health, birth, death and succession, government, stability, unrest, rebels, control, culture, religion, conversion, technology, ideas, cores, claims, subjects, events, decisions, country formation/release, country-depth AI and UI, deterministic replay through 1700, the hundred-year multi-generation soak, the twenty-year Iberian AI soak, the ten-year global soak, and Windows export startup.

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
