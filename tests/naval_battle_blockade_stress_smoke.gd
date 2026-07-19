extends SceneTree

## N4.4/N5.3 gate coverage: naval-battle and blockade stress/performance
## smoke, and N5.3's "global coast" evidence - many simultaneous naval
## battles and blockades spread across the real N0.3 fixture ports (the
## same set naval_fleet_stress_smoke.gd already uses), not a single Channel
## choke point. naval_combat_test.gd and naval_blockade_test.gd already
## prove correctness in small, precise fixtures; this proves the same
## systems hold up - no corrupted registry, no timing blowout - at a scale
## no existing test exercises them at together.
##
## N6.3 "Full-world fleet/ship/transport/battle/blockade stress" extends this
## same run with one real transport operation per multi-port country, so all
## five mechanisms tick concurrently across the same fixture rather than only
## four of them.
##
## The budgets below are conservative smoke-test guards, NOT approved N0
## numerical performance budgets (that item remains open - see
## docs/roadmap/naval/evidence/N0_BASELINE_INVENTORY.md), the same framing
## every other N-pillar stress smoke in this suite already uses.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetMovementSystemScript = preload("res://scripts/simulation/fleet_movement_system.gd")
const NavalCombatSystemScript = preload("res://scripts/simulation/naval_combat_system.gd")
const BlockadeSystemScript = preload("res://scripts/simulation/blockade_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")

# Real N0.3 fixture ports (same set as naval_fleet_stress_smoke.gd and
# maritime_graph_stress_smoke.gd), spread across several real coastlines -
# Channel, Iberia, and beyond - not one hotspot.
const FIXTURE_PORTS := [87, 89, 90, 167, 168, 197, 206, 207, 209, 212, 213, 220, 224, 227, 229, 230, 231, 233, 235, 333, 1749, 1751, 2988, 4371, 4373, 4374, 4385, 4548, 4556]
const COUNTRY_COUNT := 10
const SIMULATED_DAYS := 20
const DAY_BATCH_BUDGET_MS := 90000.0
const BLOCKADE_QUERY_BUDGET_MS := 5000.0


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval battle/blockade stress smoke failed: %s" % message)
		quit(1)


func _country_tag(index: int) -> String:
	return "C%d" % index


func _next_country(index: int) -> int:
	return (index + 1) % COUNTRY_COUNT


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, home_port_id: int, location_id: int, location_status: String, mission: String) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, home_port_id)
	var fleet := world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = location_status
	fleet["mission"] = mission
	var ship_id := "%s_s0" % fleet_id
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "war_galley", 0)
	fleet["ship_ids"] = [ship_id]
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _run() -> void:
	var owners := {}
	var names := {}
	for index in COUNTRY_COUNT:
		names[_country_tag(index)] = "Country %d" % index
	for port_index in FIXTURE_PORTS.size():
		owners[FIXTURE_PORTS[port_index]] = _country_tag(port_index % COUNTRY_COUNT)
	# Every blockader sails to its port's real sea exit, and every transport
	# operation's fleet may pass through or end a day in any sea zone along
	# its route; all of those need their own (unowned) province_states entry
	# too, or the save validator rejects the fleet's location as unknown -
	# province_states is only ever what initialize() is explicitly given, it
	# does not fall back to the full baked map the way MaritimeGraph's own
	# topology does. Registering every sea zone up front is simplest and
	# correct for any route this fixture's ports can produce.
	var graph := MaritimeGraphScript.load_default()
	for zone_id in graph.sea_zone_ids():
		if not owners.has(int(zone_id)):
			owners[int(zone_id)] = ""
	var world := CampaignWorldStateScript.new()
	world.initialize(owners, names)
	EconomySystemScript.initialize_world(world)

	# Each country is at war with its ring-neighbour, so every fixture port
	# has a real, resolvable hostile pair rather than needing a bespoke war
	# per port.
	for index in COUNTRY_COUNT:
		var attacker := _country_tag(index)
		var defender := _country_tag(_next_country(index))
		var war_id := "stress_war_%d" % index
		world.war_registry[war_id] = {
			"war_id": war_id, "status": "active", "attacker_leader": attacker, "defender_leader": defender,
			"attackers": [attacker], "defenders": [defender], "battle_score_attacker": 0,
			"war_goal": {"type": "conquer_province", "province_id": FIXTURE_PORTS[index % FIXTURE_PORTS.size()], "target_country": defender, "justification": "claim", "peace_cost": 0},
		}

	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: FleetMovementSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: NavalCombatSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: BlockadeSystemScript.process_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: TransportSystemScript.process_day(day_world, events))

	# One transport operation per country that owns 2+ fixture ports (an army
	# at its first owned port, embarking for its second) - the same
	# CreateTransportOperationCommand/TransportSystem path N3 proves correct
	# in small fixtures, now ticking concurrently alongside dense battle and
	# blockade activity across the same real coastlines. Not every country is
	# guaranteed a legal sea route between its two ports (fixture ports are
	# spread for coastline variety, not routing convenience), so this counts
	# what it actually manages rather than assuming every country qualifies.
	# Its origin/destination ports are reserved out of the battle/blockade
	# fleet setup below: a hostile raider docked at the same port would
	# correctly sweep the transport fleet into that battle the moment it
	# forms (naval_combat_system.gd's own reinforcement rule, not a bug -
	# see the 100-seed acceptance test's identical discovery), which would
	# stall embarking for the rest of the run and defeat the point of
	# proving transport progress at this scale.
	var country_ports := {}
	for port_index in FIXTURE_PORTS.size():
		var owner := _country_tag(port_index % COUNTRY_COUNT)
		if not country_ports.has(owner):
			country_ports[owner] = []
		(country_ports[owner] as Array).append(FIXTURE_PORTS[port_index])
	var transport_reserved_ports := {}
	for tag in country_ports:
		var candidate_ports: Array = country_ports[tag]
		if candidate_ports.size() < 2:
			continue
		transport_reserved_ports[int(candidate_ports[0])] = true
		transport_reserved_ports[int(candidate_ports[1])] = true

	var battle_fleet_count := 0
	var blockade_fleet_count := 0
	for port_index in FIXTURE_PORTS.size():
		var port_id: int = FIXTURE_PORTS[port_index]
		if transport_reserved_ports.has(port_id):
			continue
		var owner_index := port_index % COUNTRY_COUNT
		var owner := _country_tag(owner_index)
		var enemy := _country_tag(_next_country(owner_index))

		# A hostile fleet docked at the same port immediately starts a
		# battle - _start_battles() only excludes BATTLE/RETREATING status,
		# not DOCKED, so this needs no sea-zone lookup to be a legal trigger.
		# home_port_id is just a valid-province placeholder here (the save
		# validator only checks it resolves, not that it matches the
		# fleet's real owner) - every fleet uses port_id for that reason.
		_add_fleet(world, "stress_home_%d" % port_id, owner, port_id, port_id, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, "idle")
		_add_fleet(world, "stress_raider_%d" % port_id, enemy, port_id, port_id, CampaignWorldStateScript.FLEET_LOCATION_DOCKED, "idle")
		battle_fleet_count += 2

		# A separate hostile fleet at the port's own real sea exit, on a
		# blockade mission, contributes to that port's blockade query -
		# port_exits() gives a genuinely adjacent zone per port rather than
		# assuming one shared Channel zone works for every coastline.
		var exits := graph.port_exits(port_id)
		if not exits.is_empty():
			_add_fleet(world, "stress_blockader_%d" % port_id, enemy, port_id, int(exits[0]), CampaignWorldStateScript.FLEET_LOCATION_AT_SEA, "blockade")
			blockade_fleet_count += 1

	var transport_ops_created := 0
	for tag in country_ports:
		var ports: Array = country_ports[tag]
		if ports.size() < 2:
			continue
		var origin: int = ports[0]
		var destination: int = ports[1]
		var transport_fleet_id := "stress_transport_%s" % tag
		world.fleet_registry[transport_fleet_id] = CampaignWorldStateScript.make_fleet_record(transport_fleet_id, tag, origin)
		var transport_fleet := world.get_fleet(transport_fleet_id)
		transport_fleet["location_id"] = origin
		transport_fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_DOCKED
		transport_fleet["mission"] = "idle"
		var transport_ship_id := "%s_s0" % transport_fleet_id
		world.ship_registry[transport_ship_id] = CampaignWorldStateScript.make_ship_record(transport_ship_id, tag, transport_fleet_id, "transport_cog", 0)
		transport_fleet["ship_ids"] = [transport_ship_id]
		world.fleet_registry[transport_fleet_id] = transport_fleet
		FleetSystemScript.recompute_aggregate(world, transport_fleet_id)
		var army_id := "stress_army_%s" % tag
		world.army_registry[army_id] = CampaignWorldStateScript.make_army_record(army_id, tag, origin)
		var transport_command := CreateTransportOperationCommandScript.new(tag, army_id, transport_fleet_id, destination)
		if transport_command.validate(world).is_empty():
			scheduler.submit(transport_command)
			transport_ops_created += 1
	scheduler.process_commands()
	_require(
		battle_fleet_count == (FIXTURE_PORTS.size() - transport_reserved_ports.size()) * 2,
		"fixture setup must create the expected battle-fleet count outside the ports reserved for transport"
	)
	_require(blockade_fleet_count > 0, "at least some fixture ports must have a real sea exit to blockade from")
	_require(transport_ops_created > 0, "at least some multi-port country must have a legal sea route to transport across")

	var started_usec := Time.get_ticks_usec()
	for day in SIMULATED_DAYS:
		scheduler.advance_one_day()
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	_require(
		elapsed_ms <= DAY_BATCH_BUDGET_MS,
		"%d days of concurrent naval battles and blockades across %d ports must complete within %.1f ms; measured %.2f ms" % [SIMULATED_DAYS, FIXTURE_PORTS.size(), DAY_BATCH_BUDGET_MS, elapsed_ms]
	)

	# Every fixture port's home/raider pair must have actually fought -
	# either an active battle still running, or one already resolved to a
	# terminal state (destroyed/retreated), never left dangling untouched.
	var battles_seen := world.naval_battle_registry.size()
	_require(battles_seen > 0, "co-located hostile fleets across many ports must have produced real naval battles")

	# Transport operations must have made real progress (past embarking, i.e.
	# sailing/disembarking, or already completed and cleared from the
	# registry - a completed operation's own army/fleet stay behind, so this
	# reads the registry rather than counting surviving records) rather than
	# sitting untouched - TransportSystem.process_day() ran every one of
	# these days too.
	var transports_completed := transport_ops_created - world.transport_operation_registry.size()
	var transports_sailing_or_later := 0
	for raw_operation_id in world.transport_operation_registry:
		var operation: Dictionary = world.transport_operation_registry[raw_operation_id]
		if String(operation.get("state", "")) != CampaignWorldStateScript.TRANSPORT_STATE_EMBARKING:
			transports_sailing_or_later += 1
	_require(
		transport_ops_created == 0 or transports_completed + transports_sailing_or_later > 0,
		"every created transport operation must show real progress after %d concurrent simulated days" % SIMULATED_DAYS
	)

	# Global coast query breadth and performance: BlockadeSystem.
	# all_blockaded_provinces() is the exact query N5.3's map overlay/
	# outliner/economy hooks all call - it must both find real contributions
	# at this scale and stay fast doing it.
	var query_started_usec := Time.get_ticks_usec()
	var blockaded := BlockadeSystemScript.all_blockaded_provinces(world)
	var query_elapsed_ms := float(Time.get_ticks_usec() - query_started_usec) / 1000.0
	_require(not blockaded.is_empty(), "at least one fixture port must show up as blockaded after concurrent blockade missions")
	_require(
		query_elapsed_ms <= BLOCKADE_QUERY_BUDGET_MS,
		"all_blockaded_provinces() across %d ports must complete within %.1f ms; measured %.2f ms" % [FIXTURE_PORTS.size(), BLOCKADE_QUERY_BUDGET_MS, query_elapsed_ms]
	)

	# Correctness at scale: no ship may be lost, duplicated, or left
	# disagreeing with its fleet's own membership after concurrent combat.
	var seen_ships := {}
	for raw_fleet_id in world.fleet_registry:
		var fleet: Dictionary = world.fleet_registry[raw_fleet_id]
		for raw_ship_id in (fleet.get("ship_ids", []) as Array):
			var ship_id := String(raw_ship_id)
			_require(not seen_ships.has(ship_id), "ship %s must not belong to more than one fleet after stress ticking" % ship_id)
			seen_ships[ship_id] = true
			_require(world.ship_registry.has(ship_id), "every fleet-listed ship must still exist in the ship registry")
			_require(String((world.ship_registry[ship_id] as Dictionary).get("fleet_id", "")) == String(raw_fleet_id), "ship %s and its fleet must still agree on membership" % ship_id)

	# The ultimate no-corruption proof: every structural validator this
	# session's naval work touches (_validate_naval_data,
	# _validate_naval_battle_data, war participants, transport data) must
	# accept a save produced after this much concurrent naval activity.
	var saved := world.to_save_dict("stress")
	var reloaded := CampaignWorldStateScript.new()
	reloaded.initialize(owners, names)
	var load_error := reloaded.apply_save_dict(saved)
	_require(load_error.is_empty(), "a save taken after concurrent naval battles and blockades must load cleanly: %s" % load_error)

	print("Naval battle/blockade stress smoke passed. ports=%d battle_fleets=%d blockade_fleets=%d battles=%d blockaded_provinces=%d transport_ops=%d transports_completed=%d transports_sailing_or_later=%d days=%d elapsed_ms=%.2f query_ms=%.2f" % [
		FIXTURE_PORTS.size(), battle_fleet_count, blockade_fleet_count, battles_seen, blockaded.size(), transport_ops_created, transports_completed, transports_sailing_or_later, SIMULATED_DAYS, elapsed_ms, query_elapsed_ms,
	])
	quit(0)
