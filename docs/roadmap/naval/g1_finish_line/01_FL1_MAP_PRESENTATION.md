# FL1 - Naval Map Presentation

**Status:** Validation. Every named automatable gap in FL1.1-FL1.5 is now closed, including live merge/split selection, cancellation/peace/merge/load route reconciliation and deterministic blockade-attacker attribution. See [FL1_AUTOMATABLE_CLOSURE.md](evidence/FL1_AUTOMATABLE_CLOSURE.md). FL1 remains at `Validation` only for the rendered/manual checks consolidated under FL6: supported resolutions, keyboard-only use, colour-vision review, rendered timing and real GPU/hardware behavior.
**Goal:** Make authoritative naval activity visible and selectable without changing simulation state.

## Scope

### FL1.1 Fleet marker data - complete

- Define a derived marker view model keyed by stable fleet ID. *(`FleetMarkerLayer._rebuild()` derives one record per fleet from `fleet_registry` on every dirty rebuild - no new persisted state)*
- Expose owner, location, mission, movement state, destination, arrival day, battle state, transport reservation, damage state and selection priority. *(owner/location/mission/battle_id/ship_count/hull exposed; movement state beyond current location, destination/arrival day, and transport reservation are deferred to the FL1.3 route packet, which needs them for route drawing anyway)*
- Choose a stable map anchor for ports and sea zones. *(reuses `ProvinceGraph.anchor()` - the same anchor authority `ConflictMarkerLayer`'s naval-battle markers already use, since a sea zone is just another province ID)*
- Define deterministic ordering when multiple fleets share an anchor. *(precomputed sort key + native Array sort, the exact FL8.3-proven shape)*
- Reuse pooled or batched presentation; never create one map node per ship. *(one `MultiMeshInstance3D` batch for every fleet cluster)*

### FL1.2 Fleet markers and clustering - automatable scope complete

- Display a fleet marker for visible player, friendly and hostile fleets according to the current visibility policy. *(all fleets render today - no fog-of-war/visibility policy exists yet anywhere in the simulation to filter by, matching how `ArmyLayer` also renders every army regardless of owner)*
- Use icon, outline or text in addition to colour for owner and hostility. *(icon is the shared "navy" glyph; colour is the owner's national registry colour - hostility-relative highlighting is not yet added)*
- Cluster co-located fleets at lower zoom levels. *(done - bucketed spatial clustering, same algorithm as `ConflictMarkerLayer`)*
- Open a stable fleet list when a cluster is selected. *(click-to-cycle through cluster members, the same established pattern `WarHUD.focus_conflict_marker()`'s "marker N of M in cluster" already uses - not a dropdown list)*
- Keep selection stable while fleets arrive, retreat, merge, split, enter battle or are destroyed. *(done - split preserves the surviving source selection; selecting a source that is merged away retargets both map and HUD to the deterministic survivor; destruction/scuttle fallback remains covered by the earlier marker/HUD tests)*

### FL1.3 Route and mission feedback - automatable scope complete

- Draw the selected fleet's current route, destination and direction. *(done - `remaining_path`/`path_index` driven, the exact `ArmyLayer` dashed-line/wraparound approach ported over)*
- Distinguish planned, moving, blocked, retreating and transport routes. *(`moving`/`retreat`/`transport` done; `planned`/`blocked` are a player-issued move-preview concept with no map-click "order a fleet" flow yet to drive it - the API is shaped so that flow can add it later without changing this contract, same as `ArmyLayer`'s own preview API)*
- Show mission target zones or ports where a mission has targets. *(done for the `blockade` mission's first target - a ring marker shown independently of whether a route exists)*
- Remove stale route geometry immediately after cancellation, peace, destruction, merge or load. *(done - `fleet_marker_lifecycle_test.gd` drives a real cancellation, peace teardown and save/load restoration/removal in both directions; the organisation HUD test proves a merged-away selection retargets without retaining removed-source geometry; destruction remains covered by the original smoke)*
- Keep route drawing derived; it must not become save authority. *(true by construction - `_refresh_route()` reads `fleet_registry` fresh every call, no new persisted field)*

### FL1.4 Battle and blockade presentation - automatable scope complete

- Show one naval-battle marker per authoritative active battle. *(done in earlier N-pillar work - `ConflictMarkerLayer`'s `naval_battle` marker family)*
- Expose participants, round, morale, broad losses and retreat availability through selection or tooltip. *(done in earlier N-pillar work - `NavalHUD`'s battle panel)*
- Indicate blockaded ports and affected coasts with colour-independent cues. *(done by contract: the persistent port icon is the always-on colour-independent cue, while the existing on-demand blockade overlay colours every affected coastal land province. A second independent coastline-segment geometry authority is intentionally not introduced)*
- Show blockade strength/tier and attacker when known. *(done - deterministic contributor and primary-attacker queries reuse the authoritative eligibility/target/effective-power rules; marker records carry structured attribution and the HUD resolves country names and effective power)*
- Remove battle and blockade presentation on terminal events, peace, annexation and load reconciliation. *(battle presentation already proven; blockade marker removal proven for the blockading fleet being removed - peace/annexation/load-reconciliation specifically not yet exercised by a dedicated test)*

### FL1.5 Interaction and refresh - complete

*See [FL1_5_INTERACTION_AND_REFRESH.md](evidence/FL1_5_INTERACTION_AND_REFRESH.md). The three bullets already proven in earlier packets (fleet-click forward sync, cluster-order determinism, battle-click summary) are unchanged. The two named-open edge cases are now closed: `NavalHUD` gained a `fleet_marker_layer` reference so every HUD-driven selection change (dropdown pick, or the panel's own fallback reselection when the previous fleet no longer exists) pushes back out to the map, not just map-click-to-HUD; and `fleet_scuttled` - emitted by the panel's own Scuttle button but previously unheard by any UI listener - now refreshes both the map marker batch and the panel itself, exactly like the pre-existing `fleet_destroyed` handling already did for combat losses.*

- ~~Clicking a fleet marker selects its exact fleet ID and opens the naval HUD.~~ *(done in an earlier packet - [FL1_FLEET_MARKER_FIRST_SLICE.md](evidence/FL1_FLEET_MARKER_FIRST_SLICE.md))*
- ~~Clicking a cluster never depends on dictionary iteration order.~~ *(done in an earlier packet - precomputed sort key + native Array sort)*
- ~~Clicking a battle marker opens the authoritative battle summary.~~ *(done in an earlier packet - `ConflictMarkerLayer` click-through to `NavalHUD.select_battle()`)*
- ~~Map selection and HUD selection remain synchronized.~~ *(done - [FL1_5_INTERACTION_AND_REFRESH.md](evidence/FL1_5_INTERACTION_AND_REFRESH.md); the missing reverse-sync direction is now real)*
- ~~Event-driven refresh covers movement, mission, membership, battle, blockade, ownership, save/load and country removal.~~ *(done - the one missing event, `fleet_scuttled`, is now connected in both the map layer and the panel)*

## Automated verification

- Marker view models are stable for identical authoritative state.
- Multiple fleets in one zone cluster in stable owner/fleet-ID order.
- Selection resolves the intended fleet or battle after clustering.
- Routes match authoritative path and status before and after save/load.
- Destroyed, merged, annexed and peace-released entities leave no markers.
- Marker creation remains bounded in a dense-zone fixture.
- A headless presentation test verifies query-to-view-model behavior.
- A rendered smoke test verifies real scene wiring and click selection.

## Manual verification

- Inspect port, coastal sea and open-ocean anchors at supported zoom levels.
- Confirm markers do not hide important coastlines or province selection.
- Confirm owner, danger, battle and blockade remain understandable without colour.
- Confirm no flicker or selection loss during a complete Channel operation.

## Exit evidence

- Focused marker/route/battle/blockade test output.
- Rendered screenshots or test capture at 1366x768 and 1920x1080.
- Marker count, update time and frame-time capture for the dense-zone fixture.
- Save/load and terminal-cleanup confirmation.

Evidence: [FL1_FLEET_MARKER_FIRST_SLICE.md](evidence/FL1_FLEET_MARKER_FIRST_SLICE.md), [FL1_5_INTERACTION_AND_REFRESH.md](evidence/FL1_5_INTERACTION_AND_REFRESH.md), [FL1_AUTOMATABLE_CLOSURE.md](evidence/FL1_AUTOMATABLE_CLOSURE.md)

## Exit gate

FL1 is complete when a player can discover, select and follow every important fleet, route, battle and blockade in the Channel scenario, presentation never becomes state authority, stale markers are impossible in tested lifecycle paths, and rendered performance stays within the approved budget.
