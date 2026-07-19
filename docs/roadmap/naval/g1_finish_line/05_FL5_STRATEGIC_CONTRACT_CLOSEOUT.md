# FL5 - Strategic Contract Closeout

**Status:** Complete (FL5.1, FL5.2, FL5.3 all complete - see evidence)
**Goal:** Close the remaining naval output contracts without prematurely implementing trade or colonisation.

## Scope

### FL5.1 Trade-protection output

*Complete - [FL5_1_TRADE_PROTECTION.md](evidence/FL5_1_TRADE_PROTECTION.md). `NavalTradeProtection` mirrors `BlockadeSystem`'s own eligibility/effective-power/contested-zone shape, gated on a `trade_protection` mission instead of `blockade`, returning a zero-with-reason result; a pure, currently-unconsumed query that writes nothing and fabricates no income/route/market concept.*

- Define a stable, derived naval trade-protection result by country and relevant zone or port.
- Use eligible fleet mission, effective power, supply and contested-zone rules.
- Keep trade income calculation outside the naval system.
- Return zero with an explanation when no future trade consumer exists.
- Do not fabricate income, routes, markets or trade nodes for this slice.

### FL5.2 Blockade and coastal query contract

*Complete - [FL5_2_BLOCKADE_COASTAL_CONTRACT.md](evidence/FL5_2_BLOCKADE_COASTAL_CONTRACT.md). Audit confirmed every `BlockadeSystem` query is pure/live and every consumer read-only; two previously-untested transitions (peace, annexation) were found genuinely gapped and closed with a new focused test proving same-day, no-lag blockade release for both.*

- Document blockade strength, tier, attacker, contested state and affected port/coast queries.
- Confirm consumers cannot mutate blockade state.
- Define event ordering for blockade start, level change, full blockade, release, peace and annexation.
- Confirm economy, repair, construction, siege and war-score consumers reconcile from the same authoritative result.

### FL5.3 Downstream boundary lock

*Complete - [FL5_3_DOWNSTREAM_BOUNDARY_LOCK.md](evidence/FL5_3_DOWNSTREAM_BOUNDARY_LOCK.md). Documentation-only packet: no trade/exploration/colonisation pillar exists yet (grepped clean), so this locks the ID/query contract, the identity-mutation prohibition, and versioning expectations in writing before one is built, plus a deferred-mechanics list kept separate from any G1 blocker.*

- Document which naval IDs and queries future trade, exploration and colonisation may consume.
- Explicitly forbid downstream pillars from changing fleet identity, transport ownership, sea-zone identity or port identity without schema review.
- Define versioning and compatibility expectations for the consumer API.
- Record intentionally deferred mechanics separately from G1 blockers.

## Automated verification

- Trade-protection output is deterministic, bounded and zero when ineligible or contested.
- Mission, damage, supply, battle, peace and annexation transitions update the derived output correctly.
- Blockade consumers receive consistent values within the scheduler order.
- Save/load produces identical outputs without persisting redundant derived state.
- Existing economy and war-score accounting remain unchanged unless an approved consumer uses the output.

## Exit evidence

- Versioned naval downstream contract.
- Targeted transition and determinism test results.
- Scheduler/consumer reconciliation table.
- Explicit list of deferred non-G1 trade and colonisation mechanics.

## Exit gate

FL5 is complete when the remaining trade-protection and blockade/coastal outputs are stable, test-backed and safe for future consumers, with no trade or colonisation gameplay implemented as part of this work.
