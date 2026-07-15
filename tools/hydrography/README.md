# River data ingestion

The game deliberately has no shipping `assets/river_definitions.json` yet. The current repository contains no approved river source, so drawing guessed river vectors would create false geography and a provenance problem.

Use `river_definitions.template.json` only as the data contract. A production file must provide:

- Stable lowercase river IDs and display names.
- Ordered source-to-mouth map-pixel points on the canonical `5632×2048` projection.
- Major, secondary, or minor width class and minimum zoom band.
- Ocean, lake, or downstream-river mouth connectivity.
- Navigability semantics.
- Source title, URI, licence, attribution, and an approved review status.

Validate an incoming source with:

```powershell
python tools/hydrography/validate_river_definitions.py assets/river_definitions.json
```

The validator rejects missing provenance, empty production data, invalid coordinates, duplicate IDs, malformed points, and broken downstream-river references. `--allow-empty --allow-unapproved` exists only for validating the template or doing a non-shipping technical spike.
