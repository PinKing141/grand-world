# Historical Placeholder Marker Art Specification

## Decision

Use an original early-modern painted cartographic marker language with EU4-like strategic clarity, but do not copy Paradox assets, exact frames, textures, icons, flags, fonts, shaders, or proportions. These assets are intentionally replaceable placeholders for a later bespoke art pass.

Country identity should use a real period flag, royal banner, civic banner, dynastic arms, or near-period manuscript reconstruction when one can be sourced responsibly. Do not invent an authentic-sounding history for countries without evidence.

## Current delivery

- One stable shield-atlas slot for all **1,007** canonical country definitions.
- Each runtime shield now has a **128×128** atlas cell, rendered internally at **256×256** before final downsampling; the complete atlas remains within a broadly supported **4096×4096** texture with an approximately **64 MiB** uncompressed RGBA GPU footprint.
- Complete coverage for all **703** owners in the 1444 ownership manifest.
- **39** openly licensed sourced historical/near-period placeholders with source, author, licence, evidence class, review warning, and content hash.
- **968** transparent reserved slots labelled `unassigned_requires_historical_research`; invented country heraldry is not displayed.
- Ten project-original map-marker assets: army, navy, battle, siege, capital, fort, port, cluster, destination, and invalid action.
- Army markers render the owning country's shield through one atlas-backed `MultiMesh` batch.
- Battle and siege markers use one atlas-backed instance per visible cluster, preserve their two-batch priority, and draw an exact count up to 99 inside the same shader pass.
- Existing post-drag click selection, repeated-click cluster cycling, zoom culling, route state language, and world-seam behaviour remain intact.

## Why every country cannot honestly receive a “real 1444 flag” immediately

Modern national-flag conventions do not map cleanly onto the 1444 world. The registry includes:

- Kingdoms and republics with well-attested banners.
- Dynastic territories better represented by arms or standards.
- Religious orders and appanages.
- Decentralised communities that did not use a single state flag.
- Proposed aggregate tags and historical abstractions.
- Releasable or formable states not active in 1444.
- Polities whose surviving visual evidence is later, disputed, or reconstructed.

The production rule is therefore evidence-first:

| Tier | Runtime status | Meaning |
|---|---|---|
| A | `sourced_open_historical_placeholder` + date-specific evidence | Source explicitly covers or closely brackets 1444 |
| B | `sourced_open_historical_placeholder` + period representative evidence | Banner/arms are historically associated with the polity but exact form/proportions need review |
| C | `sourced_open_historical_placeholder` + near-period reconstruction | Useful research-backed placeholder with an explicit warning |
| D | `unassigned_requires_historical_research` | Transparent reserved slot; no country shield is displayed until reviewed evidence is added |

## Visual construction

### Country shield

- Dark ink outer silhouette.
- Fine muted-gold inner keyline.
- Rounded upper corners and a pointed lower field.
- Reviewed sourced flag, banner, arms, or visual evidence clipped inside; otherwise the complete slot remains transparent.
- Very restrained top highlight and lower shade for tactile atlas character.
- Transparent exterior so the marker reads over terrain, political fills, water, and occupation.

### Conflict icon

- Strong dark outline to survive any underlying map colour.
- Warm parchment fill for neutral readability.
- State tint supplied by the runtime rather than baked into separate textures.
- Battle: crossed weapons and central boss.
- Siege: fortified wall/castle silhouette.
- Cluster count: shader-drawn gold badge with dark seven-segment numerals, avoiding per-marker labels or extra draw calls.

### Other icon families

- Army: shield plus military cross.
- Navy: sail and hull.
- Capital: crown.
- Fort: tower.
- Port: anchor.
- Cluster: grouped circular tokens.
- Destination: ring target.
- Invalid: geometric cross.

## Historical and legal requirements

Every sourced work must retain:

- Commons file title.
- Description page URL.
- Original and downloaded thumbnail URL.
- Author, credit, or required attribution.
- Licence and licence URL.
- Evidence classification.
- Review note.
- SHA-256 hash of the vendored source image.

The generated atlas crops, scales, clips, and shades sourced images. Distribution must retain [the third-party notices](../../../assets/marker_art/THIRD_PARTY_NOTICES.md). Source provenance is not the same as historical approval; a historian still needs to review disputed and reconstructed entries.

## Replacement workflow

1. Research a country and record the source and licence.
2. Add or update its entry in `tools/marker_art/historical_flag_sources.json`.
3. Run `python tools/marker_art/build_marker_assets.py --fetch-sources` once.
4. Inspect `assets/marker_art/source_flags/source_manifest.json` and the downloaded image.
5. Run `python tools/marker_art/build_marker_assets.py` offline.
6. Review `marker_placeholder_contact_sheet.png` and a live map capture.
7. Run `python tools/marker_art/build_marker_assets.py --check` and `python tests/marker_asset_contract_smoke.py`.
8. Run the Godot semantic, conflict-marker, performance, and export gates.

When bespoke final art replaces these placeholders, preserve atlas indices where practical. If slot ordering or tile dimensions change, regenerate the manifest and update the runtime shader contract rather than hand-editing coordinates.

## Remaining historical-art queue

1. Expand Tier A–C evidence across every high-visibility active 1444 country.
2. Prioritise the Ottoman Empire, remaining Italian states, Holy Roman electors, North Africa, Persia, India, East Asia, West Africa, and the major American polities.
3. Review decentralised-community presentation with regional historians instead of forcing modern national flags onto them.
4. Replace near-period and traditional sources when a stronger primary visual source is found.
5. Complete a historian sign-off pass before the commercial release gate.
