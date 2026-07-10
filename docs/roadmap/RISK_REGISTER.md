# Risk Register

## Usage

Review this register:

- At the start of every phase.
- At every major milestone gate.
- When a trigger condition occurs.
- When scope, engine version, data source, or target platform changes.

Ratings:

- Likelihood: Low, Medium, High.
- Impact: Low, Medium, High, Critical.

## Active Risks

| ID | Risk | Likelihood | Impact | Trigger | Mitigation |
|---|---|---:|---:|---|---|
| R-001 | Scope expands toward full CK and EU feature parity before the vertical slice | High | Critical | New major systems enter active phase without displaced scope | Enforce milestone non-goals and change control |
| R-002 | Imported map or historical data cannot be redistributed | Medium | Critical | Public/commercial release planning begins without provenance | Track sources, review rights, replace unlicensed content |
| R-003 | Global content volume exceeds sustainable throughput | High | High | Slice content metrics project an unmanageable workload | Improve tools, reduce required content, phase regions |
| R-004 | AI works locally but fails in long campaigns | High | High | Soak tests show stalls, loops, or incoherent strategy | Shared command API, debug inspector, scheduled AI, soak tests |
| R-005 | Simulation is not deterministic | Medium | High | Replay checksums diverge | Stable ordering, seeded RNG, fixed-point values, deterministic tests |
| R-006 | Late-game simulation becomes too slow | High | Critical | Tick time rises non-linearly in soak tests | Budgets, profiling, scheduling, data-oriented systems, targeted C++ |
| R-007 | Save schema changes break campaigns | High | High | Runtime models change without migration | Version schemas, migrations, round-trip and upgrade fixtures |
| R-008 | Addon or Godot upgrade breaks native classes or shaders | Medium | High | Engine upgrade proposed or plugin fails CI | Pin version, compatibility branch, smoke tests, source availability |
| R-009 | Main scene and source data remain too tightly coupled | Medium | High | Gameplay changes require editing huge scene dictionaries | Bake runtime database and separate GameRoot early |
| R-010 | UI cannot explain simulation depth | High | High | Testers repeatedly misunderstand outcomes | Explanation APIs, tooltips, ledgers, UX testing from early phases |
| R-011 | Warfare complexity overwhelms economy and diplomacy | Medium | High | Phase 5 grows advanced combat before peace loop works | Thin complete war loop, defer advanced combat |
| R-012 | Character layer destabilises country state | Medium | Critical | Succession changes ownership through special cases | Keep Country, Title, Character separate; gate after vertical slice |
| R-013 | Historical research and data entry produce inconsistent content | High | Medium | Validation warnings and conflicting sources increase | Provenance fields, review rules, schema validation |
| R-014 | Single-developer knowledge concentration causes recovery risk | High | High | Unrecorded systems or manual-only pipelines appear | Docs, automated tools, backups, decision records |
| R-015 | Maximum-speed memory growth causes long-session crashes | Medium | High | Soak memory trends continuously upward | Leak testing, pooling, bounded histories, profiling |
| R-016 | Feature work continues during Beta | High | High | New mechanics proposed after feature lock | Formal exception process and displaced-scope rule |
| R-017 | Naval and trade systems expand beyond 1.0 capacity | High | High | Global design assumes deep naval/trade before slice evidence | Explicit scope gate; use thin placeholders first |
| R-018 | Content bake is not reproducible | Medium | High | Same source produces different IDs or checksum | Stable sort and IDs, deterministic bake tests |

## Top Risk Actions

### R-001 Scope Expansion

Immediate actions:

- Keep explicit phase non-goals.
- Require a product-pillar justification.
- Split XL work before production.
- Defer 1700–1821 mechanics.

Success signal:

- Active work maps directly to the current phase exit criteria.

### R-003 Content Volume

Immediate actions:

- Measure content creation during the Iberia slice.
- Automate validation and baking.
- Separate required simulation content from optional flavour.
- Create templates and batch tools.

Success signal:

- Global content forecast fits available capacity or scope is adjusted.

### R-006 Late-Game Performance

Immediate actions:

- Establish phase budgets.
- Build AI scheduling from the beginning.
- Maintain reverse indexes.
- Run growing-scale soak tests before global content complete.

Success signal:

- Tick-time percentiles remain within target as scale increases.

### R-007 Save Compatibility

Immediate actions:

- Version every save.
- Store stable definition IDs.
- Create migration fixtures.
- Run round-trip tests on every state system.

Success signal:

- Supported older saves load or fail with an explicit supported-policy message.

### R-012 Character Integration

Immediate actions:

- Preserve CountryState as political authority.
- Use titles to connect characters to territory.
- Implement one simple succession law first.
- Test death and succession during war, occupation, and subject relationships.

Success signal:

- Multiple generations simulate without invalid country, title, or family references.

## Risk Escalation

A risk becomes a milestone blocker when:

- Its trigger has occurred.
- No tested mitigation exists.
- It threatens an exit criterion.
- Continuing would create expensive throwaway work or data.

Blocked work should pivot to mitigation, tool development, tests, or another dependency-safe task rather than silently bypassing the gate.

