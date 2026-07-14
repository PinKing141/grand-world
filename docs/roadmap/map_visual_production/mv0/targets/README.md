# MV-0 Target Concept Frames

This folder stores project-original visual-direction concepts used for side-by-side production review. They are not shipping map textures, do not replace province/ownership data, and must not be imported into the runtime as geographic truth.

Expected artifacts:

| File | Benchmark |
|---|---|
| `target_a_france_low_countries_political.png` | `tests/baselines/map_visual_mv0/current/current_france_low_countries_political_1920x1080.png` |
| `target_b_sahara_nile_terrain.png` | `tests/baselines/map_visual_mv0/current/current_sahara_nile_terrain_1700x960.png` |
| `target_c_italy_alps_integrated.png` | `tests/baselines/map_visual_mv0/current/current_italy_alps_political_1152x648.png` |

Prompts, invariants, layer ownership, and approval criteria are defined in [MV0_TARGET_MOCKUPS.md](../MV0_TARGET_MOCKUPS.md).

Do not approve a frame solely because it is attractive. Confirm historical/political semantics, readability, original identity, plausible runtime decomposition, and an achievable performance path.

