extends SceneTree

const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")
const ChangeProvinceOwnerCommand = preload("res://scripts/simulation/commands/change_province_owner_command.gd")
const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")
const CreateTransportOperationCommandScript = preload("res://scripts/simulation/commands/create_transport_operation_command.gd")

# Calais -> Straits of Dover -> Kent, the same real-map Channel fixture route
# used throughout the N2 naval tests.
const CALAIS := 87
const KENT := 235


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Frame-rate determinism test failed: %s" % message)
		quit(1)


func _make_controller(node_name: String) -> GrandWorldSimulationController:
	var data := CountryData.new()
	data.name = "%sCountryData" % node_name
	data.country_id_to_country_name = {"SWE": "Sweden", "DAN": "Denmark"}
	data.country_id_to_color = {"SWE": Color.BLUE, "DAN": Color.RED}
	data.province_id_to_owner = {1: "SWE", 2: "DAN", 3: "SWE"}
	var controller := GrandWorldSimulationController.new()
	controller.name = node_name
	controller.country_data = data
	root.add_child(controller)
	controller.set_process(false)
	controller.set_game_speed(3)
	controller.scheduler.submit(ChangeProvinceOwnerCommand.new(2, "SWE", "test", 50))

	# A moving, then repairing/supply-checked fleet - naval's daily/monthly
	# systems were wired into this same scheduler in N2.4, but nothing had
	# ever put a fleet in this harness's world to actually exercise them.
	controller.world.fleet_registry["fleet_1"] = CampaignWorldStateScript.make_fleet_record("fleet_1", "SWE", CALAIS)
	controller.world.ship_registry["s1"] = CampaignWorldStateScript.make_ship_record("s1", "SWE", "fleet_1", "war_galley", 0)
	var fleet := controller.world.get_fleet("fleet_1")
	fleet["ship_ids"] = ["s1"]
	controller.world.fleet_registry["fleet_1"] = fleet
	FleetSystemScript.recompute_aggregate(controller.world, "fleet_1")
	controller.scheduler.submit(MoveFleetCommandScript.new("fleet_1", KENT, "SWE"))

	# The full N3 Channel transport operation (embark -> sail -> disembark),
	# on an independent second fleet, must also resolve identically across
	# frame rates - 03_N3's own "England-France Channel operation repeats
	# deterministically across seeds/frame rates/game speeds" required test.
	controller.world.army_registry["army_1"] = CampaignWorldStateScript.make_army_record("army_1", "SWE", CALAIS)
	controller.world.fleet_registry["fleet_2"] = CampaignWorldStateScript.make_fleet_record("fleet_2", "SWE", CALAIS)
	controller.world.ship_registry["s2"] = CampaignWorldStateScript.make_ship_record("s2", "SWE", "fleet_2", "transport_cog", 0)
	var transport_fleet := controller.world.get_fleet("fleet_2")
	transport_fleet["ship_ids"] = ["s2"]
	controller.world.fleet_registry["fleet_2"] = transport_fleet
	FleetSystemScript.recompute_aggregate(controller.world, "fleet_2")
	controller.scheduler.submit(CreateTransportOperationCommandScript.new("SWE", "army_1", "fleet_2", KENT))
	return controller


func _run() -> void:
	var at_30_fps := _make_controller("At30Fps")
	var at_120_fps := _make_controller("At120Fps")
	for frame in range(300):
		at_30_fps._process(1.0 / 30.0)
	for frame in range(1200):
		at_120_fps._process(1.0 / 120.0)
	_require(at_30_fps.world.current_day == at_120_fps.world.current_day, "equal elapsed time must schedule the same day count")
	_require(at_30_fps.world.current_day == 100, "ten seconds at speed 3 must advance 100 days")
	_require(String(at_30_fps.world.get_fleet("fleet_1")["location_status"]) == CampaignWorldStateScript.FLEET_LOCATION_DOCKED, "the fleet must have completed its Channel crossing and docked well within 100 days")
	_require(int(at_30_fps.world.get_fleet("fleet_1")["location_id"]) == KENT, "the fleet must have arrived at Kent")
	_require(String(at_30_fps.world.get_fleet("fleet_1")["location_status"]) == String(at_120_fps.world.get_fleet("fleet_1")["location_status"]), "fleet movement must resolve identically across frame rates")
	_require(int(at_30_fps.world.get_fleet("fleet_1")["location_id"]) == int(at_120_fps.world.get_fleet("fleet_1")["location_id"]), "fleet location must match across frame rates")
	_require(String(at_30_fps.world.get_army("army_1")["status"]) == CampaignWorldStateScript.ARMY_STATUS_IDLE, "the transported army must have completed its full embark/sail/disembark journey well within 100 days")
	_require(int(at_30_fps.world.get_army("army_1")["current_province_id"]) == KENT, "the transported army must have disembarked at Kent")
	_require(at_30_fps.world.transport_operation_registry.is_empty(), "a completed transport operation must leave no dangling registry entry")
	_require(String(at_30_fps.world.get_army("army_1")["status"]) == String(at_120_fps.world.get_army("army_1")["status"]), "the transport operation's outcome must resolve identically across frame rates")
	_require(int(at_30_fps.world.get_army("army_1")["current_province_id"]) == int(at_120_fps.world.get_army("army_1")["current_province_id"]), "the transported army's final province must match across frame rates")
	_require(at_30_fps.world.checksum() == at_120_fps.world.checksum(), "30 FPS and 120 FPS runs must produce the same checksum")
	print("Frame-rate determinism test passed. day=%d checksum=%s" % [
		at_30_fps.world.current_day,
		at_30_fps.world.checksum().left(16),
	])
	quit(0)
