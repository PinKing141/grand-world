# Content Pipeline

## Purpose

Grand World requires a large volume of interconnected historical and gameplay data. Content must be reproducible, validated, reviewable, and safe to load.

The runtime should consume baked data rather than reparsing thousands of source files during every campaign start.

## Pipeline

~~~text
Authoring sources
→ Parse
→ Schema validation
→ Reference validation
→ Historical review
→ Normalisation
→ Bake
→ Runtime database
→ Campaign load
~~~

## Content Layers

### Source Definitions

Human-editable content:

- Provinces.
- Countries.
- Cultures.
- Religions.
- Governments.
- Technologies.
- Buildings.
- Units.
- Modifiers.
- Events.
- Decisions.
- Characters.
- Dynasties.
- Titles.
- Localisation.

### Scenario Data

Date-specific state:

- Province owner and controller.
- Active countries.
- Capitals.
- Rulers and heirs.
- Title holders.
- Diplomacy.
- Wars and truces.
- Technology levels.
- Treasury and manpower starting values.

### Baked Runtime Data

Optimised and validated:

- Stable integer IDs.
- Packed arrays.
- Resolved references.
- Adjacency.
- Province centres.
- Reverse indexes.
- Localisation lookup keys.
- Content version and checksum.

Phase 8's first validated country-depth runtime bundle is `assets/country_depth_definitions.json` (`phase8-iberia-1`). It validates government/reform references, contiguous technology levels, culture/religion IDs, idea groups, event/decision localisation and supported effects, country provenance, province provenance, and authored cross-references. Its explicit “historical review required” provenance is a production flag, not a claim of final historical accuracy.

### Canonical Country Registry

`assets/country_registry.json` is the authoritative baked catalogue for country identity. Each scenario-country record owns its stable tag, display-name and adjective localisation keys, political colour, canonical history/colour source paths and source hashes, and scenario/selectable status. `No Owner` and `Ocean` are separately declared non-scenario pseudo-countries.

Campaign bootstrap validates province ownership against this registry before constructing `WorldState`. Unknown non-empty owner tags are fatal data errors; they are never silently converted to unowned land. The native `CountryData` dictionaries are presentation mirrors regenerated from the registry at startup, not the campaign authority.

After changing country history, country colours, or the 1444 ownership manifest, regenerate and validate with:

~~~powershell
python tools/country_registry/build_country_registry.py
python tools/country_registry/build_country_registry.py --check
~~~

The blocking validator rejects malformed filenames, duplicate tags, missing colour definitions, unresolved manifest owners or localisation keys, unapproved duplicate display names, and stale generated source hashes. The headless runtime gate additionally checks registry/bootstrap parity, pseudo-country exclusion, and complete province-owner resolution.

### Country Label Presentation Bake

`assets/label_territory_map.png` is a conservative quarter-resolution province-ID raster generated from `assets/provinces.bmp`. A baked cell is usable only when its entire `4x4` source block belongs to one province, allowing runtime label rectangles to remain inside owned political territory. `assets/label_territory_map.json` records the source hashes, scale, dimensions, encoding, and PNG hash.

Country labels use the bundled OFL-licensed Libre Baskerville font, projected screen-space collision bounds, off-screen culling, lazy node creation, and incremental old/new-owner layout queues. Regenerate and validate the territory bake with:

~~~powershell
python tools/map_labels/build_label_territory_map.py
python tools/map_labels/build_label_territory_map.py --check
~~~

The headless suite checks lifecycle, territory fit modes, overlap, camera/viewport invalidation, map-mode policy, save/load refresh, and explicit CPU/node budgets. GPU-rendered reference images are checked separately with `python tools/testing/run_all_tests.py --quick --visual` because that gate opens a rendering window.

### Campaign Save Data

Only changing campaign state:

- Date.
- RNG state.
- Country state.
- Province state.
- Armies.
- Wars.
- Relations.
- Characters.
- Titles.
- Modifiers.
- Events.
- Construction.
- Subjects and integration.
- Rebel factions.
- Country-depth technology, government, culture, religion, ideas, modifiers, and event history.

Source definitions are not normal campaign saves.

## Stable ID Policy

Use namespaced source IDs:

~~~text
country.england
province.london
culture.english
religion.catholic
government.feudal_monarchy
unit.longbowmen
building.workshop
event.poor_harvest
~~~

The bake step assigns stable integer runtime IDs.

Rules:

- IDs are unique within their type.
- IDs do not depend on file order.
- Renaming an ID requires a migration alias.
- Deleted IDs remain reserved when save compatibility requires it.
- Player-facing names use localisation keys, not IDs.

## Required Schemas

Every content type declares:

- Required fields.
- Optional fields and defaults.
- Field types.
- Valid ranges.
- Reference types.
- Version.
- Migration behaviour.

Example province requirements:

- Unique province ID.
- Unique map colour.
- Name localisation key.
- Land or sea classification.
- Terrain.
- Region.
- Valid adjacency after bake.

Example country requirements:

- Unique tag.
- Name and adjective keys.
- Political colour.
- Capital in active scenarios.
- Valid government.
- Valid primary culture and religion.

## Validation Levels

### Syntax

- File can be parsed.
- Required delimiters and structures exist.
- Values use valid types.

### Schema

- Required fields exist.
- Ranges are valid.
- Enumerated values are allowed.

### References

- Owner country exists.
- Capital province exists.
- Character parents exist.
- Title holders exist.
- Event effects reference valid definitions.

### World Integrity

- Province colours are unique.
- Adjacency is symmetric.
- Active country has valid territory or an explicitly permitted landless state.
- Capital ownership rules pass.
- No character ancestry loop.
- No title-liege cycle.
- No country appears on both sides of one war.

### Historical Review

- Date and source recorded where required.
- Uncertainty marked explicitly.
- Interpretation distinguished from verified fact.
- Placeholder content labelled.

## Content Bake Outputs

The bake should produce:

- Content version.
- Source checksum.
- Definition arrays.
- Resolved ID maps.
- Province adjacency.
- Province anchors.
- Country-to-province indexes.
- Title hierarchy indexes.
- Character family indexes.
- Localisation tables.
- Validation report.

The bake must fail on release-blocking validation errors.

## Content Error Severity

| Severity | Example | Action |
|---|---|---|
| Error | Unknown province owner | Bake fails |
| Error | Duplicate province colour | Bake fails |
| Error | Title hierarchy cycle | Bake fails |
| Warning | Missing optional historical source | Bake continues with report |
| Warning | Missing flavour description | Bake continues before content lock |
| Info | Default value applied | Recorded for review |

## Localisation

All player-facing content uses keys:

~~~text
country.england.name
country.england.adjective
province.london.name
event.poor_harvest.title
event.poor_harvest.description
~~~

Requirements:

- No important player-facing text hard-coded in simulation code.
- Placeholders are visible in development builds.
- UI supports text expansion.
- Pluralisation and numeric formatting are centralised.

## Historical Provenance

For historical content, record:

- Source or reference.
- Date accessed where appropriate.
- Confidence.
- Author notes.
- Licensing or redistribution status.

Before public distribution, verify the provenance and redistribution rights of imported map and historical data.

## Content Production Workflow

1. Create or modify source content.
2. Run local validation.
3. Bake runtime data.
4. Run content smoke tests.
5. Review in the game.
6. Review historical and design intent.
7. Submit with validation report.
8. CI repeats validation and bake.

## Content Complete Gate

Content complete requires:

- All planned 1.0 content categories populated.
- No missing required localisation.
- Zero validation errors.
- Historical setup review complete.
- Tutorial and onboarding content present.
- No pending schema redesign.
- Remaining content work limited to corrections, balance, and polish.
