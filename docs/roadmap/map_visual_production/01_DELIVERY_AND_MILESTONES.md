# 01 — Delivery and Milestones

## Production Model

Use a vertical-slice-first model. A small cross-discipline strike team proves the final map language in hard representative regions, converts the result into tools and rules, and only then scales production globally.

This prevents three common failures:

- Polishing a shader that cannot support all required map modes.
- Hand-authoring the world before the pipeline and budgets are stable.
- Treating labels, borders, terrain, markers, and water as independent layers that later fight for the same screen space.

Do not assign calendar dates until team capacity and measured throughput are known. Use the dependency order, effort bands, and milestone gates below. After MV-2 and MV-3, estimate the global production schedule from actual region throughput and defect rates.

## Responsibility Model

One person may hold several roles, but every deliverable needs one accountable owner.

| Role | Accountable for |
|---|---|
| Product/Creative Direction | Target experience, scope, final visual approval |
| Art Direction | Palette, materials, typography, border language, reference captures |
| Technical Art | Shader graphs/code, texture strategy, LOD, asset budgets, authoring guidance |
| Rendering Engineering | Render architecture, map modes, GPU/CPU performance, compatibility |
| Map/Environment Art | Terrain, water, rivers, coasts, vegetation, settlements, regional polish |
| UX Design | Information hierarchy, interaction states, settings, accessibility |
| Content/Historical Research | Names, political setup, terrain/hydrography sources, historical review |
| Tools/Data Engineering | Importers, bakes, validators, registries, content reports |
| QA/Performance | Test matrix, captures, visual regression, hardware profiles, defect triage |
| Production | Dependencies, milestone health, change control, risk and approval records |

For a solo developer, write the role next to each task anyway. It forces separate art, engineering, historical, and QA reviews instead of treating a successful implementation as automatic approval.

## Effort Bands

| Band | Meaning |
|---|---|
| XS | Isolated documentation, data correction, or test update |
| S | Small contained feature with known architecture |
| M | Multi-file feature or content tool with moderate integration |
| L | Cross-system feature, new render layer, or regional content pass |
| XL | Epic that must be split before implementation begins |

Effort is not duration. Re-estimate after technical spikes and vertical slices.

## Milestone MV-0 — Direction Lock

**Objective:** Make the target explicit and measure the current baseline.

**Implementation status:** In progress. See the live [MV-0 working package](mv0/README.md) and [gate status](mv0/MV0_STATUS.md). The reproducible capture/audit foundation is implemented and a hidden global-checksum stall was fixed; target mock-ups, external GPU pass evidence, source-rights resolution, and remaining decision spikes are open.

### Required work

| ID | Deliverable | Lead role | Effort | Dependency |
|---|---|---|---|---|
| MV0-01 | Capture current map at standard camera bookmarks, modes, resolutions, and graphics settings | QA/Performance | S | None |
| MV0-02 | Record CPU/GPU frame capture, texture memory, load time, and panning hitches | Rendering + QA | M | MV0-01 |
| MV0-03 | Approve legal reference board and visual thesis | Art Direction | M | None |
| MV0-04 | Produce political, terrain, water, and typography target mock-ups | Art Direction + Technical Art | L | MV0-03 |
| MV0-05 | Define wide/regional/close zoom bands and layer visibility matrix | UX + Art Direction | M | MV0-04 |
| MV0-06 | Write render-layer architecture and technical decision records | Rendering Engineering | M | MV0-02, MV0-04 |
| MV0-07 | Establish reference hardware and provisional budgets | QA/Performance | S | MV0-02 |
| MV0-08 | Audit all source textures/data for resolution, ownership, and licensing | Production + Content | M | None |
| MV0-09 | Resolve repository preflight debt affecting reproducible map builds | Engineering | S | None |

### Decisions that must be locked

- Forward+ as the primary rendering method and the minimum fallback policy.
- Whether the base map remains one world mesh/texture stack or moves to tiled/streamed regions.
- Anti-aliasing and texture-filtering strategy.
- Label rendering architecture: 3D label, projected decal, screen-space text, or hybrid.
- Political palette ownership and subject/uncolonised/wasteland semantics.
- Height/normal-map resolution and texture-memory tier.
- Water quality tiers and whether reflection is in 1.0 scope.
- River data representation and authoring pipeline.

### Visual Greenlight gate

- All deliverables above are approved.
- The target mock-ups solve the current dark/saturated fill, heavy border, cyan coast, blurry terrain, and blurry-label problems.
- The planned stack has a credible 60 FPS cost projection.
- No source/provenance blocker is hidden behind placeholder content.

## Milestone MV-1 — Readability Foundation

**Objective:** Fix technical output quality and semantic hierarchy before adding decoration.

### Required work

| ID | Deliverable | Lead role | Effort | Dependency |
|---|---|---|---|---|
| MV1-01 | Implement stable render-layer ownership and map-mode state contract | Rendering | L | MV0-06 |
| MV1-02 | Establish sharp full-resolution output, texture import rules, mip behaviour, and camera sampling | Rendering + Technical Art | L | MV0-06 |
| MV1-03 | Implement zoom-aware coast/country/province/interaction border stack | Rendering | L | MV1-01 |
| MV1-04 | Normalize political palette and neighbour-readability tooling | Art + Tools | M | MV0-04 |
| MV1-05 | Define sovereign, subject, uncolonised, wasteland, ocean, occupation, and control semantics | Design + UX | M | MV0-05 |
| MV1-06 | Remove bright coastline halo and edge artefacts | Rendering | M | MV1-02, MV1-03 |
| MV1-07 | Replace debug/placeholder map markers visible in normal play | Map Art + UX | M | MV1-01 |
| MV1-08 | Add capture tests for border width, palette, and mode switching | QA | M | MV1-03, MV1-04 |

### Readability Gate

- Ownership is unambiguous in France/Low Countries, Italy, Sahara, and maritime Southeast Asia.
- Orléans and equivalent subject/appanage countries keep their own province ownership and visible colour under the default political policy.
- Country borders are consistently stronger than province borders.
- Panning and zooming produce no obvious shimmer, stair-step instability, texture seam, or recurring hitch.
- Debug mode can show raw province identity without decorative interference.

## Milestone MV-2 — Political Atlas Vertical Slice

**Objective:** Demonstrate near-final political map quality in Iberia, France, the Low Countries, Italy, and the western Mediterranean.

### Required work

- Final political colour script for the slice.
- Border hierarchy under normal, selected, war, occupation, subject, and diplomatic states.
- Terrain contribution tuned for political mode.
- Country-label sharpness, hierarchy, and collision integration for the slice.
- Capitals, ports, armies, and selection markers at representative quality.
- Wide/regional/close LOD rules.
- Supported aspect-ratio and UI-scale captures.
- GPU/CPU profile with every slice layer enabled.

### Political Vertical Slice gate

- Art Direction, UX, Rendering, and QA approve the same packaged build.
- The slice remains readable in motion, not only in screenshots.
- Dense Europe does not become confetti at normal campaign zoom.
- No visible tag abbreviations replace country names.
- All slice ownership changes update colours, borders, labels, and markers correctly.
- The slice meets provisional frame and update budgets with at least 20% map-presentation headroom for global outliers.

## Milestone MV-3 — Geographic Material Slice

**Objective:** Prove the final terrain, relief, water, coast, and river pipeline across representative geography.

### Required regions

- Alps/Italy for mountain relief and dense political overlays.
- Sahara/Sahel/Nile for desert material, wasteland, transition, and major river.
- Scandinavia/Baltic for snow, forest, coasts, islands, and straits.
- Maritime Southeast Asia for coast density and water stress.
- Andes for long mountain relief and climate variation.

### Environment Gate

- Terrain mode is attractive and geographically legible without political colour.
- Political mode remains readable over every representative material.
- Rivers join sources, lakes, crossings, and coasts without visible discontinuities.
- Ocean/coast motion is restrained, seamless, and within budget.
- Low graphics settings preserve geographic meaning.
- The content team can build a new reviewed region through documented tools without shader-code changes.

## Milestone MV-4 — Labels and Identity

**Objective:** Finish country identity, typography, localisation, placement, map-mode behaviour, and campaign lifecycle.

All open P2–P4 work from the previous country-label audit is scheduled here or in its named prerequisite milestone. Detailed tasks are in [04 — Country Labels and Localisation](04_COUNTRY_LABELS_LOCALISATION.md).

### Typography Gate

- All 1444 active-country names have editorial review and provenance status.
- Localised display names and adjectives resolve through one service.
- Dynamic/formable naming has deterministic save/load behaviour.
- Disconnected realm rules are approved for named outliers.
- Labels remain crisp and correctly prioritised in every shipping map mode.
- Long, diagonal, island, microstate, transcontinental, and right-to-left/extended-character test cases pass the supported localisation policy.

## Milestone MV-5 — Living Map

**Objective:** Integrate essential settlements, capitals, ports, armies, battle/occupation feedback, ambient detail, and LOD without losing atlas readability.

### Presentation Alpha gate

- Every gameplay-relevant marker has a clear silhouette and state language.
- Marker/label/border priority is deterministic.
- Decorative objects cull and batch correctly.
- Reduced motion, low detail, and clutter controls work.
- No marker state exists only in colour; shape/icon/pattern alternatives support accessibility.

## Milestone MV-6 — Global Production

**Objective:** Apply approved materials, labels, hydrography, markers, and palette rules to the whole playable world.

### Production waves

1. Western/Central Europe and Mediterranean.
2. Eastern Europe, steppe, Middle East, and North Africa.
3. Sub-Saharan Africa.
4. South, Central, East, and Southeast Asia.
5. North and South America.
6. Oceania, islands, polar, and global outliers.

This order is a pipeline suggestion, not a historical priority. Reorder waves when the content team or source data makes another sequence safer.

Each wave requires:

- Automated data/bake validation.
- Historical/geographic content review.
- Art pass at three zoom bands.
- Political readability and colour review.
- Label outlier review.
- Performance/memory delta capture.
- Defect triage before the next wave doubles scope.

### Visual Content Complete gate

- No region uses a known placeholder base, debug marker, missing river class, or unreviewed ownership visual.
- Regional capture matrix passes.
- All generated outputs reproduce from source data.
- Art and historical provenance records are complete.
- Remaining P2/P3 waivers have owners, fallbacks, and release approval.

## Milestone MV-7 — Optimisation and Beta

**Objective:** Feature lock the visual stack and harden it across global play, hardware, resolutions, settings, and long sessions.

### Required activities

- GPU frame analysis at worst-case zooms and modes.
- CPU profiling during camera motion, map-mode changes, peace transfers, and mass occupation.
- VRAM and system-memory tracking through repeated load/save and century soak.
- Shader permutation and texture residency review.
- LOD/culling tuning with representative armies and markers.
- Colour-blind, UI-scale, reduced-motion, and text-readability review.
- Driver/GPU compatibility and export verification.
- Golden-image triage and intentional baseline lock.

### Visual Beta gate

- No P0 or unmitigated P1 map-visual defect remains.
- Performance and compatibility budgets pass on the reference matrix.
- New visual features are locked; changes are bug fixes, tuning, localisation layout, and approved accessibility corrections.
- A full campaign soak shows no unbounded map-layer memory growth.

## Milestone MV-8 — Release Candidate

**Objective:** Prove that the shipping build contains the approved, legal, stable, and reproducible map presentation.

### Visual RC gate

- Clean install and packaged build display every required map asset.
- No editor-only import dependency is required at runtime.
- Asset licences and source provenance pass review.
- Country names, ownership, borders, and labels match authoritative campaign data after new game, save, load, formation, release, annexation, and peace transfer.
- All supported graphics settings have intentional output.
- Release captures, known issues, and baseline hashes are archived with the build ID.

## Work-in-Progress Limits

- Only one render-foundation epic may be on the critical path at a time.
- Do not run global terrain, global label editorial review, and global object placement as unmanaged parallel content floods.
- Limit regional production to one active wave plus one review/fix wave.
- Any new visual feature after MV-5 must displace named scope or move to post-1.0.
- If a vertical-slice feature misses budget, reduce layers or complexity before scaling it globally.

## Change Control

Every request that changes the locked visual target must state:

1. Which product pillar it improves.
2. Which milestone it enters.
3. Which existing work it displaces.
4. New asset, localisation, testing, memory, and compatibility cost.
5. Whether it changes a content or save schema.
6. Whether existing golden captures should intentionally change.
7. The fallback if it cannot ship.
