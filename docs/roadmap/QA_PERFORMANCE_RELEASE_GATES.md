# Quality, Performance, and Release Gates

## Purpose

Quality and performance are production requirements, not final polishing tasks. Every phase must define tests and remain within the current budgets.

All budgets are provisional until reference-hardware captures establish realistic baselines.

## Reference Targets

### Presentation

- Target resolution: 1920 × 1080.
- Target frame rate: 60 frames per second.
- Target frame time: 16.67 milliseconds.
- Input response target: under 100 milliseconds.
- Avoid recurring normal-play hitches above 50 milliseconds.

### Simulation

- Speed one should leave most frame time available for presentation.
- High speed uses a bounded tick count per rendered frame.
- Target maximum-speed throughput after global scaling: at least 30 game days per real second on reference hardware, subject to measured revision.
- Simulation must remain responsive to pause input.
- AI work must be scheduled and budgeted.

### Memory and Storage

- Establish a baseline after the vertical slice.
- No continuous memory growth during campaign soak.
- Saves should be versioned and compressed when justified.
- Provisional global save target: under 100 MB.
- Provisional global load target: under 10 seconds on reference storage.

These are targets, not permission to hide degradation. Measurements must be stored with milestone builds.

## Test Pyramid

### Unit Tests

Use for:

- Date conversion.
- Economy formulas.
- Command validation.
- Modifier stacking.
- Succession eligibility.
- War-score calculation.
- Path costs.
- Content parsing.

### Integration Tests

Use for:

- Command to WorldState mutation.
- Ownership index updates.
- Economy month processing.
- Movement and arrival.
- Battle to occupation.
- Peace to ownership transfer.
- Character death to succession.
- Save and load.

### Simulation Tests

Use for:

- Fixed-seed deterministic replay.
- Multi-year economy.
- Repeated wars.
- AI-only campaigns.
- Dynasty generation.
- Country formation and extinction.

### End-to-End Tests

Use for:

- New campaign.
- Country selection.
- Main gameplay loop.
- Save and resume.
- Campaign reaching 1700.
- Packaged-build startup.

### Exploratory Tests

Focus on:

- UI behaviour.
- Unusual diplomatic states.
- Exploits.
- Player confusion.
- Balance.
- Emergent outcomes.

## Determinism Gate

For a fixed scenario, seed, and command stream:

- World checksum must match between runs.
- Rendering frame rate must not change the checksum.
- Save/load inserted during the run must not change the final checksum.
- Supported platforms must produce compatible authoritative results where required.

Any intentional non-deterministic system must be documented and excluded from authoritative state.

## Campaign Soak Tests

Required soak profiles:

- Ten-year regional simulation.
- Fifty-year regional simulation.
- 1444–1700 global AI-only simulation by Alpha.
- Repeated war stress.
- Repeated save/load stress.
- Maximum-speed memory test.

Capture:

- Crashes.
- Assertions.
- Invalid references.
- Countries with impossible state.
- Tick time percentiles.
- Memory trend.
- Save size.
- AI command rejection rate.

## Data Validation Gate

Release builds require:

- Zero unknown required references.
- Zero duplicate stable IDs.
- Zero duplicate province colours.
- Symmetric required adjacency.
- Valid capitals.
- Valid active rulers where required.
- Valid title hierarchies.
- Resolved localisation keys for required content.

## Defect Severity

| Severity | Meaning | Example |
|---|---|---|
| P0 Blocker | Build cannot be used or state is catastrophically corrupted | Campaign cannot start, save destroys data |
| P1 Critical | Core loop broken with no acceptable workaround | Wars cannot end, frequent crash |
| P2 Major | Significant defect with workaround | Incorrect map mode, AI stalls |
| P3 Minor | Limited impact or polish issue | Tooltip alignment |
| P4 Trivial | Cosmetic or very low impact | Small text inconsistency |

## Milestone Defect Gates

### First Playable

- No open P0.
- P1 issues documented and tightly controlled.

### Vertical Slice

- No open P0.
- No open P1 in the demonstrated loop.
- P2 count stable or decreasing.

### Alpha

- No open P0.
- P1 defects have owners and approved plans.

### Beta

- No open P0.
- Feature lock active.
- P1 count trends toward zero.

### Release Candidate

- Zero P0.
- Zero unmitigated P1.
- P2 exceptions explicitly approved and documented.

## Performance Review Points

Capture profiles at:

- Phase 0 baseline.
- Map UX Gate.
- First Playable.
- Movement Gate.
- Economy Loop Gate.
- War Loop Gate.
- Vertical Slice.
- Alpha.
- Content Complete.
- Every release candidate.

Profiles should include:

- CPU frame breakdown.
- GPU frame breakdown.
- Simulation systems.
- AI systems.
- Map update cost.
- UI cost.
- Memory.
- Save and load.

## Compatibility Matrix

Before Beta, define:

- Supported Windows versions.
- Minimum and recommended CPU.
- Minimum and recommended GPU.
- Required graphics APIs.
- Memory requirement.
- Storage requirement.
- Supported display resolutions.
- UI scaling range.

Test the GDExtension addon against the pinned Godot version and every shipping architecture.

## Release Checklist

- Version and build ID.
- Clean install.
- Upgrade install.
- Uninstall.
- New campaign.
- Save and load.
- Campaign soak.
- Supported hardware.
- Input remapping.
- UI scaling.
- Audio settings.
- Crash logs.
- Content validation.
- Localisation validation.
- Legal and provenance review.
- Release notes.
- Known issues.
- Rollback procedure.

