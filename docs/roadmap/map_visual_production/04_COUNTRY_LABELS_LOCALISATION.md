# 04 — Country Labels, Names, and Localisation

## Mission

Finish the country-identity layer so every player-facing name is historically reviewed, localisable, sharp, correctly placed, mode-aware, performant, deterministic, and stable across campaign changes and saves.

This document absorbs all remaining P2–P4 work from [Country Names and Map Labels — Priority Audit](../COUNTRY_NAMES_MAP_LABELS_AUDIT.md). The completed P0/P1 registry, territory bake, full-name policy, shape-aligned placement, screen-space collision, incremental lifecycle, bundled font, tests, and export gates remain the implementation baseline.

## Non-Negotiable Rules

- Player-facing UI and map labels use full authored names such as `England`, never internal tags such as `ENG`.
- Stable tags remain valid for data, saves, developer tools, logs, and search context.
- A country name is identity data; a label is one presentation of that identity.
- Province ownership, subject relationship, realm grouping, and label footprint are separate concepts.
- A label may simplify its layout, line breaks, visibility, or leader treatment, but it may not silently rename the country.
- Straight shape-aligned text is the default. Curved text ships only for reviewed cases with a validated safe path and no readability regression.

## Completed Foundation to Preserve

- Generated canonical registry at `assets/country_registry.json`.
- Registry/source validator and runtime ownership test.
- Full public display names with no raw-tag fallback.
- Duplicate name/colour resolution and neighbour-distance validation.
- Bundled Libre Baskerville font and licensing record.
- Conservative territory raster bake.
- Dominant-axis country fit with deterministic scale and rotation.
- Projected screen-space collision and off-screen culling.
- Lazy one-label-per-visible-country lifecycle.
- Incremental invalidation for affected countries.
- Deterministic layout, lifecycle, performance, export, and five-view visual-regression coverage.

Any replacement architecture must match these correctness and performance gates before the old path is removed.

## Epic CL-1 — Identity and Localisation Architecture

### CL-1.1 Create one runtime localisation service — P1 / L

The registry already carries localisation-ready keys, but runtime presentation still needs one resolver used by map labels, panels, search, tooltips, messages, diplomacy, saves, and debug context.

Minimum identity schema:

| Field | Purpose |
|---|---|
| `tag` | Stable internal country ID |
| `name_key` | Standard display-name localisation key |
| `adjective_key` | Country adjective key |
| `formal_name_key` | Optional formal/state title |
| `short_context_name_key` | Optional approved UI-only context, never a raw tag fallback |
| `historical_alias_keys` | Search/history aliases |
| `government_name_overrides` | Optional form-of-government names |
| `subject_name_overrides` | Optional subject/colonial naming policy |
| `dynamic_name_state` | Campaign-specific/player rename where supported |
| `map_layout_hints` | Authored full-name breaks, priority, components, or placement hints |
| `review_status` and `sources` | Editorial/historical provenance |

**Done when**

- Every player-facing path resolves names through the same service.
- Missing required keys fail content validation rather than displaying a tag.
- Search indexes localised names, tags, aliases, and approved historical names, while results visibly distinguish ambiguous names.
- Runtime language changes invalidate affected text and label layout.

### CL-1.2 Define fallback policy — P1 / M

Recommended order:

1. Campaign-specific approved dynamic name.
2. Contextual government/subject/form override.
3. Localised standard name.
4. Shipping-language localised standard name.
5. Explicit `Missing country name` development error in non-release builds.

Internal tag display is not an acceptable player-facing fallback.

**Done when**

- Fallback behaviour is tested in editor, headless logic, and packaged builds.
- Missing localisation is visible in validation reports and cannot silently enter a release build.

### CL-1.3 Define dynamic naming and save schema — P1 / L

Decide which values are static content and which become authoritative campaign state.

Required cases:

- Country formation.
- Government/form change.
- Subject/colonial naming.
- Country release and restoration.
- Optional player rename.
- Localisation content update after a save was created.
- Renamed or removed localisation key during a supported save migration.

**Done when**

- Dynamic name state is versioned, saved, checksummed, migrated, and replay deterministic.
- Static localisation updates do not alter authoritative game logic.
- Old saves have a documented fallback for missing keys.
- Formation/release/rename signals invalidate map labels, search indexes, panels, notifications, and tooltips.

## Epic CL-2 — Editorial and Historical Name Review

### CL-2.1 Write the country-name style guide — P1 / M

The guide must decide:

- Historical exonym versus endonym policy.
- English display-language baseline.
- Diacritics and Unicode normalization.
- Articles such as “The”.
- Dynastic, geographic, tribal, confederation, order, company, and imperial titles.
- Spacing, hyphens, apostrophes, punctuation, and title case.
- When a government form belongs in a standard versus formal name.
- 1444 date validity and formable/future-name separation.
- How uncertain or disputed identities are documented.
- Adjective construction and exceptions.
- Search aliases for common alternate spellings.

### CL-2.2 Correct known catalogue candidates — P1 / M

The earlier audit identified at least the following unresolved visible problems or review candidates.

Confirmed error still requiring correction and validation:

- `VOC`: `Eat Indies Company`.

Concatenation/CamelCase review queue:

`AngevinEmpire, KanemBornu, MongolKhanate, LivonianOrder, LanNa, TheIsles, LanXang, MacCarthy, MuanPhuan, MongYang, OiratHorde, QasimKhanate, RomanEmpire, SardiniaPiedmont, TeArawa, TeTaiTokerau, HawaiiUnited, WestIndies`

Likely spelling/source-review queue:

`Armangnac, Iroqouis, Khazak Horde, Lousiana, Luxembourgh, Mescaslero, Mississage, Zwahili`

These are candidates, not automatic replacements. Historical/content research must verify tag identity, date, preferred display language, and source before editing.

**Done when**

- Every active 1444 country has reviewer, source, decision, adjective, and status.
- Formables, dormant/future tags, companies, colonial entities, and pseudo-countries have separate review queues.
- Automated checks reject leading/trailing whitespace, empty names, invalid normalization, suspicious concatenation, control characters, and forbidden raw-tag public fallbacks.

### CL-2.3 Add editorial reports and review UI — P2 / L

Generate CSV/HTML or in-tool reports containing tag, current name, adjective, political colour, 1444 status, owned provinces, capital, source links, aliases, last reviewer, validation warnings, and in-game label capture.

**Done when**

- Reviewers can approve/correct content without editing the generated registry directly.
- Registry rebuild preserves reviewer/source metadata.
- A global review completion report is a Phase 9 Content Complete input.

## Epic CL-3 — Territory Components and Realm Layout

### CL-3.1 Define disconnected-realm rules — P1 / L

The current label fit uses the largest direct-land component. Approximately 95 starting countries have multiple components under that rule. Examples requiring reviewed outcomes include:

| Country | Starting issue to review |
|---|---|
| Aragon | Mainland/islands and multiple disconnected possessions |
| England | Britain, continental holdings, islands |
| Ottoman Empire | Transcontinental components and straits |
| Portugal | Mainland, islands, future overseas territory |
| Venice | Highly fragmented maritime possessions |
| Denmark | Straits, islands, and relation to larger realm structures |

Create component classes:

- Homeland/core continuous land.
- Strait-connected integrated land.
- Integral near island.
- Detached regional possession.
- Overseas possession/colony.
- Occupied but not owned land.
- Subject-owned land.
- Temporary control.

Default recommendation:

- Primary label fits the reviewed homeland/integrated component set.
- Distant colonies and subjects do not distort the sovereign country label.
- A secondary regional full-name label is permitted only when geography and zoom make it useful.
- Subject territory never becomes part of the overlord's ownership label by accident.

**Done when**

- Graph rules include approved strait connectivity where appropriate.
- Component choice is deterministic and data-driven.
- Aragon, England, Ottoman Empire, Portugal, Venice, and Denmark have approved captures at 1444 and representative changed borders.
- Dynamic annexation/colonisation can change component class without full-world rebuilding.

### CL-3.2 Add authored layout hints without replacing automation — P2 / L

Supported hints may include:

- Preferred included/excluded component IDs or region classes.
- Priority weight.
- Maximum rotation.
- Preferred baseline anchor or offset.
- Full-name line break alternatives.
- Secondary regional label permission.
- Straight-only/curve-candidate policy.

**Done when**

- Hints are stable data, validated, localisable where text-related, and optional.
- Normal border changes still produce a reasonable automatic layout.
- A hint cannot place a label outside owned/approved territory without an explicit reviewed exception.

### CL-3.3 Decide curved-label scope — P2 / M spike, then conditional L

Straight dominant-axis labels already solve many long/diagonal shapes with far lower complexity. Prototype a safe curved-centreline algorithm only for reviewed concave/crescent cases.

The spike must compare:

- Straight PCA baseline.
- Piecewise/medial-axis centreline.
- Curved glyph layout footprint.
- Screen readability at motion and supported resolutions.
- Node/draw/performance cost.

**Ship decision**

- If the curve is not consistently safer and clearer, ship straight text plus authored placement hints.
- If curves ship, every glyph position/tangent must be inside an approved safe region and collision must use the combined projected hull.

## Epic CL-4 — Crisp Typography and Render Integration

### CL-4.1 Choose final label render method — P1 / L spike

The current `Label3D` path is correct enough to test but can appear soft because of projection, outline, filtering, depth policy, and camera conditions. Compare:

- Improved `Label3D`/MSDF configuration.
- Screen-space labels anchored to projected world bounds.
- World/projected decal text.
- Hybrid country labels in screen space with world-space marker integration.

Evaluate:

- Still sharpness.
- Motion stability.
- Rotation and perspective.
- Terrain interaction.
- Collision accuracy.
- Outline/shadow quality.
- Localisation and glyph atlas support.
- GPU/CPU/draw cost.
- Export and graphics-tier compatibility.

**Done when**

- Decision record and representative captures are approved.
- Glyph stems remain crisp at supported scale; labels are not visibly blurred by the chosen AA path.
- Visual regression uses the final supported renderer, not the dummy headless renderer.

### CL-4.2 Establish type scale and priority — P1 / M

Define clamped screen-pixel ranges for:

- Major country.
- Normal country.
- Microstate/close-zoom country.
- Regional label.
- Province label.
- Capital/settlement.
- Water/geographic label if included.

Priority inputs should include:

- Selected/player country.
- On-screen area.
- Government rank/approved design importance.
- Territory extent.
- Distance from screen centre.
- Current map mode.
- Active interaction or war relevance.

Tie-breaking must be deterministic.

### CL-4.3 Add smooth zoom presentation — P1 / M

- Use entry/exit hysteresis.
- Fade rather than hard-pop where motion settings permit.
- Clamp screen size.
- Avoid recalculating geometry for every tiny camera delta.
- Do not let off-screen countries participate in detailed collision work.

**Done when**

- Continuous zoom has no visible size jumps or rapid toggle flicker.
- Reduced-motion mode can shorten/disable fades without losing state clarity.
- Label update cost stays within the camera-motion budget.

### CL-4.4 Make labels terrain- and marker-aware — P1 / L

Choose and document priority between:

- Country labels.
- Province/capital labels.
- Army/navy markers.
- Battle/siege/occupation markers.
- Selection/hover.
- Country/province borders.
- Terrain relief.

**Done when**

- Labels do not float at obviously wrong terrain height or clip into raised relief.
- Army/battle/selection markers are never hidden by a decorative country label.
- Label contrast adapts by mode/background without pulsing or per-frame instability.
- Depth-disabled text does not incorrectly draw through essential foreground markers.

### CL-4.5 Support full-name alternate layouts — P2 / M

Allow authored full-name line breaks, leader lines, or close-zoom screen treatments for long names and microstates. Do not add public tag abbreviations.

**Done when**

- One-province and microstate rules are consistent.
- Tooltips and panels retain the full formal/standard name.
- Alternate layouts are localisation-specific where necessary.

## Epic CL-5 — Map Modes and Player Controls

### CL-5.1 Add declarative label policies per map mode — P1 / M

Each mode selects one of:

- Country labels primary.
- Country labels reduced.
- Selected/relevant labels only.
- Recoloured/outlined for the semantic background.
- Hidden.

Province-ID/debug mode should default to labels off. Political mode should use country labels. War/diplomatic modes should prioritise participants/relevant countries. Terrain mode may reduce political naming or allow a player preference.

### CL-5.2 Add player settings — P1 / M

Required controls:

- Country labels: automatic/on/off.
- Province or local labels: automatic/on/off if implemented.
- Label scale within safe limits.
- High-contrast label treatment.
- Reduced-motion/fade behaviour.

**Done when**

- Settings persist, load safely, and apply without restarting where technically safe.
- Player settings never cause raw tags or invalid layouts.

## Epic CL-6 — Geometry, Lifecycle, and Performance

### CL-6.1 Remove hard-coded map geometry — P1 / M

Replace duplicated `0.01`, `28.16`, and `10.24`-style map constants with the authoritative render/map transform defined in RP-1.2.

**Done when**

- Map resolution/projection changes cannot silently misalign labels.
- Province anchors, terrain, marker, selection, and label transforms agree in automation.

### CL-6.2 Preserve incremental lifecycle guarantees — P1 / M

Extend current invalidation to localisation, dynamic rename, component-class change, map mode, player settings, viewport, font/glyph atlas, and render-method changes.

**Done when**

- A change identifies the minimum affected countries/layers.
- Eliminated-country resources are reclaimed.
- Mass formation/release/peace cases remain budgeted.

### CL-6.3 Expand layout and visual coverage — P1 / L

Existing coverage: world/default, dense Europe, island Southeast Asia, Scandinavia, and Italian peninsula.

Add:

- Colonial/transcontinental realm.
- Subject/appanage grouping including France/Orléans.
- Microstate and one-province long name.
- Arabic/right-to-left or another supported complex-script case when localisation scope is locked.
- Diacritic-heavy Latin test.
- Multiple resolutions, ultrawide, high DPI, and label-scale settings.
- Every shipping map-mode policy.
- Large peace transfer, formation, release, dynamic rename, language switch, save/load, and replay.

## Epic CL-7 — Repository and Test Hygiene

### CL-7.1 Resolve script UID policy — P2 / XS

`scripts/ui/country_label_layer.gd.uid` and comparable UIDs must follow one documented repository rule.

**Done when**

- A fresh clone/import produces no unexpected UID churn.
- Export and scene references pass.

### CL-7.2 Separate shared draggable-panel behaviour — P2 / M

The earlier label work also touched shared HUD stacking in `scripts/ui/draggable_panel.gd`. Treat that as a UI focus/input feature, not hidden label scope.

**Done when**

- HUD stacking has its own requirements and tests.
- Labels can be changed/reverted independently.
- Modal panels, notifications, tooltips, focus, and click routing keep intended priority.

### CL-7.3 Document rendered versus simulation-headless tests — P1 / S

Godot 4.7's dummy headless renderer previously crashed during a diagnostic Movie Maker capture while normal logic-headless and exported startup tests passed.

**Done when**

- Simulation-headless and rendered-visual jobs are distinct.
- Visual capture uses a supported renderer/host.
- Failures identify renderer/environment separately from label logic.
- Trusted-host PCK fallback remains documented for Windows Application Control blocks without hiding a real packaging failure.

## Typography Gate

The label/name work is complete only when:

- All active 1444 names and adjectives pass editorial/historical review.
- No player-facing raw country tag appears in map labels, panels, buttons, tooltips, notifications, search results, saves, or export-only paths.
- The localisation service, dynamic naming, and save compatibility rules are implemented and tested.
- Disconnected/strait/island/overseas component rules are approved.
- Labels are visibly sharp at target resolutions and stable in camera motion.
- Mode policies, player settings, marker priority, and terrain interaction pass.
- Global layout, lifecycle, performance, visual-regression, export, and hands-on UX gates pass.

