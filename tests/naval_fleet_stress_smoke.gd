extends SceneTree

## N2.5 gate coverage: fleet/ship-scale stress and performance smoke for the
## N2.4 daily/monthly systems (FleetMovementSystem, FleetLogisticsSystem).
## N1.4's maritime_graph_stress_smoke.gd already stress-tests pure pathfinding;
## this exercises the full per-day/per-month fleet walk those systems perform
## in the real scheduler, at a scale no correctness test so far has used.
##
## The budgets below are conservative smoke-test guards, NOT approved N0
## numerical performance budgets (that item remains open - see
## docs/roadmap/naval/evidence/N0_BASELINE_INVENTORY.md). This catches an
## accidental O(n^2) regression; it does not certify a release-quality target.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const FleetLogisticsSystemScript = preload("res://scripts/simulation/fleet_logistics_system.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")

# Real N0.3 fixture ports (same set as maritime_graph_stress_smoke.gd),
# distributed across ten synthetic countries so each fixture fleet is
# genuinely docked, owned, and supplied at scale - not a degenerate
# single-country case.
const FIXTURE_PORTS := [87, 89, 90, 167, 168, 197, 206, 207, 209, 212, 213, 220, 224, 227, 229, 230, 231, 233, 235, 333, 1749, 1751, 2988, 4371, 4373, 4374, 4385, 4548, 4556]
const COUNTRY_COUNT := 10
const FLEETS_PER_PORT := 10
const SHIPS_PER_FLEET := 3
const SIMULATED_DAYS := 30
const DAY_BATCH_BUDGET_MS := 15000.0


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval fleet stress smoke failed: %s" % message)
		quit(1)


func _country_tag(index: int) -> String:
	return "C%d" % index


func _make_world() -> CampaignWorldState:
	var owners := {}
	var names := {}
	for index in COUNTRY_COUNT:
		names[_country_tag(index)] = "Country %d" % index
	for port_index in FIXTURE_PORTS.size():
		owners[FIXTURE_PORTS[port_index]] = _country_tag(port_index % COUNTRY_COUNT)
	var world := CampaignWorldStateScript.new()
	world.initialize(owners, names)
	EconomySystemScript.initialize_world(world)
	return world


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: FleetMovementSystemScript.advance_day(day_world, events))
	scheduler.start_of_day_systems.append(func(day_world: CampaignWorldState) -> void: FleetLogisticsSystemScript.process_day(day_world, events))
	scheduler.monthly_systems.append(func(month_world: CampaignWorldState) -> void: FleetLogisticsSystemScript.process_month(month_world, events))

	# Ports sharing an owner, so move orders target a friendly destination a
	# fleet can actually legally dock at - MoveFleetCommand correctly rejects
	# a route into a foreign, access-less port, exactly like the real game.
	var ports_by_owner := {}
	for port_index in FIXTURE_PORTS.size():
		var owner_tag := _country_tag(port_index % COUNTRY_COUNT)
		var group: Array = ports_by_owner.get(owner_tag, [])
		group.append(FIXTURE_PORTS[port_index])
		ports_by_owner[owner_tag] = group

	var fleet_count := 0
	var ship_count := 0
	var move_orders := 0
	for port_index in FIXTURE_PORTS.size():
		var port_id: int = FIXTURE_PORTS[port_index]
		var owner := _country_tag(port_index % COUNTRY_COUNT)
		for fleet_index in FLEETS_PER_PORT:
			var fleet_id := "stress_fleet_%d_%d" % [port_id, fleet_index]
			world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, port_id)
			var ship_ids: Array = []
			for ship_index in SHIPS_PER_FLEET:
				var ship_id := "stress_ship_%d_%d_%d" % [port_id, fleet_index, ship_index]
				world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "war_galley", 0)
				ship_ids.append(ship_id)
				ship_count += 1
			var fleet := world.get_fleet(fleet_id)
			fleet["ship_ids"] = ship_ids
			# Half the fleets start pre-damaged so repair is genuinely
			# exercised at scale, not just idle bookkeeping.
			if fleet_index % 2 == 0:
				for ship_id in ship_ids:
					var ship := world.get_ship(ship_id)
					ship["hull_bp"] = 6000
					world.ship_registry[ship_id] = ship
			world.fleet_registry[fleet_id] = fleet
			FleetSystemScript.recompute_aggregate(world, fleet_id)
			fleet_count += 1
			# A third of fleets are ordered to a different, friendly fixture
			# port, so FleetMovementSystem's per-leg revalidation is
			# exercised too.
			if fleet_index % 3 == 0:
				var owned_ports: Array = ports_by_owner[owner]
				var destination: int = owned_ports[(owned_ports.find(port_id) + 1) % owned_ports.size()]
				if destination != port_id:
					var move := MoveFleetCommandScript.new(fleet_id, destination, owner)
					if move.validate(world).is_empty():
						scheduler.submit(move)
						move_orders += 1
	scheduler.process_commands()
	_require(fleet_count == FIXTURE_PORTS.size() * FLEETS_PER_PORT, "fixture setup must create the expected fleet count")
	_require(move_orders > 0, "the fixture must actually exercise fleet movement, not just idle fleets")

	var started_usec := Time.get_ticks_usec()
	for day in SIMULATED_DAYS:
		scheduler.advance_one_day()
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	_require(
		elapsed_ms <= DAY_BATCH_BUDGET_MS,
		"%d days over %d fleets (%d ships) must complete within %.1f ms; measured %.2f ms" % [SIMULATED_DAYS, fleet_count, ship_count, DAY_BATCH_BUDGET_MS, elapsed_ms]
	)

	# Correctness at scale, not just timing: no ship may be lost, duplicated,
	# or left disagreeing with its fleet's own membership list after thirty
	# days of concurrent movement/supply/repair/attrition across every fleet.
	var seen_ships := {}
	for raw_fleet_id in world.fleet_registry:
		var fleet: Dictionary = world.fleet_registry[raw_fleet_id]
		for raw_ship_id in (fleet.get("ship_ids", []) as Array):
			var ship_id := String(raw_ship_id)
			_require(not seen_ships.has(ship_id), "ship %s must not belong to more than one fleet after stress ticking" % ship_id)
			seen_ships[ship_id] = true
			_require(world.ship_registry.has(ship_id), "every fleet-listed ship must still exist in the ship registry")
			_require(String((world.ship_registry[ship_id] as Dictionary).get("fleet_id", "")) == String(raw_fleet_id), "ship %s and its fleet must still agree on membership" % ship_id)
	_require(seen_ships.size() == ship_count, "no ship may be silently lost across a month of stress ticking")

	print("Naval fleet stress smoke passed. fleets=%d ships=%d move_orders=%d days=%d elapsed_ms=%.2f" % [fleet_count, ship_count, move_orders, SIMULATED_DAYS, elapsed_ms])
	quit(0)
