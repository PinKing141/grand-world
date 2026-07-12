# Latest Headless Test Report

- Overall: **PASS**
- Completed: **23/23 checks passed**
- Started: `2026-07-12T07:23:08+01:00`
- Duration: **311.91 seconds**
- Platform: `Windows-11-10.0.26200-SP0`
- Python: `3.14.3`
- Godot: `C:\Users\Favour\Documents\Godot_v4.7-stable_mono_win64\Godot_v4.7-stable_mono_win64_console.exe`

## Results

| Check | Category | Result | Seconds |
|---|---|---:|---:|
| Terrain classification | Data | **PASS** | 0.53 |
| Biome classification | Data | **PASS** | 1.16 |
| Baked economy definitions | Data | **PASS** | 2.33 |
| Phase 1 map interaction | Regression | **PASS** | 17.89 |
| Camera controls | Regression | **PASS** | 10.81 |
| Responsive UI layout | Regression | **PASS** | 10.35 |
| Simulation core and save corruption | Regression | **PASS** | 1.35 |
| Frame-rate determinism | Regression | **PASS** | 1.65 |
| Phase 2 scene integration | Regression | **PASS** | 15.39 |
| Phase 3 graph, route, movement, and save | Regression | **PASS** | 1.10 |
| Phase 4 economy rules and edge cases | Regression | **PASS** | 1.22 |
| Phase 4 UI, heatmap, and save integration | Regression | **PASS** | 16.09 |
| Phase 5 diplomacy, war, battle, siege, peace, and save | Regression | **PASS** | 1.29 |
| Phase 5 UI, overlays, declaration, and active-war save | Regression | **PASS** | 19.59 |
| Phase 6 deterministic economic, diplomatic, and military AI | Regression | **PASS** | 4.56 |
| Phase 6 campaign UI, objectives, overlay, and AI-state save | Regression | **PASS** | 17.97 |
| Phase 7 characters, dynasties, titles, succession, claims, and save | Regression | **PASS** | 1.60 |
| Phase 7 court UI, character AI, claim-war UI, and succession integration | Regression | **PASS** | 18.01 |
| Hundred-year multi-generation character soak | Performance | **PASS** | 23.49 |
| Twenty-year Iberian AI soak | Performance | **PASS** | 13.91 |
| Ten-year full-world soak | Performance | **PASS** | 63.49 |
| Windows debug export | Packaging | **PASS** | 50.97 |
| Exported build startup | Packaging | **PASS** | 17.05 |

## Automated scope

This report covers map selection/search, camera controls, responsive UI containment, deterministic calendar/commands/RNG, save corruption and migrations, graph/pathfinding/movement, economy, construction, recruitment, diplomacy, warfare and peace, utility AI, campaign objectives, characters/dynasties/titles/claims, marriages, commanders, opinions, ruler modifiers, health, birth, death and succession, character AI and court UI, deterministic family replay, the hundred-year multi-generation soak, the twenty-year Iberian AI soak, the ten-year global soak, and Windows export startup.

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
