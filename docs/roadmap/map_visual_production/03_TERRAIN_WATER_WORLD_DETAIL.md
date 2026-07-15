# 03 — Terrain, Water, and World Detail

## Outcome

Build a geographically credible, painterly world material that supports strategic information. Terrain should make the Sahara, Alps, Nile, Baltic, Andes, steppe, forests, tropics, and coasts feel different without becoming a noisy satellite image.

## Current Baseline

The current pipeline already provides useful starting data:

- `tools/terrain/build_biome_map.py` classifies terrain/biome regions.
- `tools/terrain/build_heightmap.py` creates height information.
- `tools/terrain/build_terrain_base.py` combines hard biome colour, blurred biome colour, noise, elevation rock, and snow.
- The main terrain, height, and water outputs are currently lower resolution than the authoritative province map.
- The final shader applies simplified relief and static water composition.

The main visual shortcomings are the soft/blurred base, limited material separation, weak connected mountain forms, missing authored normal detail, absent river/vegetation/settlement layers, static water, and a coastline treatment that can read as an artificial halo.

## Terrain Data Model

Separate permanent geography from presentation.

### Permanent geographic data

- Land/ocean/lake mask.
- Elevation and bathymetry.
- Terrain/biome class.
- Mountain range/ridge importance.
- River centreline, width class, flow direction, source, mouth, and lake connections.
- Coastal shelf and beach/rock class where justified.
- Impassable/wasteland status.
- Climate normals needed for long-term biome presentation.

### Presentation data

- Macro terrain colour.
- Normal/roughness/detail material parameters.
- Vegetation density and object scatter masks.
- Snow/seasonal tint.
- Weather/cloud/fog masks.
- Coast foam and water motion.

Gameplay must never infer authoritative ownership or traversal solely from a presentation texture.

## Epic TW-1 — Source Audit and Geographic Authority

### TW-1.1 Inventory terrain sources — P1 / M

For every source and generated output, record:

- Origin and licence.
- Geographic projection and dimensions.
- Date/version.
- Resampling method.
- No-data and seam treatment.
- Manual corrections.
- Generated hashes and dependencies.

**Done when**

- A fresh clone can reproduce every derived terrain asset.
- No shipping texture depends on an undocumented downloaded image.
- Source rights are compatible with intended distribution.

### TW-1.2 Validate biome and climate transitions — P1 / L

Review representative cross-sections instead of judging only a world view:

- Mediterranean coast → Atlas → Sahara → Sahel.
- Atlantic Europe → Alps → Po Valley.
- Baltic forest → Scandinavian uplands → polar zone.
- Steppe → mountain → Central/South Asian climate.
- Congo/tropical forest → savanna.
- Andes elevation bands → Pacific/Atlantic lowlands.
- Monsoon mainland → maritime tropics.

**Done when**

- Hard errors and missing land receive explicit fixes in source data.
- Transitions are driven by geography/biome rules, not arbitrary blur alone.
- Historical/geographic review records known simplifications.

### TW-1.3 Establish elevation conventions — P1 / M

Define sea level, maximum rendered displacement, mountain emphasis, lake level, river relationship, and world-edge behaviour.

**Done when**

- Height sampling agrees across terrain, labels, markers, and selection.
- Relief exaggeration has wide/regional/close limits.
- Mountains remain readable without clipping labels or objects.

## Epic TW-2 — Macro Terrain and Relief

### TW-2.1 Replace the blur-led terrain base — P1 / L

Build a layered macro material using biome identity, elevation, slope, ridge importance, moisture/aridity, and low-frequency variation. Gaussian blending may soften transitions but must not define the whole look.

**Done when**

- Major biome boundaries are deliberate and geographically plausible.
- Political colours remain readable over every macro terrain class.
- The world does not look airbrushed or uniformly muddy at regional zoom.

### TW-2.2 Generate authored normal/slope data — P1 / L

Derive a world normal map from the approved height source, then add controlled detail normals by material. Avoid using tiny colour differences as fake relief.

**Done when**

- Connected ranges such as Alps, Atlas, Himalayas, Andes, Rockies, and Ethiopian Highlands read clearly.
- Plains do not acquire noisy fake mountains.
- Normal maps use correct import colour space and compression.
- Lighting remains stable during panning and zoom.

### TW-2.3 Define terrain material library — P1 / L

Minimum material families:

- Temperate plains/farmland.
- Temperate forest.
- Boreal forest/tundra.
- Steppe/grassland.
- Desert sand and desert rock.
- Sahel/semi-arid transition.
- Tropical forest.
- Wetland/marsh.
- Mountain/alpine rock.
- Snow/ice.
- Volcanic or other special terrain only where needed.

Each material defines macro hue/value, normal strength, roughness, tiling scale, vegetation relationship, border/label contrast response, and low-quality fallback.

**Done when**

- Materials tile without visible repetition at supported zooms.
- Detail does not shimmer or produce moiré.
- Terrain mode distinguishes families without a legend becoming necessary for obvious geography.

### TW-2.4 Art-direct relief by zoom — P1 / M

- Strategic zoom: low-contrast continental/range forms.
- Regional zoom: clear ridges, valleys, and biome texture.
- Close zoom: additional material detail without excessive displacement.

**Done when**

- Relief does not grow into a wall at the horizon.
- Screen-space slope/detail remains within the approved contrast range.
- Camera controls and selection remain accurate over displacement.

## Epic TW-3 — Hydrography

### TW-3.1 Create authoritative river data — P1 / XL, split before production

**Implementation status (15 July 2026):** Source-gated. The versioned `map_pixels` schema, provenance requirements, validator, template, and positive/negative contract tests are implemented under `tools/hydrography/`. No approved river source exists in the repository, so production river geometry is intentionally not invented or shipped. Source selection/licensing, populated data, downhill/network validation, and historical review remain.

Required river classes:

- Major navigational/geographic rivers.
- Secondary rivers important for terrain or movement.
- Optional minor decorative rivers only if affordable.

Data should include stable ID, points/segments, width class, source/mouth, connected lake/ocean, crossing metadata where gameplay needs it, and provenance.

Split into:

1. Source/import decision.
2. River graph validation.
3. Raster/vector render bake.
4. Gameplay crossing integration.
5. Regional correction passes.

**Done when**

- Rivers flow downhill within approved tolerance.
- No unexplained dead ends, ocean-to-inland reversals, or broken lake joins remain.
- Major rivers such as Nile, Danube, Rhine, Ganges, Yangtze, Mississippi, Amazon, and major regional equivalents receive manual review.

### TW-3.2 Render rivers by zoom and class — P1 / L

**Implementation status (15 July 2026):** Blocked by TW-3.1 content approval. The schema already carries major/secondary/minor width classes and strategic/regional/close visibility bands, but runtime rendering must wait for validated production river definitions.

- Strategic zoom: only the largest rivers, subtle.
- Regional zoom: major and secondary rivers.
- Close zoom: width/material detail and crossings as relevant.

**Done when**

- River width is screen-stable and never becomes a thick blue province border.
- Political and province borders remain distinguishable from rivers.
- Rivers do not disappear under common country colours.

### TW-3.3 Define lake and inland-water policy — P1 / M

**Implementation status (15 July 2026):** Engineering first pass live. A deterministic bake derives 50 named inland-lake provinces from the canonical province graph into `assets/lake_mask.png`; the final shader distinguishes lake surface and lake shore from ocean water and ocean coast. Automated checks cover exact raster area, water classification, shoreline contact, world-edge exclusion, and Maui/Oahu/Kauai tiny-island preservation. Historical naming/policy review, labels, and final art tuning remain.

Differentiate true lakes from ocean, decorative water, and unplayable holes. Define province selection/ownership behaviour for lake polygons.

**Done when**

- Lakes have correct coast, label, selection, and border treatment.
- Water masks contain no accidental land holes or unexplained empty spots.

## Epic TW-4 — Ocean and Coast Material

### TW-4.1 Build bathymetry/coastal shelf mask — P1 / L

Use distance from coast and source bathymetry where legally and technically appropriate. Keep shallow/deep transitions low contrast in political mode.

**Done when**

- Continental shelves improve coast form without becoming a glowing outline.
- Tiny islands are not swallowed by the shelf treatment.

### TW-4.2 Add controlled water motion — P1 / L

Candidate stack:

- Two low-frequency scrolling normal/noise layers with different direction/scale.
- View/light response restrained for an atlas surface.
- Optional coast foam driven by a dedicated mask.
- Optional route/trade currents as gameplay overlays, not baked decoration.

**Done when**

- Motion has no visible world seam.
- Pausing simulation does not need to freeze purely visual motion unless the settings policy says so.
- Reduced-motion mode can lower or disable movement.
- Low tier preserves water depth and coast readability with minimal animation.

### TW-4.3 Decide reflection/shadow scope — P2 / M spike

Reflections can be expensive and visually distracting. Prototype only after the core material meets quality.

**Ship rule**

- Reflection is optional, measured, and disabled on Low.
- Do not hold MV-3 for reflection if restrained non-reflective water meets the art target.

### TW-4.4 Fix map seams and boundaries — P1 / M

Test texture wrap, antimeridian/world edge, top/bottom edges, UV precision, and coast-distance generation.

**Done when**

- No red/blue debug line, texture seam, half-pixel gap, or repeated edge is visible in normal play.
- Mouse selection and labels agree across the full map boundary policy.

## Epic TW-5 — Vegetation, Snow, and Climate Presentation

### TW-5.1 Add restrained vegetation scatter — P2 / L

Vegetation is a regional material cue, not one tree for every forest pixel.

**Rules**

- GPU-instanced/batched representation.
- Density derived from authored biome masks.
- Aggressive distance culling and quality tiers.
- No forest object may obscure a border, label, capital, or unit marker.
- Avoid visually implying modern land use from contemporary source data.

### TW-5.2 Add seasonal presentation only after base terrain passes — P2 / L

If seasons ship in 1.0, use controlled regional tint/snow and vegetation state. Seasons must not require a unique world texture for every date.

**Done when**

- Date-to-season rules are deterministic presentation inputs.
- Hemisphere and climate zones behave plausibly.
- Snow does not erase ownership, rivers, or labels.
- Season transition cost stays within update budget.

### TW-5.3 Add weather/cloud/fog only as a subordinate layer — P3 / L

Weather is atmosphere, not a blocker for the political/terrain vertical slice. It must have reduced-motion/disable settings and cannot obscure active interaction.

## Epic TW-6 — Regional Content Passes

Each region uses the same review template:

1. Source and projection validation.
2. Land/water mask inspection.
3. Elevation/ridge review.
4. Biome/climate review.
5. River/lake/coast review.
6. Political-mode contrast review.
7. Terrain-mode beauty/readability review.
8. Label and marker occlusion review.
9. Performance and memory delta.
10. Historical/geographic approval and known simplifications.

## Asset Acceptance Checklist

- Correct dimensions, format, colour space, compression, filtering, and mip policy.
- Seamless where designed to tile.
- No baked political borders, labels, or current ownership in permanent terrain assets.
- No accidental copyrighted source content or missing licence.
- Deterministic generation command recorded.
- Source and output hashes recorded.
- Low/medium/high variants share semantic alignment.
- Visual baseline updated only with approval.

## Environment Exit Criteria

- Terrain mode is attractive and readable without political fill.
- Political mode preserves clear ownership over all terrain families.
- Sahara/Sahel, Alps, Scandinavia/Baltic, Nile, Southeast Asian islands, and Andes pass representative review.
- Major rivers, lakes, coastlines, and water seams are correct.
- Terrain and water motion are stable during camera movement.
- The complete environment stack passes performance/memory budgets and quality settings.
- Global assets are reproducible and legally cleared.
