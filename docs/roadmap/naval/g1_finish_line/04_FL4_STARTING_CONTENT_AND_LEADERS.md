# FL4 - Starting Naval Content and Leaders

**Status:** Complete - see [FL4_STARTING_CONTENT_AND_LEADERS.md](evidence/FL4_STARTING_CONTENT_AND_LEADERS.md).
**Goal:** Replace release-blocking placeholders with reviewed, traceable starting naval content or explicitly approved generation policies.

## Scope

### FL4.1 Content policy

- Decide whether G1 ships exact historical forces, gameplay-balanced approximations, or a documented mixture.
- Define what `reviewed`, `approved placeholder`, `generated` and `unknown` mean.
- Require a source, reasoning note, reviewer and review date for each release row.
- Do not present gameplay estimates as exact historical counts.

### FL4.2 Starting fleet review

- Review England, France, Portugal, Castile and Aragon fleet ownership, home ports, ship families, counts and transport capacity.
- Confirm every home port exists and belongs to or legally bases the country at campaign start.
- Confirm stable fleet and ship IDs remain collision-free and deterministic.
- Review balance against the Channel and Iberian acceptance fixtures.
- Expand to additional countries only when required by the approved G1 content boundary.

### FL4.3 Admiral policy and content

- Add reviewed named admirals where the historical/content standard supports them.
- Otherwise approve a deterministic generated-leader policy before generating any leader.
- Define eligibility, country, age/lifespan, skill bounds, traits, fleet assignment and replacement behavior.
- Validate that one admiral cannot command multiple fleets and dead/ineligible leaders cannot remain assigned.
- Define save migration behavior for older saves without starting admirals.

### FL4.4 Validation and tooling

- Validate schema, unique IDs, owner/port references, ship definitions and provenance fields.
- Fail loudly on a participating country's invalid row; skip countries outside focused synthetic fixtures without creating ghosts.
- Verify initialization is idempotent.
- Verify content is included in Windows exports.
- Generate a human-readable content report with unresolved review states.

## Automated verification

- Starting content initializes the expected fleets, ships and leaders exactly once.
- Every membership and leader reverse reference is valid.
- Identical starting state produces identical IDs and checksum.
- Save/load and old-schema migration do not duplicate starting forces or leaders.
- Annexation, death and fleet destruction clean up assignments.
- Focused synthetic scenarios remain isolated from unrelated world content.

## Manual verification

- Content owner reviews the generated report and signs each release row.
- Gameplay review confirms neither Channel side starts with an accidental forced outcome.
- Names, ports and country labels display correctly in the real HUD.

## Exit evidence

- Approved content policy.
- Generated fleet/admiral validation report.
- Named sources and review metadata.
- Starting-content, migration, lifecycle and export test results.

## Exit gate

FL4 is complete when every shipped starting fleet and admiral has an approved status and provenance, unresolved placeholders are absent from the G1 content boundary, and initialization, migration and lifecycle tests pass.
