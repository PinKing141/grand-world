# Phase 0 — Pre-production and Foundation

## Mission

Turn the working map demo into a safe, testable, production-ready foundation before building campaign systems.

## Production Gate

Pre-production Exit.

## Player Outcome

The player does not receive a complete game loop in this phase. The outcome is a reliable map application that opens consistently, displays valid data, and can support future systems without source-data corruption.

## Entry Conditions

- The map demo runs.
- The map editor addon loads.
- Province and country files are present.
- Forward+ rendering is configured.

## Major Deliverables

### Source and Build Discipline

- Initialise Git.
- Commit the known working baseline.
- Define ignored generated files.
- Record the Godot and addon versions.
- Add a packaged-build smoke-test procedure.
- Define branch and commit conventions.

### Scene Separation

Create a minimal runtime hierarchy:

~~~text
GameRoot
├── SimulationRoot
├── MapRoot
└── UIRoot
~~~

The existing map renderer remains responsible only for map presentation and province colour updates.

### Data Separation

- Define static data versus campaign state.
- Create stable integer IDs for runtime entities.
- Define content ID naming rules.
- Stop using the large main scene as the long-term gameplay database.
- Design a baked runtime database.
- Preserve original source data as scenario input.

### Import and Bake Pipeline

Create a documented process:

~~~text
Source text and CSV
→ Parse
→ Validate
→ Normalise
→ Bake runtime data
→ Load campaign
~~~

Required validators:

- Duplicate province IDs.
- Duplicate province colours.
- Unknown owners.
- Missing country colours.
- Invalid capital references.
- Undefined map pixels.
- Missing source files.

### Map Safety

- Guard province dictionary lookups.
- Handle oceans, wastelands, and invalid pixels safely.
- Disable writing debug map images during normal gameplay.
- Keep explicit developer controls for regenerating debug images.
- Confirm generated texture paths are not used as campaign saves.

### Test Foundation

Add a headless test path for:

- Project loading.
- Addon class availability.
- Province database loading.
- Country database loading.
- Known province lookup.
- Invalid province lookup.
- Data bake validation.

### Technical Decision Records

Record at minimum:

- Country-first player identity.
- 1444–1700 initial scope.
- Daily deterministic simulation.
- Static definition and runtime-state split.
- Command-based state mutation.
- Single-player first.
- GDScript first, C++ only for measured bottlenecks.

## Work Breakdown

| Epic | Tasks | Exit evidence |
|---|---|---|
| Repository safety | Git, ignore rules, baseline tag, recovery notes | Clean checkout runs |
| Runtime shell | GameRoot, map/UI/simulation separation | Scene boots with clear ownership |
| Data architecture | ID rules, definition/state schemas | Architecture review |
| Bake pipeline | Parser, validators, baked output | Repeatable bake with zero errors |
| Map hardening | Lookup guards, debug flags, error UI | Invalid input does not crash |
| Test harness | Headless smoke and data tests | Automated test report |
| Budgets | Frame, simulation, memory, save targets | Budget document approved |

## Acceptance Criteria

- A clean project checkout can rebuild required imported assets.
- The project opens without resource or script errors.
- Invalid province pixels fail safely and produce a diagnostic.
- Source scenario data is not modified by normal campaign play.
- A data bake produces the same stable IDs on repeated runs.
- The project has a documented recovery process.
- A packaged build reaches the main map.
- Core smoke tests can run without manual editor interaction.
- The detailed architecture plan and roadmap link correctly.

## Quality Gates

- No P0 or P1 startup defects.
- No known source-data corruption path during runtime.
- No unexplained addon or shader load warning.
- Data validator results are deterministic.
- A baseline performance capture exists.

## Primary Risks

- Existing EU-style data contains inconsistent or missing references.
- The main scene embeds too much generated data.
- Runtime and editor editing paths may be confused.
- Addon binaries may fail after a Godot upgrade.
- Scope pressure may begin gameplay work before the foundation is recoverable.

## Mitigations

- Keep source and baked data separate.
- Pin the working engine version during this phase.
- Add validation before global content work.
- Require the Pre-production Exit gate before starting economy, war, or character systems.

## Explicitly Out of Scope

- Economy.
- Armies.
- Diplomacy.
- Characters.
- Global historical balancing.
- Final UI art.
- Multiplayer.
- 1700–1821 content.

