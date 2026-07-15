# MV-0 Rendering Architecture, Resolution, and Budget Decisions

## Decision state

These decisions close the MV-0 engineering spikes sufficiently to enter MV-1. Visual Greenlight still requires approval of all three target mock-ups, an external GPU trace, and resolution of release-blocking provenance.

## Anti-aliasing and sampling

### Accepted default

- Regional/close province, subject, sovereign, and coast borders use a canonical between-texel adjacency lattice with final-silhouette analytic AA; the country distance field is retained only as a distant strategic minification fallback.
- Province IDs, lookup maps, categorical terrain classes, categorical biomes, masks, and label territory IDs are lossless, unmipped, and nearest-sampled.
- Height is lossless with mipmaps and linear sampling because it is continuous displacement data.
- Terrain/water presentation art may use validated block compression, linear sampling, and mipmaps.
- Country glyphs use MSDF, linear sampling, and no bitmap mip transition.
- TAA and FXAA remain disabled by default because their whole-frame blur/ghosting directly harms atlas text and fine borders.
- 3D MSAA remains disabled on the low-end default. A measured 2× quality option may be added for later 3D map objects; it is not the solution for texture/shader-internal map edges.

### Implemented evidence

- `political_map.gdshader` replaces hard border branches with derivative-aware smooth masks.
- Libre Baskerville is imported as MSDF at a 64-pixel source size and 16-pixel range.
- Project AA defaults are explicit instead of inheriting engine changes.
- Categorical import violations found by the audit were corrected and reimported successfully in Godot 4.7.

## Label-rendering architecture

### Final architecture: batched screen-space atlas text

Retain the existing deterministic territory analysis, safe-fit, main-component selection, full-name lookup, angle, priority, collision, invalidation, and debug APIs. Replace one-`Label3D`-per-country rendering with a batched screen-space renderer using a shared MSDF glyph atlas and instance/mesh data.

The renderer must:

- accept world anchors and axes from the current layout system;
- project anchors/corners through the active camera;
- keep glyph weight stable in screen pixels;
- batch labels by font/material/pass;
- perform collision and tiny-label culling before draw submission;
- rebuild only labels invalidated by ownership/name/mode changes;
- provide exact draw-count, glyph-count, rebuild-time, and visible-label metrics;
- support localisation, authored line breaks, outline/shadow tiers, accessibility scale, and deterministic screenshots.

### Production implementation

The MV-1 renderer retains the deterministic territory, fit, collision, and invalidation system but projects glyphs into screen space and submits one `MultiMeshInstance2D` per active MSDF atlas page. The tested view uses three draw batches, 68 glyph instances, and zero `Label3D` nodes. The old node renderer remains code-only as a disabled fallback.

During compatible orthographic pans, existing batches receive an exact screen translation. Candidate/collision rebuilding occurs after 192 screen pixels or 90 ms after movement settles, preventing 700-country visibility work every motion frame while keeping labels attached to the map.

## Texture and resolution tiers

| Asset/layer | Source size | Import/sampling decision | Status |
|---|---:|---|---|
| Province authority | `5632×2048` | Lossless, no mips, nearest | Accepted; provenance blocked |
| Biome class | `5632×2048` | Lossless, no mips, nearest | Accepted; upstream licence review open |
| Terrain class | `5632×2048` | Lossless, no mips, nearest | Accepted; inherits province provenance |
| Lookup/masks | up to `5632×2048` | Lossless, no mips, nearest | Accepted; inherited provenance varies |
| Height macro | `2816×1024` | Lossless, mipped, linear | Accepted for MV-1/MV-3 slice; exact source archive open |
| Terrain macro colour | `2816×1024` | Compressed, mipped, linear | Accepted as macro layer |
| Water macro colour | `2816×1024` | Compressed, mipped, linear | Technically accepted; source rights blocked |
| Label territory IDs | `1408×512` | Lossless, no mips, nearest | Accepted for placement; derived-rights blocked |
| Future micro detail | Tileable regional material/normal textures | Mipped and quality-tiered | Required in MV-3; not baked into authority maps |

### Resolution conclusion

Keep full-resolution semantic authority and half-resolution continuous macro art. Add geographic detail through tileable micro material/normal layers rather than multiplying every full-world texture. A full-resolution height/water tier is not approved until MV-3 shows a visible benefit and the memory/load budget can afford it.

## Hardware target and budgets

These are provisional production budgets approved for MV-1 implementation. Phase 9 must validate multiple real machines before marketing minimum/recommended specifications.

### Development minimum tier

- CPU class: four modern cores/eight threads comparable to Ryzen 3 7320U.
- GPU class: Forward+-capable integrated GPU comparable to Radeon 610M.
- Reported graphics memory: 2 GiB.
- System memory: 6 GiB usable minimum for the current development baseline; 8 GiB is the release-planning floor.
- Target: 1280×720 low preset at 30 FPS during ordinary map interaction.

### Recommended validation tier

- CPU: four or more modern performance cores/eight threads.
- GPU: Forward+-capable discrete or strong integrated GPU with at least 4 GiB graphics memory.
- System memory: 8 GiB minimum, 16 GiB recommended.
- Target: 1920×1080 medium preset at 60 FPS during ordinary map interaction.

### Frame and memory budgets

| Budget | Development minimum | Recommended tier |
|---|---:|---:|
| Ordinary camera motion P95 | ≤ 33.3 ms | ≤ 16.67 ms |
| Ordinary camera motion P99 | ≤ 40 ms | ≤ 20 ms |
| Recurring interaction hitch | no frame > 50 ms | no frame > 33.3 ms |
| Map presentation GPU time | ≤ 24 ms | ≤ 11 ms |
| Simulation/UI CPU headroom | ≥ 6 ms | ≥ 4 ms |
| Country label render cost | ≤ 4 ms | ≤ 2 ms |
| Country label steady draw submissions | ≤ 8 | ≤ 4 |
| Total graphics allocation | ≤ 1.25 GiB | ≤ 3 GiB |
| Map texture allocation | ≤ 512 MiB | ≤ 1 GiB |
| Warm regional transition hitch | ≤ 50 ms once | ≤ 33.3 ms once |

Current evidence uses approximately 330–357 MiB texture memory and roughly 543–590 MiB total reported video allocation in the existing captures. The final 14 July 2026 post-batching probe measured all-layer 1920×1080 movement at `13.270 ms` P50, `14.716 ms` P95, and `25.106 ms` maximum with no frame above 50 ms on the Radeon 610M machine. The no-label motion P95 was `14.623 ms`, placing the ordinary-motion result inside the provisional 16.67 ms gate.

## External GPU profile gate

RenderDoc 1.45 is installed and successfully attached to the Godot 4.7 D3D12 build after the AMD driver update. A capture completed, while earlier attempts recorded D3D12 readback `E_OUTOFMEMORY` failures. A retained capture with event/pass analysis is still required; attachment success alone does not close this gate.

The gate requires a France/Low Countries orthographic capture containing:

- build/commit ID, Godot version, driver, GPU, resolution, projection, and graphics preset;
- event/pass list and GPU duration where supported;
- label glyph/draw passes, map subviewports, final map material, and UI composition;
- texture/render-target allocation and attachment formats;
- interpretation identifying the dominant pass and the next measured change;
- the capture file or a tool-generated report plus screenshot.

Visual Greenlight remains blocked until the capture artifact and pass-level interpretation are stored with the benchmark evidence.

## Provenance gate

Technical import validity does not establish commercial rights. The deterministic audit still reports release-blocking provenance for `provinces.bmp`, `definition.csv`, `colormap_water.png`, and derivatives. The biome and height sources also need exact version/licence/archive records.

Accepted outcomes are:

1. documented source, licence, redistribution permission, version, hash, attribution, and reviewer approval; or
2. replacement with project-owned/generated assets and regeneration of every derivative.

No milestone may convert an unknown source into “approved” merely because it imports, renders, or passes tests.
