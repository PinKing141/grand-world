# Grand Strategy Development Plan

## Vision

The goal is to turn the existing political map demo into a pauseable real-time world simulation similar in structure to games such as *Europa Universalis IV* and *Crusader Kings II*.

## Confirmed Campaign Scope

- Historical start date: 11 November 1444.
- Initial campaign endpoint: 1 January 1700.
- Future extension endpoint: 3 January 1821.
- Initial player model: country-first.
- Planned later layer: rulers, characters, dynasties, titles, succession, and vassals.
- Recommended first vertical-slice region: Iberia.

The 1444–1700 campaign is the active product scope. The 1700–1821 period is a future expansion and must not pull era-specific mechanics or content into the initial production plan.

This document is the detailed architecture reference. The gated production roadmap and smaller phase plans are located in [docs/roadmap](docs/roadmap/README.md).

The existing project is the map presentation foundation. It already provides:

- A high-resolution province map.
- Province IDs, names, colours, and ownership.
- Country tags, names, and political colours.
- Mouse-based province and country selection.
- GPU-generated political borders.
- Dynamic province recolouring.
- EU4-style country and province data importing.
- An editor inspector for changing colours and ownership.

The project does not yet contain the actual grand-strategy simulation: time, economy, armies, wars, diplomacy, AI, characters, saves, events, technology, or gameplay UI. These systems must be constructed around the existing map.

The recommended development order is:

1. Build an EU4-style country simulation first.
2. Implement economy, diplomacy, armies, warfare, AI, time, and saving.
3. Create a small but complete playable regional scenario.
4. Expand the simulation to the global map.
5. Add CK2-style characters, dynasties, titles, succession, and vassals.
6. Add deeper systems such as trade, religion, culture, colonisation, espionage, and naval warfare.

## 1. Decide What the Player Controls

CK2 and EU4 appear similar on the map, but their player identities are fundamentally different.

| Style | Player controls | Game continues through |
|---|---|---|
| EU4 | A country or state | Monarch changes, revolutions, and government changes |
| CK2 | A character and dynasty | Succession to an eligible heir |
| Hybrid | A dynasty controlling a political realm | Characters, titles, governments, and borders changing |

Examples:

- In an EU4-style game, England remains the player's entity when the king dies.
- In a CK2-style game, the current character dies and the player continues as an heir.
- In a hybrid, England is a political object while its ruler and ruling dynasty are separate objects.

Start with the EU4 model because the existing data naturally supports it:

~~~text
Province → owned by Country
Country → controlled by Player or AI
~~~

Later, the model can become:

~~~text
Province → belongs to Title or Realm
Title → held by Character
Character → belongs to Dynasty
Realm → governed by Character and government
~~~

Do not permanently connect a province directly to a character. Legal ownership, military control, titles, realms, and characters should remain separate concepts.

## 2. Overall Architecture

The simulation should flow through clear layers:

~~~text
Scenario definitions
        ↓
Runtime WorldState
        ↓
Commands from player and AI
        ↓
Simulation systems process each game day
        ↓
WorldState changes
        ↓
Events and notifications
        ↓
Map and UI display the changes
~~~

Keep these responsibilities separate:

| Layer | Responsibility |
|---|---|
| Definitions | Permanent facts loaded from game content |
| Runtime state | Facts that change during a campaign |
| Simulation | Rules that modify runtime state |
| Presentation | Map, interface, sound, and animation |
| Commands | Validated requests from the player or AI |

For example:

~~~text
CountryDefinition
- Name: England
- Tag: ENG
- Default colour: red
- Historical capital: London

CountryState
- Treasury: 356
- Current capital: York
- Stability: -1
- Current wars: [War 17]
- Current ruler: Character 284
~~~

Definitions should not be modified during a campaign. Runtime state is what gets written to a save game.

## 3. Avoid Creating a Node for Every Entity

A complete campaign may contain:

- Approximately 5,000 provinces.
- Hundreds of active countries.
- Thousands of characters.
- Hundreds or thousands of armies.
- Titles, claims, treaties, wars, events, and modifiers.

Do not create a Godot Node for every province, character, title, or relationship. That would add unnecessary scene-tree, signal, and processing overhead.

Store simulation entities as plain data indexed by stable integer IDs:

~~~gdscript
var province_states: Array[ProvinceState]
var country_states: Array[CountryState]
var character_states: Array[CharacterState]
var army_states: Dictionary[int, ArmyState]
var wars: Dictionary[int, WarState]
~~~

Godot nodes should represent visible or coordinating objects:

~~~text
GameRoot
├── Simulation
├── MapView
├── UserInterface
├── AudioManager
└── Visible army markers
~~~

The map does not need thousands of province nodes. The existing lookup texture already handles province identification efficiently.

## 4. Recommended Project Structure

The project can gradually be reorganised into this structure:

~~~text
game/
├── core/
│   ├── game_session.gd
│   ├── game_clock.gd
│   ├── simulation_scheduler.gd
│   ├── command_bus.gd
│   ├── event_bus.gd
│   ├── random_manager.gd
│   └── game_rules.gd
│
├── definitions/
│   ├── province_definition.gd
│   ├── country_definition.gd
│   ├── character_definition.gd
│   ├── title_definition.gd
│   ├── building_definition.gd
│   ├── unit_definition.gd
│   └── modifier_definition.gd
│
├── state/
│   ├── world_state.gd
│   ├── province_state.gd
│   ├── country_state.gd
│   ├── character_state.gd
│   ├── title_state.gd
│   ├── army_state.gd
│   ├── war_state.gd
│   └── relation_state.gd
│
├── systems/
│   ├── economy_system.gd
│   ├── population_system.gd
│   ├── movement_system.gd
│   ├── combat_system.gd
│   ├── siege_system.gd
│   ├── diplomacy_system.gd
│   ├── technology_system.gd
│   ├── character_system.gd
│   ├── succession_system.gd
│   ├── event_system.gd
│   └── ai_system.gd
│
├── commands/
│   ├── move_army_command.gd
│   ├── declare_war_command.gd
│   ├── recruit_unit_command.gd
│   ├── construct_building_command.gd
│   └── propose_peace_command.gd
│
├── map/
│   ├── map_controller.gd
│   ├── map_mode_manager.gd
│   ├── map_highlighter.gd
│   ├── adjacency_database.gd
│   └── map_labels.gd
│
├── ai/
│   ├── country_ai.gd
│   ├── military_ai.gd
│   ├── diplomacy_ai.gd
│   └── economic_ai.gd
│
├── save/
│   ├── save_manager.gd
│   ├── save_migrations.gd
│   └── world_serializer.gd
│
└── ui/
    ├── hud/
    ├── province_panel/
    ├── country_panel/
    ├── diplomacy/
    ├── economy/
    ├── military/
    └── characters/
~~~

This is a target structure. Build it incrementally rather than creating every file before it is needed.

## 5. Build a Deterministic Game Clock

A grand-strategy game is real-time from the player's perspective, but internally it is a sequence of discrete simulation ticks.

Use one game day as the fundamental simulation tick:

~~~text
Visual rendering: 60 or more frames per second
Simulation: one or more game days when sufficient real time passes
~~~

The player should have:

- Pause.
- Speed 1.
- Speed 2.
- Speed 3.
- Speed 4.
- Speed 5.
- An optional maximum-speed mode.

Internally, store the date as an integer number of elapsed days. Convert it to a calendar date for the interface.

A simplified clock:

~~~gdscript
class_name GameClock
extends Node

signal day_started(day: int)
signal month_started(year: int, month: int)
signal year_started(year: int)

var paused := true
var speed_index := 1
var accumulated_days := 0.0
var current_day := 0

const DAYS_PER_SECOND := [
    0.0,
    1.0,
    3.0,
    8.0,
    20.0,
    60.0,
]

const MAX_TICKS_PER_FRAME := 8

func _process(delta: float) -> void:
    if paused:
        return

    accumulated_days += delta * DAYS_PER_SECOND[speed_index]

    var ticks_processed := 0

    while accumulated_days >= 1.0:
        if ticks_processed >= MAX_TICKS_PER_FRAME:
            break

        process_next_day()
        accumulated_days -= 1.0
        ticks_processed += 1

func process_next_day() -> void:
    current_day += 1
    day_started.emit(current_day)
~~~

The tick cap prevents high simulation speeds from freezing the visual interface.

For deterministic behaviour:

- Always process systems in the same order.
- Iterate simulation entities in stable ID order.
- Use a seeded random-number generator.
- Never generate simulation randomness directly from UI scripts.
- Never make simulation results depend on frame rate.
- Avoid using floating-point time as the campaign date.
- Process player and AI actions through the same command system.

## 6. Simulation Scheduler

Not every system needs to run every game day.

| Frequency | Appropriate systems |
|---|---|
| Daily | Movement, battles, sieges, occupations, and attrition |
| Weekly | Military planning and diplomatic reconsideration |
| Monthly | Income, expenses, manpower, unrest, and construction |
| Quarterly | Trade, migration, and long-term strategic AI |
| Yearly | Population growth, cultural changes, and major statistics |

A deterministic daily order might be:

~~~text
1. Apply queued player and AI commands
2. Advance army movement
3. Start new battles
4. Process existing battles
5. Process retreats
6. Process sieges and occupations
7. Apply attrition and supply
8. Process monthly systems if the month changed
9. Process yearly systems if the year changed
10. Run scheduled AI
11. Trigger events
12. Generate notifications
13. Send visual changes to the map and UI
~~~

System order matters. For example, armies should move before the game checks whether a new battle begins.

## 7. Command System

The UI should not directly modify the simulation state.

Do not let a diplomacy button directly do this:

~~~gdscript
target_country.is_at_war = true
~~~

It should submit a command:

~~~gdscript
var command := DeclareWarCommand.new()
command.attacker_id = player_country_id
command.defender_id = selected_country_id
command.war_goal_id = selected_war_goal

CommandBus.submit(command)
~~~

The command validates the request:

~~~gdscript
func validate(world: WorldState) -> bool:
    if attacker_id == defender_id:
        return false

    if world.are_at_war(attacker_id, defender_id):
        return false

    if world.has_active_truce(attacker_id, defender_id):
        return false

    if not world.country_has_valid_war_goal(
        attacker_id,
        defender_id,
        war_goal_id
    ):
        return false

    return true
~~~

This produces:

- One rules path for players and AI.
- Easier automated testing.
- Better save compatibility.
- Consistent error messages.
- A potential command replay system.
- A possible route to multiplayer later.

Useful initial commands:

- MoveArmyCommand.
- RecruitUnitCommand.
- DisbandUnitCommand.
- ConstructBuildingCommand.
- CancelConstructionCommand.
- DeclareWarCommand.
- JoinWarCommand.
- ProposePeaceCommand.
- AcceptPeaceCommand.
- FormAllianceCommand.
- BreakAllianceCommand.
- ChangeProvinceOwnerCommand.

## 8. Province Database

The existing province system primarily knows:

- Province colour.
- Province ID.
- Province name.
- Country owner.

A grand-strategy province needs static definition data and dynamic campaign state.

### Static Province Definition

~~~gdscript
class_name ProvinceDefinition
extends Resource

var id: int
var name: String
var map_color: Color
var center_position: Vector2
var terrain_id: String
var climate_id: String
var continent_id: String
var region_id: String
var area_id: String
var trade_node_id: String
var resource_id: String
var neighbour_ids: PackedInt32Array
var sea_neighbour_ids: PackedInt32Array
var is_land: bool
var is_coastal: bool
var is_strait: bool
~~~

### Dynamic Province State

~~~gdscript
class_name ProvinceState
extends RefCounted

var owner_country_id: int
var controller_country_id: int
var occupying_army_id: int = -1

var population: int
var development: int
var base_tax: int
var base_production: int
var base_manpower: int

var culture_id: int
var religion_id: int

var control: float = 1.0
var unrest: float = 0.0
var devastation: float = 0.0
var prosperity: float = 0.0

var fort_level: int = 0
var siege_progress: float = 0.0

var building_ids: PackedInt32Array
var active_modifiers: Array
~~~

Definitions remain unchanged during play. Province state is stored in the campaign save.

## 9. Province Adjacency

Adjacency generation should be one of the first major technical tasks.

The current project can identify a clicked province, but it does not yet know which provinces share borders.

The adjacency generator should scan provinces.bmp. Whenever two neighbouring pixels contain different valid province colours, the corresponding province IDs should become neighbours.

For each pixel, compare:

- The pixel to the right.
- The pixel below.
- The opposite horizontal map edge when world wrapping is enabled.

Generated data might look like:

~~~json
{
  "245": [244, 246, 311, 502],
  "246": [245, 247, 502]
}
~~~

The generator should also calculate:

- Province centre point.
- Pixel bounding box.
- Province area in pixels.
- Whether the province touches the sea.
- Border length with each neighbour.
- Connected land components.
- Map-edge wrapping connections.
- Potential straits and crossings.

Adjacency must be symmetric:

~~~text
If province 245 neighbours province 246,
province 246 must neighbour province 245.
~~~

Adjacency enables:

- Army movement.
- Pathfinding.
- Supply calculations.
- AI expansion.
- Diplomatic neighbour checks.
- Religion, culture, and disease spread.
- Trade routes.
- Country labels.
- Connected-territory checks.

Generate this data once with an editor tool and save it. Do not rescan the entire map whenever a campaign starts.

## 10. Map Renderer and Map Modes

The current map renderer can recolour an individual province by updating one pixel in the colour-map texture. This is a strong basis for map modes.

Create a MapModeManager:

~~~gdscript
enum MapMode {
    POLITICAL,
    TERRAIN,
    DIPLOMACY,
    ECONOMY,
    POPULATION,
    CULTURE,
    RELIGION,
    UNREST,
    DEVELOPMENT,
    SUPPLY,
    WAR,
}
~~~

Every map mode should provide a colour for a province:

~~~gdscript
func get_province_color(
    province_id: int,
    world: WorldState,
    player_country_id: int
) -> Color:
    return Color.WHITE
~~~

Examples:

~~~text
Political
Province colour = owner country colour

Diplomacy
Green = player
Blue = ally
Red = enemy
Yellow = truce
Grey = neutral

Unrest
Dark or green = calm
Yellow = moderate unrest
Red = rebellion imminent

Development
Dark = low development
Bright = high development
~~~

The renderer should eventually support:

- Hover outline.
- Selected province outline.
- Selected country highlighting.
- Occupation stripes.
- Siege indicators.
- Fog of war.
- Claims and cores.
- Map-mode colouring.
- Country and region labels.

Do not recompute every border every frame. Update borders only when ownership or control changes.

## 11. Countries

### Country Definition

~~~gdscript
class_name CountryDefinition
extends Resource

var id: int
var tag: String
var name: String
var adjective: String
var default_color: Color
var flag_path: String
var historical_capital_id: int
var primary_culture_id: int
var historical_religion_id: int
var government_type_id: int
~~~

### Country State

~~~gdscript
class_name CountryState
extends RefCounted

var exists := true
var capital_province_id: int
var ruler_character_id: int = -1

var treasury: int
var debt: int
var prestige: int
var stability: int
var legitimacy: int
var corruption: int

var manpower: int
var maximum_manpower: int
var sailors: int

var technology_levels: PackedInt32Array
var idea_ids: PackedInt32Array
var law_ids: PackedInt32Array

var owned_province_ids: PackedInt32Array
var controlled_province_ids: PackedInt32Array
var army_ids: PackedInt32Array
var navy_ids: PackedInt32Array

var ally_ids: PackedInt32Array
var rival_ids: PackedInt32Array
var subject_ids: PackedInt32Array

var active_modifier_ids: PackedInt32Array
~~~

Maintain owned_province_ids as a reverse index. Do not scan every province whenever the interface asks which provinces a country owns.

When ownership changes:

~~~text
1. Remove the province from its previous owner
2. Add the province to its new owner
3. Update ProvinceState.owner_country_id
4. Update the political map colour
5. Recalculate affected country borders
6. Mark economy values as dirty
7. Publish a ProvinceOwnerChanged event
~~~

## 12. Economy

Start with a simple monthly economy. Do not begin with a highly detailed world trade simulation.

### Province Income

A basic tax formula:

~~~text
tax income =
base tax
× local control
× stability modifier
× building modifier
× culture modifier
× religion modifier
× (1 - devastation)
× (1 - unrest penalty)
~~~

Example:

~~~gdscript
func calculate_monthly_tax(
    province: ProvinceState,
    country: CountryState
) -> int:
    var amount := province.base_tax * 100

    amount = apply_factor(amount, province.control)
    amount = apply_factor(amount, 1.0 - province.devastation)
    amount = apply_factor(amount, country.stability_tax_modifier)

    return amount
~~~

Use integer or fixed-point values for important simulation money:

~~~text
1 displayed gold = 1,000 internal money units
~~~

This avoids floating-point drift and improves determinism.

### Country Ledger

Track categories separately:

~~~text
Income
- Tax
- Production
- Trade
- Subject payments
- War reparations
- Events

Expenses
- Army maintenance
- Navy maintenance
- Forts
- Advisors
- Interest
- Subjects
- Construction
~~~

The interface should explain calculations. Players need to understand why their money changed.

### Construction

Buildings should be queued:

~~~gdscript
class_name ConstructionState
extends RefCounted

var province_id: int
var building_id: int
var country_id: int
var start_day: int
var completion_day: int
var amount_paid: int
~~~

## 13. Universal Modifier System

Build a reusable modifier system so each feature does not invent its own bonus logic.

~~~gdscript
class_name ModifierInstance
extends RefCounted

var definition_id: int
var source_type: int
var source_id: int
var start_day: int
var expiration_day: int = -1
var stack_count: int = 1
~~~

Example modifier:

~~~text
recently_conquered

province_unrest_add = 5
province_tax_multiplier = -0.25
province_manpower_multiplier = -0.25
duration_days = 3650
~~~

Use consistent operations:

- Flat addition.
- Percentage addition.
- Final multiplication.
- Minimum cap.
- Maximum cap.
- Boolean enable or disable.

Example calculation:

~~~text
base tax = 10
flat tax bonus = +2
percentage bonuses = +25%
final multiplier = 90%

(10 + 2) × 1.25 × 0.90 = 13.5
~~~

Modifiers can come from:

- Buildings.
- Terrain.
- Rulers.
- Laws.
- Religion.
- Culture.
- Technology.
- Events.
- Occupation.
- War.
- Government.
- Advisors.
- Character traits.

## 14. Armies and Movement

An army is a simulation object. Only its visible marker should be a scene node.

~~~gdscript
class_name ArmyState
extends RefCounted

var id: int
var owner_country_id: int
var current_province_id: int
var destination_province_id: int = -1

var regiment_ids: PackedInt32Array
var commander_character_id: int = -1

var morale: int
var organisation: int
var supply: int

var movement_path: PackedInt32Array
var path_index: int
var movement_started_day: int
var arrival_day: int

var battle_id: int = -1
var locked_movement := false
var retreating := false
~~~

When an army marker is clicked:

~~~text
Marker Node
    ↓
Army ID
    ↓
ArmyState in WorldState
    ↓
Army panel displays its data
~~~

Use A* or Dijkstra pathfinding over the province adjacency graph.

Movement cost may include:

- Province distance.
- Terrain.
- Rivers.
- Mountains.
- Roads.
- Enemy forts.
- Military access.
- Weather.
- Naval crossings.
- Army size.
- Commander manoeuvre.

Armies should have an arrival date rather than teleporting:

~~~text
London → Kent
Movement begins: 3 March
Expected arrival: 12 March
~~~

Movement may become locked after a chosen percentage of progress to prevent instant cancellation.

## 15. Warfare

Separate legal ownership from temporary military control:

~~~text
Owner       Country legally owning the province
Controller  Country currently occupying the province
~~~

A war should not immediately change legal ownership.

~~~gdscript
class_name WarState
extends RefCounted

var id: int
var name: String
var start_day: int

var attacker_leader_id: int
var defender_leader_id: int

var attacker_ids: PackedInt32Array
var defender_ids: PackedInt32Array

var war_goal_type_id: int
var war_goal_target_id: int

var battle_score: int
var occupation_score: int
var blockade_score: int
var ticking_score: int

var battle_ids: PackedInt32Array
var occupied_province_ids: PackedInt32Array
~~~

### Battle Prototype

Start with:

- Soldiers.
- Attack.
- Defence.
- Morale.
- Terrain.
- Commander bonus.
- A roll from the seeded random-number generator.

A conceptual daily combat formula:

~~~text
damage =
attacker strength
× attack modifier
× terrain modifier
× commander modifier
× random roll
÷ defender defence
~~~

Later, add:

- Infantry, cavalry, and artillery.
- Combat width.
- Front and back rows.
- Discipline.
- Tactics.
- Flanking.
- Reinforcement.
- Casualties.
- Retreat.
- Pursuit.
- Supply.
- Weather.

### Sieges

Forts should control strategic movement and require occupation.

Useful siege values:

- Fort level.
- Garrison.
- Besieging soldiers.
- Siege progress.
- Breach status.
- Blockade.
- Supply status.
- Commander siege skill.
- Terrain.

### Peace Deals

Every peace term should define:

- War-score cost.
- Diplomatic cost.
- Aggressive-expansion cost.
- Eligibility rules.
- AI desirability.

Possible terms:

- Transfer provinces.
- Release country.
- Return cores.
- Become a subject.
- Pay money.
- War reparations.
- Break alliances.
- Change religion.
- Renounce claims.

## 16. Diplomacy

Store diplomatic relationships using country pairs.

~~~gdscript
class_name DiplomaticRelation
extends RefCounted

var country_a_id: int
var country_b_id: int

var opinion_a_of_b: int
var opinion_b_of_a: int

var alliance := false
var truce_expiration_day := -1
var military_access_a_to_b := false
var military_access_b_to_a := false
var royal_marriage := false
var guarantee := false

var active_modifier_ids: PackedInt32Array
~~~

Relations are directional. England may like France more than France likes England.

Initial diplomatic actions:

- Improve relations.
- Insult.
- Form alliance.
- Break alliance.
- Request military access.
- Declare war.
- Offer peace.
- Guarantee independence.
- Create a subject.
- Integrate a subject.

Every action should pass through a command and validation system.

## 17. Technology, Institutions, and Ideas

Keep the first implementation simple:

~~~text
Administrative technology
Diplomatic technology
Military technology
~~~

Technology can unlock:

- Buildings.
- Units.
- Governments.
- Laws.
- Combat bonuses.
- Economic bonuses.
- Diplomatic actions.

Later, add eras or institutions:

~~~text
Feudalism
Renaissance
Printing
Industrialisation
Nationalism
~~~

Technology definitions should grant modifiers and unlock IDs rather than placing every effect directly inside the technology system.

## 18. CK2-Style Character Layer

Add the character layer after the country-level campaign loop works.

### Character State

~~~gdscript
class_name CharacterState
extends RefCounted

var id: int
var name: String
var dynasty_id: int
var culture_id: int
var religion_id: int

var birth_day: int
var death_day: int = -1
var alive := true

var sex: int
var father_id: int = -1
var mother_id: int = -1
var spouse_ids: PackedInt32Array
var child_ids: PackedInt32Array

var diplomacy: int
var martial: int
var stewardship: int
var intrigue: int
var learning: int

var health: int
var fertility: int
var stress: int

var trait_ids: PackedInt32Array
var title_ids: PackedInt32Array
var claim_ids: PackedInt32Array

var liege_character_id: int = -1
var employer_character_id: int = -1
~~~

Characters should not directly own map pixels. Titles connect characters to territory.

### Titles

~~~gdscript
class_name TitleState
extends RefCounted

var id: int
var rank: int
var holder_character_id: int
var liege_title_id: int = -1
var capital_province_id: int
var de_jure_vassal_title_ids: PackedInt32Array
var province_ids: PackedInt32Array
var succession_law_id: int
~~~

Title ranks might include:

~~~text
Barony
County
Duchy
Kingdom
Empire
~~~

This distinguishes:

~~~text
Character: William
Dynasty: Normandy
Title: Kingdom of England
Realm: England and its vassals
Province: London
~~~

### Succession

When a character dies:

1. Determine the succession law.
2. Find eligible heirs.
3. Rank eligible heirs.
4. Transfer titles.
5. Split titles when partition applies.
6. Recalculate vassal relationships.
7. Update realm borders if necessary.
8. Switch player control to the heir.
9. Trigger death and succession events.
10. End the game only if no playable dynasty member remains.

### Opinions

Character diplomacy should use explainable opinion modifiers:

~~~text
Base opinion
+ Same religion
+ Same culture
+ Family
+ Friend
- Rival
+ Liege opinion
- Short reign
- Title claimant
+ or - personality traits
+ or - recent actions
~~~

Store individual sources so the interface can explain the final value.

## 19. Population, Culture, and Religion

Do not simulate every civilian as an independent object. Aggregate population by province.

An initial version can store:

~~~gdscript
var population: int
var culture_id: int
var religion_id: int
~~~

A deeper version can use population groups:

~~~gdscript
class_name PopulationGroup
extends RefCounted

var culture_id: int
var religion_id: int
var social_class_id: int
var population: int
var wealth: int
var literacy: int
var militancy: int
~~~

Annual growth could use:

~~~text
new population =
population
× growth rate
× food modifier
× prosperity
× disease modifier
× war modifier
~~~

Culture and religion conversion should be gradual rather than instant.

## 20. Events and Decisions

Avoid hard-coding every event in one large chain of conditions.

An event definition should include:

- ID.
- Title.
- Description.
- Picture.
- Scope.
- Trigger.
- Mean time or scheduled date.
- Options.
- Effects.
- AI weights.

Conceptual example:

~~~json
{
  "id": "poor_harvest",
  "scope": "province",
  "trigger": {
    "terrain": "farmlands",
    "is_at_war": false
  },
  "options": [
    {
      "text": "Provide relief",
      "effects": {
        "owner_treasury": -20,
        "province_unrest": -2
      }
    },
    {
      "text": "They must endure",
      "effects": {
        "province_unrest": 4,
        "province_population_multiplier": -0.02
      }
    }
  ]
}
~~~

Do not test every possible event against every province every day. Use:

- Scheduled event dates.
- Event categories.
- Trigger indexes.
- Monthly random checks.
- Explicit event calls from other systems.

## 21. AI Architecture

AI should use the same commands and rules as the player.

~~~text
Observe world
    ↓
Choose strategic goals
    ↓
Create plans
    ↓
Score possible actions
    ↓
Submit commands
~~~

Possible strategic goals:

- Defend territory.
- Recover manpower.
- Improve the economy.
- Conquer a claim.
- Secure an alliance.
- Break encirclement.
- Suppress a rebellion.
- Expand trade.
- Gain a title.
- Protect the dynasty.

### Military AI

Military AI should:

1. Identify threats.
2. Estimate friendly and enemy strength.
3. Group armies.
4. Select fronts.
5. Choose defensive positions.
6. Prioritise forts and war goals.
7. Avoid extreme attrition.
8. Retreat from hopeless battles.
9. Protect capitals.

### Diplomatic AI

Score proposals using understandable factors:

~~~text
acceptance =
base willingness
+ opinion
+ common enemies
+ relative strength
+ strategic interest
- existing obligations
- rivalry
- border friction
~~~

### AI Frequency

Do not let hundreds of countries calculate grand strategy every day.

Suggested schedule:

- Army tactical decisions every few days.
- Country military planning weekly.
- Diplomacy monthly.
- Economy and construction monthly.
- Long-term strategy quarterly.
- Marriage and title plans periodically.

Distribute AI countries across different days so they do not all update in the same frame.

## 22. Saving and Loading

The original project data defines the scenario. The save file defines the campaign.

Save:

- Game version.
- Save schema version.
- Scenario ID.
- Current date.
- Random seed and RNG state.
- Player-controlled entity.
- Province states.
- Country states.
- Armies and navies.
- Wars.
- Diplomatic relationships.
- Characters.
- Titles.
- Events.
- Construction.
- Modifiers.
- AI state where necessary.

Do not save visual Godot nodes. Rebuild visual markers from simulation state after loading.

Use a versioned format:

~~~json
{
  "schema_version": 3,
  "game_version": "0.1.0",
  "scenario": "1444_default",
  "current_day": 581240,
  "player_country_id": 17
}
~~~

When the schema changes, a migration should convert older saves.

Test:

- Save and immediately load.
- Save during a war.
- Save during army movement.
- Save during a siege.
- Save immediately before character death.
- Load a save made by an older game version.

## 23. Modding Support

Use stable namespaced IDs:

~~~text
country.england
province.london
culture.english
religion.catholic
building.workshop
unit.longbowmen
event.poor_harvest
~~~

A future mod structure:

~~~text
mods/my_mod/
├── countries/
├── provinces/
├── characters/
├── titles/
├── events/
├── decisions/
├── buildings/
├── units/
├── localisation/
└── graphics/
~~~

Start with data replacement and extension. Avoid arbitrary mod GDScript initially unless unrestricted code execution is acceptable.

## 24. Performance Strategy

The current map size is manageable if the simulation is data-oriented.

Use these rules:

- Do not create a node for every province.
- Do not place a process callback on every simulated entity.
- Avoid scanning every province for simple country queries.
- Maintain reverse indexes such as country-to-provinces.
- Avoid allocating new arrays inside daily loops.
- Use stable integer IDs.
- Use packed arrays for large numeric datasets.
- Cache repeated calculations.
- Mark derived values dirty rather than recalculating continuously.
- Update UI only when relevant state changes.
- Batch map-colour changes.
- Run expensive AI less frequently.
- Profile before moving systems to C++.
- Use GDExtension only for measured bottlenecks.

Potential future C++ candidates:

- Adjacency generation.
- Large pathfinding batches.
- AI military scoring.
- Population simulation.
- Save compression.
- Complex trade-route calculations.

GDScript should be sufficient for the first playable vertical slice.

## 25. Testing Strategy

Important simulation invariants:

- Every active province has a valid owner or terrain owner.
- Province adjacency is symmetric.
- Country province indexes agree with province owners.
- Every army belongs to an existing country.
- Every army occupies a valid province.
- Every country capital exists.
- Every title holder exists.
- Every living character has a valid dynasty.
- A country cannot be on both sides of the same war.
- Treasury calculations balance.
- Save and load retain all important state.

A deterministic replay test:

1. Start from a fixed scenario.
2. Use a fixed random seed.
3. Submit a fixed command list.
4. Simulate ten years.
5. Calculate a checksum of WorldState.
6. Repeat the simulation.
7. Verify that the checksum is identical.

## 26. Development Phases

### Phase 0: Protect and Clean the Foundation

Tasks:

- Initialise Git.
- Make a clean baseline commit.
- Separate the map scene from gameplay.
- Stop parsing thousands of text files on every campaign start.
- Bake imported definitions into a fast database.
- Disable debug image writing for normal gameplay.
- Add error checks around province lookup.
- Add a basic automated test setup.

Definition of done:

- The map opens reliably.
- Data can be rebuilt with one editor tool.
- A campaign loads without editing source scenario data.
- Invalid province data produces a useful error.

### Phase 1: Map Interaction

Build:

- Hovered province.
- Selected province.
- Highlighting.
- Province tooltip.
- Province information panel.
- Country information panel.
- Search.
- Political map mode.
- Terrain map mode.
- Improved camera.

Definition of done:

- Every valid province can be hovered and selected.
- Province ID, name, owner, and controller are displayed.
- Gameplay UI does not directly alter source files.

### Phase 2: Simulation Core

Build:

- WorldState.
- Game clock.
- Pause and five speeds.
- Scheduler.
- Command system.
- Seeded random-number generator.
- Event bus.
- Save/load skeleton.

Definition of done:

- The simulation can advance for several years.
- Pause always stops simulation.
- Frame rate does not change simulation results.
- Save and load restore the exact date and province ownership.

### Phase 3: Adjacency and Movement

Build:

- Adjacency generator.
- Province centre points.
- Coastal detection.
- A* pathfinding.
- Army state.
- Army markers.
- Movement orders.
- Arrival dates.

Definition of done:

- An army can move through a valid path.
- It cannot cross invalid borders.
- World wrapping and sea crossings behave correctly.

### Phase 4: Basic Economy

Build:

- Monthly income.
- Treasury.
- Province tax.
- Manpower.
- Army maintenance.
- Buildings.
- Economy ledger.

Definition of done:

- Provinces generate understandable income.
- Armies cost money.
- Countries can enter debt.
- The UI explains income and expenses.

### Phase 5: Warfare

Build:

- War declarations.
- War participants.
- Battles.
- Morale.
- Casualties.
- Retreat.
- Sieges.
- Occupation.
- War score.
- Peace deals.

Definition of done:

- Two countries can fight a complete war.
- Provinces change controller during occupation.
- Provinces change legal owner only through peace.

### Phase 6: Basic AI

Build:

- Economic AI.
- Recruitment AI.
- Movement AI.
- Defensive AI.
- Offensive AI.
- Diplomatic acceptance.

Definition of done:

- Five AI countries can play for decades without crashing.
- AI can recruit, fight, occupy, make peace, and recover.

### Phase 7: Country Depth

Add:

- Stability.
- Prestige.
- Technology.
- Government.
- Laws.
- Culture.
- Religion.
- Unrest.
- Rebellions.
- Subjects.
- Alliances.
- Claims and cores.
- Missions or objectives.

### Phase 8: Global Scaling

Expand to:

- The entire map.
- Many active countries.
- Large wars.
- Global AI scheduling.
- Large save files.
- More map modes.
- Country labels.
- Performance optimisation.

### Phase 9: CK-Style Character Layer

Add:

- Characters.
- Dynasties.
- Traits.
- Skills.
- Marriage.
- Children.
- Health.
- Death.
- Titles.
- Vassals.
- Opinions.
- Claims.
- Succession.
- Intrigue.
- Character events.

Do not begin this phase until the country-level campaign loop is stable.

## 27. First Playable Version

Do not start with every country and every desired system.

Create a small test scenario:

~~~text
20–50 provinces
5 countries
1 terrain type
1 religion
1 culture
1 building
1 army type
1 basic AI personality
~~~

The first complete loop:

~~~text
Choose country
      ↓
Unpause
      ↓
Collect monthly money and manpower
      ↓
Recruit an army
      ↓
Declare war
      ↓
Move across adjacent provinces
      ↓
Fight and occupy territory
      ↓
Make peace
      ↓
Gain provinces
      ↓
Save and continue
~~~

This is the minimum viable grand-strategy game.

Once this loop is enjoyable and stable, add diplomacy depth, technology, characters, religion, trade, ships, colonisation, and other systems.

## 28. Immediate Work for This Project

Recommended implementation sequence:

1. Initialise Git and make a backup.
2. Add a GameRoot scene around the existing map.
3. Create WorldState, ProvinceState, and CountryState.
4. Import current addon data into those runtime structures.
5. Stop treating CountryData as the campaign save.
6. Add hover detection to province_selector.gd.
7. Add province and country information panels.
8. Generate adjacency and province centre data.
9. Add political, terrain, and selected-country map modes.
10. Implement the pauseable daily clock.
11. Add a command bus.
12. Implement a versioned save/load skeleton.
13. Add monthly tax and manpower.
14. Add one army type and movement.
15. Add war, occupation, and peace.
16. Add five-country AI.
17. Build a small regional vertical slice.
18. Add the gated character, dynasty, title, and succession layer.
19. Expand country depth and historical content for 1444–1700.
20. Scale to the global map and progress through Alpha, Beta, and 1.0.

## Final Target

The first major target should be:

> A pauseable real-time historical grand-strategy game spanning 11 November 1444 to 1 January 1700, with province economies, armies, diplomacy, warfare, AI, rulers, dynasties, titles, map modes, saving, and mod-friendly scenarios.

The country-level vertical slice comes first. The character and dynasty layer is then added through the existing command, event, modifier, AI, and save architecture. The 1700–1821 era remains a future extension after the initial campaign is stable and released.
