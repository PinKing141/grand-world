# FL7 Headless Simultaneous Fixtures

**Date:** 2026-07-20
**Result:** PASS - FL7 now owns named dense-presentation and combined global simultaneous headless fixtures. Rendered-mode and approved target-hardware budgets remain outside headless reach, so FL7 stays at `Validation`.

## FL7.1 dense-zone presentation

`tests/naval_dense_zone_presentation_stress_test.gd` loads the real main scene and places 120 friendly, allied, neutral and hostile fleets in the Channel view and adjacent ports while selected-route, land-battle, siege, naval-battle and blockade presentation are all active.

Measured result on this development host:

- 120 logical fleets -> 5 fleet marker clusters.
- Largest stack: 60 fleets, with deterministic click-to-cycle selection.
- 30 repeated full fleet/conflict rebuild samples.
- Rebuild P50 299.588 ms, P95 719.042 ms, maximum 733.782 ms.
- Static memory monitor at completion: 486,182,260 bytes.
- Stable cluster signature, selected route and bounded one-instance-per-cluster contract: PASS.

These are conservative headless regression measurements, not approved rendered-frame budgets.

## FL7.2-FL7.6 combined global simulation

`tests/naval_global_simultaneous_stress_test.gd` runs the production scheduler and systems together across eight synthetic maritime countries. It includes:

- eight real transport operations and an intentional carrier drop below the 50% usable-capacity threshold;
- three seeded multi-fleet/multi-ship battle sites, reaching eight simultaneous authoritative battles after reinforcements;
- multi-coast blockade processing;
- economy, accelerated real-command naval construction completion, fleet movement/logistics/missions and global naval AI;
- peace cleanup, country extinction cleanup, admiral death and AI replacement, plus two mixed-state save/load continuations;
- terminal fleet/ship membership validation and a final save/load validator pass;
- an uninterrupted run compared with the twice-reloaded continuation by terminal world checksum.

Measured reloaded-run result:

- 24 days, 8 transports, maximum 8 battles, 2 blockaded provinces, 29 fleets and 69 ships.
- 58 country-planning visits and 15 real naval-AI commands.
- AI P50 7.795 ms, P95 136.554 ms, maximum 138.685 ms.
- Day P95 590.340 ms, maximum 592.425 ms.
- Largest midpoint save: 501,804 bytes; measured load: 48.615 ms.
- Uninterrupted time 7,278.97 ms; twice-reloaded time 8,301.04 ms.
- Matching terminal checksum: `f4994ac57b11a9650636bd7d229baf5265e835502987a722ac2f665d601398f7`.

The broader focused suite remains the authority for each destructive outcome in isolation; this fixture's purpose is to prove those major systems can operate concurrently without replay drift or registry corruption.

## Remaining boundary

FL7's exit gate still requires rendered-mode evidence and approved low-end/target-hardware CPU, memory, save and frame budgets. The measurements above are regression guards on the available development host and do not replace that human/hardware approval.
