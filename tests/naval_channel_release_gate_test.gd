extends SceneTree

## Final G1 naval release-gate scenario. This deliberately crosses subsystem
## boundaries instead of re-testing individual formulas in isolation. Every
## fixed seed is executed twice and the terminal checksum is compared.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const FleetLogisticsSystemScript = preload("res://scripts/simulation/fleet_logistics_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")
const ConstructShipCommandScript = preload("res://scripts/simulation/commands/construct_ship_command.gd")
const MergeFleetsCommandScript = preload("res://scripts/simulation/commands/merge_fleets_command.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")
const SetFleetMissionCommandScript = preload("res://scripts/simulation/commands/set_fleet_mission_command.gd")
const OfferPeaceCommandScript = preload("res://scripts/simulation/commands/offer_peace_command.gd")
const AcceptPeaceCommandScript = preload("res://scripts/simulation/commands/accept_peace_command.gd")

const CALAIS := 87
const PICARDIE := 89
const KENT := 235
const STRAITS_OF_DOVER := 1271
const SEED_COUNT := 100
const MAX_WAIT_DAYS := 50

var _failure_counts: Dictionary = {}
var _failure_samples: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _record_failure(code: String, seed_index: int, detail: String, record_failures: bool) -> void:
	if not record_failures:
		return
	_failure_counts[code] = int(_failure_counts.get(code, 0)) + 1
	if not _failure_samples.has(code):
		_failure_samples[code] = "seed=%d %s" % [seed_index, detail]


func _check(condition: bool, code: String, seed_index: int, detail: String, record_failures: bool) -> bool:
	if condition:
		return true
	_record_failure(code, seed_index, detail, record_failures)
	return false


func _make_world(seed_index: int) -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", PICARDIE: "FRA", KENT: "ENG", STRAITS_OF_DOVER: ""},
		{"ENG": "England", "FRA": "France"},
		"naval_channel_release_gate",
		14440000 + seed_index
	)
	EconomySystemScript.initialize_world(world)
	world.army_registry.clear()
	var army := CampaignWorldStateScript.make_army_record("army_eng", "ENG", KENT)
	army["regiment_count"] = 1
	army["strength"] = 1000
	army["maximum_strength"] = 1000
	world.army_registry["army_eng"] = army
	world.war_registry["war_channel"] = {
		"war_id": "war_channel",
		"name": "England-France Channel audit war",
		"status": "active",
		"start_day": world.current_day,
		"attacker_leader": "ENG",
		"defender_leader": "FRA",
		"attackers": ["ENG"],
		"defenders": ["FRA"],
		"war_goal": {"type": "conquer_province", "province_id": PICARDIE, "target_country": "FRA", "justification": "claim", "peace_cost": 15},
		"battles": {},
		"sieges": {},
		"occupied_provinces": {},
		"peace_offers": {},
		"battle_score_attacker": 0,
		"occupation_score_attacker": 0,
		"ticking_score_attacker": 0,
		"blockade_score_attacker": 0,
		"total_war_score": 0,
		"history": [],
	}
	for tag in ["ENG", "FRA"]:
		var runtime := world.country_runtime(tag)
		runtime["treasury"] = 100000000
		runtime["sailors"] = int(runtime.get("maximum_sailors", 0))
		world.set_country_runtime(tag, runtime)
	return world


func _make_scheduler(world: CampaignWorldState, events: SimulationEventBus) -> SimulationScheduler:
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world) -> void: FleetMovementSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world) -> void: NavalCombatSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world) -> void: BlockadeSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world) -> void: EconomySystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world) -> void: FleetLogisticsSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world) -> void: TransportSystemScript.process_day(day_world, events))
	scheduler.monthly_systems.append(func(month_world) -> void: EconomySystemScript.process_month(month_world, events))
	scheduler.monthly_systems.append(func(month_world) -> void: FleetLogisticsSystemScript.process_month(month_world, events))
	return scheduler


func _queue_fast_construction(world: CampaignWorldState, events: SimulationEventBus, country: String, port_id: int, definition_id: String, seed_index: int, record_failures: bool) -> bool:
	var command := ConstructShipCommandScript.new(country, port_id, definition_id)
	var failure := command.validate(world)
	if not _check(failure.is_empty(), "CONSTRUCTION_REJECTED", seed_index, "%s %d %s: %s" % [country, port_id, definition_id, failure], record_failures):
		return false
	command.apply(world, events)
	var construction_ids := world.naval_construction_registry.keys()
	construction_ids.sort()
	for raw_id in construction_ids:
		var record: Dictionary = world.naval_construction_registry[raw_id]
		if String(record.get("country_tag", "")) == country and int(record.get("port_id", -1)) == port_id and String(record.get("definition_id", "")) == definition_id:
			record["completion_day"] = world.current_day + 1
			world.naval_construction_registry[raw_id] = record
			return true
	_record_failure("CONSTRUCTION_RECORD_MISSING", seed_index, "%s %d %s" % [country, port_id, definition_id], record_failures)
	return false


func _wait_until(scheduler: SimulationScheduler, condition: Callable, maximum_days: int = MAX_WAIT_DAYS) -> bool:
	for day in range(maximum_days + 1):
		if bool(condition.call()):
			return true
		if day < maximum_days:
			scheduler.advance_one_day()
	return false


func _fleet_at(world: CampaignWorldState, country: String, location_id: int) -> String:
	for fleet_id in world.country_fleets(country):
		if int(world.get_fleet(fleet_id).get("location_id", -1)) == location_id:
			return fleet_id
	return ""


func _validate_world_invariants(world: CampaignWorldState) -> String:
	var seen_ships := {}
	for raw_fleet_id in world.fleet_registry:
		var fleet_id := String(raw_fleet_id)
		var fleet: Dictionary = world.fleet_registry[raw_fleet_id]
		for raw_ship_id in (fleet.get("ship_ids", []) as Array):
			var ship_id := String(raw_ship_id)
			if seen_ships.has(ship_id):
				return "ship %s belongs to multiple fleets" % ship_id
			seen_ships[ship_id] = true
			if not world.ship_registry.has(ship_id):
				return "fleet %s references missing ship %s" % [fleet_id, ship_id]
			if String((world.ship_registry[ship_id] as Dictionary).get("fleet_id", "")) != fleet_id:
				return "ship %s and fleet %s disagree" % [ship_id, fleet_id]
		for raw_operation_id in (fleet.get("transport_operation_ids", []) as Array):
			if not world.transport_operation_registry.has(String(raw_operation_id)):
				return "fleet %s references missing transport %s" % [fleet_id, String(raw_operation_id)]
	for raw_operation_id in world.transport_operation_registry:
		var operation_id := String(raw_operation_id)
		var operation: Dictionary = world.transport_operation_registry[raw_operation_id]
		var army_id := String(operation.get("army_id", ""))
		var fleet_id := String(operation.get("fleet_id", ""))
		if not world.army_registry.has(army_id):
			return "operation %s references missing army" % operation_id
		if not world.fleet_registry.has(fleet_id):
			return "operation %s references missing fleet" % operation_id
		if String(world.get_army(army_id).get("transport_operation_id", "")) != operation_id:
			return "operation %s and army disagree" % operation_id
		if not (world.get_fleet(fleet_id).get("transport_operation_ids", []) as Array).has(operation_id):
			return "operation %s and fleet disagree" % operation_id
		if int(operation.get("reserved_capacity", -1)) < 0:
			return "operation %s has negative reservation" % operation_id
	for raw_battle_id in world.naval_battle_registry:
		var battle_id := String(raw_battle_id)
		var battle: Dictionary = world.naval_battle_registry[raw_battle_id]
		if String(battle.get("status", "")) != "active":
			continue
		var war_id := String(battle.get("war_id", ""))
		if not world.war_registry.has(war_id) or String((world.war_registry[war_id] as Dictionary).get("status", "")) != "active":
			return "active naval battle %s belongs to an ended/missing war" % battle_id
		for raw_fleet_id in (battle.get("attacker_fleets", []) as Array) + (battle.get("defender_fleets", []) as Array):
			var fleet_id := String(raw_fleet_id)
			if not world.fleet_registry.has(fleet_id) or String(world.get_fleet(fleet_id).get("battle_id", "")) != battle_id:
				return "active battle %s and fleet %s disagree" % [battle_id, fleet_id]
	return ""


func _reload_world(world: CampaignWorldState, seed_index: int) -> Dictionary:
	var saved := world.to_save_dict("naval_release_gate")
	var reloaded := _make_world(seed_index)
	var error := reloaded.apply_save_dict(saved)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	return {"world": reloaded, "events": events, "scheduler": _make_scheduler(reloaded, events), "error": error}


func _run_scenario(seed_index: int, record_failures: bool) -> String:
	var world := _make_world(seed_index)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := _make_scheduler(world, events)

	# Build both navies through the real construction command/completion path.
	_queue_fast_construction(world, events, "ENG", CALAIS, "war_galley", seed_index, record_failures)
	_queue_fast_construction(world, events, "FRA", PICARDIE, "war_galley", seed_index, record_failures)
	scheduler.advance_one_day()
	_queue_fast_construction(world, events, "ENG", CALAIS, "war_galley", seed_index, record_failures)
	# Build the transport after both escorts have lower stable ship IDs. The
	# current deterministic damage allocator targets in stable-ID order; this
	# fixture is meant to audit the normal crossing, while total carrier loss
	# belongs to the destructive-edge gate.
	_queue_fast_construction(world, events, "ENG", KENT, "transport_cog", seed_index, record_failures)
	scheduler.advance_one_day()
	_check(world.country_ships("ENG").size() == 3 and world.country_ships("FRA").size() == 1, "FLEET_BUILD_COUNT", seed_index, "ENG=%d FRA=%d" % [world.country_ships("ENG").size(), world.country_ships("FRA").size()], record_failures)

	var eng_kent := _fleet_at(world, "ENG", KENT)
	var eng_calais := _fleet_at(world, "ENG", CALAIS)
	var fra_fleet := _fleet_at(world, "FRA", PICARDIE)
	if eng_kent.is_empty() or eng_calais.is_empty() or fra_fleet.is_empty():
		_record_failure("FLEET_BUILD_MISSING", seed_index, "Kent=%s Calais=%s France=%s" % [eng_kent, eng_calais, fra_fleet], record_failures)
		return world.checksum()
	var gather := MoveFleetCommandScript.new(eng_calais, KENT, "ENG")
	_check(gather.validate(world).is_empty(), "GATHER_ROUTE_REJECTED", seed_index, gather.validate(world), record_failures)
	if gather.validate(world).is_empty():
		gather.apply(world, events)
	_wait_until(scheduler, func(): return int(world.get_fleet(eng_calais).get("location_id", -1)) == KENT and String(world.get_fleet(eng_calais).get("location_status", "")) == CampaignWorldStateScript.FLEET_LOCATION_DOCKED)
	var merge := MergeFleetsCommandScript.new("ENG", [eng_kent, eng_calais])
	_check(merge.validate(world).is_empty(), "GATHER_MERGE_REJECTED", seed_index, merge.validate(world), record_failures)
	if merge.validate(world).is_empty():
		merge.apply(world, events)
	var eng_fleet := _fleet_at(world, "ENG", KENT)
	_check(not eng_fleet.is_empty() and world.fleet_ships(eng_fleet).size() == 3, "GATHER_MERGE_RESULT", seed_index, "fleet=%s ships=%d" % [eng_fleet, world.fleet_ships(eng_fleet).size()], record_failures)
	if eng_fleet.is_empty():
		return world.checksum()

	# Embark, save/reload while sailing, and order a French interception.
	var embark := CreateTransportOperationCommandScript.new("ENG", "army_eng", eng_fleet, CALAIS)
	_check(embark.validate(world).is_empty(), "EMBARK_REJECTED", seed_index, embark.validate(world), record_failures)
	if not embark.validate(world).is_empty():
		return world.checksum()
	embark.apply(world, events)
	var operation_id := String(world.get_army("army_eng").get("transport_operation_id", ""))
	var reached_sailing := _wait_until(scheduler, func(): return String(world.get_transport_operation(operation_id).get("state", "")) == CampaignWorldStateScript.TRANSPORT_STATE_SAILING, 12)
	_check(reached_sailing, "SAILING_NOT_REACHED", seed_index, "operation=%s" % operation_id, record_failures)
	if not reached_sailing:
		return world.checksum()
	var before_reload := world.checksum()
	var loaded := _reload_world(world, seed_index)
	_check(String(loaded["error"]).is_empty(), "TRANSPORT_RELOAD_REJECTED", seed_index, String(loaded["error"]), record_failures)
	world = loaded["world"]
	events = loaded["events"]
	scheduler = loaded["scheduler"]
	_check(world.checksum() == before_reload, "TRANSPORT_RELOAD_DRIFT", seed_index, "checksum changed", record_failures)

	fra_fleet = _fleet_at(world, "FRA", PICARDIE)
	var intercept := MoveFleetCommandScript.new(fra_fleet, STRAITS_OF_DOVER, "FRA")
	_check(intercept.validate(world).is_empty(), "INTERCEPT_ORDER_REJECTED", seed_index, intercept.validate(world), record_failures)
	if intercept.validate(world).is_empty():
		intercept.apply(world, events)
	var battle_started := _wait_until(scheduler, func(): return not world.naval_battle_registry.is_empty(), 5)
	_check(battle_started, "INTERCEPTION_NOT_TRIGGERED", seed_index, "no Channel battle", record_failures)
	var battle_id := ""
	if battle_started:
		var battle_ids := world.naval_battle_registry.keys()
		battle_ids.sort()
		battle_id = String(battle_ids[0])
		var operation := world.get_transport_operation(operation_id)
		_check(String(operation.get("battle_pause_reference", "")) == battle_id, "TRANSPORT_BATTLE_NOT_LINKED", seed_index, "state=%s battle_ref=%s expected=%s" % [String(operation.get("state", "")), String(operation.get("battle_pause_reference", "")), battle_id], record_failures)
		var battle_reload := _reload_world(world, seed_index)
		_check(String(battle_reload["error"]).is_empty(), "BATTLE_RELOAD_REJECTED", seed_index, String(battle_reload["error"]), record_failures)
		if String(battle_reload["error"]).is_empty():
			world = battle_reload["world"]
			events = battle_reload["events"]
			scheduler = battle_reload["scheduler"]
	var battle_completed := battle_id.is_empty() or _wait_until(scheduler, func(): return String(world.get_naval_battle(battle_id).get("status", "")) == "completed", 40)
	_check(battle_completed, "BATTLE_NOT_TERMINAL", seed_index, "battle=%s" % battle_id, record_failures)

	# The surviving carrier must resume and disembark exactly once.
	var transport_terminal := _wait_until(scheduler, func(): return not world.transport_operation_registry.has(operation_id), 20)
	_check(transport_terminal, "TRANSPORT_STRANDED_AFTER_BATTLE", seed_index, "operation=%s" % operation_id, record_failures)
	if world.army_registry.has("army_eng"):
		var army := world.get_army("army_eng")
		_check(int(army.get("current_province_id", -1)) == CALAIS, "DISEMBARK_WRONG_PROVINCE", seed_index, "province=%d" % int(army.get("current_province_id", -1)), record_failures)
		_check(String(army.get("transport_operation_id", "")).is_empty() and not bool(army.get("movement_locked", false)), "DISEMBARK_DANGLING_ARMY", seed_index, "army still locked/referenced", record_failures)
		_check(world.armies_in_province(CALAIS).count("army_eng") == 1 and not world.armies_in_province(KENT).has("army_eng"), "DISEMBARK_DUPLICATION", seed_index, "land presence is not unique", record_failures)
	else:
		_record_failure("TRANSPORT_ARMY_LOST", seed_index, "army did not survive the main crossing", record_failures)
	_check(TransportSystemScript.reserved_capacity(world, eng_fleet) == 0, "CAPACITY_LEAK_AFTER_LANDING", seed_index, "fleet=%s" % eng_fleet, record_failures)

	# Apply and remove a blockade against Picardie.
	if world.fleet_registry.has(eng_fleet):
		var to_zone := MoveFleetCommandScript.new(eng_fleet, STRAITS_OF_DOVER, "ENG")
		if to_zone.validate(world).is_empty():
			to_zone.apply(world, events)
		_wait_until(scheduler, func(): return int(world.get_fleet(eng_fleet).get("location_id", -1)) == STRAITS_OF_DOVER and String(world.get_fleet(eng_fleet).get("location_status", "")) == CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, 10)
		var blockade := SetFleetMissionCommandScript.new("ENG", eng_fleet, "blockade")
		_check(blockade.validate(world).is_empty(), "BLOCKADE_ORDER_REJECTED", seed_index, blockade.validate(world), record_failures)
		if blockade.validate(world).is_empty():
			blockade.apply(world, events)
		BlockadeSystemScript.process_day(world, events)
		_check(int(world.blockaded_provinces.get(str(PICARDIE), 0)) > 0, "BLOCKADE_NOT_APPLIED", seed_index, "Picardie bp=%d" % int(world.blockaded_provinces.get(str(PICARDIE), 0)), record_failures)
		var idle := SetFleetMissionCommandScript.new("ENG", eng_fleet, "idle")
		if idle.validate(world).is_empty():
			idle.apply(world, events)
		BlockadeSystemScript.process_day(world, events)
		_check(not world.blockaded_provinces.has(str(PICARDIE)), "BLOCKADE_NOT_REMOVED", seed_index, "Picardie remained blockaded", record_failures)

	# End the war while a second transport/interception is active. Release
	# approval requires peace to unwind battle and transport references.
	if world.army_registry.has("army_eng") and world.fleet_registry.has(eng_fleet):
		var return_port := MoveFleetCommandScript.new(eng_fleet, CALAIS, "ENG")
		if return_port.validate(world).is_empty():
			return_port.apply(world, events)
		_wait_until(scheduler, func(): return int(world.get_fleet(eng_fleet).get("location_id", -1)) == CALAIS and String(world.get_fleet(eng_fleet).get("location_status", "")) == CampaignWorldStateScript.FLEET_LOCATION_DOCKED, 10)
		var second_embark := CreateTransportOperationCommandScript.new("ENG", "army_eng", eng_fleet, KENT)
		if second_embark.validate(world).is_empty():
			second_embark.apply(world, events)
			var second_operation := String(world.get_army("army_eng").get("transport_operation_id", ""))
			_wait_until(scheduler, func(): return String(world.get_transport_operation(second_operation).get("state", "")) == CampaignWorldStateScript.TRANSPORT_STATE_SAILING, 12)
			fra_fleet = _fleet_at(world, "FRA", PICARDIE)
			if fra_fleet.is_empty():
				# A deterministic replacement represents a surviving French reserve
				# for the peace-lifecycle portion, not a construction assertion.
				fra_fleet = "fra_release_gate_reserve"
				world.fleet_registry[fra_fleet] = CampaignWorldStateScript.make_fleet_record(fra_fleet, "FRA", PICARDIE)
				var replacement_ship := "fra_release_gate_ship"
				world.ship_registry[replacement_ship] = CampaignWorldStateScript.make_ship_record(replacement_ship, "FRA", fra_fleet, "war_galley", world.current_day)
				var replacement := world.get_fleet(fra_fleet)
				replacement["ship_ids"] = [replacement_ship]
				world.fleet_registry[fra_fleet] = replacement
				FleetSystemScript.recompute_aggregate(world, fra_fleet)
			var second_intercept := MoveFleetCommandScript.new(fra_fleet, STRAITS_OF_DOVER, "FRA")
			if second_intercept.validate(world).is_empty():
				second_intercept.apply(world, events)
			_wait_until(scheduler, func():
				for active_battle in world.naval_battle_registry.values():
					if String((active_battle as Dictionary).get("status", "")) == "active":
						return true
				return false
			, 6)
			var offer := OfferPeaceCommandScript.new("war_channel", "ENG", "FRA", [{"type": "white_peace"}])
			_check(offer.validate(world).is_empty(), "PEACE_OFFER_REJECTED", seed_index, offer.validate(world), record_failures)
			if offer.validate(world).is_empty():
				offer.apply(world, events)
				var offer_ids := (world.war_registry["war_channel"]["peace_offers"] as Dictionary).keys()
				offer_ids.sort()
				var accept := AcceptPeaceCommandScript.new("war_channel", String(offer_ids[0]), "FRA")
				if accept.validate(world).is_empty():
					accept.apply(world, events)
			_check(String((world.war_registry["war_channel"] as Dictionary).get("status", "")) == "ended", "WAR_DID_NOT_END", seed_index, "white peace failed", record_failures)
			scheduler.advance_days(5)
			_check(not world.transport_operation_registry.has(second_operation), "PEACE_TRANSPORT_NOT_RESOLVED", seed_index, "operation=%s" % second_operation, record_failures)
	var invariant_error := _validate_world_invariants(world)
	_check(invariant_error.is_empty(), "TERMINAL_INVARIANT_FAILURE", seed_index, invariant_error, record_failures)
	return world.checksum()


func _run() -> void:
	var started_ms := Time.get_ticks_msec()
	var seed_count := SEED_COUNT
	if not OS.get_environment("NAVAL_GATE_SEEDS").is_empty():
		seed_count = clampi(int(OS.get_environment("NAVAL_GATE_SEEDS")), 1, SEED_COUNT)
	for seed_index in range(seed_count):
		var first_checksum := _run_scenario(seed_index, true)
		var replay_checksum := _run_scenario(seed_index, false)
		_check(first_checksum == replay_checksum, "DETERMINISTIC_REPLAY_DESYNC", seed_index, "first=%s replay=%s" % [first_checksum, replay_checksum], true)
	var elapsed_ms := Time.get_ticks_msec() - started_ms
	if not _failure_counts.is_empty():
		var codes := _failure_counts.keys()
		codes.sort()
		for raw_code in codes:
			var code := String(raw_code)
			push_error("Naval Channel release gate failed: %s count=%d sample=%s" % [code, int(_failure_counts[code]), String(_failure_samples.get(code, ""))])
		print("Naval Channel release gate FAILED. seeds=%d failures=%d elapsed_ms=%d" % [seed_count, _failure_counts.size(), elapsed_ms])
		quit(1)
		return
	print("Naval Channel release gate passed. seeds=%d replays=%d elapsed_ms=%d" % [seed_count, seed_count, elapsed_ms])
	quit(0)
