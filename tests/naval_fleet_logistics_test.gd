extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const FleetLogisticsSystemScript = preload("res://scripts/simulation/fleet_logistics_system.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89

# war_galley: cost=8000, sailor_cost=150, repair_rate_bp=500, maximum_hull=800.
const WAR_GALLEY_COST := 8000
const WAR_GALLEY_MAX_HULL := 800
const REPAIR_RATE_BP := 500
const REPAIR_COST_FRACTION_BP := 500


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval fleet logistics test failed: %s" % message)
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
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, port_id)
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, definition_id, 0)
	var fleet := world.get_fleet(fleet_id)
	fleet["ship_ids"] = [ship_id]
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)

	# Supply: a fleet docked at its own port is trivially supplied.
	_add_ship(world, "fleet_1", "s1", "ENG", CALAIS, "war_galley")
	FleetLogisticsSystemScript.recompute_supply(world, events, "fleet_1")
	var fleet := world.get_fleet("fleet_1")
	_require(bool(fleet["supplied"]), "a fleet docked at its own port must be supplied")
	_require(String(fleet["supply_reason"]).is_empty(), "a supplied fleet must have no failure reason")

	# Repair: damage the ship, then verify daily progression, cost, and the
	# aggregate staying in sync, using the ship definition's repair_rate_bp
	# rather than a hardcoded constant.
	var ship := world.get_ship("s1")
	ship["hull_bp"] = 5000
	ship["crew_bp"] = 8000
	world.ship_registry["s1"] = ship
	var runtime := world.country_runtime("ENG")
	var treasury_before := int(runtime["treasury"])
	var sailors_before := int(runtime["sailors"])

	FleetLogisticsSystemScript.process_day(world, events)
	ship = world.get_ship("s1")
	_require(int(ship["hull_bp"]) == 5500, "hull must repair by the ship definition's repair_rate_bp (500) per day")
	_require(int(ship["crew_bp"]) == 8500, "crew must repair by the same repair_rate_bp per day")
	_require(bool(ship["repairing"]), "a partially repaired ship must report repairing=true")
	var expected_daily_cost: int = (WAR_GALLEY_COST * REPAIR_COST_FRACTION_BP / 10000) * REPAIR_RATE_BP / 10000
	runtime = world.country_runtime("ENG")
	_require(int(runtime["treasury"]) == treasury_before - expected_daily_cost, "repair must deduct treasury according to the ship's cost and repair rate")
	_require(int(runtime["sailors"]) < sailors_before, "repair must consume sailors to restore crew")
	fleet = world.get_fleet("fleet_1")
	_require(int(fleet["aggregate"]["total_hull"]) == WAR_GALLEY_MAX_HULL * 5500 / 10000, "the fleet aggregate must reflect the ship's new hull_bp immediately")

	for i in range(9):
		FleetLogisticsSystemScript.process_day(world, events)
	ship = world.get_ship("s1")
	_require(int(ship["hull_bp"]) == 10000, "ten total repair days must fully restore hull from 5000bp")
	_require(int(ship["crew_bp"]) == 10000, "crew (a smaller deficit) must have finished repairing well before hull")
	_require(not bool(ship["repairing"]), "a fully repaired ship must report repairing=false")

	FleetLogisticsSystemScript.process_day(world, events)
	ship = world.get_ship("s1")
	_require(int(ship["hull_bp"]) == 10000 and int(ship["crew_bp"]) == 10000, "a fully repaired ship must not be touched by further repair days")

	# Repair must be gated by treasury: an insufficient treasury blocks hull
	# repair (and only hull - sailors are a separate, independently gated
	# resource) without touching country funds.
	_add_ship(world, "fleet_poor", "s_poor", "ENG", CALAIS, "war_galley")
	var poor_ship := world.get_ship("s_poor")
	poor_ship["hull_bp"] = 5000
	world.ship_registry["s_poor"] = poor_ship
	var poor_runtime := world.country_runtime("ENG")
	poor_runtime["treasury"] = 5
	world.set_country_runtime("ENG", poor_runtime)
	FleetLogisticsSystemScript.process_day(world, events)
	poor_ship = world.get_ship("s_poor")
	_require(int(poor_ship["hull_bp"]) == 5000, "insufficient treasury must block hull repair entirely for that day")
	_require(int(world.country_runtime("ENG")["treasury"]) == 5, "a blocked repair must not deduct any treasury")

	# Repair requires a legal repair port, not just "supplied": a fleet docked
	# somewhere it cannot base (no basing rights) must not repair even if the
	# range query would call it supplied.
	_add_ship(world, "fleet_no_base", "s_no_base", "ENG", PICARDIE, "war_galley")
	var no_base_ship := world.get_ship("s_no_base")
	no_base_ship["hull_bp"] = 5000
	world.ship_registry["s_no_base"] = no_base_ship
	FleetLogisticsSystemScript.process_day(world, events)
	no_base_ship = world.get_ship("s_no_base")
	_require(int(no_base_ship["hull_bp"]) == 5000, "a fleet docked without basing rights must not repair")

	# Attrition: an unsupplied fleet loses hull/crew monthly, floored, and a
	# supplied fleet's ships are never touched by the same pass.
	_add_ship(world, "fleet_stranded", "s_stranded", "ENG", CALAIS, "war_galley")
	var stranded_fleet := world.get_fleet("fleet_stranded")
	stranded_fleet["supplied"] = false
	world.fleet_registry["fleet_stranded"] = stranded_fleet

	FleetLogisticsSystemScript.process_month(world, events)
	var stranded_ship := world.get_ship("s_stranded")
	_require(int(stranded_ship["hull_bp"]) == 9500, "an unsupplied fleet must lose hull to attrition")
	_require(int(stranded_ship["crew_bp"]) == 9500, "an unsupplied fleet must lose crew to attrition")
	var supplied_ship := world.get_ship("s1")
	_require(int(supplied_ship["hull_bp"]) == 10000, "a supplied fleet must be untouched by the same attrition pass")

	for i in range(20):
		FleetLogisticsSystemScript.process_month(world, events)
	stranded_ship = world.get_ship("s_stranded")
	_require(int(stranded_ship["hull_bp"]) == 1000, "attrition must never reduce hull below the defined floor")
	_require(int(stranded_ship["crew_bp"]) == 1000, "attrition must never reduce crew below the defined floor")

	print("Naval fleet logistics test passed. repair_days=10 attrition_floor_bp=1000")
	quit(0)
