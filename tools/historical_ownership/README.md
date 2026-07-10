# Historical Ownership Tooling

This directory contains the reproducible workflow for assigning the 11 November 1444 political map. It changes province history data, not the province-ID bitmap. Godot regenerates the colour lookup and political mask from that history data.

## Safe workflow

1. Generate geographic evidence used to distinguish likely water from land:

   ~~~powershell
   & "C:\path\to\Godot.exe" --headless --path . --script res://tools/historical_ownership/audit_geography.gd
   ~~~

2. Build the ownership manifest without changing province histories:

   ~~~powershell
   python tools/historical_ownership/build_manifest.py
   ~~~

3. Review `docs/data/1444_ownership_manifest.csv` and add researched decisions to `ownership_overrides.csv`.

   The cultural-homeland pass is reproducible but intentionally marked medium-confidence. It generates documented authority slots for cultures that have no usable country tag, then chooses the nearest encoded authority capital for inhabited provinces:

   ~~~powershell
   python tools/historical_ownership/generate_authorities.py
   python tools/historical_ownership/stage_cultural_homelands.py
   python tools/historical_ownership/stage_terrain_exclusions.py
   ~~~

   This pass is a gameplay territorialization, not a claim that every community used centralized government or hard borders. Its rows remain individually reviewable and replaceable.

   The terrain-exclusion pass documents every remaining sea, inland lake, and imported impassable/wasteland definition. These areas deliberately stay non-country and therefore remain absent from the political mask.

4. Apply only reviewed rows:

   ~~~powershell
   python tools/historical_ownership/build_manifest.py --apply-approved --check
   ~~~

5. Bake the political textures and the explicit terrain-class texture. The latter records water, owned land, unowned land, and impassable terrain without runtime colour guessing. The CPU baker is deterministic and avoids the Godot 4.7 compute-shader crash path:

   ~~~powershell
   python tools/historical_ownership/bake_political_textures.py
   ~~~

6. Normalize imported comments/dates for the current addon's lightweight live parser:

   ~~~powershell
   python tools/historical_ownership/normalize_addon_compatibility.py
   ~~~

   The addon searches raw text rather than parsing comments or dated blocks. The normalizer makes the canonical runtime owner the first `owner =` token and renames remaining historical `tribal_owner` tokens to `tribal_authority`. It creates safety copies and does not alter the reviewed 1444 assignment.

The one-time `--apply-explicit-tribal` option promotes imported `tribal_owner` fields. These are already explicit territorial-authority assignments in the source data, but the current addon deliberately renders every file containing `tribal_owner` as `No Owner`.

The one-time `--apply-dated-1444` option evaluates direct province-owner events through 11 November 1444 and promotes the latest result. This repairs cases such as Palembang and Sulu, whose imported files contain a valid pre-start owner event that the addon's lightweight parser otherwise ignores.

Before each apply operation, the tool copies every affected history file to a timestamped `backups/` directory and writes an `applied.json` ledger. Backups are deliberately ignored by version control.

## Override rules

- `province_id`: numeric province ID from `definition.csv`.
- `assigned_tag`: an existing three-character country tag.
- `status`: use `approved` only after historical and map-placement review.
- `confidence`: `high`, `medium`, or `low`.
- `authority_type`: state, confederacy, city-state, tribal authority, indigenous nation, or another precise description.
- `source_url`: direct link to the strongest supporting source.
- `source_note`: short explanation of what the source supports and any uncertainty.
- `reviewer` and `review_date`: accountability for the decision.

Do not infer sovereignty from culture alone. A culture field is evidence that land was inhabited, not proof that one sharply bounded state owned it.
