# Country Names and Map Labels — Priority Audit

**Audit date:** 14 July 2026  
**Status:** P0 and P1 complete and verified; P2–P4 migrated into the Strategic Map Visual Production Roadmap  
**Scope:** Country-name source data, runtime loading, political colours, map-label placement, visibility, performance, export behaviour, and automated coverage  
**Primary implementation:** `scripts/ui/country_label_layer.gd`

> **Successor production plan:** This audit remains the detailed implementation and evidence record for completed P0/P1 work. All unfinished P2–P4 tasks are now scheduled, prioritised, and traced in [Strategic Map Visual Production Roadmap](map_visual_production/README.md), especially [Country Labels, Names, and Localisation](map_visual_production/04_COUNTRY_LABELS_LOCALISATION.md) and [Audit Traceability, Priority Backlog, and Risks](map_visual_production/08_AUDIT_TRACEABILITY_RISKS.md).

## Executive Summary

The critical catalogue and player-facing P0/P1 work is implemented and verified. Country identity now has one generated authority; labels use conservative political raster samples, follow the dominant axis of each main land body, collide in bounded projected screen space, update incrementally, use a bundled serif font, and have direct layout, lifecycle, performance, export, and rendered screenshot gates. P2–P4 still contain architecture, content-quality, presentation-polish, save-compatibility, and repository-hygiene work, so the overall feature is not content-complete. Those open items are no longer an unsequenced audit backlog: they are governed by the dedicated map-visual roadmap linked above.

Work should proceed in the following order:

| Priority | Meaning | Release treatment |
|---|---|---|
| P0 | Data integrity or campaign correctness risk | Must be completed before further country-content scaling |
| P1 | Major player-facing correctness, readability, or performance problem | Must be completed before Phase 9 Alpha gate |
| P2 | Important architecture, UX, and content-quality work | Complete before content-complete/Beta |
| P3 | Presentation polish and future-proofing | Complete before release candidate where practical |
| P4 | Repository hygiene and optional refinements | Schedule when higher priorities are stable |

## Pre-P0 Verified Baseline

The following checks passed during the audit:

- Phase 1 map-interaction smoke test.
- Responsive UI layout smoke test at `1700x960` and `1152x648`.
- Phase 8 integration smoke test.
- Windows debug export.
- Exported headless startup.
- Export contained the compiled country-label script.
- Exported startup reported `Parsed Countries:1010`.

These passes prove that the feature loads and packages. They do **not** prove that labels fit countries, avoid overlap, remain readable, or update correctly during a campaign.

---

## P0 — Data Integrity and Authoritative Source

**Implementation status:** Complete — 14 July 2026

P0 now has a generated authority at `assets/country_registry.json`, built and checked by `tools/country_registry/build_country_registry.py`. Campaign bootstrap consumes that registry directly, validates imported ownership before creating `WorldState`, and then regenerates the native `CountryData` presentation dictionaries from the same source. `No Owner` and `Ocean` are explicit non-scenario pseudo-countries and cannot enter the playable/runtime country catalogue.

Verification completed after implementation:

- Canonical registry check: 1,007 unique countries, 703 manifest owner tags, and 2 non-playable pseudo-countries.
- Runtime ownership test: all 1,007 registry countries enter `WorldState`; all 36 countries previously absent from the scene cache retain starting territory; every non-empty province owner resolves.
- Complete quick regression suite: 22/22 checks passed across data validation and Phases 1–8.
- Windows debug export and exported headless startup passed with the registry and loader present in the package.
- Corrected import baseline: `Parsed Provinces:3924`, `Parsed Country Colors:1021`, and `Parsed Countries:1009`.

### P0.1 Remove the conflicting duplicate `KER` definition

**Complete.** `assets/countries/KER - Keres.txt` and `assets/country_colors/Keres.txt` are authoritative. The malformed `KER- Keres.txt`/`eres.txt` records were removed, the scene mirror was corrected to `Keres`, and RGB `183, 76, 132` is enforced by the runtime integrity test.

At audit time, two different files defined the same country tag:

- `assets/countries/KER - Keres.txt`
- `assets/countries/KER- Keres.txt`

The second filename did not follow the required `TAG - Name.txt` convention. Fixed-offset parsing turned `Keres` into `eres`, which was serialized in `scenes/main.tscn` as `"KER": "eres"`.

The files were not duplicates of identical content. They contained different reforms and other history details. Their associated colour files also conflicted:

- `Keres`: RGB `183, 76, 132`
- `eres`: RGB `162, 28, 58`

The pre-P0 serialized political colour showed that the malformed `eres` record won the last parse. Parser or filesystem ordering could therefore decide which definition became active.

**Impact**

- Incorrect visible country name.
- Conflicting country history and reforms.
- Conflicting political colour.
- Order-dependent results between tools or platforms.
- Future edits may modify the wrong file.

**Done when**

- Exactly one country file exists for tag `KER`.
- Exactly one matching colour definition is authoritative.
- Its filename follows the required convention.
- A validator fails on any duplicate tag or malformed filename.
- Main-scene data is regenerated from the chosen canonical record.

### P0.2 Establish one canonical country registry

**Complete.** The generated record owns each tag's display name, name/adjective localisation keys, canonical source paths and hashes, political colour, scenario/selectable flags, and review status. Startup no longer uses the presentation name dictionary as the validity list for campaign countries. P1.4 subsequently removed the two temporary display-name exceptions, so the canonical catalogue now requires unique active names.

Country identity and display data currently exist in several places:

- Country filenames.
- The serialized `CountryData` dictionaries in `scenes/main.tscn`.
- `docs/data/1444_ownership_manifest.csv`.
- Country colour filenames and files.
- Direct UI lookups against `CountryData`.
- Before the July 2026 full-name pass, some presentation paths fell back to raw tags when a name was missing.

At audit time there were 1,008 country files but only 1,007 unique tags because of the duplicate `KER` record. The main scene serialized only 973 country-name entries, including `Ocean` and `No Owner`.

The following 36 asset tags are absent from the serialized name dictionary:

`ALQ, ALU, BEM, CMR, DNE, DUA, EVK, FMC, GCH, GLC, HET, HRP, INU, JUK, JVR, KHN, KSN, KWK, KYU, LGT, LST, MIC, NCN, NGU, NIL, NNT, OGE, PNG, RPN, SHC, SKH, SWZ, TEH, THT, TSW, TZI`

Before P0, normal startup reparsed the country folder and restored the runtime list. However, `CampaignScenarioDefinition` used the name dictionary as the list of valid countries. If an imported province owner was absent, the owner was replaced with an empty string.

**Impact**

- A parser failure, missing addon, startup-order change, or alternate scene can silently turn valid countries into unowned land.
- Static scene data and runtime data disagree.
- Save/debug behaviour depends on presentation data being loaded first.
- Content tools cannot reliably know which source is authoritative.

**Done when**

- A single generated registry owns tag, name key, adjective key, colour reference, and content path.
- Scenario bootstrap consumes that registry directly rather than a UI dictionary.
- Every manifest owner resolves to exactly one country.
- Every country resolves to exactly one political colour.
- Generated scene/runtime caches are reproducible and validated against the registry.
- Missing owners fail loudly instead of becoming unowned land silently.

### P0.3 Add a blocking country-data validator

**Complete.** `python tools/country_registry/build_country_registry.py --check` performs source and generated-output validation, while `tests/country_registry_test.gd` verifies the packaged runtime/bootstrap ownership contract. Both are registered in `tools/testing/run_all_tests.py`; export validation also requires the registry and loader.

Before P0, no automated gate validated the complete country catalogue.

The validator must reject:

- Duplicate tags.
- Malformed country filenames.
- Missing or empty display names.
- Missing colour records.
- Duplicate active aliases unless explicitly approved.
- Manifest owners without a country definition.
- Province owners without a valid tag.
- Registry/scene cache mismatches.
- Unresolved localisation keys.
- Unexpected pseudo-country records in playable-country lists.

**Done when**

- Validation runs in local headless tests and CI.
- A duplicate such as the current `KER` files makes the test fail.
- The generated report names the exact file and tag responsible.
- Phase 9 content imports cannot complete when validation fails.

---

## P1 — Player-Facing Correctness and Performance

**Implementation status:** Complete — 14 July 2026

P1 replaces the prototype with one lazily-created `Label3D` per visible country, fitted against `assets/label_territory_map.png`. The quarter-resolution bake accepts a cell only when its complete `4x4` full-resolution source block belongs to one province. Runtime layout measures the main connected body's raster covariance, rotates the name along its dominant axis within a readable `±72°` limit, and derives its scale from the oriented geographic extent. Tiny or ambiguous bodies retain deterministic conservative/screen fallbacks. Screen collision projects the rotated font/outline footprint through the active camera, clips horizon-scale projections to the viewport, and uses a spatial grid; camera transform, zoom, viewport size, font, map mode, ownership, and reload changes all invalidate the correct layer.

Verification completed after implementation:

- 703 starting territorial country layouts; every layout uses its canonical full display name and zero layouts use a country tag. A complete ownership/annexation/save-load lifecycle run ended with 702 active layouts: 581 raster-fitted, including 546 shape-aligned labels, and 121 close-zoom screen fallbacks.
- Representative shape-aware performance run: 362.3 ms total layout CPU spread across frames, 8.6 ms worst four-country layout batch, 1.1 ms incremental rebuild, 13.9 ms visibility pass, and sub-millisecond lazy-node allocation batches.
- Default view instantiates fewer than 250 nodes; maximum zoom is capped at 450. The pre-P1 estimate was roughly 2,434 label-layer scene nodes.
- Country-label logic/lifecycle test, five-view projected-layout baseline, and five GPU-rendered PNG comparisons passed. The new focused views lock Sweden's diagonal axis and Naples' Italian-peninsula axis in addition to the world, dense-Europe, and island-Southeast-Asia views.
- Complete quick-plus-visual regression suite: 26/26 checks passed across data validation, Phases 1–8, deterministic label layouts, and GPU-rendered label screenshots.
- Windows debug export passed with the registry, territory bake, bundled font, and label renderer packaged. A fresh direct launch on 14 July 2026 also passed and reported `Parsed Countries:1009`; the earlier Windows Application Control `error 4551` did not recur. The automated gate retains its trusted-host PCK fallback in case that machine policy blocks a future unsigned temporary executable.
- Current import baseline: `Parsed Provinces:3924`, `Parsed Country Colors:1023`, and `Parsed Countries:1009`.

### P1.1 Replace the current overlap model with screen-space bounds

**Complete.** Every candidate uses the bundled font's measured text/outline size, its rotated world transform, and all four projected camera-space corners. Collision uses full rectangles plus three pixels of screen padding and a spatial hash. Projected rectangles are intersected with the padded viewport before grid insertion, preventing near-horizon labels from producing unbounded work. Off-screen labels are culled before collision, and transform/zoom/pan/viewport changes trigger a new pass. The renderer intentionally uses one shape-aligned straight label instead of the former per-glyph curved path, eliminating the inaccurate curved-footprint case.

The current overlap pass does not compare the actual rendered screen bounds of labels.

Confirmed problems:

- Curved text is laid out around the country mean, but its collision rectangle is centred on a province anchor called `seat`.
- Rotated straight text uses an unrotated axis-aligned footprint.
- Curvature and per-character rotation are not included in the footprint.
- Camera perspective and tilt are ignored.
- Collision rectangles are reduced to 62% of the calculated footprint, allowing outer glyphs to overlap.
- Visibility is recalculated when camera height changes, but not for horizontal panning or viewport resizing.
- Font fallback can change the actual bounds without changing the stored assumptions.

**Impact**

- Names can overlap even though the collision pass reports no collision.
- A label can be hidden by a rectangle that does not match the visible text.
- Results can change by resolution, aspect ratio, or operating system.
- Repeated size/tolerance tuning cannot solve the underlying geometry error.

**Done when**

- Collision uses the projected screen-space bounds of the rendered label.
- Curved labels account for every glyph or an accurate combined hull.
- Camera movement, zoom, viewport resize, and font changes invalidate the layout.
- Automated scenarios cover dense Europe, fragmented islands, long names, and multiple resolutions.
- No visible overlap exceeds the approved art-direction tolerance.

### P1.2 Make label fitting use political territory, not only province anchors

**Complete for P1.** `tools/map_labels/build_label_territory_map.py` bakes a conservative province-ID raster from `provinces.bmp`; its hashes and exact PNG output are blocking data gates. Runtime uses those owned samples to place the canonical full name at the main body's geographic centre, align it to the dominant territory axis, and scale it from the major/minor extents. Low-anisotropy shapes remain horizontal and every rotation is capped for readability. When a full name cannot remain readable inside a small territory, it keeps that full name and becomes visible only at close zoom through the screen fallback. Internal tags are never substituted for visible country names. Highly concave countries and optional curved centrelines remain P2/P3 art-direction work.

The current system fits names to province centre anchors. It does not inspect the actual country polygon or safe interior.

Consequences include:

- Text can cross the sea or a neighbouring country.
- Concave and crescent-shaped countries cannot be fitted reliably.
- Province area is ignored.
- A few large provinces and many small provinces are represented only by point distribution.
- The calculated centre may not be the visual centre of the territory.

There are approximately 225 starting countries whose selected main component contains one province. Their calculated span is zero, after which the hard minimum text size is used. Long names therefore do not genuinely fit those provinces.

**Done when**

- Placement uses a baked country/province shape representation or another verified safe-area method.
- The baseline and glyph path remain within owned territory or an approved tolerance.
- One-province countries keep their full name and use a deterministic screen-space fallback when necessary.
- Long-name behaviour is deterministic and art-directable.

### P1.3 Stop rebuilding the entire world for one ownership change

**Complete.** Ownership events queue only the old and new tags, with at most four layouts processed per frame. Formation, release, extinction, and world-reload signals have explicit lifecycle handling. Hidden labels are not instantiated, a country uses at most one label node, node creation is capped at 24 per frame, off-screen candidates are culled, and annexed-country nodes are reclaimed. The direct gate enforces CPU, frame-batch, visibility, node-allocation, and node-count budgets.

The 1444 audit model estimates that the layer creates:

- About 703 country holder nodes.
- 559 straight labels.
- 144 curved labels.
- About 1,731 individual `Label3D` nodes.
- Roughly 2,434 scene nodes in total for the label layer.

All are allocated before zoom culling, including labels that are immediately hidden.

Any province ownership change marks the whole layer dirty. The next rebuild recalculates every country’s components, principal axis, curve, font metrics, glyph transforms, and overlap state.

Additional costs:

- Eliminated countries retain their holders and glyphs.
- Glyph pools grow but never shrink.
- Curved names use one `Label3D` per character.
- Every glyph has an outline and disabled depth testing.
- Overlap checks can approach quadratic behaviour when many labels qualify.

**Impact**

- Startup presentation cost.
- Frame spikes after peace, annexation, release, or country formation.
- Possible contribution to map-panning and menu-presentation lag.
- Long-campaign memory growth.

**Done when**

- Ownership events identify only affected old/new countries.
- Layout recomputation is incremental and budgeted.
- Hidden labels are not fully instantiated until needed, or are rendered through a batched system.
- Dead-country resources can be reclaimed.
- Profiling records startup time, rebuild time, visible draw count, and long-session memory.
- Performance gates cover default, Europe-close, and maximum-zoom views.

### P1.4 Resolve duplicate visible names and colour collisions

**Complete.** Irish `MNS` remains `Munster`; German `MUN` is now `Münster`. East African `SFA` remains `Sofala`; `SOF`, whose source history is for the Bambara state, is now `Segu`. The eight exact colour pairs were separated. The registry now rejects every exact RGB duplicate and checks all 1,542 starting land-neighbour country pairs using a minimum Oklab distance of `0.04`. Search results already include both display name and tag.

At audit time, two tag pairs shared both their display name and exact political colour:

- `MNS` and `MUN`: `Munster`, RGB `205, 133, 117`.
- `SFA` and `SOF`: `Sofala`, RGB `55, 108, 158`.

Six additional exact political-colour collisions existed:

- `RAS` Rassids / `ROT` Rothenburg — RGB `194, 16, 16`.
- `BLG` Bologna / `HAM` Hamburg — RGB `194, 87, 16`.
- `UES` Uesugi / `WAI` Waitaha — RGB `200, 176, 176`.
- `FEZ` Fez / `GDW` Gondwana — RGB `224, 146, 113`.
- `MGR` Maregh / `SMI` Sami — RGB `252, 209, 22`.
- `BHU` Bhutan / `SKK` Sikkim — RGB `93, 180, 76`.

**Impact**

- Ambiguous country search and UI text.
- Indistinguishable map labels.
- Countries may look politically identical.
- Borders can become unclear if colliding countries become adjacent.

**Done when**

- Active country names are unique or have approved contextual disambiguation.
- Political colours meet a defined perceptual-distance threshold for likely neighbours.
- Duplicate colour exceptions are explicit and tested.
- Search results always show enough context to distinguish countries.

### P1.5 Bundle and control the label font

**Complete.** The project bundles the unmodified Libre Baskerville variable font under the SIL Open Font License 1.1. `assets/fonts/README.md` records its upstream source, SHA-256, current Latin coverage, and fallback policy. Runtime loads the resource path directly; export validation requires the font to be packaged.

At audit time, the code requested Georgia, Times New Roman, or a generic system serif through `SystemFont`; the project did not bundle the actual country-label font.

**Impact**

- Different operating systems can use different glyph metrics.
- Label fitting and overlap can change between machines.
- Visual style is not controlled.
- Future translated names may fall back unpredictably or lack glyphs.

**Done when**

- A licensed, bundled font is the authoritative label font.
- Required Latin and future localisation glyph ranges are documented.
- Font metrics are identical in editor and exported builds.
- Cross-platform screenshots confirm acceptable results.

### P1.6 Add direct label tests and a visual regression gate

**Complete.** `tests/country_label_layer_test.gd` covers full names, shape sample/extent/angle limits, prominent representative sizes, Sweden/England/Naples orientations, zoom scaling, bounded projected collision, pan, resize, political/terrain/debug/thematic map modes, incremental ownership transfer, one-province annexation/reclamation, formation/release/extinction signals, save/load refresh, and performance budgets. `tests/country_label_visual_regression_test.gd` compares deterministic projected layouts for the default world, dense Europe, island-heavy Southeast Asia, Scandinavia, and the Italian peninsula. `tools/map_labels/run_visual_regression.py` captures and compares GPU-rendered PNGs for the same five views; it is exposed through the suite's explicit `--visual` gate.

No automated test currently references `CountryLabelLayer` directly. The existing UI layout smoke test validates HUD rectangles, not country labels.

Required coverage:

- Every active country resolves to a valid display name.
- No malformed filename or duplicate tag enters runtime data.
- Labels are created, updated, and removed correctly.
- Ownership transfer updates both affected countries.
- Formation, release, annexation, save, and load refresh labels.
- Zoom, pan, and viewport resize recalculate visibility correctly.
- Political, terrain, debug, and thematic map modes follow the approved visibility rules.
- Dense Europe and island-heavy regions meet overlap thresholds.
- Exported builds use the expected font and data.
- Performance stays within an explicit frame/rebuild budget.

**Done when**

- Headless logic tests cover data and lifecycle behaviour.
- Rendered screenshot comparisons cover representative regions and zoom levels.
- Test failures identify the country/tag and layout condition involved.

---

## P2 — Architecture, UX, and Content Quality

### P2.1 Define how disconnected realms, islands, and straits contribute

The current algorithm considers only direct land neighbours and selects the largest component. It ignores straits and every secondary component.

Approximately 95 starting countries have multiple components under this rule. Examples:

| Country | Total provinces | Provinces used by label | Components |
|---|---:|---:|---:|
| Aragon | 25 | 13 | 7 |
| England | 40 | 30 | 6 |
| Ottoman Empire | 41 | 22 | 2 |
| Portugal | 13 | 10 | 4 |
| Venice | 16 | 6 | 10 |

Ignoring distant colonies is useful. Ignoring integral islands, strait-connected territory, or the second half of a transcontinental state is not always useful.

**Done when**

- Design rules distinguish homeland, integrated islands, strait-connected land, subjects, and overseas possessions.
- Countries can have one primary label and, where appropriate, secondary regional labels.
- The chosen component is deterministic and historically/politically sensible.
- Aragon, England, Venice, Denmark, Portugal, and the Ottoman Empire have reviewed outcomes.

### P2.2 Decide whether any country needs a curved safe label path

The unsafe quadratic per-glyph curve has been removed. The current implementation uses a single straight label aligned by principal-component analysis of conservative owned raster samples. This produces the EU4-like directional treatment required for Italy, Scandinavia, Britain, Castile, Lithuania, and similar shapes without per-character scene nodes. It does not bend around highly concave or crescent-shaped territory; curved labels should return only if a reviewed country genuinely benefits and a safe centreline can be calculated.

**Done when**

- Curved text follows a baked or calculated safe centreline.
- Outlier provinces cannot pull the label outside the main territory.
- Every glyph has a validated position and tangent.
- Curvature has art-direction controls and readable limits.
- Straight text is preferred whenever a curved result is less readable.

### P2.3 Add map-mode visibility rules and a player toggle

The label layer is not connected to map-mode changes. Labels remain visible over political, terrain, province-ID, culture, religion, unrest, control, technology, war, relations, and access displays.

**Done when**

- Each map mode declares whether country labels are on, off, recoloured, or simplified.
- Province-ID/debug mode can present an unobstructed map.
- The player has a country-label toggle in settings or map controls.
- The selected country can remain labelled or highlighted where the design calls for it.

### P2.4 Introduce localisation-ready country identity

Current labels use the canonical registry display name with its authored casing. The registry has localisation-ready keys, but runtime language switching, adjectives, formal names, and contextual names remain future work.

Required model fields should include at least:

- Stable country tag.
- Display-name localisation key.
- Adjective localisation key.
- Optional alternate full/formal name.
- Optional authored line breaks and full-name placement hints.
- Optional government/subject/form-based overrides.
- Name history or rename event support where required.

**Done when**

- UI and map labels resolve names through one localisation service.
- Language changes invalidate visible labels.
- Dynamic renames invalidate labels without requiring an ownership change.
- Search indexes localised names, tags, aliases, and approved historical names.
- Save compatibility for renamed/formable countries is defined.

### P2.5 Complete an editorial and historical name review

The audit confirmed these visible formatting errors:

- `KER`: `eres` — **fixed in P0**.
- `VOC`: `Eat Indies Company`.
- `DAU`: `Dauphine ` with trailing whitespace — **fixed in P0**.

CamelCase or concatenated records requiring review:

`AngevinEmpire, KanemBornu, MongolKhanate, LivonianOrder, LanNa, TheIsles, LanXang, MacCarthy, MuanPhuan, MongYang, OiratHorde, QasimKhanate, RomanEmpire, SardiniaPiedmont, TeArawa, TeTaiTokerau, HawaiiUnited, WestIndies`

Likely spelling candidates requiring authoritative review include:

`Armangnac, Iroqouis, Khazak Horde, Lousiana, Luxembourgh, Mescaslero, Mississage, Zwahili`

At audit time all country names were ASCII-only. P1 introduced the contextual `Münster` spelling, but the wider catalogue still requires the planned sourced diacritic and editorial review.

**Done when**

- A style guide defines endonyms/exonyms, diacritics, punctuation, title usage, and historical date rules.
- Every 1444 active country has source provenance and review status.
- Formables and future tags are reviewed separately from active 1444 countries.
- Automated checks reject leading/trailing whitespace and suspicious concatenation.

### P2.6 Remove hard-coded map geometry from the label layer

The label layer hard-codes:

- Pixel scale `0.01`.
- Half-width `28.16`.
- Half-height `10.24`.

These currently match a `5632x2048` map but duplicate information already available from map/graph data.

**Done when**

- Label coordinates derive from the authoritative map transform and graph size.
- Changing map resolution or world projection cannot silently misalign labels.
- A transform validation test compares province anchors, terrain, markers, and labels.

---

## P3 — Presentation Polish and Long-Term Robustness

### P3.1 Improve zoom-level presentation

Current visibility uses the province count of the largest component and changes abruptly. Close zoom now smoothly tempers the rendered label scale from `1.0` to `0.48`, and close-view priority favours countries nearest the screen centre before territory weight, but fade transitions and strategic priority are still open.

It does not consider:

- Player country.
- Selected country.
- Government rank.
- Capital or strategic importance.
- On-screen presence.
- Actual screen-pixel readability.

**Done when**

- Labels have minimum and maximum screen-space sizes.
- Visibility transitions fade rather than pop.
- Priority considers player selection, rank, territory, and design importance.
- Off-screen countries do not participate in expensive detailed layout work.
- Tie-breaking is explicit and deterministic.

### P3.2 Make labels terrain- and marker-aware

P1 removed curved per-glyph labels. Each current shape-aligned straight label shares one sampled terrain height at the main body's raster centroid, and depth testing remains disabled to prevent relief clipping.

**Impact**

- Letters can float or appear embedded inconsistently.
- Labels can draw through terrain and over army markers.
- Visual hierarchy is controlled by render priority rather than contextual rules.

**Done when**

- The final rendering method has an explicit art-direction decision: terrain decal, projected overlay, screen-space layer, or validated 3D placement.
- Army markers, selections, borders, and labels have documented priority.
- Raised terrain cannot clip text or make it appear detached.

### P3.3 Support full-name alternate layouts

Long formal names cannot always fit tiny countries. The project direction is that a country must always be presented by its full name, never by an internal tag or abbreviation. P1 therefore keeps the canonical full name and uses a close-zoom screen fallback; P3 can improve the shape and placement of that full-name treatment.

**Done when**

- Countries may provide alternate full-name line breaks or authored placement hints, but not abbreviated public names.
- One-province and microstate full-name rules are consistent.
- Tooltips and panels still show the full formal name.
- Internal tags remain searchable for developer convenience without being displayed to players.

### P3.4 Define save and replay behaviour for names

Country names are currently presentation data rather than authoritative save state. Changing assets can change how an old save is displayed.

**Done when**

- The project decides which name properties are static localisation and which are campaign state.
- Player/dynamic renames are saved and checksummed if supported.
- Old saves have a documented fallback when content keys are renamed or removed.
- Deterministic replays resolve the same campaign-specific names.

---

## P4 — Repository Hygiene and Scope Control

### P4.1 Resolve the untracked script UID

`scripts/ui/country_label_layer.gd.uid` is currently untracked while comparable script UIDs are committed.

The scene references the script by path and the export currently succeeds, so this is not a runtime blocker. It is an incomplete repository state.

**Done when**

- The UID is either intentionally tracked or intentionally excluded according to one project-wide rule.
- A fresh clone imports without unexpected UID churn.

### P4.2 Separate unrelated shared-UI changes from label work

The first country-label change also altered `scripts/ui/draggable_panel.gd` so clicking a panel can raise its entire HUD hierarchy.

That behaviour affects all draggable windows, not only country names, and currently lacks focus/input-order regression tests.

**Done when**

- Shared HUD stacking has its own requirement and tests.
- Country-label work can be reviewed and reverted independently of draggable-window behaviour.
- Notifications, modal panels, tooltips, and click routing retain the intended priority.

### P4.3 Document the headless-rendering limitation

A diagnostic Movie Maker capture using Godot 4.7’s dummy headless renderer crashed on a null texture. Normal headless smoke tests and the exported startup test passed, so this is not evidence that the normal rendered game crashes.

**Done when**

- Visual regression capture uses a supported rendering driver/environment.
- CI documentation distinguishes simulation-headless tests from rendered screenshot tests.
- Renderer crashes are not confused with country-label logic failures.

---

## Recommended Execution Order

### Work Package A — Catalogue Safety

1. **Complete:** Resolve the duplicate `KER` records.
2. **Complete:** Define the canonical registry schema.
3. **Complete:** Generate country/name/colour caches from the registry.
4. **Complete:** Add blocking validation.
5. **Complete:** Resolve duplicate names and exact colour collisions.

**Exit gate:** Every province owner and country tag resolves exactly once, and malformed/duplicate data fails automation.

### Work Package B — Label Rendering Foundation

1. **Complete:** Bundle the approved font.
2. Replace hard-coded map geometry.
3. **Complete:** Implement territory-safe label regions/paths.
4. **Complete:** Implement screen-space footprint and collision calculations.
5. **Complete:** Add map-mode and visibility invalidation.

**Exit gate:** Representative labels remain inside their countries and do not visibly overlap at supported resolutions and zoom levels.

### Work Package C — Performance and Lifecycle

1. **Complete:** Update only affected countries after ownership changes.
2. **Complete:** Avoid allocating hidden labels eagerly.
3. **Complete:** Batch or otherwise reduce per-glyph rendering overhead.
4. **Complete:** Reclaim eliminated-country resources.
5. **Complete:** Add profiling and performance budgets.

**Exit gate:** Startup, camera movement, peace transfers, and long campaign sessions meet the Phase 9 presentation budget.

### Work Package D — Content and Localisation

1. Add localisation-ready display names, adjectives, alternate full names, and formal names without public tag/abbreviation fallbacks.
2. Complete editorial and historical review.
3. Add contextual/formable/dynamic naming rules.
4. Define save compatibility.

**Exit gate:** The 1444 catalogue is reviewed, localisable, searchable, and stable across saves.

### Work Package E — Visual and Release Validation

1. **Complete:** Add direct lifecycle tests.
2. **Complete:** Add rendered screenshot comparisons.
3. Test dense, sparse, island, colonial, and transcontinental regions. Dense Europe, island Southeast Asia, Scandinavia, and the Italian peninsula are covered; colonial/transcontinental coverage remains P2.
4. Test supported resolutions, aspect ratios, platforms, and map modes. Current Windows resolutions and modes are covered; additional release platforms remain Phase 9 work.
5. Complete hands-on UX review.

**Exit gate:** Automated and human validation agree that the feature is readable, correct, performant, and export-safe.

## Phase 9 Release Gate

Country names and map labels should not pass the Phase 9 Alpha presentation gate until all P0 and P1 items are complete. P2 items should be complete before content complete/Beta. Remaining P3 and P4 work must be explicitly accepted, scheduled, or waived before release candidate. Detailed ownership and exit gates now live in the [Strategic Map Visual Production Roadmap](map_visual_production/README.md).

## Audit Boundary

This document records code, data-consistency, presentation, performance, and test problems visible in the repository. It does not claim to be a complete historical verification of all 1,007 canonical country names. Historical correctness requires a separate sourced content review under the Phase 8/Phase 9 content pipeline.
