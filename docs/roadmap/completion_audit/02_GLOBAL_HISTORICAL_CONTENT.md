# 02 — Global Historical Content

## Current state

The frameworks for rulers, dynasties, governments, ideas, claims, religion, events and decisions exist, but authored depth is concentrated in a small Iberian sample. Approximately 703 countries are active in the 1444 scenario and 1,007 entries exist in the country registry, so manual ad hoc editing will not scale safely.

## Definition of a Content-Complete Country

Every active 1444 country must have a reviewed record for each field below. “Not applicable” must be explicit; blank must never silently mean complete.

| Content area | Required country record |
|---|---|
| Identity | Stable tag, full display name, localisation key, adjective, map colour and provenance. |
| Heraldry | Approved historical shield/flag or an explicit researched placeholder status. |
| Government | Government family, starting reform, rank and mechanic eligibility. |
| Ruler state | Historical ruler, dynasty/house, age/birth approximation, legitimacy equivalent and succession state. |
| Heir/regency | Heir or explicit no-heir state, succession rules and regency eligibility. |
| Culture/religion | Primary culture, culture group, accepted cultures, state faith and tolerance modifiers. |
| Territory | Owned provinces, capital, cores, permanent claims and disputed claims. |
| Relations | Subjects, unions, alliances, truces, rivals, access and historically important attitudes. |
| National direction | National ideas or equivalent bonuses, strategic AI priorities and country archetype. |
| Technology/economy | Starting technology, institutions/equivalent, treasury, manpower, force limits and special modifiers. |
| Content | Starting missions/objectives, decisions, event hooks and formation/release rules. |
| Sources | Source citation, researcher, reviewer, confidence and last-updated date. |

## Content Production Pipeline

### Stage 1 — Schema lock

- Freeze the required fields and allowed values.
- Add explicit `status`, `source`, `confidence`, `reviewer` and `review_date` fields.
- Version schemas and define migration rules.
- Prevent silent fallback from being counted as authored content.

### Stage 2 — Research packet

For each country, create one packet containing:

- selected historical date and territorial interpretation;
- ruler/dynasty evidence;
- government and religion interpretation;
- diplomatic relationships and claims;
- heraldry evidence and licence/provenance;
- known uncertainty and chosen gameplay abstraction.

### Stage 3 — Data entry and automated validation

- Enter through structured templates/tools, not scattered hand-edits.
- Validate IDs, duplicate claims, invalid dates, impossible subject loops and unsupported enum values.
- Generate a human-readable country preview.
- Run deterministic scenario load and save round-trip checks.

### Stage 4 — Historical review

- A second reviewer checks claims against the research packet.
- Disputed interpretations receive a recorded design decision.
- Review status becomes `approved`, `approved_with_caveat`, `needs_revision` or `blocked`.

### Stage 5 — Gameplay and AI review

- Confirm the country has a viable starting economy and military position.
- Confirm AI priorities do not force suicidal or ahistorical behaviour.
- Run regional 10-, 50- and 100-year seeded simulations.
- Record outliers, dominant patterns and dead countries.

## Recommended Geographic Waves

The exact order can change, but each wave must be small enough to validate before the next begins.

1. **Pilot outside Iberia:** British Isles and France, including French appanages and subject presentation.
2. **Western Europe:** Burgundy, Low Countries, western German states and Italy.
3. **Central/Northern Europe:** HRE remainder, Scandinavia, Poland-Lithuania and Baltic states.
4. **Eastern Europe and steppe:** Muscovy/Rus principalities, Balkans, Black Sea and steppe powers.
5. **Mediterranean and Middle East:** Ottomans, Mamluks, Maghreb, Arabia and Persia.
6. **Sub-Saharan Africa:** regional political entities, trade links and religion/culture review.
7. **South and Central Asia:** Indian subcontinent, Central Asian states and Himalayan polities.
8. **East and Southeast Asia:** Ming sphere, Japan, Korea, mainland and island Southeast Asia.
9. **Americas and Oceania:** indigenous states, colonisation interaction and non-European gameplay review.
10. **Global harmonisation:** relations, claims, trade, AI, balance, localisation and map-label integration.

## Required Tooling

- Country completeness dashboard by field and review state.
- Historical-source registry with link/archive metadata.
- Batch validators for IDs, dates, relationships, claims and ownership.
- Scenario diff viewer showing changes from the approved baseline.
- Country preview card with ruler, government, territory, relations and source status.
- Regional soak runner and outcome comparison report.
- Missing-localisation and short-tag leakage detector.
- Heraldry approval tracker tied to the existing shield research register.

## Acceptance Gates

### Global Content Pilot Gate

- At least 20 non-Iberian countries meet the complete-country definition.
- Two reviewers can use the packet/template process without direct code changes.
- Validation finds intentionally injected invalid data.
- A 100-year regional soak completes deterministically.
- The measured authoring time per country is recorded and used to forecast global production.

### Regional Wave Gate

- 100% of active countries in the wave have explicit status for every required field.
- 95% or more of planned records are approved; remaining caveats have owners and deadlines.
- No unresolved blocker-level ownership, subject, ruler or capital error remains.
- AI and economy outliers are reviewed rather than silently accepted.

### Global Content Complete Gate

- Every active 1444 country is approved under the same schema.
- All province ownership, cores, claims, culture, religion and capital records validate.
- Historical shields, portraits and other sourced assets have approval/licence status.
- Worldwide 1444–1700 multi-seed soaks meet stability and performance budgets.

## Principal Risks

- Historical ambiguity will create inconsistent interpretations without decision logs.
- New pillar schemas may invalidate content if authored too early.
- Generated rulers and generic ideas can hide missing content unless dashboards distinguish authored from fallback.
- Heraldry and source-map provenance can create commercial release blockers even when gameplay is complete.
- A single-person research process can become the project’s longest critical path; templates and review batches are essential.
