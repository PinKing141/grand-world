# Phase 2 — Deterministic Simulation Core

## Mission

Create the authoritative campaign state and time-processing framework that every later gameplay system will use.

## Production Gate

First Playable.

## Player Outcome

The player can choose a country, pause and advance time from 11 November 1444, issue at least one validated world-changing command, save, load, and observe the same state after loading.

## Entry Conditions

- Map UX Gate passes.
- Province and country data can be addressed by stable IDs.
- Runtime state is separate from source definitions.

## Major Deliverables

### WorldState

Authoritative containers for:

- ProvinceState.
- CountryState.
- DiplomaticRelation placeholders.
- Army and war registries prepared but not yet fully implemented.
- Current date.
- Player-controlled country.
- Global flags and counters.

### Game Clock

- Integer day count.
- 11 November 1444 initial date.
- Pause.
- Five speed levels.
- Maximum ticks-per-frame cap.
- Daily, monthly, and yearly boundaries.
- Calendar formatting.

### Scheduler

Stable system order:

1. Apply commands.
2. Run daily systems.
3. Run periodic systems.
4. Process events.
5. Run scheduled AI hooks.
6. Publish state changes.
7. Update presentation.

### Command Bus

Base command contract:

- Command ID.
- Issuing entity.
- Scheduled day.
- Validation.
- Application.
- Failure reason.
- Optional player-facing description.

Initial commands:

- SelectPlayerCountryCommand.
- ChangeProvinceOwnerCommand for controlled testing.
- SetGameSpeedCommand.
- PauseCommand.

### Event and Notification Bus

Structured events:

- DateChanged.
- MonthStarted.
- YearStarted.
- ProvinceOwnerChanged.
- PlayerCountryChanged.
- CommandRejected.

Presentation subscribes to events but does not own authoritative state.

### Deterministic Randomness

- Campaign seed.
- Stored RNG state.
- Named random streams or deterministic sequencing.
- No untracked global randomness in simulation rules.

### Save and Load Skeleton

Save:

- Schema version.
- Game version.
- Scenario ID.
- Current day.
- RNG state.
- Player country.
- Province owners and controllers.
- Country runtime values.
- Global flags.

Load:

- Validate header.
- Migrate supported older schema.
- Reject incompatible or corrupted saves with a useful message.
- Rebuild derived indexes.
- Rebuild presentation.

### Debug Tools

- Pause and single-step one day.
- Jump a month for testing.
- Display current tick cost.
- Dump selected province or country state.
- World-state checksum.
- Command history for the current session.

## First Playable Definition

The first playable is deliberately small:

~~~text
Choose a country
→ Hover and select provinces
→ Pause and unpause
→ Advance days and months
→ Issue a controlled ownership command
→ Map updates from WorldState
→ Save
→ Load
→ State is restored
~~~

This proves the complete data-to-simulation-to-presentation path.

## Acceptance Criteria

- Campaign begins on 11 November 1444.
- Pause prevents all authoritative simulation changes.
- Different rendering frame rates produce the same state for the same commands and seed.
- Maximum speed cannot permanently lock the UI.
- Commands are validated before mutation.
- Rejected commands return an understandable reason.
- The map reads ownership from WorldState.
- Save/load round-trip produces an equivalent checksum.
- Derived country-to-province indexes rebuild correctly.
- The simulation can advance ten automated years without state corruption.

## Determinism Tests

1. Load fixed scenario.
2. Set fixed seed.
3. Submit fixed command list.
4. Simulate a fixed number of days.
5. Record checksum.
6. Repeat under a different rendering frame rate.
7. Verify the same checksum.

## Performance Gates

- Typical speed-one simulation work stays within its provisional frame budget.
- High speed is limited by a tick cap rather than unbounded loops.
- No simulation entity receives its own process callback.
- No full save serialisation occurs inside a normal daily tick.

## Primary Risks

- Godot Dictionary iteration order may be used accidentally.
- Floating-point calculations may cause replay divergence.
- Presentation code may directly mutate WorldState.
- Save schema may be over-designed before real systems exist.
- Excessive signals may create hidden ordering problems.

## Explicitly Out of Scope

- Full economy.
- Army movement.
- Battles.
- Character simulation.
- Strategic AI.
- Final save compression.
- Multiplayer networking.

