extends SceneTree

## Phase 3 acceptance checks: canonical graph invariants, deterministic
## pathfinding, day-based movement, and save/load during movement.

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBus = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationScheduler = preload("res://scripts/simulation/simulation_scheduler.gd")
const ProvincePathfinderScript = preload("res://scripts/simulation/province_pathfinder.gd")
const ArmyMovementSystemScript = preload("res://scripts/simulation/army_movement_system.gd")
const MoveArmyCommandScript = preload("res://scripts/simulation/commands/move_army_command.gd")
const CancelArmyMovementCommandScript = preload("res://scripts/simulation/commands/cancel_army_movement_command.gd")

const GIBRALTAR := 226
const CEUTA := 1751
const SKANE := 6
const SJAELLAND := 12
const STOCKHOLM := 1
const ALASKA_WASTELAND := 1810
const COVENTRY := 4372


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 3 movement test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldState.new()
	world.initialize(
		{GIBRALTAR: "CAS", CEUTA: "MOR", STOCKHOLM: "SWE"},
		{"CAS": "Castile", "MOR": "Morocco", "SWE": "Sweden"}
	)
	return world


func _run() -> void:
	var graph := ProvinceGraph.load_default()
	_require(graph.province_count() > 3000, "canonical graph must load")

	# Adjacency invariants: symmetry, no self-connections, sorted neighbours.
	var land_ids := graph.land_province_ids()
	_require(land_ids.size() > 3000, "graph must contain the land provinces")
	for sample_index in range(0, land_ids.size(), 37):
		var province_id := land_ids[sample_index]
		var neighbors := graph.land_neighbors(province_id)
		var previous := -1
		for neighbor in neighbors:
			_require(neighbor != province_id, "province %d must not connect to itself" % province_id)
			_require(neighbor > previous, "neighbours of %d must be sorted ascending" % province_id)
			previous = neighbor
			_require(
				graph.land_neighbors(neighbor).has(province_id),
				"connection %d -> %d must be symmetric" % [province_id, neighbor]
			)

	# Known geography: straits exist exactly where configured.
	_require(graph.is_strait(GIBRALTAR, CEUTA) and graph.is_strait(CEUTA, GIBRALTAR), "Gibraltar strait must exist")
	_require(graph.is_strait(SKANE, SJAELLAND), "Oresund strait must exist")
	_require(not graph.is_strait(GIBRALTAR, SKANE), "unrelated provinces must not be straits")
	_require(graph.land_neighbors(GIBRALTAR).has(CEUTA), "strait must create adjacency")
	_require(graph.is_coastal(STOCKHOLM), "Stockholm must be coastal")
	_require(graph.is_impassable(ALASKA_WASTELAND), "the Alaska wasteland must be impassable")
	_require(not graph.land_neighbors(STOCKHOLM).has(GIBRALTAR), "non-neighbours must stay unconnected")

	# Anchors sit inside their bounding boxes and exist for all land provinces.
	for sample_index in range(0, land_ids.size(), 53):
		var province_id := land_ids[sample_index]
		var anchor := graph.anchor(province_id)
		_require(anchor.x >= 0 and anchor.y >= 0, "province %d needs an anchor" % province_id)

	# Deterministic pathfinding: identical requests, identical routes.
	var world := _make_world()
	var route_a := ProvincePathfinderScript.find_route(graph, world, "CAS", GIBRALTAR, CEUTA)
	var route_b := ProvincePathfinderScript.find_route(graph, world, "CAS", GIBRALTAR, CEUTA)
	_require(bool(route_a["exists"]), "Gibraltar -> Ceuta route must exist")
	_require(route_a["path"] == route_b["path"], "identical requests must return identical routes")
	_require(bool(route_a["uses_strait"]), "the Gibraltar route must report its strait")
	_require(int(route_a["total_cost_days"]) > 0, "routes must cost whole days")

	var impossible := ProvincePathfinderScript.find_route(graph, world, "CAS", GIBRALTAR, COVENTRY)
	_require(not bool(impossible["exists"]), "there must be no land route onto Great Britain")
	_require(not String(impossible["failure_reason"]).is_empty(), "failed routes must explain themselves")
	var into_wasteland := ProvincePathfinderScript.find_route(graph, world, "CAS", GIBRALTAR, ALASKA_WASTELAND)
	_require(not bool(into_wasteland["exists"]), "impassable destinations must be rejected")

	# Day-based movement through the scheduler.
	var events := SimulationEventBus.new()
	root.add_child(events)
	var scheduler := SimulationScheduler.new(world, events)
	scheduler.daily_systems.append(
		func(day_world: CampaignWorldState) -> void:
			ArmyMovementSystemScript.advance_day(day_world, events)
	)
	_require(world.get_army("a_CAS").size() > 0, "the scenario must create a default test army")
	_require(int(world.get_army("a_CAS")["current_province_id"]) == GIBRALTAR, "the test army starts at its country's first province")

	scheduler.submit(MoveArmyCommandScript.new("a_CAS", CEUTA, "CAS"))
	scheduler.process_commands()
	var army := world.get_army("a_CAS")
	_require(String(army["status"]) == "moving", "a valid order must start movement")
	var expected_arrival := int(army["next_arrival_day"])
	_require(expected_arrival > world.current_day, "arrival must be scheduled in the future")

	# Rejected orders must not alter state.
	var checksum_before_bad_order := world.checksum()
	scheduler.submit(MoveArmyCommandScript.new("a_CAS", CEUTA, "SWE"))
	scheduler.process_commands()
	_require(world.checksum() == checksum_before_bad_order, "rejected orders must not change the world")

	# Save during movement, then continue both copies identically.
	var arrival_record := [-1]
	events.army_movement_completed.connect(func(army_id: String, _province: int) -> void:
		if army_id == "a_CAS":
			arrival_record[0] = world.current_day)
	var mid_move_save := world.to_save_dict("test")
	while int(world.get_army("a_CAS")["next_arrival_day"]) >= 0 and world.current_day < expected_arrival + 5:
		scheduler.advance_one_day()
	army = world.get_army("a_CAS")
	_require(int(army["current_province_id"]) == CEUTA, "the army must arrive at Ceuta")
	_require(String(army["status"]) == "idle", "arrival must end the movement")
	_require(arrival_record[0] == expected_arrival, "arrival must happen exactly on the scheduled day")

	var reloaded := _make_world()
	_require(reloaded.apply_save_dict(mid_move_save).is_empty(), "the mid-movement save must load")
	var reloaded_events := SimulationEventBus.new()
	root.add_child(reloaded_events)
	var reloaded_scheduler := SimulationScheduler.new(reloaded, reloaded_events)
	reloaded_scheduler.daily_systems.append(
		func(day_world: CampaignWorldState) -> void:
			ArmyMovementSystemScript.advance_day(day_world, reloaded_events)
	)
	var reloaded_army := reloaded.get_army("a_CAS")
	_require(String(reloaded_army["status"]) == "moving", "loading must preserve active movement")
	_require(int(reloaded_army["next_arrival_day"]) == expected_arrival, "loading must not change the arrival day")
	var reloaded_arrival := [-1]
	reloaded_events.army_movement_completed.connect(func(army_id: String, _province: int) -> void:
		if army_id == "a_CAS":
			reloaded_arrival[0] = reloaded.current_day)
	while int(reloaded.get_army("a_CAS")["next_arrival_day"]) >= 0 and reloaded.current_day < expected_arrival + 5:
		reloaded_scheduler.advance_one_day()
	_require(reloaded_arrival[0] == expected_arrival, "the reloaded campaign must arrive on the same day")
	_require(reloaded.checksum() == world.checksum(), "save/load must preserve movement exactly")

	# Cancelling stops in the current authoritative province.
	scheduler.submit(MoveArmyCommandScript.new("a_CAS", GIBRALTAR, "CAS"))
	scheduler.process_commands()
	scheduler.submit(CancelArmyMovementCommandScript.new("a_CAS", "CAS"))
	scheduler.process_commands()
	army = world.get_army("a_CAS")
	_require(String(army["status"]) == "idle", "cancel must stop the movement")
	_require(int(army["current_province_id"]) == CEUTA, "cancel must keep the army in its current province")

	# Schema 1 saves migrate by recreating default armies.
	var legacy := world.to_save_dict("test")
	legacy["schema_version"] = 1
	legacy.erase("army_registry")
	var migrated := CampaignWorldState.migrate_save_data(legacy)
	_require(int(migrated["schema_version"]) == CampaignWorldState.SAVE_SCHEMA_VERSION, "migration must upgrade the schema")
	_require((migrated["army_registry"] as Dictionary).size() > 0, "migration must recreate default armies")

	print("Phase 3 movement test passed. route=%s arrival_day=%d" % [route_a["path"], expected_arrival])
	quit(0)
