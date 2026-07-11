class_name WarfareSystem
extends RefCounted

## Deterministic daily land warfare prototype. All calculations use integers,
## stable sorted IDs, campaign days, and named RNG streams.

const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")

const BASIS_POINTS := 10000
const RETREAT_MORALE_BP := 2000
const RECOVERY_DAYS := 5
const BASE_SIEGE_DAYS := 20


static func initialize_armies(world: CampaignWorldState) -> void:
	var army_ids := world.army_registry.keys()
	army_ids.sort()
	for raw_army_id in army_ids:
		var army: Dictionary = world.army_registry[raw_army_id]
		army["maximum_strength"] = int(army.get("maximum_strength", maxi(int(army.get("strength", 1000)), 1000)))
		army["morale_bp"] = int(army.get("morale_bp", BASIS_POINTS))
		army["maximum_morale_bp"] = int(army.get("maximum_morale_bp", BASIS_POINTS))
		army["attack"] = int(army.get("attack", 100))
		army["defence"] = int(army.get("defence", 100))
		army["commander_id"] = String(army.get("commander_id", ""))
		army["battle_id"] = String(army.get("battle_id", ""))
		army["retreating"] = bool(army.get("retreating", false))
		army["recovery_until_day"] = int(army.get("recovery_until_day", -1))
		world.army_registry[raw_army_id] = army


static func advance_day(world: CampaignWorldState, events: SimulationEventBus) -> void:
	_recover_armies(world, events)
	if not _has_active_wars(world):
		return
	_join_reinforcements(world, events)
	_resolve_battles(world, events)
	_start_battles(world, events)
	_advance_sieges_and_occupations(world, events)
	_update_war_scores(world, events)


static func _recover_armies(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var army_ids := world.army_registry.keys()
	army_ids.sort()
	for raw_army_id in army_ids:
		var army: Dictionary = world.army_registry[raw_army_id]
		if String(army.get("status", "")) != CampaignWorldState.ARMY_STATUS_RECOVERING:
			continue
		var morale := mini(int(army.get("maximum_morale_bp", BASIS_POINTS)), int(army.get("morale_bp", 0)) + 600)
		army["morale_bp"] = morale
		if world.current_day >= int(army.get("recovery_until_day", -1)) and morale >= 5000:
			army["status"] = CampaignWorldState.ARMY_STATUS_IDLE
			army["movement_locked"] = false
			army["recovery_until_day"] = -1
			events.army_recovered.emit(String(raw_army_id))
		world.army_registry[raw_army_id] = army


static func _start_battles(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var province_armies := _armies_by_province(world)
	var province_ids := province_armies.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var candidates: Array[String] = []
		for raw_army_id in province_armies[raw_province_id]:
			var army_id := String(raw_army_id)
			var army := world.get_army(army_id)
			var status := String(army.get("status", CampaignWorldState.ARMY_STATUS_IDLE))
			if status not in [CampaignWorldState.ARMY_STATUS_BATTLE, CampaignWorldState.ARMY_STATUS_RETREATING]:
				candidates.append(army_id)
		if candidates.size() < 2:
			continue
		var war_id := ""
		for first_index in range(candidates.size()):
			for second_index in range(first_index + 1, candidates.size()):
				var first_owner := String(world.get_army(candidates[first_index]).get("owner_country_id", ""))
				var second_owner := String(world.get_army(candidates[second_index]).get("owner_country_id", ""))
				war_id = DiplomacySystemScript.active_war_between(world, first_owner, second_owner)
				if not war_id.is_empty():
					break
			if not war_id.is_empty():
				break
		if war_id.is_empty():
			continue
		var war: Dictionary = world.war_registry[war_id]
		var attacker_armies: Array[String] = []
		var defender_armies: Array[String] = []
		for army_id in candidates:
			var owner := String(world.get_army(army_id).get("owner_country_id", ""))
			var side := DiplomacySystemScript.side_in_war(war, owner)
			if side > 0:
				attacker_armies.append(army_id)
			elif side < 0:
				defender_armies.append(army_id)
		if attacker_armies.is_empty() or defender_armies.is_empty():
			continue
		var battle_id := "battle_%06d" % world.take_counter("next_battle_id")
		var battle := {
			"battle_id": battle_id,
			"war_id": war_id,
			"province_id": province_id,
			"start_day": world.current_day,
			"last_round_day": -1,
			"round": 0,
			"status": "active",
			"attacker_armies": attacker_armies,
			"defender_armies": defender_armies,
			"attacker_casualties": 0,
			"defender_casualties": 0,
			"terrain": ProvinceGraph.load_default().move_class(province_id),
		}
		var battles: Dictionary = war.get("battles", {})
		battles[battle_id] = battle
		war["battles"] = battles
		world.war_registry[war_id] = war
		for army_id in attacker_armies + defender_armies:
			var army := world.get_army(army_id)
			_cancel_route(army)
			army["status"] = CampaignWorldState.ARMY_STATUS_BATTLE
			army["movement_locked"] = true
			army["battle_id"] = battle_id
			world.army_registry[army_id] = army
		events.battle_started.emit(war_id, battle_id, province_id)


static func _join_reinforcements(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var province_armies := _armies_by_province(world)
	var war_ids := world.war_registry.keys()
	war_ids.sort()
	for raw_war_id in war_ids:
		var war_id := String(raw_war_id)
		var war: Dictionary = world.war_registry[raw_war_id]
		if String(war.get("status", "active")) != "active":
			continue
		var battles: Dictionary = war.get("battles", {})
		var battle_ids := battles.keys()
		battle_ids.sort()
		for raw_battle_id in battle_ids:
			var battle_id := String(raw_battle_id)
			var battle: Dictionary = battles[raw_battle_id]
			if String(battle.get("status", "")) != "active":
				continue
			var province_id := int(battle.get("province_id", -1))
			for raw_army_id in province_armies.get(province_id, []):
				var army_id := String(raw_army_id)
				var army := world.get_army(army_id)
				if not String(army.get("battle_id", "")).is_empty() or String(army.get("status", "")) == CampaignWorldState.ARMY_STATUS_RETREATING:
					continue
				var side := DiplomacySystemScript.side_in_war(war, String(army.get("owner_country_id", "")))
				if side == 0:
					continue
				var field := "attacker_armies" if side > 0 else "defender_armies"
				var participants: Array = battle.get(field, [])
				if participants.has(army_id):
					continue
				participants.append(army_id)
				participants.sort()
				battle[field] = participants
				_cancel_route(army)
				army["status"] = CampaignWorldState.ARMY_STATUS_BATTLE
				army["movement_locked"] = true
				army["battle_id"] = battle_id
				world.army_registry[army_id] = army
				events.battle_reinforced.emit(battle_id, army_id, "attacker" if side > 0 else "defender")
			battles[battle_id] = battle
		war["battles"] = battles
		world.war_registry[war_id] = war


static func _resolve_battles(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var war_ids := world.war_registry.keys()
	war_ids.sort()
	for raw_war_id in war_ids:
		var war_id := String(raw_war_id)
		var war: Dictionary = world.war_registry[raw_war_id]
		if String(war.get("status", "active")) != "active":
			continue
		var battles: Dictionary = war.get("battles", {})
		var battle_ids := battles.keys()
		battle_ids.sort()
		for raw_battle_id in battle_ids:
			var battle_id := String(raw_battle_id)
			var battle: Dictionary = battles[raw_battle_id]
			if String(battle.get("status", "")) != "active" or int(battle.get("last_round_day", -1)) == world.current_day:
				continue
			var attacker_ids := _living_armies(world, battle.get("attacker_armies", []))
			var defender_ids := _living_armies(world, battle.get("defender_armies", []))
			if attacker_ids.is_empty() or defender_ids.is_empty():
				_finish_battle(world, events, war, battle, not attacker_ids.is_empty())
				war = world.war_registry[war_id]
				battles = war.get("battles", {})
				continue
			var attacker_strength := _total_strength(world, attacker_ids)
			var defender_strength := _total_strength(world, defender_ids)
			var attacker_power := _combat_power(world, attacker_ids, "attack")
			var defender_power := _combat_power(world, defender_ids, "attack")
			var terrain_bp := _terrain_defence_bp(String(battle.get("terrain", "plains")))
			var attacker_roll := 1 + int(world.next_random_u32("combat:%s:attacker" % battle_id) % 6)
			var defender_roll := 1 + int(world.next_random_u32("combat:%s:defender" % battle_id) % 6)
			var defender_losses := maxi(10, attacker_power * (80 + attacker_roll * 5) / 100 * BASIS_POINTS / terrain_bp / 20)
			var attacker_losses := maxi(10, defender_power * (80 + defender_roll * 5) / 100 / 20)
			defender_losses = mini(defender_losses, defender_strength)
			attacker_losses = mini(attacker_losses, attacker_strength)
			_apply_casualties(world, attacker_ids, attacker_losses)
			_apply_casualties(world, defender_ids, defender_losses)
			_apply_morale_damage(world, attacker_ids, 350 + attacker_losses * 3000 / maxi(attacker_strength, 1))
			_apply_morale_damage(world, defender_ids, 350 + defender_losses * 3000 / maxi(defender_strength, 1))
			battle["round"] = int(battle.get("round", 0)) + 1
			battle["last_round_day"] = world.current_day
			battle["attacker_casualties"] = int(battle.get("attacker_casualties", 0)) + attacker_losses
			battle["defender_casualties"] = int(battle.get("defender_casualties", 0)) + defender_losses
			battles[battle_id] = battle
			war["battles"] = battles
			world.war_registry[war_id] = war
			events.battle_round_resolved.emit(battle_id, int(battle["round"]), attacker_losses, defender_losses)
			var attacker_defeated := _total_strength(world, attacker_ids) <= 0 or _average_morale(world, attacker_ids) <= RETREAT_MORALE_BP
			var defender_defeated := _total_strength(world, defender_ids) <= 0 or _average_morale(world, defender_ids) <= RETREAT_MORALE_BP
			if attacker_defeated or defender_defeated or int(battle["round"]) >= 30:
				var attacker_won := defender_defeated or (not attacker_defeated and _total_strength(world, attacker_ids) >= _total_strength(world, defender_ids))
				_finish_battle(world, events, war, battle, attacker_won)


static func _finish_battle(world: CampaignWorldState, events: SimulationEventBus, war: Dictionary, battle: Dictionary, attacker_won: bool) -> void:
	var battle_id := String(battle["battle_id"])
	var loser_ids: Array = battle.get("defender_armies", []) if attacker_won else battle.get("attacker_armies", [])
	var winner_ids: Array = battle.get("attacker_armies", []) if attacker_won else battle.get("defender_armies", [])
	for raw_army_id in loser_ids:
		var army_id := String(raw_army_id)
		if not world.army_registry.has(army_id):
			continue
		var army := world.get_army(army_id)
		if int(army.get("strength", 0)) <= 0:
			world.army_registry.erase(army_id)
			events.army_destroyed.emit(army_id, battle_id)
		else:
			_begin_retreat(world, events, army_id, army, int(battle["province_id"]))
	for raw_army_id in winner_ids:
		var army_id := String(raw_army_id)
		if not world.army_registry.has(army_id):
			continue
		var army := world.get_army(army_id)
		if int(army.get("strength", 0)) <= 0:
			world.army_registry.erase(army_id)
			events.army_destroyed.emit(army_id, battle_id)
			continue
		army["battle_id"] = ""
		army["movement_locked"] = true
		army["status"] = CampaignWorldState.ARMY_STATUS_RECOVERING
		army["recovery_until_day"] = world.current_day + RECOVERY_DAYS
		world.army_registry[army_id] = army
	battle["status"] = "completed"
	battle["end_day"] = world.current_day
	battle["winner_side"] = "attacker" if attacker_won else "defender"
	var battles: Dictionary = war.get("battles", {})
	battles[battle_id] = battle
	war["battles"] = battles
	var score := clampi((int(battle.get("attacker_casualties", 0)) + int(battle.get("defender_casualties", 0))) / 100, 1, 10)
	war["battle_score_attacker"] = int(war.get("battle_score_attacker", 0)) + (score if attacker_won else -score)
	var history: Array = war.get("history", [])
	history.append({"day": world.current_day, "type": "battle_ended", "battle_id": battle_id, "winner": battle["winner_side"]})
	war["history"] = history
	world.war_registry[String(war["war_id"])] = war
	events.battle_ended.emit(String(war["war_id"]), battle_id, String(battle["winner_side"]))


static func _begin_retreat(world: CampaignWorldState, events: SimulationEventBus, army_id: String, army: Dictionary, province_id: int) -> void:
	var graph := ProvinceGraph.load_default()
	var owner := String(army.get("owner_country_id", ""))
	var destination := -1
	for neighbor in graph.land_neighbors(province_id):
		if world.get_province_controller(neighbor) == owner or world.get_province_owner(neighbor) == owner:
			destination = neighbor
			break
	army["battle_id"] = ""
	army["movement_locked"] = true
	army["retreating"] = true
	if destination < 0:
		army["status"] = CampaignWorldState.ARMY_STATUS_RECOVERING
		army["retreating"] = false
		army["recovery_until_day"] = world.current_day + RECOVERY_DAYS
	else:
		army["status"] = CampaignWorldState.ARMY_STATUS_RETREATING
		army["destination_province_id"] = destination
		army["remaining_path"] = [destination]
		army["path_index"] = 0
		army["movement_start_day"] = world.current_day
		army["next_arrival_day"] = world.current_day + ProvincePathfinder.leg_cost_days(graph, province_id, destination)
		army["movement_progress"] = 0.0
		events.army_retreat_started.emit(army_id, destination)
	world.army_registry[army_id] = army


static func _advance_sieges_and_occupations(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var province_armies := _armies_by_province(world)
	var war_ids := world.war_registry.keys()
	war_ids.sort()
	for raw_war_id in war_ids:
		var war_id := String(raw_war_id)
		var war: Dictionary = world.war_registry[raw_war_id]
		if String(war.get("status", "active")) != "active":
			continue
		var province_ids := province_armies.keys()
		province_ids.sort()
		var sieges: Dictionary = war.get("sieges", {})
		for raw_province_id in province_ids:
			var province_id := int(raw_province_id)
			var owner := world.get_province_owner(province_id)
			var owner_side := DiplomacySystemScript.side_in_war(war, owner)
			if owner_side == 0:
				continue
			var current_controller := world.get_province_controller(province_id)
			var target_side := owner_side if current_controller != owner else -owner_side
			var besieger_country := ""
			var besieger_side := 0
			var besieging_strength := 0
			for raw_army_id in province_armies[raw_province_id]:
				var army_id := String(raw_army_id)
				var army := world.get_army(army_id)
				if String(army.get("status", "")) in [CampaignWorldState.ARMY_STATUS_BATTLE, CampaignWorldState.ARMY_STATUS_RETREATING]:
					continue
				var country := String(army.get("owner_country_id", ""))
				var side := DiplomacySystemScript.side_in_war(war, country)
				if side == target_side:
					besieger_country = country
					besieger_side = side
					besieging_strength += int(army.get("strength", 0))
			if besieger_side == 0 or besieging_strength < 500:
				continue
			if current_controller == besieger_country:
				continue
			var key := str(province_id)
			var siege: Dictionary = sieges.get(key, {
				"province_id": province_id,
				"besieger_country": besieger_country,
				"side": besieger_side,
				"start_day": world.current_day,
				"progress_bp": 0,
				"fort_level": _fort_level(world, province_id),
				"garrison": 500,
				"breached": false,
			})
			siege["besieger_country"] = besieger_country
			siege["side"] = besieger_side
			var fort_level := int(siege.get("fort_level", 0))
			var daily_progress := BASIS_POINTS / (BASE_SIEGE_DAYS + fort_level * 10)
			if (world.current_day - int(siege.get("start_day", world.current_day))) % 7 == 0:
				daily_progress += int(world.next_random_u32("siege:%s:%d" % [war_id, province_id]) % 201)
			siege["progress_bp"] = mini(BASIS_POINTS, int(siege.get("progress_bp", 0)) + daily_progress)
			sieges[key] = siege
			if int(siege["progress_bp"]) >= BASIS_POINTS:
				_complete_occupation(world, events, war, province_id, besieger_country, besieger_side)
				war = world.war_registry[war_id]
				sieges = war.get("sieges", {})
				sieges.erase(key)
		war["sieges"] = sieges
		world.war_registry[war_id] = war


static func _complete_occupation(world: CampaignWorldState, events: SimulationEventBus, war: Dictionary, province_id: int, controller: String, controller_side: int) -> void:
	var war_id := String(war["war_id"])
	var occupations: Dictionary = war.get("occupied_provinces", {})
	var key := str(province_id)
	var owner := world.get_province_owner(province_id)
	if controller == owner:
		_restore_province_control(world, occupations.get(key, {}), province_id)
		occupations.erase(key)
	else:
		var state: Dictionary = world.province_states[province_id]
		var economy: Dictionary = state.get("economy", {})
		var previous_control := int(economy.get("control_bp", BASIS_POINTS))
		economy["control_bp"] = mini(previous_control, 2500)
		state["economy"] = economy
		world.province_states[province_id] = state
		occupations[key] = {
			"province_id": province_id,
			"controller": controller,
			"side": controller_side,
			"since_day": world.current_day,
			"previous_control_bp": previous_control,
		}
	var old_controller := world.set_province_controller(province_id, controller)
	war["occupied_provinces"] = occupations
	var history: Array = war.get("history", [])
	history.append({"day": world.current_day, "type": "occupation_changed", "province_id": province_id, "controller": controller})
	war["history"] = history
	world.war_registry[war_id] = war
	events.province_controller_changed.emit(province_id, old_controller, controller)
	events.occupation_changed.emit(war_id, province_id, controller)


static func clear_war_occupations(world: CampaignWorldState, events: SimulationEventBus, war: Dictionary) -> void:
	var occupations: Dictionary = war.get("occupied_provinces", {})
	var keys := occupations.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for raw_key in keys:
		var province_id := int(raw_key)
		_restore_province_control(world, occupations[raw_key], province_id)
		var owner := world.get_province_owner(province_id)
		var old_controller := world.set_province_controller(province_id, owner)
		events.province_controller_changed.emit(province_id, old_controller, owner)


static func _restore_province_control(world: CampaignWorldState, occupation: Dictionary, province_id: int) -> void:
	if not world.has_province(province_id):
		return
	var state: Dictionary = world.province_states[province_id]
	var economy: Dictionary = state.get("economy", {})
	if not economy.is_empty():
		economy["control_bp"] = int(occupation.get("previous_control_bp", BASIS_POINTS))
		state["economy"] = economy
		world.province_states[province_id] = state


static func _update_war_scores(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var war_ids := world.war_registry.keys()
	war_ids.sort()
	for raw_war_id in war_ids:
		var war: Dictionary = world.war_registry[raw_war_id]
		if String(war.get("status", "active")) != "active":
			continue
		var occupation_score := 0
		for occupation in (war.get("occupied_provinces", {}) as Dictionary).values():
			occupation_score += int((occupation as Dictionary).get("side", 0)) * 2
		war["occupation_score_attacker"] = clampi(occupation_score, -50, 50)
		if world.current_day > int(war.get("start_day", 0)) and world.current_day % 30 == 0:
			var goal_id := int((war.get("war_goal", {}) as Dictionary).get("province_id", -1))
			var controller := world.get_province_controller(goal_id) if world.has_province(goal_id) else ""
			var goal_side := DiplomacySystemScript.side_in_war(war, controller)
			war["ticking_score_attacker"] = clampi(int(war.get("ticking_score_attacker", 0)) + goal_side, -25, 25)
		var total := clampi(int(war.get("battle_score_attacker", 0)) + int(war.get("occupation_score_attacker", 0)) + int(war.get("ticking_score_attacker", 0)), -100, 100)
		var changed := total != int(war.get("total_war_score", 0))
		war["total_war_score"] = total
		world.war_registry[raw_war_id] = war
		if changed:
			events.war_score_changed.emit(String(raw_war_id), total)


static func _living_armies(world: CampaignWorldState, raw_ids: Array) -> Array[String]:
	var ids: Array[String] = []
	for raw_id in raw_ids:
		var army_id := String(raw_id)
		if world.army_registry.has(army_id) and int(world.get_army(army_id).get("strength", 0)) > 0:
			ids.append(army_id)
	ids.sort()
	return ids


static func _total_strength(world: CampaignWorldState, army_ids: Array) -> int:
	var total := 0
	for raw_id in army_ids:
		total += maxi(0, int(world.get_army(String(raw_id)).get("strength", 0)))
	return total


static func _combat_power(world: CampaignWorldState, army_ids: Array, stat: String) -> int:
	var total := 0
	for raw_id in army_ids:
		var army := world.get_army(String(raw_id))
		total += int(army.get("strength", 0)) * int(army.get(stat, 100)) / 100
	return total


static func _average_morale(world: CampaignWorldState, army_ids: Array) -> int:
	if army_ids.is_empty():
		return 0
	var total := 0
	for raw_id in army_ids:
		total += int(world.get_army(String(raw_id)).get("morale_bp", 0))
	return total / army_ids.size()


static func _apply_casualties(world: CampaignWorldState, army_ids: Array, casualties: int) -> void:
	var remaining := casualties
	var total_before := maxi(_total_strength(world, army_ids), 1)
	for index in range(army_ids.size()):
		var army_id := String(army_ids[index])
		var army := world.get_army(army_id)
		var loss := remaining if index == army_ids.size() - 1 else casualties * int(army.get("strength", 0)) / total_before
		loss = mini(loss, int(army.get("strength", 0)))
		army["strength"] = int(army.get("strength", 0)) - loss
		remaining -= loss
		world.army_registry[army_id] = army


static func _apply_morale_damage(world: CampaignWorldState, army_ids: Array, damage: int) -> void:
	for raw_id in army_ids:
		var army_id := String(raw_id)
		var army := world.get_army(army_id)
		army["morale_bp"] = maxi(0, int(army.get("morale_bp", BASIS_POINTS)) - damage)
		world.army_registry[army_id] = army


static func _terrain_defence_bp(terrain: String) -> int:
	return int({"plains": 10000, "desert": 10500, "forest": 11000, "hills": 11500, "marsh": 12000, "tundra": 11000, "mountains": 13000}.get(terrain, 10000))


static func _fort_level(world: CampaignWorldState, province_id: int) -> int:
	var economy: Dictionary = world.province_states[province_id].get("economy", {})
	return 1 if (economy.get("buildings", []) as Array).has("fort") else 0


static func _cancel_route(army: Dictionary) -> void:
	army["destination_province_id"] = -1
	army["remaining_path"] = []
	army["path_index"] = 0
	army["movement_start_day"] = -1
	army["next_arrival_day"] = -1
	army["movement_progress"] = 0.0


static func _has_active_wars(world: CampaignWorldState) -> bool:
	for war in world.war_registry.values():
		if String((war as Dictionary).get("status", "active")) == "active":
			return true
	return false


static func _armies_by_province(world: CampaignWorldState) -> Dictionary:
	var indexed := {}
	var army_ids := world.army_registry.keys()
	army_ids.sort()
	for raw_army_id in army_ids:
		var province_id := int(world.army_registry[raw_army_id].get("current_province_id", -1))
		if province_id < 0:
			continue
		if not indexed.has(province_id):
			indexed[province_id] = []
		(indexed[province_id] as Array).append(String(raw_army_id))
	return indexed
