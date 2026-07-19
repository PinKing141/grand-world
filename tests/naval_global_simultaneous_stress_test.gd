extends SceneTree

## FL7.2-FL7.6 combined headless fixture. Unlike the focused subsystem
## smokes, this runs combat, movement, logistics, transport, blockades,
## economy/construction and every synthetic country's naval AI together in
## one world. The same seeded scenario is run uninterrupted and through a
## midpoint save/load; terminal checksums must agree.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const FleetLogisticsSystemScript = preload("res://scripts/simulation/fleet_logistics_system.gd")
const FleetMissionSystemScript = preload("res://scripts/simulation/fleet_mission_system.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const CountryDepthSystemScript = preload("res://scripts/simulation/country_depth_system.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const AIDefinitionsScript = preload("res://scripts/simulation/ai_definitions.gd")
const NavalAISystemScript = preload("res://scripts/simulation/naval_ai_system.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")
const ConstructShipCommandScript = preload("res://scripts/simulation/commands/construct_ship_command.gd")

const FIXTURE_PORTS := [87, 89, 90, 167, 168, 197, 206, 207, 209, 212, 213, 220, 224, 227, 229, 230, 231, 233, 235, 333, 1749, 1751, 2988, 4371]
const COUNTRY_COUNT := 8
const SIMULATED_DAYS := 24
const RELOAD_DAYS := [8, 16]
const SIMULATION_BUDGET_MS := 120000.0
const AI_P95_BUDGET_MS := 15000.0

var _failed := false
var _owners: Dictionary = {}
var _names: Dictionary = {}
var _country_ports: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Naval global simultaneous stress failed: %s" % message)


func _tag(index: int) -> String:
	return "G%02d" % index


func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	return sorted_values[clampi(ceili(float(sorted_values.size()) * fraction) - 1, 0, sorted_values.size() - 1)]


func _prepare_static_fixture() -> void:
	_owners.clear()
	_names.clear()
	_country_ports.clear()
	for index in COUNTRY_COUNT:
		var tag := _tag(index)
		_names[tag] = "Global Fleet Country %d" % index
		_country_ports[tag] = []
	for port_index in FIXTURE_PORTS.size():
		var tag := _tag(port_index % COUNTRY_COUNT)
		var port_id: int = FIXTURE_PORTS[port_index]
		_owners[port_id] = tag
		(_country_ports[tag] as Array).append(port_id)
	var graph := MaritimeGraphScript.load_default()
	for raw_zone_id in graph.sea_zone_ids():
		var zone_id := int(raw_zone_id)
		if not _owners.has(zone_id):
			_owners[zone_id] = ""
	# Legal long-distance routes may use an intermediate port as a graph
	# node. Register every port (unowned unless it is one of the fixture's
	# country ports) so a save taken mid-leg can always validate the fleet's
	# authoritative current location.
	for raw_port_id in graph.port_province_ids():
		var port_id := int(raw_port_id)
		if not _owners.has(port_id):
			_owners[port_id] = ""


func _make_definitions() -> AIDefinitions:
	var countries := {}
	for index in COUNTRY_COUNT:
		var tag := _tag(index)
		countries[tag] = {
			"slot": index,
			"capital_province_id": int((_country_ports[tag] as Array)[0]),
			"strategy": "balanced", "objective": "expand",
			"government": "monarchy", "ruler": "Stress Ruler %d" % index,
			"minimum_reserve": 50000,
		}
	return AIDefinitionsScript.from_data({
		"version": 1, "slice_id": "naval_global_simultaneous_stress",
		"start_day": 0, "end_day": 7305, "countries": countries,
	})


func _make_base_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(_owners, _names, "naval_global_simultaneous_stress", 773311)
	EconomySystemScript.initialize_world(world)
	world.player_country = _tag(0)
	for index in COUNTRY_COUNT:
		var tag := _tag(index)
		var runtime := world.country_runtime(tag)
		runtime["treasury"] = 250000
		runtime["sailors"] = 10000
		runtime["country_status"] = "active"
		world.set_country_runtime(tag, runtime)
	world.global_flags["country_depth_active_countries"] = _names.keys()
	return world


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, home_port_id: int, location_id: int, ship_definitions: Array[String], mission := "idle") -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, home_port_id)
	var fleet: Dictionary = world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED if location_id == home_port_id else CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	fleet["mission"] = mission
	var ship_ids: Array[String] = []
	for ship_index in ship_definitions.size():
		var ship_id := "%s_s%d" % [fleet_id, ship_index]
		world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, ship_definitions[ship_index], 0)
		ship_ids.append(ship_id)
	fleet["ship_ids"] = ship_ids
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _add_admiral_candidate(world: CampaignWorldState, character_id: String, employer: String) -> void:
	world.character_registry[character_id] = {
		"character_id": character_id, "name": character_id, "sex": "male",
		"birth": {"year": 1400, "month": 1, "day": 1},
		"alive": true, "death_day": -1, "death_cause": "",
		"culture": "Test", "religion": "Test", "dynasty_id": "",
		"father_id": "", "mother_id": "", "spouse_id": "", "former_spouses": [], "children": [],
		"employer_country": employer,
		"skills": {"diplomacy": 1, "martial": 8, "stewardship": 1, "intrigue": 1, "learning": 1},
		"traits": [], "health_bp": 8000, "fertility_bp": 5000, "stress_bp": 0,
		"titles": [], "claims": [], "event_cooldowns": {}, "last_birth_day": -9999,
		"commander_army_id": "", "admiral_fleet_id": "",
		"illness": "", "illness_until_day": -1, "opinion_modifiers": [], "came_of_age": true,
	}


func _setup_world() -> Dictionary:
	var world := _make_base_world()
	var graph := MaritimeGraphScript.load_default()
	for index in COUNTRY_COUNT:
		var attacker := _tag(index)
		var defender := _tag((index + 1) % COUNTRY_COUNT)
		var war_id := "global_war_%d" % index
		world.war_registry[war_id] = {
			"war_id": war_id, "status": "active",
			"attacker_leader": attacker, "defender_leader": defender,
			"attackers": [attacker], "defenders": [defender], "battle_score_attacker": 0,
			"war_goal": {"type": "conquer_province", "province_id": int((_country_ports[defender] as Array)[0]), "target_country": defender, "justification": "claim", "peace_cost": 0},
		}

	# Three concurrent multi-fleet, multi-ship engagements. Other countries
	# stay lighter so their AI still has a construction deficit to plan for.
	for battle_index in 3:
		var attacker_index := battle_index * 2
		var defender_index := attacker_index + 1
		var attacker := _tag(attacker_index)
		var defender := _tag(defender_index)
		var battle_port := int((_country_ports[attacker] as Array)[2])
		for fleet_index in 2:
			_add_fleet(world, "battle_%d_a_%d" % [battle_index, fleet_index], attacker, battle_port, battle_port, ["war_galley", "war_galley", "war_galley"])
			_add_fleet(world, "battle_%d_d_%d" % [battle_index, fleet_index], defender, battle_port, battle_port, ["war_galley", "war_galley", "war_galley"])

	var setup_commands: Array = []
	for index in COUNTRY_COUNT:
		var tag := _tag(index)
		var ports: Array = _country_ports[tag]
		var origin := int(ports[0])
		var destination := int(ports[1])
		var transport_id := "transport_%s" % tag
		_add_fleet(world, transport_id, tag, origin, origin, ["transport_cog", "war_galley"])
		var army_id := "a_%s" % tag
		var army: Dictionary = world.get_army(army_id)
		army["current_province_id"] = origin
		army["regiment_count"] = 1
		world.army_registry[army_id] = army
		var command := CreateTransportOperationCommandScript.new(tag, army_id, transport_id, destination)
		if command.validate(world).is_empty():
			setup_commands.append(command)

		var exits := graph.port_exits(int(ports[2]))
		if not exits.is_empty():
			_add_fleet(world, "blockader_%s" % tag, tag, origin, int(exits[0]), ["war_galley", "war_galley"], "blockade")
	world.dynasty_registry[""] = {}
	_add_admiral_candidate(world, "global_admiral_old", _tag(6))
	_add_admiral_candidate(world, "global_admiral_replacement", _tag(6))
	var led_fleet: Dictionary = world.get_fleet("blockader_%s" % _tag(6))
	led_fleet["admiral_id"] = "global_admiral_old"
	world.fleet_registry["blockader_%s" % _tag(6)] = led_fleet
	world.character_registry["global_admiral_old"]["admiral_fleet_id"] = "blockader_%s" % _tag(6)
	# Seed one construction through the real command path, then accelerate
	# only its completion date once applied. This keeps the fixture bounded
	# while still exercising economy completion amid combat/transport/AI.
	setup_commands.append(ConstructShipCommandScript.new(_tag(6), int((_country_ports[_tag(6)] as Array)[0]), "war_galley"))
	return {"world": world, "setup_commands": setup_commands}


func _make_runtime(world: CampaignWorldState, definitions: AIDefinitions) -> Dictionary:
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: FleetMovementSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: NavalCombatSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: BlockadeSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: EconomySystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: FleetLogisticsSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: TransportSystemScript.process_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: FleetMissionSystemScript.process_day(day_world, events))
	var naval_ai := NavalAISystemScript.new(scheduler, events, definitions)
	return {"events": events, "scheduler": scheduler, "naval_ai": naval_ai}


func _reload_runtime(world: CampaignWorldState, definitions: AIDefinitions) -> Dictionary:
	var saved := world.to_save_dict("naval_global_simultaneous_stress")
	var reloaded := _make_base_world()
	var load_started := Time.get_ticks_usec()
	var error := reloaded.apply_save_dict(saved)
	var load_ms := float(Time.get_ticks_usec() - load_started) / 1000.0
	var runtime := _make_runtime(reloaded, definitions)
	runtime["world"] = reloaded
	runtime["error"] = error
	runtime["load_ms"] = load_ms
	runtime["save_size"] = JSON.stringify(saved).to_utf8_buffer().size()
	return runtime


func _damage_first_active_carrier(world: CampaignWorldState) -> bool:
	var operation_ids := world.transport_operation_registry.keys()
	operation_ids.sort()
	for raw_operation_id in operation_ids:
		var operation: Dictionary = world.transport_operation_registry[raw_operation_id]
		var fleet_id := String(operation.get("fleet_id", ""))
		var ship_id := ""
		for raw_ship_id in world.fleet_ships(fleet_id):
			var candidate_id := String(raw_ship_id)
			if String(world.get_ship(candidate_id).get("definition_id", "")) == "transport_cog":
				ship_id = candidate_id
				break
		if ship_id.is_empty():
			continue
		var ship: Dictionary = world.ship_registry[ship_id]
		ship["hull_bp"] = 4000
		world.ship_registry[ship_id] = ship
		FleetSystemScript.recompute_aggregate(world, fleet_id)
		return true
	return false


func _validate_membership(world: CampaignWorldState) -> String:
	var seen: Dictionary = {}
	for raw_fleet_id in world.fleet_registry:
		var fleet_id := String(raw_fleet_id)
		var fleet: Dictionary = world.fleet_registry[raw_fleet_id]
		for raw_ship_id in (fleet.get("ship_ids", []) as Array):
			var ship_id := String(raw_ship_id)
			if seen.has(ship_id):
				return "ship %s belongs to multiple fleets" % ship_id
			if not world.ship_registry.has(ship_id):
				return "fleet %s references missing ship %s" % [fleet_id, ship_id]
			if String((world.ship_registry[ship_id] as Dictionary).get("fleet_id", "")) != fleet_id:
				return "ship %s disagrees with fleet %s" % [ship_id, fleet_id]
			seen[ship_id] = true
	for raw_ship_id in world.ship_registry:
		if not seen.has(String(raw_ship_id)):
			return "ship %s is orphaned" % String(raw_ship_id)
	return ""


func _run_scenario(definitions: AIDefinitions, reload_midpoint: bool) -> Dictionary:
	var setup := _setup_world()
	var world: CampaignWorldState = setup["world"]
	var runtime := _make_runtime(world, definitions)
	var scheduler: SimulationScheduler = runtime["scheduler"]
	var events: SimulationEventBus = runtime["events"]
	var naval_ai: NavalAISystem = runtime["naval_ai"]
	for command in (setup["setup_commands"] as Array):
		scheduler.submit(command)
	scheduler.process_commands()
	var transport_ops_created := world.transport_operation_registry.size()
	var accelerated_construction_id := ""
	for raw_construction_id in world.naval_construction_registry:
		var construction: Dictionary = world.naval_construction_registry[raw_construction_id]
		if String(construction.get("country_tag", "")) == _tag(6):
			accelerated_construction_id = String(raw_construction_id)
			construction["completion_day"] = world.current_day + 5
			world.naval_construction_registry[raw_construction_id] = construction
			break
	var ai_samples: Array[float] = []
	var day_samples: Array[float] = []
	var max_battles := 0
	var max_blockades := 0
	var max_transports := transport_ops_created
	var max_fleets := world.fleet_registry.size()
	var max_ships := world.ship_registry.size()
	var damaged_carrier := false
	var admiral_death_clean := false
	var reload_load_ms := 0.0
	var reload_save_size := 0
	var reload_count := 0
	var started := Time.get_ticks_usec()
	for day_index in SIMULATED_DAYS:
		var day_started := Time.get_ticks_usec()
		scheduler.advance_one_day()
		var ai_started := Time.get_ticks_usec()
		naval_ai.process_day(world)
		ai_samples.append(float(Time.get_ticks_usec() - ai_started) / 1000.0)
		scheduler.process_commands()

		# Force a real capacity-loss failure while all other systems continue.
		if day_index == 1:
			damaged_carrier = _damage_first_active_carrier(world)
		if day_index == 5:
			admiral_death_clean = CharacterSystemScript.kill_character(world, events, "global_admiral_old", "stress_fixture").is_empty()
		# End one war during the run and unwind any battle that still belongs
		# to it, exercising peace cleanup under simultaneous global load.
		if day_index == 9:
			var war: Dictionary = world.war_registry.get("global_war_0", {})
			war["status"] = "ended"
			world.war_registry["global_war_0"] = war
			NavalCombatSystemScript.end_war_battles(world, events, "global_war_0", "peace")
		# Remove every land province from one AI country while its naval
		# records coexist with the rest of the stress world. The production
		# reconciliation path must clean fleets, ships, operations,
		# construction and battle/blockade references without disturbing the
		# other seven countries.
		if day_index == 13:
			for province_id in (_country_ports[_tag(7)] as Array):
				world.set_province_owner(int(province_id), _tag(6))
			CountryDepthSystemScript._reconcile_country_status(world, events)

		max_battles = maxi(max_battles, world.naval_battle_registry.size())
		max_blockades = maxi(max_blockades, BlockadeSystemScript.all_blockaded_provinces(world).size())
		max_transports = maxi(max_transports, world.transport_operation_registry.size())
		max_fleets = maxi(max_fleets, world.fleet_registry.size())
		max_ships = maxi(max_ships, world.ship_registry.size())
		day_samples.append(float(Time.get_ticks_usec() - day_started) / 1000.0)

		if reload_midpoint and RELOAD_DAYS.has(day_index + 1):
			var loaded := _reload_runtime(world, definitions)
			_require(String(loaded["error"]).is_empty(), "midpoint mixed-state save must reload cleanly: %s" % String(loaded["error"]))
			events.queue_free()
			world = loaded["world"]
			events = loaded["events"]
			scheduler = loaded["scheduler"]
			naval_ai = loaded["naval_ai"]
			reload_load_ms = float(loaded["load_ms"])
			reload_save_size = maxi(reload_save_size, int(loaded["save_size"]))
			reload_count += 1

	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	ai_samples.sort()
	day_samples.sort()
	var final_saved := world.to_save_dict("naval_global_simultaneous_stress_terminal")
	var validator := _make_base_world()
	var validation_error := validator.apply_save_dict(final_saved)
	var membership_error := _validate_membership(world)
	events.queue_free()
	return {
		"checksum": world.checksum(), "elapsed_ms": elapsed_ms,
		"ai_p50_ms": _percentile(ai_samples, 0.50), "ai_p95_ms": _percentile(ai_samples, 0.95), "ai_max_ms": ai_samples[-1],
		"day_p95_ms": _percentile(day_samples, 0.95), "day_max_ms": day_samples[-1],
		"transport_ops_created": transport_ops_created, "damaged_carrier": damaged_carrier,
		"construction_completed": not accelerated_construction_id.is_empty() and not world.naval_construction_registry.has(accelerated_construction_id),
		"country_extinct": String(world.country_runtime(_tag(7)).get("country_status", "")) == "extinct",
		"admiral_lifecycle": admiral_death_clean and not String((world.character_registry.get("global_admiral_replacement", {}) as Dictionary).get("admiral_fleet_id", "")).is_empty(),
		"max_battles": max_battles, "max_blockades": max_blockades, "max_transports": max_transports,
		"max_fleets": max_fleets, "max_ships": max_ships,
		"ai_planned": int(world.global_counters.get("naval_ai_countries_planned", 0)),
		"ai_commands": int(world.global_counters.get("naval_ai_commands_submitted", 0)),
		"validation_error": validation_error, "membership_error": membership_error,
		"reload_count": reload_count, "reload_load_ms": reload_load_ms, "reload_save_size": reload_save_size,
	}


func _run() -> void:
	_prepare_static_fixture()
	var definitions := _make_definitions()
	_require(definitions.is_valid(), "synthetic global AI roster must validate: %s" % definitions.error())
	var uninterrupted := _run_scenario(definitions, false)
	var reloaded := _run_scenario(definitions, true)
	_require(String(uninterrupted["checksum"]) == String(reloaded["checksum"]), "uninterrupted and midpoint-reloaded runs must produce the same terminal checksum")
	for result in [uninterrupted, reloaded]:
		_require(float(result["elapsed_ms"]) <= SIMULATION_BUDGET_MS, "the combined 24-day simulation must stay inside its conservative headless smoke budget")
		_require(float(result["ai_p95_ms"]) <= AI_P95_BUDGET_MS, "global naval-AI planning P95 must stay inside its conservative headless smoke budget")
		_require(int(result["transport_ops_created"]) > 0, "the combined fixture must create real transport operations")
		_require(bool(result["damaged_carrier"]), "the combined fixture must exercise a real below-threshold carrier damage transition")
		_require(bool(result["construction_completed"]), "a real naval construction must complete under simultaneous load")
		_require(bool(result["country_extinct"]), "country-extinction cleanup must complete under simultaneous load")
		_require(bool(result["admiral_lifecycle"]), "a dead fleet admiral must detach and the AI must assign the available replacement under simultaneous load")
		_require(int(result["max_battles"]) >= 3, "three concurrent multi-fleet naval battles must actually start")
		_require(int(result["max_blockades"]) > 0, "global coast blockade queries must find a real active blockade")
		_require(int(result["ai_planned"]) > 0 and int(result["ai_commands"]) > 0, "naval AI must perform real planning and submit real commands under simultaneous load")
		_require(String(result["validation_error"]).is_empty(), "the terminal mixed world must pass save/load validation: %s" % String(result["validation_error"]))
		_require(String(result["membership_error"]).is_empty(), "the terminal mixed world must preserve fleet/ship invariants: %s" % String(result["membership_error"]))
	_require(int(reloaded["reload_count"]) == RELOAD_DAYS.size(), "the continuation branch must survive both scheduled mixed-state reloads")

	print("Naval global simultaneous stress passed. days=%d transports=%d max_battles=%d max_blockades=%d max_fleets=%d max_ships=%d ai_planned=%d ai_commands=%d uninterrupted_ms=%.2f reload_ms=%.2f ai_p50_ms=%.3f ai_p95_ms=%.3f ai_max_ms=%.3f day_p95_ms=%.3f day_max_ms=%.3f save_bytes=%d load_ms=%.3f checksum=%s" % [
		SIMULATED_DAYS, int(reloaded["transport_ops_created"]), int(reloaded["max_battles"]), int(reloaded["max_blockades"]), int(reloaded["max_fleets"]), int(reloaded["max_ships"]), int(reloaded["ai_planned"]), int(reloaded["ai_commands"]), float(uninterrupted["elapsed_ms"]), float(reloaded["elapsed_ms"]), float(reloaded["ai_p50_ms"]), float(reloaded["ai_p95_ms"]), float(reloaded["ai_max_ms"]), float(reloaded["day_p95_ms"]), float(reloaded["day_max_ms"]), int(reloaded["reload_save_size"]), float(reloaded["reload_load_ms"]), String(reloaded["checksum"]),
	])
	quit(1 if _failed else 0)
