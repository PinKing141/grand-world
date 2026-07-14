# MV-0 Zoom and Layer Matrix

## Status

**State:** Proposed for Visual Greenlight. Thresholds are provisional until motion captures and UX review.

The current camera supports approximately `0.8` to `13.0` world-height units with a `3.5` reference height. This proposal gives every map layer the same named zoom policy instead of scattered magic numbers.

## Proposed Zoom Bands

| Band | Provisional camera height | Primary player question |
|---|---:|---|
| Strategic | `6.5–13.0` | Who controls major regions and where are the great powers/conflicts? |
| Regional | `2.0–6.5` | Which countries, provinces, armies, routes, and terrain affect my next decision? |
| Close | `0.8–2.0` | What is in this province and what can I interact with? |

All band boundaries require entry/exit hysteresis. Effects may blend across a transition range; they should not toggle every time camera height crosses one exact value.

## Default Political-Mode Matrix

| Layer | Strategic | Regional | Close |
|---|---|---|---|
| Country fill | Primary, muted terrain contribution | Primary with more terrain | Primary but province interaction may dominate |
| Sovereign border | Strong, stable 1.5–2.5 px target | Strong 2–3 px | Strong but must not consume small provinces |
| Subject/special border | Simplified/patterned if readable | Visible | Visible with relationship detail |
| Province border | Hidden or extremely faint | Restrained | Clear but thinner than sovereign border |
| Coast | Clear silhouette, no glow | Clear with shallow-water support | Detailed but selection-aligned |
| Terrain macro | Low contrast | Medium | Medium/high |
| Terrain micro/normal | Off or minimal | Controlled | Visible within shimmer budget |
| Rivers | Only world-class major rivers | Major and secondary | Full approved gameplay set |
| Country labels | Major/high-priority names | Normal country set | Fade/yield to local labels and markers |
| Province/regional labels | Off | Important-only by mode | Visible according to mode/settings |
| Capitals | Major capitals only | Capitals and important centres | All required capital/settlement tiers |
| Armies/navies | Aggregated/important | Normal strategic markers | Detailed selected/nearby markers |
| Battles/sieges | Always important and clustered | Visible | Visible with progress detail |
| Vegetation/settlements | Off | Sparse/batched | Approved density tier |
| Water motion | Very slow/low contrast | Standard restrained | Standard; no high-frequency shimmer |
| Atmosphere | Minimal | Optional | Optional and subordinate |

## Terrain-Mode Differences

- Political fill becomes absent or a very restrained interaction tint.
- Country borders reduce; coast, rivers, relief, and terrain materials become primary.
- Country labels reduce or become player-configurable.
- Political army rectangles/markers do not remain simply because their system is always visible; terrain mode receives an explicit marker policy.
- Selected province/country still has a clear accessible treatment.

## Debug/Province-ID Differences

- Terrain, water decoration, labels, markers, atmosphere, and post effects default off.
- Exact province IDs/colours and boundaries are primary.
- Selection and hover remain available.
- Debug information must not be contaminated by filtered categorical data.

## Label Priority Proposal

1. Selected/player country.
2. Active war participant or urgent state.
3. Major country by reviewed rank and on-screen territory.
4. Normal country by on-screen fit.
5. Microstate/one-province full name at close zoom.

Priority never grants an overlord permission to place its country label over independently owned subject/appanage territory in the default political ownership view.

## Marker Density Proposal

- Strategic: cluster armies/navies by country/region; show urgent battles.
- Regional: show individual relevant armies with screen-space clustering.
- Close: show individual stacks, selected paths, ports, forts, and settlements within caps.
- Decorative markers cull before labels or gameplay markers.

## Transition Acceptance

- No visible allocation hitch when crossing a band.
- No repeated pop/flicker during a small zoom oscillation.
- Country labels remain within screen-pixel min/max size.
- Border line weights remain screen-stable.
- Reduced-motion mode can remove fades without losing correct visibility.
- The same camera state produces deterministic layer selection.

