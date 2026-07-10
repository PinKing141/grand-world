# Product Vision and Pillars

## Product Statement

Grand World is a pauseable real-time historical grand-strategy simulation beginning on 11 November 1444. The player initially controls a country, guides it through war, diplomacy, economic development, religious and political change, and eventually interacts with rulers, dynasties, titles, succession, and vassal relationships.

The first campaign scope ends on 1 January 1700. The architecture must permit a later extension to 3 January 1821 without requiring a rewrite of the simulation clock, save format, country model, technology system, event framework, or content pipeline.

## Player Fantasy

The player should feel that they are:

- Directing a historical realm rather than moving pieces on a static map.
- Responding to a world that continues to evolve when they do nothing.
- Making understandable decisions with long-term consequences.
- Managing both institutions and people.
- Turning political intent into military, diplomatic, and economic action.
- Watching borders, alliances, dynasties, religions, and centres of power change over centuries.

## Core Pillars

### 1. A Living, Legible World

The simulation must be deep enough to create surprising outcomes but clear enough that the player can understand why they happened.

Every major value should have an explanation:

- Why income increased or decreased.
- Why an alliance was accepted or rejected.
- Why an army lost a battle.
- Why a province is rebellious.
- Why a character supports or opposes the ruler.
- Why AI countries chose a war, peace, alliance, or reform.

### 2. Meaningful Strategic Trade-offs

Strong choices should involve competing benefits rather than obvious upgrades.

Examples:

- Centralisation increases state power but angers nobles.
- High taxation funds armies but increases unrest.
- Rapid conquest creates strategic depth but produces overextension.
- Dynastic marriages improve diplomacy but create foreign claims.
- Professional armies improve reliability but increase permanent expenses.

### 3. History as a Starting Point, Not a Script

The campaign begins from a researched 1444 scenario, but systems determine what happens next.

Historical events may provide pressure and context, but the simulation must allow:

- Countries to survive or collapse differently.
- Dynasties to produce different heirs.
- Wars to have different outcomes.
- Religions and cultures to spread differently.
- New alliances, rivalries, and powers to emerge.

### 4. Country First, Characters with Consequences

The first playable layer is country control. The character layer is added after the country simulation is stable.

Characters should influence:

- Succession.
- Legitimacy.
- Diplomacy.
- Vassal loyalty.
- Military leadership.
- Administration.
- Claims.
- Internal factions.

Characters should enrich the state simulation rather than replace it.

### 5. Data-Driven and Mod-Friendly

Countries, provinces, units, buildings, technologies, governments, religions, cultures, events, decisions, characters, and titles should be defined through validated content data.

Stable IDs and versioned schemas are mandatory. Core gameplay rules may be implemented in code, but content volume should not require code changes.

### 6. Performance Is a Feature

The map, UI, and simulation must remain responsive at global scale and maximum speed. Systems that work only in a five-country test are incomplete until they satisfy their declared scale budget.

## Initial Audience and Platform Assumptions

- Primary platform: Windows PC.
- Primary input: mouse and keyboard.
- Initial mode: single-player.
- Presentation: 2D political map rendered in a 3D scene.
- Simulation model: discrete daily ticks with pause and multiple speeds.
- Initial language: English, with localisation-ready content formats.

These assumptions can be revisited at a formal milestone gate, not changed silently during implementation.

## Confirmed Historical Scope

### Initial Campaign

- Start: 11 November 1444.
- Initial endpoint: 1 January 1700.
- Calendar granularity: daily.
- First development region: a small representative region, recommended Iberia.
- Full-map target: after the regional vertical slice proves the gameplay loop.

### Deferred Extension

- 1700 to 1821.
- Enlightenment and revolutionary content.
- Nationalism.
- Expanded constitutional politics.
- Industrialisation foundations.
- Mass conscription.
- Independence movements.

## Non-Goals for the First Playable

- Full 1444–1821 content.
- Multiplayer.
- Every historical country active.
- Complete naval warfare.
- Detailed global trade simulation.
- Individual civilian simulation.
- Full dynasty and succession depth.
- Complete mod scripting.
- Cinematic presentation.
- Final art, audio, localisation, or balance.

## Non-Goals for the Vertical Slice

- The complete world.
- Every government, religion, culture, technology, building, and unit.
- Final historical database.
- Final late-game balance.
- The 1700–1821 extension.
- Feature parity with any existing commercial grand-strategy game.

The vertical slice proves product quality and pipeline viability. It is not a miniature content-complete game.

