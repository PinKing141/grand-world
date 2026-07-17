class_name NavalCombatSystem
extends RefCounted

## N4 (first slice): deterministic daily naval combat, mirroring
## WarfareSystem's land-combat architecture at fleet/ship scale - same
## integer-only, stable-sorted-ID, named-RNG-stream discipline. See
## docs/roadmap/naval/04_N4_NAVAL_COMBAT.md.
##
## This slice covers battle records, engagement start, deterministic hull
## damage, sinking, forced and voluntary retreat, and reinforcement - enough
## for a naval battle to start, grow, and reach a terminal state either by
## exhaustion or by a side choosing to withdraw. Positioning breakdown beyond
## a single zone modifier, morale-based early collapse, capture, and pursuit
## are explicitly deferred; see the evidence docs' "Deliberately simple /
## deferred" for why the packet boundary was drawn where it was (a battle
## that starts and deals damage but can never sink a ship or let anyone
## retreat would never reach a testable terminal state).

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")

const BASIS_POINTS := 10000
const MAX_ROUNDS := 30

# Placeholder first-slice minimum, not an approved N0 budget - 04_N4 "Retreat
# is unavailable until a minimum battle duration unless a side is
# destroyed/collapsed."
const MIN_RETREAT_ROUNDS := 3

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
			fleet["battle_id"] = battle_id
			fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_BATTLE
			fleet["destination_id"] = -1
			fleet["remaining_path"] = []
			fleet["path_index"] = 0
			fleet["next_arrival_day"] = -1
			world.fleet_registry[fleet_id] = fleet
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
		events.naval_battle_started.emit(war_id, battle_id, location_id)


static func _resolve_battles(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var ship_definitions := ShipDefinitionsScript.load_default()
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
		var attacker_power := _combat_power(world, attacker_ships, ship_definitions, "attack")
		var defender_power := _combat_power(world, defender_ships, ship_definitions, "attack")
		var zone_bp := int(ZONE_DEFENCE_BP.get(MaritimeGraphScript.load_default().sea_zone_classification(int(battle.get("zone_id", -1))), 10000))
		var attacker_roll := 1 + int(world.next_random_u32("naval_combat:%s:attacker" % battle_id) % 6)
		var defender_roll := 1 + int(world.next_random_u32("naval_combat:%s:defender" % battle_id) % 6)
		var defender_losses := maxi(10, attacker_power * (80 + attacker_roll * 5) / 100 * BASIS_POINTS / zone_bp / 20)
		var attacker_losses := maxi(10, defender_power * (80 + defender_roll * 5) / 100 / 20)
		var defender_sunk := _apply_hull_losses(world, defender_ships, defender_losses, ship_definitions)
		var attacker_sunk := _apply_hull_losses(world, attacker_ships, attacker_losses, ship_definitions)
		for ship_id in defender_sunk:
			events.ship_sunk.emit(ship_id, battle_id)
		for ship_id in attacker_sunk:
			events.ship_sunk.emit(ship_id, battle_id)
		_remove_sunk_ships(world, defender_sunk, ship_definitions)
		_remove_sunk_ships(world, attacker_sunk, ship_definitions)
		battle["round"] = int(battle.get("round", 0)) + 1
		battle["last_round_day"] = world.current_day
		battle["attacker_hull_lost"] = int(battle.get("attacker_hull_lost", 0)) + attacker_losses
		battle["defender_hull_lost"] = int(battle.get("defender_hull_lost", 0)) + defender_losses
		battle["attacker_ships_sunk"] = int(battle.get("attacker_ships_sunk", 0)) + attacker_sunk.size()
		battle["defender_ships_sunk"] = int(battle.get("defender_ships_sunk", 0)) + defender_sunk.size()
		world.naval_battle_registry[battle_id] = battle
		events.naval_battle_round_resolved.emit(battle_id, int(battle["round"]), attacker_losses, defender_losses)
		var attacker_survivors := _living_fleets(world, battle.get("attacker_fleets", []))
		var defender_survivors := _living_fleets(world, battle.get("defender_fleets", []))
		var attacker_defeated := attacker_survivors.is_empty()
		var defender_defeated := defender_survivors.is_empty()
		if attacker_defeated or defender_defeated or int(battle["round"]) >= MAX_ROUNDS:
			var attacker_won := defender_defeated or (not attacker_defeated and _total_hull(world, attacker_survivors, ship_definitions) >= _total_hull(world, defender_survivors, ship_definitions))
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
	var total := 0
	for ship_id in _ships_of(world, fleet_ids):
		total += _raw_hull(world.get_ship(ship_id), ship_definitions)
	return total


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
static func _combat_power(world: CampaignWorldState, ship_ids: Array, ship_definitions: ShipDefinitions, stat: String) -> int:
	var total := 0
	var admirals_applied := {}
	for ship_id in ship_ids:
		var ship := world.get_ship(ship_id)
		var definition_id := String(ship.get("definition_id", ""))
		if not ship_definitions.has_ship(definition_id):
			continue
		var definition := ship_definitions.ship(definition_id)
		var power := int(definition.get(stat, 0)) * int(ship.get("hull_bp", 0)) / BASIS_POINTS
		var fleet_id := String(ship.get("fleet_id", ""))
		if not admirals_applied.has(fleet_id):
			admirals_applied[fleet_id] = true
			var admiral_id := String(world.get_fleet(fleet_id).get("admiral_id", ""))
			if world.character_registry.has(admiral_id):
				var admiral: Dictionary = world.character_registry[admiral_id]
				if bool(admiral.get("alive", false)):
					var martial := int((admiral.get("skills", {}) as Dictionary).get("martial", 5))
					power = power * (BASIS_POINTS + (martial - 5) * 500) / BASIS_POINTS
		total += power
	return total


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
	battle["status"] = "completed"
	battle["end_day"] = world.current_day
	battle["winner_side"] = "attacker" if attacker_won else "defender"
	world.naval_battle_registry[battle_id] = battle
	var war_id := String(battle.get("war_id", ""))
	if world.war_registry.has(war_id):
		var war: Dictionary = world.war_registry[war_id]
		var score := clampi((int(battle.get("attacker_hull_lost", 0)) + int(battle.get("defender_hull_lost", 0))) / 500, 1, 10)
		war["battle_score_attacker"] = int(war.get("battle_score_attacker", 0)) + (score if attacker_won else -score)
		world.war_registry[war_id] = war
	events.naval_battle_ended.emit(war_id, battle_id, String(battle["winner_side"]))


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
		world.fleet_registry.erase(fleet_id)
		events.fleet_destroyed.emit(fleet_id, "no_legal_retreat")
		return
	if destination_id == zone_id:
		fleet["location_status"] = CampaignWorldState.FLEET_LOCATION_DOCKED if graph.is_port_province(zone_id) else CampaignWorldState.FLEET_LOCATION_AT_SEA
		world.fleet_registry[fleet_id] = fleet
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
	events.fleet_retreat_started.emit(fleet_id, destination_id)
