# 07 — Metrics and Evidence

## Audit Basis

This is a snapshot of the repository as reviewed on 15 July 2026. It records concrete evidence behind the completion estimates and should be updated when milestone gates pass.

## Current Content Scale

| Metric | Current recorded value | Interpretation |
|---|---:|---|
| Active countries in 1444 scenario | 703 | The playable world is already broad in geographic coverage. |
| Country registry entries | 1,007 | Includes active, inactive, formation/release or otherwise registered entities. |
| Province manifest rows | 4,940 | Full-world province data requires scalable validation and tooling. |
| Economic province records | 3,924 | Most relevant land has economic records, but this is not equivalent to full historical authoring. |
| Eligible land provinces | 3,256 | Used by current scenario/economy coverage checks. |
| Non-economic province rows | 668 | Require explicit classification so omissions are intentional. |
| Trade goods | 31 | Goods exist; a global trade-flow system does not. |
| Buildings | 10 | Functional economy content, still shallow for a full campaign. |
| Land units | 5 | Working recruitment/combat set, not full era progression. |
| Authored AI country profiles | 5 | Aragon, Castile, Granada, Navarre and Portugal. |
| Country-depth profiles | 5 | Representative Iberian slice. |
| Authored country-depth provinces | 18 | Deep data coverage is highly regional. |
| Authored characters | 12 | Insufficient for worldwide historical rulers. |
| Dynasties | 5 | Iberian representative set. |
| Titles | 5 | Character/title framework exists but global content is thin. |
| Character claims | 2 | Representative rather than global. |
| Ruler assignments | 5 | Most countries still rely on generated/default state. |
| Cultures | 6 | Framework/content is intentionally narrow. |
| Religions | 3 | Does not yet cover worldwide faith depth or the Reformation arc. |
| Government families/types | 4 | Foundation exists. |
| Government reforms | 3 | Too thin for differentiated worldwide politics. |
| Idea groups | 4 | Framework exists; country/era breadth remains. |
| Authored events | 3 | Representative sample only. |
| Authored decisions | 3 | Representative sample only. |
| Approved historical shields | 39 | Small approved subset. |
| Missing/unapproved shield entries | 968 | Major research/art/provenance backlog. |

## Automated Quality Evidence

| Evidence | Recorded result | Limitation |
|---|---|---|
| Full headless test report | 42/42 PASS | Predates some later front-end additions; rerun at every major gate. |
| Deterministic campaign coverage | Present | Must expand for all missing pillars. |
| Save/load round-trip coverage | Present | New schema fields require migration and replay expansion. |
| Front-end/country-selection/layout checks | Passing in latest recorded run | Does not replace hands-on UX/accessibility sessions. |
| Export test fallback | Trusted-host PCK fallback available | Windows Application Control can block newly generated unsigned temporary executables with error 4551. |

## Performance Evidence

| Scenario | Hardware | Result |
|---|---|---|
| 1080p map movement | AMD Radeon 610M | P50 13.266 ms, P95 15.748 ms, maximum 26.185 ms. |

This is encouraging for ordinary map movement, but it does not yet prove performance with finished terrain, worldwide AI, naval fleets, global trade, colonisation, dense wars, final labels/markers and full UI panels active simultaneously.

## Known Release Blockers

- Province map and `definition.csv` provenance is not fully approved.
- Water-source provenance/authority is unresolved.
- Rivers have no approved production data source.
- Visual Greenlight remains incomplete.
- Only 39 historical shields are approved.
- No production music or SFX files exist.
- Worldwide historical rulers, claims, ideas, relations, events and decisions are largely unauthored.
- Naval, colonisation, trade, HRE and Reformation pillars do not yet meet thin-loop status.

## Evidence Update Rules

When a milestone is declared complete, update this file with:

1. Build/version identifier.
2. Commit or content-version identifier.
3. Test report path and pass/fail count.
4. Performance capture path and hardware profile.
5. Save-compatibility statement.
6. Content coverage counts.
7. Historical/provenance review status.
8. Known blockers and approved exceptions.

## Completion Estimate Rationale

The current 25–35% full-product estimate reflects the difference between breadth of code and breadth of finished player experience:

- Architecture and connected land gameplay are advanced.
- A representative region demonstrates many country-level systems.
- Five global pillars remain missing.
- Worldwide authored historical content is only a small percentage of the required volume.
- Final UI, map, portrait, river, audio, accessibility and tutorial work remains substantial.
- Release gates for world-scale AI, balance, compatibility and legal provenance have not passed.

The estimate should rise only when gates pass, not simply when more classes or rows are added.

