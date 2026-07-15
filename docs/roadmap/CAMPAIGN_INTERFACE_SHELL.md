# Campaign Interface Shell

## Purpose

The campaign now uses one coherent interface hierarchy after the player chooses a country. It follows the information architecture common to early-modern grand-strategy games while using original project styling, fonts, code and assets.

The shell is presentation-only. It reads the authoritative campaign state and opens the existing Phase 4–8 windows; it does not duplicate or replace simulation systems.

## Implemented layout

### Top-left: country command block

- Approved historical country crest when one exists in `assets/marker_art/source_flags/`.
- Neutral `Crest pending` state when the historical-art audit has no approved asset. No invented heraldry is displayed.
- Full country display name; internal three-letter tags remain hidden from the player-facing shell.
- Treasury, monthly balance, manpower, stability, technology and field-army summaries.
- Contextual alerts for war, deficit, debt, manpower, stability, events and rebel activity.
- Government, Economy, Military, Diplomacy, Religion and Court navigation.

### Top-right: time controls

- Full current date.
- Pause/resume.
- Five simulation speeds.
- Quick save and quick load.

### Right side: strategic outliner

- Player armies with location, strength and status.
- Click-to-focus army entries.
- Active wars and war score.
- Building and recruitment queues with province and completion date.
- Subject states, subject type and liberty desire.
- Direct access to campaign plans and deterministic-AI review.
- Collapsible content.

### Bottom-right: navigation

- World minimap using the authored terrain map rather than a second rendered viewport.
- Current-camera coverage rectangle.
- Click-to-pan using the canonical `56.32 × 20.48` world bounds.
- Political, terrain and province-ID map modes.
- Search access for countries and provinces.

### Left side: selected province

- Province details dock beneath the country command block.
- Content is scrollable at compact resolutions instead of escaping the viewport.
- The existing controller, terrain, culture, religion, trade-good and country-window actions remain functional.

## Consolidation rules

While the shell is active, it hides the old overlapping resource strip, clock, map-mode strip, permanent control-hint ribbon and floating Campaign/AI button. Existing economy, province economy, army, diplomacy, court, country-state and AI windows remain available through the shell and receive the shared dark-navy and bronze panel treatment.

During the country-selection screen the campaign shell is hidden. It becomes active immediately after Play commits the selected country.

## Performance decisions

- The minimap reuses `terrain_base_map.png`; it does not render the 3D world a second time.
- Camera coverage redraws at 10 Hz.
- Strategic summaries refresh at 2.5 Hz and only while the shell is visible.
- Player-only outliner filtering prevents the global army registry from producing hundreds of controls.
- Legacy UI elements are hidden instead of kept visible underneath the shell.

## Verification

- `tests/campaign_interface_shell_smoke.gd`
  - Country-selection handoff.
  - Full country names.
  - Replacement of legacy chrome.
  - Outliner population.
  - Canonical minimap coordinate conversion.
  - Map-mode navigation.
  - Left-side province docking.
- `tests/ui_layout_smoke.gd`
  - 1700×960 and 1152×648 containment.
- GPU preview: `docs/test_reports/campaign_interface_shell_preview.png`.
- Verified with Godot 4.7 Forward+ on AMD Radeon 610M.

## Remaining art-production work

The functional interface is complete, but final presentation still requires project-owned production art:

1. Replace temporary flat StyleBoxes with a nine-sliced UI atlas covering normal, hover, pressed, selected, disabled and alert states.
2. Supply approved historical crests for countries still listed as research-required in the heraldry audit.
3. Create original resource, alert, tab, map-mode and speed-control icons.
4. Add restrained click, alert, panel-open and time-speed audio cues.
5. Perform hands-on readability and navigation testing at 100%, 125%, 150% and 200% UI scale.
6. Complete colour-vision-deficiency review with players rather than relying only on simulated filters.

## Reference boundary

The layout is informed by the functional hierarchy described by the official *Europa Universalis IV* manual and the community interface guide. Paradox artwork, logos, textures and proprietary UI assets are not included. Final art must remain recognizably original to Grand World.

- Official manual: <https://cdn.akamai.steamstatic.com/steam/apps/236850/manuals/EuropaUniversalisIV_Manual.pdf>
- Community interface guide supplied for research: <https://eu4.paradoxwikis.com/User_interface>

