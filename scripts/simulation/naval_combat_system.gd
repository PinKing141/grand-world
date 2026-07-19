class_name NavalCombatSystem
extends RefCounted

## N4 (first slice): deterministic daily naval combat, mirroring
## WarfareSystem's land-combat architecture at fleet/ship scale - same
## integer-only, stable-sorted-ID, named-RNG-stream discipline. See
## docs/roadmap/naval/04_N4_NAVAL_COMBAT.md.
##
## Battle rounds use integer positioning, stable class/ID active-ship and
## target ordering, hull/crew/morale effectiveness, morale collapse, bounded
## pursuit, capture, sinking, retreat, and reinforcement. Battle summaries
## remain reports; ship and fleet records remain authority.

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")

const BASIS_POINTS := 10000
const MAX_ROUNDS := 30

# Placeholder first-slice minimum, not an approved N0 budget - 04_N4 "Retreat
# is unavailable until a minimum battle duration unless a side is
# destroyed/collapsed."
const MIN_RETREAT_ROUNDS := 3
const MORALE_COLLAPSE_BP := 2000
const DISABLED_HULL_BP := 2500
const CAPTURE_HULL_BP := 1000
const CAPTURED_CREW_BP := 5000
const CAPTURED_MORALE_BP := 2000
const BASE_ENGAGEMENT_WIDTH := 12
const MIN_POSITIONING_BP := 5000
const MAX_POSITIONING_BP := 12500
const PURSUIT_DAMAGE_PER_LIGHT_SHIP := 25

# Placeholder first-slice zone modifiers, not approved N0 budgets - mirrors
# WarfareSystem's own _terrain_defence_bp table exactly in shape and spirit.
# Sheltered water favours whoever is nominally defending the zone (the war's
# defender side); open ocean is the neutral baseline. A port (empty
# classification) counts as sheltered, like inland_sea.
const ZONE_DEFENCE_BP := {
	"coastal_sea": 11000,
	"inland_sea": 12000,
	"open_ocean": 10000,
	"": 12000,
}


static func advance_day(world: CampaignWorldState, events: SimulationEventBus) -> void:
	_end_orphaned_battles(world, events)
	if not _has_active_wars(world):
		return
	_join_reinforcements(world, events)
	_resolve_battles(world, events)
	_start_battles(world, events)


## Friendly fleets arriving at an already-active battle's location join on
## the correct side before that day's round resolves - "Newly arrived ships
## enter positioning/active selection on the defined next phase, not midway
## through already-calculated damage" (04_N4 "Reinforcement"). Mirrors
## WarfareSystem._join_reinforcements exactly.
static func _join_reinforcements(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var location_fleets := _fleets_by_location(world)
	var battle_ids := world.naval_battle_registry.keys()
	battle_ids.sort()
	for raw_battle_id in battle_ids:
		var battle_id := String(raw_battle_id)
		var battle: Dictionary = world.naval_battle_registry[battle_id]
		if String(battle.get("status", "")) != "active":
			continue
		var zone_id := int(battle.get("zone_id", -1))
		var war_id := String(battle.get("war_id", ""))
		if not world.war_registry.has(war_id):
			continue
		var war: Dictionary = world.war_registry[war_id]
		for raw_fleet_id in location_fleets.get(zone_id, []):
			var fleet_id := String(raw_fleet_id)
			var fleet := world.get_fleet(fleet_id)
			if not String(fleet.get("battle_id", "")).is_empty():
				continue
			var status := String(fleet.get("location_status", ""))
			if status in [CampaignWorldState.FLEET_LOCATION_BATTLE, CampaignWorldState.FLEET_LOCATION_RETREATING]:
				continue
			var owner := String(fleet.get("owner_country_id", ""))
			var side := DiplomacySystemScript.side_in_war(war, owner)
			if side == 0:
				continue
			var field := "attacker_fleets" if side > 0 else "defender_fleets"
			var participants: Array = battle.get(field, [])
			if participants.has(fleet_id):
				continue
			participants.append(fleet_id)
			participants.sort()
			battle[field] = participants
			var countries_field := "attacker_countries" if side > 0 else "defender_countries"
			var countries: Array = battle.get(countries_field, [])
			if not countries.has(owner):
				countries.append(owner)
				countries.sort()
			battle[countries_field] = countries
			var history: Array = battle.get("reinforcement_history", [])
			history.append({"day": world.current_day, "fleet_id": fleet_id, "side": "attacker" if side > 0 else "defender"})
			battle["reinforcement_history"] = history
			fleet["battle_id"] = battle_id
			fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_BATTLE
			fleet["destination_id"] = -1
			fleet["remaining_path"] = []
			fleet["path_index"] = 0
			fleet["next_arrival_day"] = -1
			world.fleet_registry[fleet_id] = fleet
			TransportSystemScript.link_fleet_operations_to_battle(world, fleet_id, battle_id)
			events.naval_battle_reinforced.emit(battle_id, fleet_id, "attacker" if side > 0 else "defender")
		world.naval_battle_registry[battle_id] = battle


static func _has_active_wars(world: CampaignWorldState) -> bool:
	for war in world.war_registry.values():
		if String((war as Dictionary).get("status", "active")) == "active":
			return true
	return false


static func _fleets_by_location(world: CampaignWorldState) -> Dictionary:
	var indexed := {}
	var fleet_ids := world.fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		var location_id := int((world.fleet_registry[raw_fleet_id] as Dictionary).get("location_id", -1))
		if location_id < 0:
			continue
		var bucket: Array = indexed.get(location_id, [])
		bucket.append(String(raw_fleet_id))
		indexed[location_id] = bucket
	return indexed


## Engagement start: hostile fleets sharing a location, neither already in a
## battle or retreating, with an active war between their owners. Detection/
## interception (04_N4 "the first abstraction is strategic") is a flat 100%
## when co-located for this slice - the same "simple explainable formula
## first" precedent every other N2/N3 first slice already established.
static func _start_battles(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var location_fleets := _fleets_by_location(world)
	var location_ids := location_fleets.keys()
	location_ids.sort()
	for raw_location_id in location_ids:
		var location_id := int(raw_location_id)
		var candidates: Array[String] = []
		for raw_fleet_id in location_fleets[raw_location_id]:
			var fleet_id := String(raw_fleet_id)
			var fleet := world.get_fleet(fleet_id)
			var status := String(fleet.get("location_status", ""))
			if status in [CampaignWorldState.FLEET_LOCATION_BATTLE, CampaignWorldState.FLEET_LOCATION_RETREATING]:
				continue
			if not String(fleet.get("battle_id", "")).is_empty():
				continue
			candidates.append(fleet_id)
		if candidates.size() < 2:
			continue
		var war_id := ""
		for first_index in range(candidates.size()):
			for second_index in range(first_index + 1, candidates.size()):
				var first_owner := String(world.get_fleet(candidates[first_index]).get("owner_country_id", ""))
				var second_owner := String(world.get_fleet(candidates[second_index]).get("owner_country_id", ""))
				war_id = DiplomacySystemScript.active_war_between(world, first_owner, second_owner)
				if not war_id.is_empty():
					break
			if not war_id.is_empty():
				break
		if war_id.is_empty():
			continue
		var war: Dictionary = world.war_registry[war_id]
		var attacker_fleets: Array = []
		var defender_fleets: Array = []
		for fleet_id in candidates:
			var owner := String(world.get_fleet(fleet_id).get("owner_country_id", ""))
			var side := DiplomacySystemScript.side_in_war(war, owner)
			if side > 0:
				attacker_fleets.append(fleet_id)
			elif side < 0:
				defender_fleets.append(fleet_id)
		if attacker_fleets.is_empty() or defender_fleets.is_empty():
			continue
		attacker_fleets.sort()
		defender_fleets.sort()
		var battle_id := "naval_battle_%06d" % world.take_counter("next_naval_battle_id")
		var battle := CampaignWorldState.make_naval_battle_record(battle_id, war_id, location_id, world.current_day)
		battle["attacker_fleets"] = attacker_fleets
		battle["defender_fleets"] = defender_fleets
		_initialize_battle_summary(world, battle)
		world.naval_battle_registry[battle_id] = battle
		for fleet_id in attacker_fleets + defender_fleets:
			var fleet := world.get_fleet(fleet_id)
			fleet["battle_id"] = battle_id
			fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_BATTLE
			fleet["destination_id"] = -1
			fleet["remaining_path"] = []
			fleet["path_index"] = 0
			fleet["next_arrival_day"] = -1
			world.fleet_registry[fleet_id] = fleet
			TransportSystemScript.link_fleet_operations_to_battle(world, fleet_id, battle_id)
		events.naval_battle_started.emit(war_id, battle_id, location_id)


static func _initialize_battle_summary(world: CampaignWorldState, battle: Dictionary) -> void:
	var definitions := ShipDefinitionsScript.load_default()
	var attacker_ships := _ships_of(world, battle.get("attacker_fleets", []))
	var defender_ships := _ships_of(world, battle.get("defender_fleets", []))
	battle["attacker_initial_ships"] = attacker_ships.size()
	battle["defender_initial_ships"] = defender_ships.size()
	battle["attacker_initial_hull"] = _raw_hull_of_ships(world, attacker_ships, definitions)
	battle["defender_initial_hull"] = _raw_hull_of_ships(world, defender_ships, definitions)
	battle["attacker_countries"] = _countries_of_fleets(world, battle.get("attacker_fleets", []))
	battle["defender_countries"] = _countries_of_fleets(world, battle.get("defender_fleets", []))
	battle["attacker_morale_bp"] = _side_morale(world, battle.get("attacker_fleets", []))
	battle["defender_morale_bp"] = _side_morale(world, battle.get("defender_fleets", []))


static func _countries_of_fleets(world: CampaignWorldState, fleet_ids: Array) -> Array[String]:
	var seen := {}
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		if world.fleet_registry.has(fleet_id):
			seen[String((world.fleet_registry[fleet_id] as Dictionary).get("owner_country_id", ""))] = true
	var countries: Array[String] = []
	for raw_country in seen:
		if not String(raw_country).is_empty():
			countries.append(String(raw_country))
	countries.sort()
	return countries


static func _resolve_battles(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var ship_definitions := ShipDefinitionsScript.load_default()
	var graph := MaritimeGraphScript.load_default()
	var battle_ids := world.naval_battle_registry.keys()
	battle_ids.sort()
	for raw_battle_id in battle_ids:
		var battle_id := String(raw_battle_id)
		if not world.naval_battle_registry.has(battle_id):
			continue
		var battle: Dictionary = world.naval_battle_registry[battle_id]
		if String(battle.get("status", "")) != "active" or int(battle.get("last_round_day", -1)) == world.current_day:
			continue
		var attacker_fleets := _living_fleets(world, battle.get("attacker_fleets", []))
		var defender_fleets := _living_fleets(world, battle.get("defender_fleets", []))
		if attacker_fleets.is_empty() or defender_fleets.is_empty():
			_finish_battle(world, events, battle, not attacker_fleets.is_empty(), ship_definitions)
			continue
		var attacker_ships := _ships_of(world, attacker_fleets)
		var defender_ships := _ships_of(world, defender_fleets)
		var classification := graph.sea_zone_classification(int(battle.get("zone_id", -1)))
		var attacker_positioning := _side_positioning(world, attacker_fleets, attacker_ships, defender_ships, ship_definitions, classification)
		var defender_positioning := _side_positioning(world, defender_fleets, defender_ships, attacker_ships, ship_definitions, classification)
		var attacker_active := _active_ships(world, attacker_ships, ship_definitions, int(attacker_positioning["value_bp"]))
		var defender_active := _active_ships(world, defender_ships, ship_definitions, int(defender_positioning["value_bp"]))
		battle["attacker_positioning_bp"] = int(attacker_positioning["value_bp"])
		battle["defender_positioning_bp"] = int(defender_positioning["value_bp"])
		battle["attacker_positioning_breakdown"] = attacker_positioning["breakdown"]
		battle["defender_positioning_breakdown"] = defender_positioning["breakdown"]
		battle["attacker_active_ships"] = attacker_active
		battle["defender_active_ships"] = defender_active
		var attacker_power := _combat_power(world, attacker_active, ship_definitions, "attack", int(attacker_positioning["value_bp"]), classification)
		var defender_power := _combat_power(world, defender_active, ship_definitions, "attack", int(defender_positioning["value_bp"]), classification)
		var zone_bp := int(ZONE_DEFENCE_BP.get(classification, 10000))
		var attacker_roll := 1 + int(world.next_random_u32("naval_combat:%s:attacker" % battle_id) % 6)
		var defender_roll := 1 + int(world.next_random_u32("naval_combat:%s:defender" % battle_id) % 6)
		var defender_losses := maxi(10, attacker_power * (80 + attacker_roll * 5) / 100 * BASIS_POINTS / zone_bp / 20)
		var attacker_losses := maxi(10, defender_power * (80 + defender_roll * 5) / 100 / 20)
		var defender_targets := _target_order(world, defender_ships, ship_definitions)
		var attacker_targets := _target_order(world, attacker_ships, ship_definitions)
		var defender_sunk := _apply_hull_losses(world, defender_targets, defender_losses, ship_definitions)
		var attacker_sunk := _apply_hull_losses(world, attacker_targets, attacker_losses, ship_definitions)
		for ship_id in defender_sunk:
			events.ship_sunk.emit(ship_id, battle_id)
		for ship_id in attacker_sunk:
			events.ship_sunk.emit(ship_id, battle_id)
		_remove_sunk_ships(world, defender_sunk, ship_definitions)
		_remove_sunk_ships(world, attacker_sunk, ship_definitions)
		var attacker_morale_loss := _morale_loss_bp(world, attacker_ships, attacker_losses, attacker_sunk.size(), ship_definitions)
		var defender_morale_loss := _morale_loss_bp(world, defender_ships, defender_losses, defender_sunk.size(), ship_definitions)
		_apply_side_morale_loss(world, attacker_fleets, attacker_morale_loss)
		_apply_side_morale_loss(world, defender_fleets, defender_morale_loss)
		battle["round"] = int(battle.get("round", 0)) + 1
		battle["last_round_day"] = world.current_day
		battle["attacker_hull_lost"] = int(battle.get("attacker_hull_lost", 0)) + attacker_losses
		battle["defender_hull_lost"] = int(battle.get("defender_hull_lost", 0)) + defender_losses
		battle["attacker_ships_sunk"] = int(battle.get("attacker_ships_sunk", 0)) + attacker_sunk.size()
		battle["defender_ships_sunk"] = int(battle.get("defender_ships_sunk", 0)) + defender_sunk.size()
		battle["attacker_morale_bp"] = _side_morale(world, attacker_fleets)
		battle["defender_morale_bp"] = _side_morale(world, defender_fleets)
		world.naval_battle_registry[battle_id] = battle
		events.naval_battle_round_resolved.emit(battle_id, int(battle["round"]), attacker_losses, defender_losses)
		var attacker_survivors := _living_fleets(world, battle.get("attacker_fleets", []))
		var defender_survivors := _living_fleets(world, battle.get("defender_fleets", []))
		var attacker_defeated := attacker_survivors.is_empty() or int(battle["attacker_morale_bp"]) <= MORALE_COLLAPSE_BP
		var defender_defeated := defender_survivors.is_empty() or int(battle["defender_morale_bp"]) <= MORALE_COLLAPSE_BP
		if attacker_defeated or defender_defeated or int(battle["round"]) >= MAX_ROUNDS:
			var attacker_won := defender_defeated or (not attacker_defeated and _total_hull(world, attacker_survivors, ship_definitions) >= _total_hull(world, defender_survivors, ship_definitions))
			battle["end_reason"] = "morale_collapse" if attacker_defeated or defender_defeated else "round_limit"
			_finish_battle(world, events, battle, attacker_won, ship_definitions)


## Fleets are "living" while they still carry at least one ship with
## positive hull - a fleet reduced to zero ships (or whose ships were all
## sunk) no longer counts as a combatant.
static func _living_fleets(world: CampaignWorldState, raw_ids: Array) -> Array[String]:
	var ids: Array[String] = []
	for raw_id in raw_ids:
		var fleet_id := String(raw_id)
		if not world.fleet_registry.has(fleet_id):
			continue
		if not world.fleet_ships(fleet_id).is_empty():
			ids.append(fleet_id)
	ids.sort()
	return ids


static func _ships_of(world: CampaignWorldState, fleet_ids: Array) -> Array[String]:
	var ids: Array[String] = []
	for fleet_id in fleet_ids:
		ids.append_array(world.fleet_ships(String(fleet_id)))
	ids.sort()
	return ids


static func _total_hull(world: CampaignWorldState, fleet_ids: Array, ship_definitions: ShipDefinitions) -> int:
	return _raw_hull_of_ships(world, _ships_of(world, fleet_ids), ship_definitions)


static func _raw_hull_of_ships(world: CampaignWorldState, ship_ids: Array, ship_definitions: ShipDefinitions) -> int:
	var total := 0
	for raw_ship_id in ship_ids:
		var ship_id := String(raw_ship_id)
		if world.ship_registry.has(ship_id):
			total += _raw_hull(world.get_ship(ship_id), ship_definitions)
	return total


static func _side_morale(world: CampaignWorldState, fleet_ids: Array) -> int:
	var weighted_total := 0
	var total_weight := 0
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		if not world.fleet_registry.has(fleet_id):
			continue
		var weight := maxi(1, world.fleet_ships(fleet_id).size())
		weighted_total += int((world.fleet_registry[fleet_id] as Dictionary).get("morale_bp", BASIS_POINTS)) * weight
		total_weight += weight
	return weighted_total / total_weight if total_weight > 0 else 0


static func _apply_side_morale_loss(world: CampaignWorldState, fleet_ids: Array, loss_bp: int) -> void:
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		if not world.fleet_registry.has(fleet_id):
			continue
		var fleet: Dictionary = world.fleet_registry[fleet_id]
		fleet["morale_bp"] = clampi(int(fleet.get("morale_bp", BASIS_POINTS)) - loss_bp, 0, BASIS_POINTS)
		world.fleet_registry[fleet_id] = fleet


static func _morale_loss_bp(world: CampaignWorldState, ship_ids: Array, hull_loss: int, sunk_count: int, ship_definitions: ShipDefinitions) -> int:
	var maximum_hull := 0
	for raw_ship_id in ship_ids:
		var ship_id := String(raw_ship_id)
		if not world.ship_registry.has(ship_id):
			continue
		var definition_id := String((world.ship_registry[ship_id] as Dictionary).get("definition_id", ""))
		if ship_definitions.has_ship(definition_id):
			maximum_hull += int(ship_definitions.ship(definition_id).get("maximum_hull", 0))
	return clampi(maxi(100, hull_loss * BASIS_POINTS * 2 / maxi(maximum_hull, 1) + sunk_count * 750), 0, 4000)


static func _ship_family(world: CampaignWorldState, ship_id: String, ship_definitions: ShipDefinitions) -> String:
	if not world.ship_registry.has(ship_id):
		return ""
	var definition_id := String((world.ship_registry[ship_id] as Dictionary).get("definition_id", ""))
	return String(ship_definitions.ship(definition_id).get("family", "")) if ship_definitions.has_ship(definition_id) else ""


static func _family_order(family: String) -> int:
	return {"heavy": 0, "galley": 1, "light": 2, "transport": 3}.get(family, 4)


static func _target_order(world: CampaignWorldState, ship_ids: Array, ship_definitions: ShipDefinitions) -> Array[String]:
	var ordered: Array[String] = []
	for raw_ship_id in ship_ids:
		ordered.append(String(raw_ship_id))
	ordered.sort_custom(func(a: String, b: String) -> bool:
		var a_order := _family_order(_ship_family(world, a, ship_definitions))
		var b_order := _family_order(_ship_family(world, b, ship_definitions))
		return a < b if a_order == b_order else a_order < b_order)
	return ordered


static func _active_ships(world: CampaignWorldState, ship_ids: Array, ship_definitions: ShipDefinitions, positioning_bp: int) -> Array[String]:
	var ordered := _target_order(world, ship_ids, ship_definitions)
	var width_limit := maxi(1, BASE_ENGAGEMENT_WIDTH * positioning_bp / BASIS_POINTS)
	var used_width := 0
	var active: Array[String] = []
	for ship_id in ordered:
		var definition_id := String(world.get_ship(ship_id).get("definition_id", ""))
		var width := maxi(1, int(ship_definitions.ship(definition_id).get("engagement_width", 1))) if ship_definitions.has_ship(definition_id) else 1
		if used_width + width > width_limit and not active.is_empty():
			continue
		active.append(ship_id)
		used_width += width
	return active


static func _side_positioning(
	world: CampaignWorldState,
	fleet_ids: Array,
	ship_ids: Array,
	opposing_ship_ids: Array,
	ship_definitions: ShipDefinitions,
	classification: String
) -> Dictionary:
	var breakdown := {"base": BASIS_POINTS}
	var value := BASIS_POINTS
	var own_speed := 0
	var enemy_speed := 0
	var light_count := 0
	var transport_count := 0
	var zone_modifier := 0
	for raw_ship_id in ship_ids:
		var ship_id := String(raw_ship_id)
		var definition_id := String(world.get_ship(ship_id).get("definition_id", ""))
		if not ship_definitions.has_ship(definition_id):
			continue
		var definition := ship_definitions.ship(definition_id)
		own_speed += int(definition.get("speed", 1))
		var family := String(definition.get("family", ""))
		light_count += 1 if family == "light" else 0
		transport_count += 1 if family == "transport" else 0
		if classification == "coastal_sea":
			zone_modifier += int(definition.get("coastal_modifier_bp", 0))
		elif classification == "inland_sea":
			zone_modifier += int(definition.get("inland_sea_modifier_bp", 0))
	for raw_ship_id in opposing_ship_ids:
		var definition_id := String(world.get_ship(String(raw_ship_id)).get("definition_id", ""))
		if ship_definitions.has_ship(definition_id):
			enemy_speed += int(ship_definitions.ship(definition_id).get("speed", 1))
	var speed_modifier := ((own_speed / maxi(ship_ids.size(), 1)) - (enemy_speed / maxi(opposing_ship_ids.size(), 1))) * 400
	var scout_modifier := light_count * 150
	var coordination_modifier := -maxi(0, ship_ids.size() - BASE_ENGAGEMENT_WIDTH) * 125
	var burden_modifier := -transport_count * 250
	zone_modifier = zone_modifier / maxi(ship_ids.size(), 1)
	var readiness_modifier := 0
	var mission_modifier := 0
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		if not world.fleet_registry.has(fleet_id):
			continue
		var fleet: Dictionary = world.fleet_registry[fleet_id]
		if not bool(fleet.get("supplied", true)):
			readiness_modifier -= 1500
		readiness_modifier -= maxi(0, BASIS_POINTS - int(fleet.get("maintenance_posture_bp", BASIS_POINTS))) / 5
		var mission := String(fleet.get("mission", "idle"))
		mission_modifier += {"intercept": 500, "patrol": 200, "protect_transport": 250, "blockade": -150, "repair": -750, "return_to_port": -500}.get(mission, 0)
	breakdown["relative_speed"] = speed_modifier
	breakdown["light_scouting"] = scout_modifier
	breakdown["coordination"] = coordination_modifier
	breakdown["transport_burden"] = burden_modifier
	breakdown["sea_zone"] = zone_modifier
	breakdown["readiness"] = readiness_modifier
	breakdown["mission"] = mission_modifier
	value = clampi(value + speed_modifier + scout_modifier + coordination_modifier + burden_modifier + zone_modifier + readiness_modifier + mission_modifier, MIN_POSITIONING_BP, MAX_POSITIONING_BP)
	return {"value_bp": value, "breakdown": breakdown}


static func _raw_hull(ship: Dictionary, ship_definitions: ShipDefinitions) -> int:
	var definition_id := String(ship.get("definition_id", ""))
	if not ship_definitions.has_ship(definition_id):
		return 0
	var max_hull := int(ship_definitions.ship(definition_id).get("maximum_hull", 0))
	return max_hull * int(ship.get("hull_bp", 0)) / BASIS_POINTS


## Damaged ships fight proportionally weaker (their own hull_bp scales their
## contribution) - a ship at 50% hull contributes half its class attack, not
## its full rating, so accumulated damage has a compounding tactical effect
## within a single battle, not just a bookkeeping one. Admiral martial skill
## contributes through the same one-function shape WarfareSystem's commander
## bonus already established for land combat.
static func _combat_power(
	world: CampaignWorldState,
	ship_ids: Array,
	ship_definitions: ShipDefinitions,
	stat: String,
	positioning_bp := BASIS_POINTS,
	classification := ""
) -> int:
	var total := 0
	for ship_id in ship_ids:
		var ship := world.get_ship(ship_id)
		var definition_id := String(ship.get("definition_id", ""))
		if not ship_definitions.has_ship(definition_id):
			continue
		var definition := ship_definitions.ship(definition_id)
		var power := int(definition.get(stat, 0)) * int(ship.get("hull_bp", 0)) / BASIS_POINTS
		power = power * int(ship.get("crew_bp", BASIS_POINTS)) / BASIS_POINTS
		var fleet_id := String(ship.get("fleet_id", ""))
		var fleet := world.get_fleet(fleet_id)
		power = power * int(fleet.get("morale_bp", BASIS_POINTS)) / BASIS_POINTS
		power = power * int(fleet.get("maintenance_posture_bp", BASIS_POINTS)) / BASIS_POINTS
		if classification == "coastal_sea":
			power = power * (BASIS_POINTS + int(definition.get("coastal_modifier_bp", 0))) / BASIS_POINTS
		elif classification == "inland_sea":
			power = power * (BASIS_POINTS + int(definition.get("inland_sea_modifier_bp", 0))) / BASIS_POINTS
		var admiral_id := String(fleet.get("admiral_id", ""))
		if world.character_registry.has(admiral_id):
			var admiral: Dictionary = world.character_registry[admiral_id]
			if bool(admiral.get("alive", false)):
				var martial := int((admiral.get("skills", {}) as Dictionary).get("martial", 5))
				power = power * (BASIS_POINTS + (martial - 5) * 500) / BASIS_POINTS
		total += power
	return maxi(1, total * positioning_bp / BASIS_POINTS)


## Distributes total_damage (in raw hull points) across ship_ids in stable
## sorted-ID order, capping each ship's loss at its own remaining hull -
## "damage is clamped and cannot... underflow" (04_N4 "Damage Model"). Any
## leftover budget after every ship has absorbed what it can is not applied
## - a simple, deterministic allocation rule, not a claim that it is the
## final balance formula. Returns the sunk ship IDs (hull reduced to zero).
static func _apply_hull_losses(world: CampaignWorldState, ship_ids: Array, total_damage: int, ship_definitions: ShipDefinitions) -> Array[String]:
	var sunk: Array[String] = []
	var remaining := total_damage
	for ship_id in ship_ids:
		if remaining <= 0:
			break
		var ship := world.get_ship(ship_id)
		var current_hull := _raw_hull(ship, ship_definitions)
		if current_hull <= 0:
			continue
		var loss := mini(remaining, current_hull)
		var new_hull := current_hull - loss
		var definition_id := String(ship.get("definition_id", ""))
		var max_hull := int(ship_definitions.ship(definition_id).get("maximum_hull", 1)) if ship_definitions.has_ship(definition_id) else 1
		ship["hull_bp"] = new_hull * BASIS_POINTS / maxi(max_hull, 1)
		var crew_loss_bp := maxi(100, loss * BASIS_POINTS / maxi(current_hull, 1) / 2)
		ship["crew_bp"] = maxi(0, int(ship.get("crew_bp", BASIS_POINTS)) - crew_loss_bp)
		ship["disabled"] = int(ship["hull_bp"]) <= DISABLED_HULL_BP or int(ship["crew_bp"]) <= DISABLED_HULL_BP
		remaining -= loss
		world.ship_registry[ship_id] = ship
		if new_hull <= 0:
			ship["hull_bp"] = 0
			world.ship_registry[ship_id] = ship
			sunk.append(ship_id)
	return sunk


static func _remove_sunk_ships(world: CampaignWorldState, sunk_ship_ids: Array[String], ship_definitions: ShipDefinitions) -> void:
	var touched_fleets := {}
	for ship_id in sunk_ship_ids:
		if not world.ship_registry.has(ship_id):
			continue
		var fleet_id := String(world.get_ship(ship_id).get("fleet_id", ""))
		touched_fleets[fleet_id] = true
		world.ship_registry.erase(ship_id)
		if world.fleet_registry.has(fleet_id):
			var fleet := world.get_fleet(fleet_id)
			var members: Array = fleet.get("ship_ids", [])
			members.erase(ship_id)
			fleet["ship_ids"] = members
			world.fleet_registry[fleet_id] = fleet
	var fleet_ids := touched_fleets.keys()
	fleet_ids.sort()
	for fleet_id in fleet_ids:
		if world.fleet_registry.has(fleet_id):
			FleetSystemScript.recompute_aggregate(world, String(fleet_id), ship_definitions)


static func _finish_battle(world: CampaignWorldState, events: SimulationEventBus, battle: Dictionary, attacker_won: bool, ship_definitions: ShipDefinitions) -> void:
	var battle_id := String(battle["battle_id"])
	var zone_id := int(battle.get("zone_id", -1))
	var loser_fleets: Array = battle.get("defender_fleets", []) if attacker_won else battle.get("attacker_fleets", [])
	var winner_fleets: Array = battle.get("attacker_fleets", []) if attacker_won else battle.get("defender_fleets", [])
	_apply_pursuit(world, events, battle, winner_fleets, loser_fleets, attacker_won, ship_definitions)
	_capture_disabled_ships(world, battle, winner_fleets, loser_fleets, attacker_won, ship_definitions)
	for raw_fleet_id in loser_fleets:
		var fleet_id := String(raw_fleet_id)
		if not world.fleet_registry.has(fleet_id):
			continue
		if world.fleet_ships(fleet_id).is_empty():
			world.fleet_registry.erase(fleet_id)
			events.fleet_destroyed.emit(fleet_id, battle_id)
		else:
			_begin_retreat(world, events, fleet_id, zone_id)
	for raw_fleet_id in winner_fleets:
		var fleet_id := String(raw_fleet_id)
		if not world.fleet_registry.has(fleet_id):
			continue
		if world.fleet_ships(fleet_id).is_empty():
			world.fleet_registry.erase(fleet_id)
			events.fleet_destroyed.emit(fleet_id, battle_id)
			continue
		var fleet := world.get_fleet(fleet_id)
		fleet["battle_id"] = ""
		fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_DOCKED if MaritimeGraphScript.load_default().is_port_province(zone_id) else CampaignWorldState.FLEET_LOCATION_AT_SEA
		world.fleet_registry[fleet_id] = fleet
		TransportSystemScript.release_fleet_operations_from_battle(world, fleet_id, battle_id)
	battle["status"] = "completed"
	battle["end_day"] = world.current_day
	battle["winner_side"] = "attacker" if attacker_won else "defender"
	if String(battle.get("end_reason", "")).is_empty():
		battle["end_reason"] = "combat_exhaustion"
	world.naval_battle_registry[battle_id] = battle
	var war_id := String(battle.get("war_id", ""))
	if world.war_registry.has(war_id):
		var war: Dictionary = world.war_registry[war_id]
		var score := clampi((int(battle.get("attacker_hull_lost", 0)) + int(battle.get("defender_hull_lost", 0))) / 500, 1, 10)
		war["battle_score_attacker"] = int(war.get("battle_score_attacker", 0)) + (score if attacker_won else -score)
		world.war_registry[war_id] = war
	events.naval_battle_ended.emit(war_id, battle_id, String(battle["winner_side"]))


## One bounded pursuit step. Only surviving light ships contribute and the
## result is committed before retreat paths are created, so it cannot become
## an unbounded second movement/combat loop.
static func _apply_pursuit(
	world: CampaignWorldState,
	events: SimulationEventBus,
	battle: Dictionary,
	winner_fleets: Array,
	loser_fleets: Array,
	attacker_won: bool,
	ship_definitions: ShipDefinitions
) -> void:
	var light_count := 0
	for ship_id in _ships_of(world, winner_fleets):
		light_count += 1 if _ship_family(world, ship_id, ship_definitions) == "light" else 0
	var pursuit_damage := light_count * PURSUIT_DAMAGE_PER_LIGHT_SHIP
	if pursuit_damage <= 0:
		return
	var targets := _target_order(world, _ships_of(world, loser_fleets), ship_definitions)
	var sunk := _apply_hull_losses(world, targets, pursuit_damage, ship_definitions)
	for ship_id in sunk:
		events.ship_sunk.emit(ship_id, String(battle.get("battle_id", "")))
	_remove_sunk_ships(world, sunk, ship_definitions)
	battle["pursuit_hull_lost"] = int(battle.get("pursuit_hull_lost", 0)) + pursuit_damage
	var hull_field := "defender_hull_lost" if attacker_won else "attacker_hull_lost"
	var sunk_field := "defender_ships_sunk" if attacker_won else "attacker_ships_sunk"
	battle[hull_field] = int(battle.get(hull_field, 0)) + pursuit_damage
	battle[sunk_field] = int(battle.get(sunk_field, 0)) + sunk.size()


## Disabled non-transport ships at extreme damage may be captured into the
## first stable-ID surviving winner fleet. Transport hulls are never captured
## because doing so would silently transfer an enemy carried army.
static func _capture_disabled_ships(
	world: CampaignWorldState,
	battle: Dictionary,
	winner_fleets: Array,
	loser_fleets: Array,
	attacker_won: bool,
	ship_definitions: ShipDefinitions
) -> void:
	var destinations: Array[String] = []
	for raw_fleet_id in winner_fleets:
		var fleet_id := String(raw_fleet_id)
		if world.fleet_registry.has(fleet_id) and not world.fleet_ships(fleet_id).is_empty():
			destinations.append(fleet_id)
	destinations.sort()
	if destinations.is_empty():
		return
	var destination_id := destinations[0]
	var destination: Dictionary = world.fleet_registry[destination_id]
	var new_owner := String(destination.get("owner_country_id", ""))
	var candidates := _target_order(world, _ships_of(world, loser_fleets), ship_definitions)
	for ship_id in candidates:
		if not world.ship_registry.has(ship_id):
			continue
		var ship: Dictionary = world.ship_registry[ship_id]
		if _ship_family(world, ship_id, ship_definitions) == "transport":
			continue
		if not bool(ship.get("disabled", false)) or int(ship.get("hull_bp", BASIS_POINTS)) > CAPTURE_HULL_BP:
			continue
		var old_owner := String(ship.get("owner_country_id", ""))
		var source_id := String(ship.get("fleet_id", ""))
		if world.fleet_registry.has(source_id):
			var source: Dictionary = world.fleet_registry[source_id]
			var source_members: Array = source.get("ship_ids", [])
			source_members.erase(ship_id)
			source["ship_ids"] = source_members
			world.fleet_registry[source_id] = source
		ship["owner_country_id"] = new_owner
		ship["fleet_id"] = destination_id
		ship["captured_from"] = old_owner
		ship["captured_battle_id"] = String(battle.get("battle_id", ""))
		ship["crew_bp"] = mini(int(ship.get("crew_bp", CAPTURED_CREW_BP)), CAPTURED_CREW_BP)
		ship["morale_contribution_bp"] = CAPTURED_MORALE_BP
		ship["disabled"] = true
		world.ship_registry[ship_id] = ship
		var destination_members: Array = destination.get("ship_ids", [])
		destination_members.append(ship_id)
		destination_members.sort()
		destination["ship_ids"] = destination_members
		world.fleet_registry[destination_id] = destination
		var field := "attacker_captured_ship_ids" if attacker_won else "defender_captured_ship_ids"
		var captured: Array = battle.get(field, [])
		captured.append(ship_id)
		captured.sort()
		battle[field] = captured
		if world.fleet_registry.has(source_id):
			FleetSystemScript.recompute_aggregate(world, source_id, ship_definitions)
		FleetSystemScript.recompute_aggregate(world, destination_id, ship_definitions)
		return


## Voluntary retreat: RequestFleetRetreatCommand's apply() calls this after
## validate() has already confirmed the battle has run at least
## MIN_RETREAT_ROUNDS - "Player/AI may request retreat; command validates
## leader/side/fleet ownership" (04_N4 "Retreat and Pursuit"). Removing the
## fleet from its side's list can leave that side empty, which ends the
## battle in the remaining side's favour exactly as if it had been defeated
## in combat - a withdrawal is still a loss for war-score purposes.
static func withdraw_fleet(world: CampaignWorldState, events: SimulationEventBus, fleet_id: String) -> void:
	var fleet := world.get_fleet(fleet_id)
	var battle_id := String(fleet.get("battle_id", ""))
	if battle_id.is_empty() or not world.naval_battle_registry.has(battle_id):
		return
	var battle: Dictionary = world.naval_battle_registry[battle_id]
	var zone_id := int(battle.get("zone_id", -1))
	var attacker_fleets: Array = battle.get("attacker_fleets", [])
	var defender_fleets: Array = battle.get("defender_fleets", [])
	var was_attacker := attacker_fleets.has(fleet_id)
	attacker_fleets.erase(fleet_id)
	defender_fleets.erase(fleet_id)
	battle["attacker_fleets"] = attacker_fleets
	battle["defender_fleets"] = defender_fleets
	var withdrawn_field := "attacker_withdrawn_fleet_ids" if was_attacker else "defender_withdrawn_fleet_ids"
	var withdrawn: Array = battle.get(withdrawn_field, [])
	withdrawn.append(fleet_id)
	withdrawn.sort()
	battle[withdrawn_field] = withdrawn
	battle["end_reason"] = "voluntary_retreat"
	world.naval_battle_registry[battle_id] = battle
	fleet["battle_id"] = ""
	world.fleet_registry[fleet_id] = fleet
	_begin_retreat(world, events, fleet_id, zone_id)
	battle = world.naval_battle_registry[battle_id]
	if _living_fleets(world, battle.get("attacker_fleets", [])).is_empty() or _living_fleets(world, battle.get("defender_fleets", [])).is_empty():
		_finish_battle(world, events, battle, not was_attacker, ShipDefinitionsScript.load_default())


## Bounded recovery: the nearest port the fleet's own country can legally
## dock at from the battle's location - the same "retreat is unavailable
## until minimum duration unless destroyed" simplification most first
## slices in this roadmap take (full retreat-timing/pursuit rules are a
## later refinement), and the same nearest_matching-excludes-the-origin
## subtlety N3.3's _attempt_recovery already had to account for. A fleet
## with no legal retreat is destroyed outright - 04_N4 "A fleet with no
## legal retreat resolves through explicit surrender/destruction rules."
static func _begin_retreat(world: CampaignWorldState, events: SimulationEventBus, fleet_id: String, zone_id: int) -> void:
	var graph := MaritimeGraphScript.load_default()
	var fleet := world.get_fleet(fleet_id)
	var owner := String(fleet.get("owner_country_id", ""))
	var destination_id := -1
	if NavalAccessPolicyScript.can_dock(graph, world, owner, zone_id):
		destination_id = zone_id
	else:
		var nearest := graph.nearest_matching(zone_id, func(candidate_id): return NavalAccessPolicyScript.can_dock(graph, world, owner, candidate_id))
		if bool(nearest["found"]):
			destination_id = int(nearest["id"])
	fleet["battle_id"] = ""
	if destination_id < 0:
		# Admiral cleanup mirrors ScuttleFleetCommand.apply()'s own reverse
		# reference clearing (commands/scuttle_fleet_command.gd) - a real,
		# previously-recorded dangling-reference gap (FL2_5_SCUTTLE_COMMAND.md):
		# without this, a fleet destroyed here left its admiral's
		# admiral_fleet_id pointing at a fleet that no longer exists, making
		# that admiral permanently ineligible for reassignment - naval AI's
		# own _best_available_admiral() excludes any character with a
		# non-empty admiral_fleet_id, with no way to ever clear a stale one.
		var admiral_id := String(fleet.get("admiral_id", ""))
		if not admiral_id.is_empty() and world.character_registry.has(admiral_id):
			var admiral: Dictionary = world.character_registry[admiral_id]
			admiral["admiral_fleet_id"] = ""
			world.character_registry[admiral_id] = admiral
		for ship_id in world.fleet_ships(fleet_id):
			world.ship_registry.erase(ship_id)
		world.fleet_registry.erase(fleet_id)
		events.fleet_destroyed.emit(fleet_id, "no_legal_retreat")
		return
	if destination_id == zone_id:
		fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_DOCKED if graph.is_port_province(zone_id) else CampaignWorldState.FLEET_LOCATION_AT_SEA
		world.fleet_registry[fleet_id] = fleet
		_release_all_transport_pauses(world, fleet_id)
		return
	var route := graph.find_route(zone_id, destination_id, FleetSystemScript.speed_multiplier_bp(fleet))
	fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_RETREATING
	fleet["destination_id"] = destination_id
	var remaining: Array = []
	for index in range(1, (route["path"] as Array).size()):
		remaining.append(int(((route["path"] as Array)[index] as Dictionary)["id"]))
	fleet["remaining_path"] = remaining
	fleet["path_index"] = 0
	fleet["movement_start_day"] = world.current_day
	fleet["next_arrival_day"] = world.current_day + (graph.leg_cost_days(zone_id, int(remaining[0]), FleetSystemScript.speed_multiplier_bp(fleet)) if not remaining.is_empty() else 1)
	fleet["movement_progress"] = 0.0
	world.fleet_registry[fleet_id] = fleet
	_release_all_transport_pauses(world, fleet_id)
	events.fleet_retreat_started.emit(fleet_id, destination_id)


## withdraw_fleet clears fleet.battle_id before entering _begin_retreat, so
## release against each operation's authoritative pause reference.
static func _release_all_transport_pauses(world: CampaignWorldState, fleet_id: String) -> void:
	if not world.fleet_registry.has(fleet_id):
		return
	var fleet := world.get_fleet(fleet_id)
	var operation_ids: Array = fleet.get("transport_operation_ids", [])
	operation_ids.sort()
	for raw_operation_id in operation_ids:
		var operation_id := String(raw_operation_id)
		if world.transport_operation_registry.has(operation_id):
			var pause_id := String((world.transport_operation_registry[operation_id] as Dictionary).get("battle_pause_reference", ""))
			if not pause_id.is_empty():
				TransportSystemScript.release_fleet_operations_from_battle(world, fleet_id, pause_id)


## Peace and country-extinction are neutral disengagements, not victories.
## They clear every battle<->fleet<->transport reverse reference without
## adding war score or forcing a retreat after hostility has ended.
static func end_war_battles(world: CampaignWorldState, events: SimulationEventBus, war_id: String, reason := "peace") -> void:
	var battle_ids := world.naval_battle_registry.keys()
	battle_ids.sort()
	for raw_battle_id in battle_ids:
		var battle: Dictionary = world.naval_battle_registry[raw_battle_id]
		if String(battle.get("status", "")) == "active" and String(battle.get("war_id", "")) == war_id:
			_disengage_battle(world, events, battle, reason)


static func _end_orphaned_battles(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var battle_ids := world.naval_battle_registry.keys()
	battle_ids.sort()
	for raw_battle_id in battle_ids:
		var battle: Dictionary = world.naval_battle_registry[raw_battle_id]
		if String(battle.get("status", "")) != "active":
			continue
		var war_id := String(battle.get("war_id", ""))
		if not world.war_registry.has(war_id) or String((world.war_registry[war_id] as Dictionary).get("status", "")) != "active":
			_disengage_battle(world, events, battle, "war_inactive")


static func _disengage_battle(world: CampaignWorldState, events: SimulationEventBus, battle: Dictionary, reason: String) -> void:
	var battle_id := String(battle.get("battle_id", ""))
	var zone_id := int(battle.get("zone_id", -1))
	var fleet_ids: Array = (battle.get("attacker_fleets", []) as Array) + (battle.get("defender_fleets", []) as Array)
	fleet_ids.sort()
	var seen := {}
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		if seen.has(fleet_id) or not world.fleet_registry.has(fleet_id):
			continue
		seen[fleet_id] = true
		var fleet := world.get_fleet(fleet_id)
		if String(fleet.get("battle_id", "")) == battle_id:
			fleet["battle_id"] = ""
		if String(fleet.get("location_status", "")) == CampaignWorldState.FLEET_LOCATION_BATTLE:
			fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_DOCKED if MaritimeGraphScript.load_default().is_port_province(zone_id) else CampaignWorldState.FLEET_LOCATION_AT_SEA
		fleet["destination_id"] = -1
		fleet["remaining_path"] = []
		fleet["path_index"] = 0
		fleet["next_arrival_day"] = -1
		world.fleet_registry[fleet_id] = fleet
		TransportSystemScript.release_fleet_operations_from_battle(world, fleet_id, battle_id)
	battle["status"] = "ended_%s" % reason
	battle["end_day"] = world.current_day
	battle["winner_side"] = "none"
	battle["end_reason"] = reason
	world.naval_battle_registry[battle_id] = battle
	events.naval_battle_ended.emit(String(battle.get("war_id", "")), battle_id, "none")
