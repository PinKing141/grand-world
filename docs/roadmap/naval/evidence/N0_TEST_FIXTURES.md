# N0.3 - Test/Content Fixture

**Status:** Recorded  
**Satisfies:** [10 - Delivery sequence and checklist](../10_DELIVERY_SEQUENCE_AND_CHECKLIST.md) N0.3  
**Method:** cross-referenced `assets/province_graph.json` (coastal flag + `sea_neighbors`) against `docs/data/1444_ownership_manifest.csv` (`dated_1444_owner`, falling back to `current_owner`) for country tags `ENG`, `FRA`, `POR`, `CAS`, `ARA`. All IDs below are the province IDs used everywhere else in the project (province graph, ownership manifest, save state) — naval will not mint a second ID namespace, per [00 - Scope](../00_SCOPE_AND_ARCHITECTURE_LOCK.md#geography).

## England/France Channel fixture

### Sea zones (water province IDs)

| ID | Name | Notes |
|---|---|---|
| 1271 | Straits of Dover | Narrowest Channel crossing; links Calais (ENG) to Kent/Sussex (ENG side of the Channel) |
| 1272 | The Channel | Wider western Channel; links Cornwall/Devon/Dorset (ENG) to Cotentin (ENG-held Normandy) |
| 1270 | Dogger Bank | North Sea approach from Kent/London/Essex/Lincoln/Norfolk/Hull |
| 1276 | Cote D'Argent | Gascon coast (ENG-held) / Castilian Cantabrian approach |

### Candidate ports

**England (`ENG`), 29 coastal candidates at 1444, Channel-relevant subset:**

| Province ID | Name | Sea exits |
|---|---|---|
| 87 | Calais | 1269, 1271 |
| 235 | Kent | 1270, 1271 |
| 4371 | Sussex | 1271, 1272 |
| 233 | Cornwall | 1272, 1285 |
| 4373 | Devon | 1272, 1285 |
| 4374 | Dorset | 1272 |
| 4385 | Cotentin | 1271, 1272 |
| 167 | Caux | 1271 |
| 168 | Normandie | 1271 |

(England holds Calais and Gascon/Norman coastal provinces at the 1444 start per the ownership manifest — historically correct pre-1453 Hundred Years War state, not a data error.)

**France (`FRA`), 4 coastal candidates at 1444** (France's Atlantic/Mediterranean coast is largely English- or Aragon-held at this date per the manifest):

| Province ID | Name | Sea exits |
|---|---|---|
| 4111 | Saintonge | 1275, 1276 |
| 4386 | Vendee | 1275 |
| 200 | Languedoc | 1296 |
| 2753 | Narbonne | 1296 |

### Recommended minimal fixture

- **Primary crossing (transport):** Calais (87, ENG) ↔ Straits of Dover (1271) ↔ Kent (235, ENG) — both English-held at 1444, suitable for the friendly-transport/embarkation happy path (no access checks to fail).
- **Interception fixture (hostile):** Calais (87, ENG) ↔ Straits of Dover (1271) ↔ Picardie (89, `BUR` Burgundy) — Picardie is coastal with its sole sea exit on zone 1271, directly opposite Calais/Kent, and is Burgundian- not English-owned at 1444, giving a real hostile/neutral pairing on the narrowest crossing for interception and access-denial tests. (Vlaanderen, 90, `FLA`/Flanders, sits one zone north on 1269 and is a secondary candidate if a second hostile approach is needed.)
- **Sea zones to fixture-test:** 1271 (Straits of Dover, narrow crossing) and 1272 (The Channel, wider crossing) cover both the roadmap's "England-France Channel scenario" cases.

## Portugal/Castile/Aragon secondary fixture

### Sea zones (water province IDs)

| ID | Name | Notes |
|---|---|---|
| 1293 | Straits of Gibraltar | Links Portuguese Algarve/Ceuta to Castilian Andalucía/Cadiz/Huelva — this is the roadmap's named Gibraltar fixture |
| 1291 | Lusitanian Sea | Portuguese Atlantic coast (Lisboa, Porto, Aviero) and Castilian Galicia/Vigo |
| 1292 | Gulf of Cadiz | Portuguese Algarve/Lisboa/Beja |
| 1295 | Gulf of Valencia | Aragonese Mediterranean coast (Valencia, Barcelona, Tarragona) |
| 1296 | Gulf of Lion | Aragonese/French Mediterranean coast (Barcelona, Girona, Roussillon, Languedoc, Narbonne) |
| 1300 | Western Mediterranean | Aragonese islands (Sardinia, Baleares, Minorca) |

### Candidate ports

**Portugal (`POR`), 10 coastal candidates:**

| Province ID | Name | Sea exits |
|---|---|---|
| 227 | Lisboa | 1291, 1292 |
| 231 | Porto | 1291 |
| 230 | Algarve | 1292, 1293 |
| 229 | Beja | 1292 |
| 1751 | Ceuta | 1293 |
| 4556 | Aviero | 1291 |

**Castile (`CAS`), 12 coastal candidates:**

| Province ID | Name | Sea exits |
|---|---|---|
| 206 | Galicia | 1278, 1290, 1291 |
| 1749 | Cadiz | 1293 |
| 224 | Andalucía | 1293 |
| 4548 | Huelva | 1293 |
| 207 | Asturias | 1276, 1278 |
| 209 | Vizcaya | 1276 |

**Aragon (`ARA`), 20 coastal candidates, Mediterranean subset:**

| Province ID | Name | Sea exits |
|---|---|---|
| 213 | Barcelona | 1295, 1296 |
| 220 | Valencia | 1295 |
| 2988 | Tarragona | 1295 |
| 212 | Girona | 1296 |
| 197 | Roussillon | 1296 |
| 333 | The Baleares | 1295, 1296, 1300, 1301 |

### Recommended minimal fixture

- **Gibraltar crossing:** Algarve (230, POR) or Ceuta (1751, POR) ↔ Straits of Gibraltar (1293) ↔ Cadiz/Huelva/Andalucía (CAS) — exercises the roadmap's "Gibraltar-Mediterranean" connectivity requirement directly, and both sides are historically distinct owners at 1444 (no war-state ambiguity like the Channel case).
- **Aragonese Mediterranean base:** Barcelona (213, ARA) as the western-Mediterranean fleet-basing fixture, exits to both 1295 and 1296.

## Provenance/review template

No existing per-record naval provenance template was found (the ownership manifest has `source_url`/`source_note`/`reviewer`/`review_date`/`confidence` columns that can be mirrored). Recommend the N1.1 port/classification override table reuse that column shape (`source`, `note`, `reviewer`, `review_date`, `confidence`) rather than inventing a new provenance schema, for consistency with `docs/data/1444_ownership_manifest.csv`.

## Numerical performance budgets

Deferred — depends on the non-naval performance baseline flagged as an open item in [N0 Baseline Inventory](N0_BASELINE_INVENTORY.md#non-naval-performance-baseline), which was not captured in this pass.

## Resolved risk

The Channel fixture's "hostile interception" pairing initially looked unresolved because the sampled `FRA`-tagged provinces are not adjacent to the Dover/Channel zones at 1444. Resolved: Picardie (89) is Burgundian-owned (`BUR`), coastal, with its sole sea exit on 1271 (Straits of Dover) — directly opposite Calais/Kent. Used above as the interception fixture.
