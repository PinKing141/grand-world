extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const ConstructShipCommandScript = preload("res://scripts/simulation/commands/construct_ship_command.gd")
const CancelShipConstructionCommandScript = preload("res://scripts/simulation/commands/cancel_ship_construction_command.gd")
const SetNavyMaintenanceCommandScript = preload("res://scripts/simulation/commands/set_navy_maintenance_command.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval economy test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(
		{CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR"},
		{"ENG": "England", "BUR": "Burgundy"}
	)
	EconomySystemScript.initialize_world(world)
	return world


func _make_scheduler(world: CampaignWorldState, events: SimulationEventBus) -> SimulationScheduler:
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.start_of_day_systems.append(
		func(day_world) -> void: EconomySystemScript.process_day(day_world, events)
	)
	scheduler.monthly_systems.append(
		func(month_world) -> void: EconomySystemScript.process_month(month_world, events)
	)
	return scheduler


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := _make_scheduler(world, events)

	# Sailors: England owns two enabled ports, Burgundy owns one.
	var eng_runtime := world.country_runtime("ENG")
	_require(int(eng_runtime["maximum_sailors"]) == 400, "England's two ports must grant 400 maximum sailors")
	_require(int(eng_runtime["sailors"]) == 200, "sailors must seed at half of maximum, like manpower")
	var bur_runtime := world.country_runtime("BUR")
	_require(int(bur_runtime["maximum_sailors"]) == 200, "Burgundy's one port must grant 200 maximum sailors")

	# Validation rejections.
	var foreign_port := ConstructShipCommandScript.new("ENG", PICARDIE, "war_galley")
	_require(not foreign_port.validate(world).is_empty(), "constructing at a foreign-owned port must be rejected")

	var unlocked_too_early := ConstructShipCommandScript.new("ENG", CALAIS, "heavy_ship_of_the_line")
	_require(not unlocked_too_early.validate(world).is_empty(), "constructing an unlocked-in-1600 ship in 1444 must be rejected")

	var unknown_ship := ConstructShipCommandScript.new("ENG", CALAIS, "does_not_exist")
	_require(not unknown_ship.validate(world).is_empty(), "an unknown ship definition must be rejected")

	var non_port := ConstructShipCommandScript.new("ENG", 1271, "war_galley")
	_require(not non_port.validate(world).is_empty(), "a sea zone is not a valid construction port")

	var poor_runtime := world.country_runtime("ENG")
	poor_runtime["treasury"] = 0
	world.set_country_runtime("ENG", poor_runtime)
	var poor := ConstructShipCommandScript.new("ENG", CALAIS, "transport_cog")
	_require(not poor.validate(world).is_empty(), "insufficient treasury must be rejected")
	poor_runtime["treasury"] = 999999999
	poor_runtime["sailors"] = 0
	world.set_country_runtime("ENG", poor_runtime)
	var no_sailors := ConstructShipCommandScript.new("ENG", CALAIS, "transport_cog")
	_require(not no_sailors.validate(world).is_empty(), "insufficient sailors must be rejected")
	# Sailors are clamped to maximum_sailors (400) on every recalculation, so
	# restore a realistic value rather than an arbitrarily large one.
	poor_runtime["sailors"] = int(poor_runtime.get("maximum_sailors", 0))
	world.set_country_runtime("ENG", poor_runtime)

	# Happy path: construct a transport cog at Calais.
	var treasury_before := int(world.country_runtime("ENG")["treasury"])
	var sailors_before := int(world.country_runtime("ENG")["sailors"])
	var construct := ConstructShipCommandScript.new("ENG", CALAIS, "transport_cog")
	_require(construct.validate(world).is_empty(), "a valid construction must be accepted: %s" % construct.validate(world))
	scheduler.submit(construct)
	scheduler.process_commands()
	_require(world.naval_construction_registry.size() == 1, "one naval construction project must be queued")
	var construction_id: String = (world.naval_construction_registry.keys() as Array)[0]
	var construction_record: Dictionary = world.naval_construction_registry[construction_id]
	_require(int(construction_record["port_id"]) == CALAIS, "the construction must be recorded at Calais")
	var runtime_after_start := world.country_runtime("ENG")
	_require(int(runtime_after_start["treasury"]) == treasury_before - 5000, "treasury must be debited the full ship cost upfront")
	_require(int(runtime_after_start["sailors"]) == sailors_before - 60, "sailors must be reserved upfront")

	# Queue cap: a second construction at the same port must be rejected.
	var queue_full := ConstructShipCommandScript.new("ENG", CALAIS, "transport_cog")
	_require(not queue_full.validate(world).is_empty(), "a second construction at the same port must exceed the queue cap")

	# Advance to completion (transport_cog takes 100 days).
	for i in range(101):
		scheduler.advance_one_day()
	_require(world.naval_construction_registry.is_empty(), "the construction must complete and leave the queue")
	var eng_fleets := world.country_fleets("ENG")
	_require(eng_fleets.size() == 1, "completion must create exactly one England fleet")
	var fleet_id: String = eng_fleets[0]
	_require(fleet_id == "reserve_%d_ENG" % CALAIS, "the ship must join the deterministic Calais port reserve fleet")
	var fleet := world.get_fleet(fleet_id)
	_require(int(fleet["home_port_id"]) == CALAIS, "the reserve fleet's home port must be Calais")
	_require(String(fleet["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_DOCKED, "a freshly completed fleet must be docked")
	var ship_ids: Array = fleet["ship_ids"]
	_require(ship_ids.size() == 1, "the reserve fleet must contain the one completed ship")
	var ship := world.get_ship(String(ship_ids[0]))
	_require(String(ship["definition_id"]) == "transport_cog", "the completed ship must be the ordered definition")
	_require(String(ship["owner_country_id"]) == "ENG", "the completed ship must belong to England")

	# Ledger reconciliation: navy_maintenance must reflect the new ship.
	# 35 more days guarantees at least one month boundary (and thus one
	# process_month recalculation) regardless of which calendar month this is.
	for i in range(35):
		scheduler.advance_one_day()
	var ledger: Dictionary = world.country_runtime("ENG")["ledger"]
	_require(int(ledger["navy_maintenance"]) == 200, "navy_maintenance must equal the transport cog's monthly maintenance")
	_require(
		int(ledger["total_expenses"]) >= int(ledger["navy_maintenance"]),
		"total_expenses must include navy_maintenance"
	)

	# FL3.2 closure: SetNavyMaintenanceCommand - the naval mirror of
	# SetArmyMaintenanceCommand (see phase_4_economy_test.gd's own
	# equivalent check), reusing the country_runtime "navy_maintenance_bp"
	# field EconomySystem's ledger calculation already scaled navy_maintenance
	# by, even before any command existed to actually change it.
	_require(not SetNavyMaintenanceCommandScript.new("ENG", 3000).validate(world).is_empty(), "an off-tier maintenance value must be rejected")
	_require(SetNavyMaintenanceCommandScript.new("ENG", 2500).validate(world).is_empty(), "25% is a valid maintenance tier")
	var reduce := SetNavyMaintenanceCommandScript.new("ENG", 2500)
	scheduler.submit(reduce)
	scheduler.process_commands()
	var reduced_ledger: Dictionary = world.country_runtime("ENG")["ledger"]
	_require(int(reduced_ledger["navy_maintenance"]) == 50, "reducing maintenance to 25%% must scale navy_maintenance proportionally: expected 50, got %d" % int(reduced_ledger["navy_maintenance"]))
	_require(int(world.country_runtime("ENG")["navy_maintenance_bp"]) == 2500, "the country's own navy_maintenance_bp must reflect the change")
	scheduler.submit(SetNavyMaintenanceCommandScript.new("ENG", 10000))
	scheduler.process_commands()
	var restored_ledger: Dictionary = world.country_runtime("ENG")["ledger"]
	_require(int(restored_ledger["navy_maintenance"]) == 200, "restoring maintenance to 100%% must restore the full navy_maintenance cost")

	# Cancellation: refund and sailor release.
	var second_world := _make_world()
	var second_events := SimulationEventBusScript.new()
	root.add_child(second_events)
	var second_scheduler := _make_scheduler(second_world, second_events)
	var pre_cancel_treasury := int(second_world.country_runtime("ENG")["treasury"])
	var pre_cancel_sailors := int(second_world.country_runtime("ENG")["sailors"])
	var to_cancel := ConstructShipCommandScript.new("ENG", CALAIS, "transport_cog")
	second_scheduler.submit(to_cancel)
	second_scheduler.process_commands()
	var cancel_id: String = (second_world.naval_construction_registry.keys() as Array)[0]
	second_scheduler.submit(CancelShipConstructionCommandScript.new("ENG", cancel_id))
	second_scheduler.process_commands()
	_require(second_world.naval_construction_registry.is_empty(), "cancellation must remove the construction project")
	var post_cancel_runtime := second_world.country_runtime("ENG")
	_require(int(post_cancel_runtime["treasury"]) == pre_cancel_treasury - 5000 + 2500, "cancellation must refund 50% of the ship cost")
	_require(int(post_cancel_runtime["sailors"]) == pre_cancel_sailors, "cancellation must fully release reserved sailors")

	# Ownership change pauses rather than corrupts an active project.
	var third_world := _make_world()
	var third_events := SimulationEventBusScript.new()
	root.add_child(third_events)
	var third_scheduler := _make_scheduler(third_world, third_events)
	third_scheduler.submit(ConstructShipCommandScript.new("ENG", CALAIS, "transport_cog"))
	third_scheduler.process_commands()
	var paused_id: String = (third_world.naval_construction_registry.keys() as Array)[0]
	third_world.set_province_owner(CALAIS, "BUR")
	for i in range(101):
		third_scheduler.advance_one_day()
	_require(third_world.naval_construction_registry.has(paused_id), "an ownership change must pause, not delete, the construction")
	third_world.set_province_owner(CALAIS, "ENG")
	for i in range(5):
		third_scheduler.advance_one_day()
	_require(not third_world.naval_construction_registry.has(paused_id), "construction must complete once ownership is restored")

	print("Naval economy test passed. eng_max_sailors=%d navy_maintenance=%d" % [int(eng_runtime["maximum_sailors"]), int(ledger["navy_maintenance"])])
	quit(0)
