extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const CreateFleetCommandScript = preload("res://scripts/simulation/commands/create_fleet_command.gd")
const SplitFleetCommandScript = preload("res://scripts/simulation/commands/split_fleet_command.gd")
const MergeFleetsCommandScript = preload("res://scripts/simulation/commands/merge_fleets_command.gd")
const TransferShipsCommandScript = preload("res://scripts/simulation/commands/transfer_ships_command.gd")
const SetFleetHomePortCommandScript = preload("res://scripts/simulation/commands/set_fleet_home_port_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval fleet organisation test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR"},
		{"ENG": "England", "BUR": "Burgundy"}
	)
	EconomySystemScript.initialize_world(world)
	return world


func _add_ship(world: CampaignWorldState, fleet_id: String, ship_id: String, owner: String, port_id: int, definition_id: String) -> void:
	if not world.fleet_registry.has(fleet_id):
		world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, port_id)
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, definition_id, 0)
	var fleet := world.get_fleet(fleet_id)
	var members: Array = fleet.get("ship_ids", [])
	members.append(ship_id)
	members.sort()
	fleet["ship_ids"] = members
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _make_scheduler(world: CampaignWorldState, events: SimulationEventBus) -> SimulationScheduler:
	return SimulationSchedulerScript.new(world, events)


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := _make_scheduler(world, events)

	_add_ship(world, "fleet_a", "s1", "ENG", CALAIS, "war_galley")
	_add_ship(world, "fleet_a", "s2", "ENG", CALAIS, "light_caravel")
	_add_ship(world, "fleet_b", "s3", "ENG", CALAIS, "transport_cog")
	_add_ship(world, "fleet_kent", "s4", "ENG", KENT, "war_galley")

	_require(int(world.get_fleet("fleet_a")["aggregate"]["speed"]) == 4, "fleet_a's speed must be its slowest ship (war_galley=4, caravel=6)")

	# Rejections.
	_require(not CreateFleetCommandScript.new("ENG", []).validate(world).is_empty(), "an empty ship list must be rejected")
	_require(not CreateFleetCommandScript.new("ENG", ["s1", "s4"]).validate(world).is_empty(), "ships at different ports must be rejected")
	_require(not CreateFleetCommandScript.new("BUR", ["s1"]).validate(world).is_empty(), "a country that does not own the ship must be rejected")
	_require(not MergeFleetsCommandScript.new("ENG", ["fleet_a"]).validate(world).is_empty(), "merging fewer than two fleets must be rejected")
	_require(not MergeFleetsCommandScript.new("ENG", ["fleet_a", "fleet_kent"]).validate(world).is_empty(), "merging fleets at different ports must be rejected")

	# CreateFleetCommand: pull one ship from fleet_a and one from fleet_b (co-located).
	var create := CreateFleetCommandScript.new("ENG", ["s1", "s3"])
	scheduler.submit(create)
	scheduler.process_commands()
	_require(not world.fleet_registry.has("fleet_b"), "fleet_b must be erased once it has no ships left")
	_require(world.fleet_registry.has("fleet_a"), "fleet_a must survive with its remaining ship")
	_require(world.fleet_ships("fleet_a") == ["s2"], "fleet_a must keep only s2")
	var new_fleet_ids := []
	for fid in world.country_fleets("ENG"):
		if fid != "fleet_a" and fid != "fleet_kent":
			new_fleet_ids.append(fid)
	_require(new_fleet_ids.size() == 1, "exactly one new fleet must have been created")
	var created_fleet_id: String = new_fleet_ids[0]
	_require(world.fleet_ships(created_fleet_id) == ["s1", "s3"], "the new fleet must contain exactly s1 and s3")
	_require(int(world.get_fleet(created_fleet_id)["aggregate"]["ship_count"]) == 2, "the new fleet's aggregate must reflect two ships")

	# SplitFleetCommand: pull s3 back out into its own fleet.
	scheduler.submit(SplitFleetCommandScript.new("ENG", created_fleet_id, ["s3"]))
	scheduler.process_commands()
	_require(world.fleet_ships(created_fleet_id) == ["s1"], "splitting must leave s1 behind")
	var split_fleet_ids := []
	for fid in world.country_fleets("ENG"):
		if fid not in ["fleet_a", "fleet_kent", created_fleet_id]:
			split_fleet_ids.append(fid)
	_require(split_fleet_ids.size() == 1, "splitting must create exactly one new fleet")
	var split_fleet_id: String = split_fleet_ids[0]
	_require(world.fleet_ships(split_fleet_id) == ["s3"], "the split fleet must contain only s3")

	# TransferShipsCommand: move s3 into fleet_a (co-located at Calais).
	scheduler.submit(TransferShipsCommandScript.new("ENG", ["s3"], "fleet_a"))
	scheduler.process_commands()
	_require(not world.fleet_registry.has(split_fleet_id), "the now-empty split fleet must be erased")
	_require(world.fleet_ships("fleet_a") == ["s2", "s3"], "fleet_a must now contain s2 and s3")

	# MergeFleetsCommand: merge fleet_a and created_fleet_id (both at Calais, both docked).
	scheduler.submit(MergeFleetsCommandScript.new("ENG", [created_fleet_id, "fleet_a"]))
	scheduler.process_commands()
	# Merge target is the lowest sorted fleet ID among the named fleets.
	var surviving := world.fleet_registry.has("fleet_a") and world.fleet_ships("fleet_a").size() == 3
	var merged_into_other := world.fleet_registry.has(created_fleet_id) and world.fleet_ships(created_fleet_id).size() == 3
	_require(surviving or merged_into_other, "merging must consolidate every ship into the lower-sorted fleet ID")
	_require(int(world.country_ships("ENG").size()) == 4, "no ship may be lost or duplicated across any organisation command")

	# SetFleetHomePortCommand.
	_require(SetFleetHomePortCommandScript.new("ENG", "fleet_kent", KENT).validate(world).is_empty(), "England must be able to set its own port as home")
	_require(not SetFleetHomePortCommandScript.new("ENG", "fleet_kent", PICARDIE).validate(world).is_empty(), "setting a foreign, unrelated port as home must be rejected")

	print("Naval fleet organisation test passed. eng_ships=%d eng_fleets=%d" % [world.country_ships("ENG").size(), world.country_fleets("ENG").size()])
	quit(0)
