# FL6 - Rendered and Accessibility Acceptance

**Status:** Validation. The automatable slice is complete and tested - see [FL6_AUTOMATABLE_ACCEPTANCE.md](evidence/FL6_AUTOMATABLE_ACCEPTANCE.md), including a real off-canvas rendering bug found and fixed (the naval panel's content had grown taller than the design canvas and needed a `ScrollContainer`). Everything requiring an actual human at real hardware - the acceptance walkthrough, keyboard-only/focus/Escape UX (a whole-game gap, not naval-specific), colour-vision-deficient review, and GPU/renderer verification - remains not started; see that document's "What FL6 needs next" section.
**Goal:** Prove that the complete naval interface is readable, operable and stable on supported displays and hardware.

## Entry conditions

- FL1 map presentation is functionally complete.
- FL2 fleet management is functionally complete.
- Required icons, tooltips, rejection reasons and focus targets exist.

## Scope

### FL6.1 Resolution and UI scale

*Partially automated - see [FL6_AUTOMATABLE_ACCEPTANCE.md](evidence/FL6_AUTOMATABLE_ACCEPTANCE.md). `tests/ui_layout_smoke.gd` covers the naval panel at 1366x768/1920x1080 plus two other breakpoints headlessly (a real off-canvas bug was found and fixed there); 16:10/ultrawide layouts and UI-scale values still need a human on real hardware, and no UI-scale feature exists in the game yet to test.*

- Test 1366x768, 1920x1080, supported 16:10 and approved ultrawide layouts.
- Test every supported UI-scale value.
- Check naval HUD, fleet/cluster lists, modals, battle report, transport workflow, alerts and tooltips.
- Ensure confirmation and rejection text is never clipped or hidden.

### FL6.2 Input and focus

*Partially automated - see [FL6_AUTOMATABLE_ACCEPTANCE.md](evidence/FL6_AUTOMATABLE_ACCEPTANCE.md). Mouse-only workflows and rapid-click/key-repeat duplicate-command safety are proven headlessly (`tests/naval_hud_duplicate_action_safety_test.gd`). Keyboard-only navigation, focus order, and Escape-modal handling do not exist yet for naval_hud or any other gameplay HUD panel in the game - a whole-game input-model gap, not naval-specific, deliberately not patched unilaterally here.*

- Complete primary naval workflows using mouse only.
- Complete the same workflows using keyboard only.
- Define stable focus order and visible focus state.
- Ensure Escape closes only the top modal and never issues or cancels an order.
- Verify double-click, rapid-click and key-repeat cannot duplicate commands.

### FL6.3 Colour, text and motion

*Not automated - see [FL6_AUTOMATABLE_ACCEPTANCE.md](evidence/FL6_AUTOMATABLE_ACCEPTANCE.md). The naval HUD panel itself never encodes state through colour alone (true by construction - it never uses colour at all, only text), but the map's colour-coded elements and reduced-motion/comprehension checks need real human colour-vision review this packet cannot perform.*

- Pair colour with icons, shapes, labels or percentages for owner, hostility, danger, supply, blockade and battle side.
- Check contrast and common colour-vision profiles.
- Use concise first-line tooltips with optional detail.
- Verify reduced-motion behavior where presentation animation exists.
- Confirm battle and blockade outcomes remain understandable without animation.

### FL6.4 Hardware and renderer

*Not automated - see [FL6_AUTOMATABLE_ACCEPTANCE.md](evidence/FL6_AUTOMATABLE_ACCEPTANCE.md). Real hardware/GPU/renderer verification cannot be done headlessly. Checksum determinism has strong indirect headless evidence (frame-rate-independence, full `main.tscn` scene graphs loading correctly under every naval integration test) but not the specific "real windowed run vs. headless run" comparison this bullet asks for.*

- Run on the current low-end Intel UHD 600-class laptop.
- Run on the project's target/reference Windows hardware when available.
- Exercise the approved Godot renderer paths.
- Use RenderDoc only when investigating a rendering defect or measuring a frame capture; it is not required for logic validation.
- Confirm rendered and headless authoritative checksums remain equal.

## Acceptance walkthrough

The reviewer must build/select a fleet, change mission, inspect a route, embark an army, observe interception and combat, request retreat where legal, disembark, inspect blockade effects, repair, and save/load without using debug commands.

## Evidence record

- Date, Godot version, build, device, GPU/driver, renderer, resolution and UI scale.
- Pass/fail per workflow and accessibility criterion.
- Screenshot or capture references for failures and final accepted layouts.
- Frame-time/device-loss observations.
- Reviewer name and unresolved severity.

## Exit gate

FL6 is complete when the acceptance walkthrough passes on required layouts and hardware, keyboard and mouse workflows are safe, important information does not rely on colour alone, and no P0/P1 usability or rendering issue remains.
