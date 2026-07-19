extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const StartingNavalForcesScript = preload("res://scripts/simulation/starting_naval_forces.gd")

const OWNERS := {213: "ARA", 1749: "CAS", 235: "ENG", 4111: "FRA", 227: "POR"}
const NAMES := {"ARA": "Aragon", "CAS": "Castile", "ENG": "England", "FRA": "France", "POR": "Portugal"}


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Starting naval forces test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize(OWNERS, NAMES, "grand_world_1444", 14441111)
	EconomySystemScript.initialize_world(world)
	world.army_registry.clear()
	return world


func _run() -> void:
	var content = StartingNavalForcesScript.load_for_scenario("grand_world_1444")
	_require(content.is_valid(), "the source-tracked content must validate: %s" % content.error())
	_require(content.fleets().size() == 5, "G1 needs England, France, Portugal, Castile, and Aragon starting fleets")
	var world := _make_world()
	_require(content.initialize_world(world).is_empty(), "valid starting fleets must initialize")
	_require(world.fleet_registry.size() == 5 and world.ship_registry.size() == 22, "the five capability fleets must create 22 unique ship records")
	var seen := {}
	for raw_fleet_id in world.fleet_registry:
		var fleet_id := String(raw_fleet_id)
		var fleet: Dictionary = world.fleet_registry[fleet_id]
		_require(world.get_province_owner(int(fleet.get("home_port_id", -1))) == String(fleet.get("owner_country_id", "")), "%s must use an owned home port" % fleet_id)
		for raw_ship_id in (fleet.get("ship_ids", []) as Array):
			var ship_id := String(raw_ship_id)
			_require(not seen.has(ship_id), "%s must belong to exactly one fleet" % ship_id)
			seen[ship_id] = true
			_require(String(world.get_ship(ship_id).get("fleet_id", "")) == fleet_id, "%s must agree with its fleet membership" % ship_id)
	_require(int(world.get_fleet("starting_fleet_eng_channel")["aggregate"]["total_transport_capacity"]) >= 2000, "England must carry the Channel acceptance army")
	_require(int(world.get_fleet("starting_fleet_fra_atlantic")["aggregate"]["total_transport_capacity"]) >= 2000, "France must support a reverse crossing")
	for tag in ["POR", "CAS", "ARA"]:
		var fleets := world.country_fleets(tag)
		_require(fleets.size() == 1 and int(world.get_fleet(fleets[0])["aggregate"]["total_transport_capacity"]) >= 1000, "%s must have a combat-and-transport fixture" % tag)
	for tag in NAMES:
		_require(bool(world.country_runtime(String(tag)).get("naval_ai_controlled", false)), "%s must be eligible for naval AI when it is not player-controlled" % String(tag))
	_require(String(world.global_flags.get("starting_naval_content_status", "")) == "approved_gameplay_placeholder", "placeholder status must be explicit in authoritative state")

	var checksum := world.checksum()
	var loaded := _make_world()
	_require(loaded.apply_save_dict(world.to_save_dict("starting-naval-test")).is_empty(), "starting fleets must save and load")
	_require(loaded.checksum() == checksum, "starting fleet save/load must preserve checksum")
	_require(content.initialize_world(loaded).is_empty() and loaded.fleet_registry.size() == 5, "initialization must be idempotent and never duplicate a loaded navy")
	print("Starting naval forces test passed. fleets=%d ships=%d" % [world.fleet_registry.size(), world.ship_registry.size()])
	quit(0)
