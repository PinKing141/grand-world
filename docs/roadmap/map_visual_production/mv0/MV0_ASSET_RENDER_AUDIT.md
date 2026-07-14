# MV-0 Asset and Render Audit

**Status:** Generated baseline; open findings require milestone decisions  
**Generator:** `python tools/map_visual_audit/build_map_visual_audit.py`  
**Stale check:** `python tools/map_visual_audit/build_map_visual_audit.py --check`

## Executive Summary

The audit tracks **13** required map assets, **4** active map shaders, and **21** findings. Finding distribution: P0=0, P1=12, P2=9.

This is a technical and provenance baseline, not an approval. It deliberately records risky import settings and missing presentation layers without changing runtime output before the MV-0 comparison spikes.

## Required Asset Inventory

| Asset | Role | Dimensions/format | Import summary | Licence/provenance |
|---|---|---|---|---|
| `assets/provinces.bmp` | Authoritative province-colour topology and land/water source | 5632×2048 BMP/RGB | compression=0; mipmaps=False | `unverified` |
| `assets/definition.csv` | Province colour and stable province definition source | n/a | n/a | `unverified` |
| `assets/biome_map.png` | Authoritative province-aligned biome class colour source | 5632×2048 PNG/RGBA | compression=2; mipmaps=True | `needs_review` |
| `assets/terrain_class_map.png` | Categorical water/owned/unowned/impassable lookup | 5632×2048 PNG/RGBA | compression=2; mipmaps=True | `inherits_unverified` |
| `assets/terrain_base_map.png` | Generated macro terrain colour presentation texture | 2816×1024 PNG/RGB | compression=2; mipmaps=True | `inherits_review` |
| `assets/heightmap.png` | Generated terrain elevation and displacement texture | 2816×1024 PNG/L | compression=2; mipmaps=True | `partially_documented` |
| `assets/colormap_water.png` | Ocean colour and bathymetric-looking presentation texture | 2816×1024 PNG/RGBA | compression=2; mipmaps=True | `unverified` |
| `assets/color_lookup_map.png` | Generated province colour to compact province-ID lookup | 5632×2048 PNG/RGB | compression=0; mipmaps=False | `inherits_unverified` |
| `assets/color_map.png` | Generated compact province-to-political-colour lookup | 256×256 PNG/RGBA | compression=0; mipmaps=False | `project_authored_review_needed` |
| `assets/mask_political_map.png` | Generated political land mask | 5632×2048 PNG/RGBA | compression=0; mipmaps=False | `inherits_unverified` |
| `assets/label_territory_map.png` | Generated conservative province-ID raster for label fitting | 1408×512 PNG/RGB | compression=0; mipmaps=False | `inherits_unverified` |
| `assets/noise.tres` | Procedural noise configuration used by the final map material | n/a | n/a | `project_authored` |
| `assets/fonts/LibreBaskerville-Variable.ttf` | Bundled country-label font | n/a | n/a | `verified_ofl_1_1` |

## Provenance Summary

| Status | Count |
|---|---:|
| `inherits_review` | 1 |
| `inherits_unverified` | 4 |
| `needs_review` | 1 |
| `partially_documented` | 1 |
| `project_authored` | 1 |
| `project_authored_review_needed` | 1 |
| `unverified` | 3 |
| `verified_ofl_1_1` | 1 |

The imported province topology, definition data, and water texture have no complete repository-level source/licence record. Every generated derivative that inherits those inputs remains unresolved for commercial distribution until the source is approved or replaced.

## Render Configuration

### Project settings

| Setting | Value |
|---|---|
| `config/features` | `PackedStringArray("4.7", "Forward Plus")` |
| `display/window/size/viewport_height` | `1080` |
| `display/window/size/viewport_width` | `1920` |
| `rendering/anti_aliasing/quality/msaa_3d` | `<engine default>` |
| `rendering/anti_aliasing/quality/screen_space_aa` | `<engine default>` |
| `rendering/anti_aliasing/quality/use_taa` | `<engine default>` |
| `rendering/renderer/rendering_method` | `<engine default>` |
| `rendering/renderer/rendering_method.mobile` | `<engine default>` |
| `rendering/rendering_device/driver.windows` | `d3d12` |
| `rendering/scaling_3d/mode` | `<engine default>` |
| `rendering/scaling_3d/scale` | `<engine default>` |
| `rendering/viewport/hdr_2d` | `True` |

### Scene facts

| Fact | Value |
|---|---|
| `plane_size` | `Vector2(56.32, 20.48)` |
| `plane_subdivide_width` | `351` |
| `plane_subdivide_depth` | `127` |
| `camera_controller_transform` | `Transform3D(1, 0, 0, 0, 0.258819, 0.965926, 0, -0.965926, 0.258819, 1.75674, 3.5915, -3.4793)` |
| `political_edge_size` | `0.106` |
| `province_edge_size` | `0.0341` |
| `province_border_color` | `Color(0, 0, 0, 0.0588235)` |
| `subviewport_count` | `3` |
| `shader_parameter_count` | `29` |

### Shader inventory

| Shader | Type/mode | Lines | Uniforms | Samplers |
|---|---|---:|---:|---:|
| `shaders/final_output_political_map.gdshader` | `spatial` / `unshaded` | 159 | 33 | 8 |
| `shaders/political_map.gdshader` | `canvas_item` / `unshaded` | 60 | 12 | 4 |
| `shaders/province_sdf.gdshader` | `canvas_item` / `<not declared>` | 61 | 3 | 2 |
| `shaders/country_sdf.gdshader` | `canvas_item` / `<not declared>` | 54 | 3 | 2 |

## Planned Presentation-Layer Gaps

| Layer | Candidate present | Matches |
|---|---|---|
| `normal_map` | **No** | None |
| `river_data_or_texture` | **No** | None |
| `coastal_shelf_or_foam_mask` | **No** | None |
| `vegetation_mask_or_object_data` | **No** | None |
| `seasonal_presentation_asset` | **No** | None |
| `roughness_or_material_parameter_map` | **No** | None |

## Findings

| Priority | Finding |
|---|---|
| **P1** | No explicit project anti-aliasing policy is recorded; MV-0 must capture and lock the chosen border/terrain/text strategy. |
| **P1** | assets/terrain_class_map.png is categorical/ID data but uses compress/mode=2; validate a lossless import path. |
| **P1** | assets/terrain_class_map.png is categorical/ID data but generates mipmaps; validate that distant sampling cannot blend semantic classes. |
| **P1** | The 56.32x20.48 map extent is duplicated in scene/camera/label code; RP-1.2 and CL-6.1 require one map transform authority. |
| **P1** | assets/heightmap.png drives geometry but uses a compressed import path; compare displacement error and memory before locking settings. |
| **P1** | assets/color_lookup_map.png has licence status inherits_unverified: Reproducible, but commercial rights depend on the original province map. |
| **P1** | assets/colormap_water.png has licence status unverified: Must be sourced, licensed, or replaced with an internally generated water asset. |
| **P1** | assets/definition.csv has licence status unverified: Critical dependency of province identity and every derived map bake. |
| **P1** | assets/label_territory_map.png has licence status inherits_unverified: Output is deterministic; original province-map rights remain unresolved. |
| **P1** | assets/mask_political_map.png has licence status inherits_unverified: Generated output must stay synchronized with its source hashes. |
| **P1** | assets/provinces.bmp has licence status unverified: Release blocker until ownership or a replacement path is documented. |
| **P1** | assets/terrain_class_map.png has licence status inherits_unverified: Treat as lossless data rather than colour artwork. |
| **P2** | No candidate asset was found for planned layer coastal_shelf_or_foam_mask. |
| **P2** | No candidate asset was found for planned layer normal_map. |
| **P2** | No candidate asset was found for planned layer river_data_or_texture. |
| **P2** | No candidate asset was found for planned layer roughness_or_material_parameter_map. |
| **P2** | No candidate asset was found for planned layer seasonal_presentation_asset. |
| **P2** | No candidate asset was found for planned layer vegetation_mask_or_object_data. |
| **P2** | assets/colormap_water.png is 2816x1024 while province authority is 5632x2048; approve this fidelity tier through MV-0 captures. |
| **P2** | assets/heightmap.png is 2816x1024 while province authority is 5632x2048; approve this fidelity tier through MV-0 captures. |
| **P2** | assets/terrain_base_map.png is 2816x1024 while province authority is 5632x2048; approve this fidelity tier through MV-0 captures. |

## MV-0 Decisions Required

1. Approve or replace the unverified province, definition, and water sources.
2. Compare lossless categorical/height imports against the current compressed/mipmapped settings before changing them.
3. Lock the anti-aliasing and texture-sampling policy using still and motion captures.
4. Approve the half-resolution terrain/water/height tier or choose a higher/tiled strategy.
5. Decide which missing normal, river, coast, vegetation, season, and material layers are required for 1.0.
6. Replace duplicated map extents with one authoritative map transform during MV-1.

## Reproduction

The JSON beside this document contains full hashes, image metadata, import settings, shader uniforms, and deterministic finding records. Do not hand-edit either generated output; update the source manifest/tool and rebuild.
