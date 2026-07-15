# Release Screens and Future Windows

These interfaces are required by the Phase 9 release roadmap even where no production scene exists yet. They must be planned before the art system is locked so shared components support them.

## Nation selection

### Purpose

Let a new or returning player understand the world state, compare countries, choose a suitable start, and begin without requiring prior tag knowledge.

### Layout

- Interactive world/regional map.
- Date/scenario identity.
- Selected-country card with full name, emblem, ruler/government, capital, religion/culture, size/strength summary, difficulty, and short historical context.
- Recommended-country carousel or filters.
- Play/observer/back actions.
- Search and map navigation.
- Data/provenance warning only where content is intentionally unfinished in development builds.

### Required states

- Playable country, non-playable/wasteland, observer.
- Recommended beginner, intermediate, difficult, and unsupported/unfinished.
- No country selected.
- Country missing optional portrait/history but still playable.
- Invalid scenario content with a clear recovery path.

Do not expose only internal tags. Tags may be available in a developer tooltip.

## Outliner

### Categories

- Armies and current orders.
- Battles and sieges.
- Construction and recruitment.
- Diplomats/offers/relations where systems support them.
- Subjects and integration.
- Rebels/unrest alerts.
- Pinned provinces, countries, characters, and objectives.

### Behaviour

- Categories are collapsible and individually configurable.
- Rows focus/select their entity and expose a context action where safe.
- Repeated units aggregate or virtualise when lists grow.
- User ordering and collapse state save with preferences.
- Critical state uses icon/shape/text as well as colour.
- The panel collapses without losing unread urgent alerts.

## Full ledger

The ledger is a comparison and analysis tool, not just the economy summary.

Potential pages:

- Country rankings and demographics.
- Economy/income/debt.
- Military/manpower/armies/losses.
- Provinces/development/trade goods/buildings.
- Diplomacy/relations/wars/truces/subjects.
- Characters/dynasties/succession where appropriate.
- History and major events.

Requirements:

- Sortable columns with visible direction.
- Search/filter, category navigation, sticky headers.
- Tabular figures, aligned units, clear unavailable/unknown data.
- Row focus opens the relevant entity.
- Virtualised or paged content at global scale.
- Keyboard navigation and screen-reader-ready semantic labels where the platform layer permits.
- Export/copy is optional and should not delay the readable in-game version.

## Notification feed and message settings

### Notification feed

- Chronological history with category, severity, date, involved entities, and action.
- Filters for unread, pinned, category, country, and date range where useful.
- Read/unread state must not depend only on colour.
- Clicking focuses the source or opens the relevant window.
- Retention and aggregation rules prevent unlimited UI growth.

### Message settings

For each message category, allow approved combinations such as:

- Alert icon.
- Toast.
- Feed entry.
- Modal popup.
- Pause game.
- Sound.
- Disabled where safe.

Provide sensible presets: recommended, minimal, verbose, and reset to defaults. Dangerous loss of critical information should require confirmation.

## Main menu

- Continue latest compatible save.
- New campaign.
- Load.
- Settings.
- Credits/licences.
- Quit.
- Build version and compatibility information.

The menu must remain readable over artwork and work without waiting for a full campaign map to initialise. Do not put critical text into the background illustration.

## Pause menu

- Resume.
- Save.
- Load.
- Settings.
- Help/controls.
- Return to main menu with unsaved-progress confirmation.
- Quit with unsaved-progress confirmation.

The paused state must be unmistakable. The pause menu should not destroy the current selection/window state when closed.

## Settings

### Categories

- Display: resolution, display mode, monitor, VSync/frame cap, graphics quality.
- Interface: UI scale, tooltip delay, font/dense-table size where supported, edge scrolling, date/number format.
- Accessibility: colour-vision preset, high contrast, reduced motion, flashing reduction, larger targets/text, map pattern assistance.
- Audio: master, music, ambience, UI, notifications.
- Controls: remapping, mouse sensitivity/drag settings, zoom direction, edge-scroll settings, reset.
- Gameplay/message settings: autosave interval, pause rules, notification preset.

Requirements:

- Apply/revert flow for display changes with a countdown.
- Explain changes that require restart.
- Defaults and per-section reset.
- Unsaved-change warning.
- Scroll and focus behaviour at high UI scale.
- Settings stored separately from campaign saves where appropriate.

## Save/load browser

Each save row/card shows:

- Country name and emblem.
- Campaign date and real timestamp.
- Save type: manual, autosave, quicksave.
- Game version/schema and compatibility state.
- Optional screenshot/thumbnail created by the game.
- Ironman/modified/debug status only if those modes exist.
- File size and corruption/error state where useful.

Actions:

- Load, save/overwrite, rename where supported, delete with confirmation.
- Sort/filter.
- Explain incompatible, missing-content, or corrupted saves and offer safe recovery/backup guidance.
- Never silently overwrite a manual save.

## Loading screen

- Stable project branding and artwork with provenance.
- Progress stages only when they represent real work.
- Helpful controls or historical/context text that remains optional.
- Error state with log/support path and return action.
- No fake progress that reaches 100% while substantial work continues without explanation.

## Tutorial, help, glossary, and recovery

### First-session flow

- Select a recommended country.
- Learn pause/speed and camera controls.
- Select a province and read its economy.
- Construct/recruit.
- Open diplomacy and understand relations.
- Move an army and understand war/peace.

Use short contextual steps and let the player skip, revisit, or disable them. Highlight real controls, not screenshots that become outdated.

### Glossary/help

- Searchable mechanics and terms.
- Deep links from tooltips.
- Current controls including remapped bindings.
- Recovery guidance for blocked actions, invalid content, save compatibility, and graphics problems.

## Confirmation and error dialogs

Create one shared modal family for:

- Destructive confirmation.
- Irreversible political/diplomatic action.
- Unsaved progress.
- Invalid/failed command with recovery.
- Save incompatibility or corruption.
- Network is out of scope unless multiplayer is introduced.

Dialog buttons use explicit verbs: `Delete Save`, `Declare War`, `Return Without Saving`, not ambiguous `Yes` and `No`. Default keyboard focus must be safe.

## Credits, attributions, and licences

The release shell needs a readable credits/licence interface or bundled documents that include:

- Team and contributor credits.
- Fonts, icons, textures, paintings, portraits, audio, and software licences.
- Required CC-BY attribution.
- Open-source licence text or links as required.
- Version/build information.

## Future-safe windows

The component system should be capable of supporting later 1700–1821 content without building them now:

- Naval/fleet panel and naval battle.
- Trade routes/markets.
- Colonisation and exploration.
- More advanced estates/parliament/internal politics.
- Extended history timeline and end-game summary.

These are not permission to expand the current 1.0 scope. They are compatibility considerations for frames, tabs, tables, and navigation.

