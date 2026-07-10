# 1444 Historical Ownership Policy

## Goal

Produce a readable and playable political map for 11 November 1444 without representing inhabited indigenous land as empty merely because it did not use a European state structure.

The map may assign a province to a kingdom, empire, principality, confederacy, city-state, clan authority, tribal polity, or indigenous territorial authority. “Country” is the runtime ownership slot; it does not imply a modern nation-state or an exact modern border.

## Non-negotiable rules

1. Oceans, sea zones, major lakes, and genuine impassable wasteland do not receive country owners.
2. Existing top-level 1444 owners are preserved unless a reviewed correction cites stronger evidence.
3. Existing `tribal_owner` data is accepted as explicit imported evidence and migrated to the runtime owner field, with its provenance retained in the manifest.
4. Culture, religion, province name, or proximity may identify research candidates but cannot alone approve ownership.
5. Uncertain and overlapping authority is recorded honestly. Province borders are gameplay abstractions, especially where political authority was seasonal, shared, tributary, mobile, or non-territorial.
6. A direct historical or institutional source is preferred. Aggregated historical datasets are leads and cross-checks, not automatic truth.
7. Every new decision records confidence, authority type, source, reviewer, and review date.

## Confidence levels

- `source_explicit`: the imported source data already names the 1444 owner or tribal authority.
- `high`: multiple credible sources agree and the province placement is clear.
- `medium`: the authority and general area are supported, but the province boundary or exact 1444 extent is approximate.
- `low`: a necessary gameplay abstraction with conflicting, sparse, or date-shifted evidence.
- `unresolved`: no assignment should be applied yet.

## Review order

1. Preserve existing explicit owners.
2. Promote explicit imported tribal authorities.
3. Exclude verified water and non-playable definitions.
4. Research inhabited unowned land by region.
5. Review sparsely inhabited and mobile-use territories.
6. Review true wasteland and impassable terrain.
7. Regenerate the political textures and inspect seams, islands, enclaves, and unexpected black areas.

## Cultural-homeland pass

Where the imported history records an inhabited province but no authority, the current first-pass scenario assigns a cultural territorial authority. Existing country tags are selected by matching primary culture and the nearest encoded capital. Where no suitable tag exists, a documented authority slot is generated. These medium-confidence assignments make inhabited land playable while retaining explicit notes that many boundaries were mobile, shared, overlapping, or not state borders.

This layer is expected to improve through regional historical review. Replacing one of these rows with stronger evidence is a correction, not a data migration failure.

Imported impassable provinces remain non-country terrain. This includes deserts, mountain barriers, dense interior wasteland blocks, major lakes, sea zones, and historically uninhabited islands. Their exclusion is a gameplay decision and must not be read as a claim that every geographic wasteland block lacked human presence or use.

## Source baseline

- Seshat Cliopatria supplies an open global polity dataset and explicitly warns that historical boundaries are one interpretation rather than indisputable borders.
- OpenHistoricalMap can provide date-aware, public-domain geographic leads, but coverage and contributor certainty vary.
- Libraries, archives, museums, peer-reviewed historical atlases, and scholarship focused on the relevant polity or people are preferred for final decisions.
- Indigenous territorial maps must be used according to their own cautions. Language, social-group, traditional-use, treaty, and sovereignty maps are not interchangeable.

## Generated records

- `province_geography.csv`: pixel area, centroid, approximate longitude/latitude, and land/water texture statistics.
- `1444_ownership_manifest.csv`: one audit row for every province definition.
- `1444_ownership_summary.json`: counts and validation findings for quick checks.
- `tools/historical_ownership/ownership_overrides.csv`: reviewed source-of-truth decisions that are not already explicit in the imported histories.

The manifest is intentionally reviewable in a spreadsheet. It is a production record, not merely a temporary conversion file.
