extends SceneTree

## FL7.1 headless dense-zone presentation fixture. This deliberately puts
## friendly, allied, neutral and hostile fleets into the same Channel view
## while route, battle and blockade presentation are active. It measures the
## derived marker rebuild rather than simulation work, and proves clustering,
## deterministic cycling and selection remain bounded under overlap.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")

const CALAIS := 87
const PICARDIE := 89
const DOVER := 220
const BLOCKADE_PORT := 197
const STRAITS_OF_DOVER := 1271
const FLEET_COUNT := 120
const REBUILD_SAMPLES := 30
const REBUILD_P95_BUDGET_MS := 5000.0

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Naval dense-zone presentation stress failed: %s" % message)


func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(ceili(float(sorted_values.size()) * fraction) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]


func _add_fleet(world: CampaignWorldState, fleet_id: String, owner: String, location_id: int) -> void:
	world.fleet_registry[fleet_id] = CampaignWorldStateScript.make_fleet_record(fleet_id, owner, CALAIS if owner != "ENG" else DOVER)
	var fleet: Dictionary = world.get_fleet(fleet_id)
	fleet["location_id"] = location_id
	fleet["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA if location_id == STRAITS_OF_DOVER else CampaignWorldStateScript.FLEET_LOCATION_DOCKED
	var ship_id := "%s_ship" % fleet_id
	world.ship_registry[ship_id] = CampaignWorldStateScript.make_ship_record(ship_id, owner, fleet_id, "war_galley", 0)
	fleet["ship_ids"] = [ship_id]
	world.fleet_registry[fleet_id] = fleet
	FleetSystemScript.recompute_aggregate(world, fleet_id)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	if packed == null:
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var simulation = scene.get_node("SimulationController")
	var fleet_markers: FleetMarkerLayer = scene.get_node("FleetMarkerLayer")
	var conflict_markers: ConflictMarkerLayer = scene.get_node("ConflictMarkerLayer")
	_require(simulation.initialized and fleet_markers != null and conflict_markers != null, "main-scene naval presentation dependencies must initialize")
	simulation.choose_player_country("ENG")
	simulation.scheduler.process_commands()
	var world: CampaignWorldState = simulation.world
	world.fleet_registry.clear()
	world.ship_registry.clear()
	world.naval_battle_registry.clear()
	world.war_registry.clear()

	var allied_relation := DiplomacySystemScript.relation(world, "ENG", "POR")
	allied_relation["alliance"] = true
	DiplomacySystemScript.set_relation(world, "ENG", "POR", allied_relation)
	world.war_registry["fl7_dense_war"] = {
		"war_id": "fl7_dense_war", "status": "active",
		"attacker_leader": "ENG", "defender_leader": "FRA",
		"attackers": ["ENG", "POR"], "defenders": ["FRA"],
		"battle_score_attacker": 0,
		"war_goal": {"type": "conquer_province", "province_id": PICARDIE, "target_country": "FRA", "justification": "claim", "peace_cost": 0},
		"battles": {
			"fl7_land_a": {"status": "active", "province_id": PICARDIE},
			"fl7_land_b": {"status": "active", "province_id": PICARDIE},
		},
		"sieges": {str(PICARDIE): {"province_id": PICARDIE, "progress_bp": 5200, "side": 1, "breached": false}},
	}
	world.set_province_owner(PICARDIE, "FRA")

	var owners := ["ENG", "POR", "CAS", "FRA"]
	var locations := [STRAITS_OF_DOVER, STRAITS_OF_DOVER, STRAITS_OF_DOVER, CALAIS, PICARDIE, DOVER]
	for index in FLEET_COUNT:
		var fleet_id := "fl7_dense_%03d" % index
		_add_fleet(world, fleet_id, owners[index % owners.size()], locations[index % locations.size()])

	# Keep one selected player fleet moving while many other markers overlap.
	var selected_id := "fl7_dense_000"
	var selected: Dictionary = world.get_fleet(selected_id)
	selected["location_id"] = STRAITS_OF_DOVER
	selected["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_MOVING
	selected["remaining_path"] = [CALAIS]
	selected["path_index"] = 0
	world.fleet_registry[selected_id] = selected

	# A separate ENG fleet supplies a real blockade contribution away from
	# the deliberately contested Channel stack. A blockade in the Channel
	# itself would correctly drop to zero while hostile at-sea fleets share
	# the zone, which is already covered by the fixture's battle pressure.
	var blockader_id := "fl7_dense_004"
	var blockader: Dictionary = world.get_fleet(blockader_id)
	var blockade_exits := MaritimeGraphScript.load_default().port_exits(BLOCKADE_PORT)
	_require(not blockade_exits.is_empty(), "the secondary blockade fixture port must have a maritime exit")
	world.set_province_owner(BLOCKADE_PORT, "FRA")
	blockader["location_id"] = int(blockade_exits[0])
	blockader["location_status"] = CampaignWorldStateScript.FLEET_LOCATION_AT_SEA
	blockader["mission"] = "blockade"
	blockader["mission_target_ids"] = [int(blockade_exits[0])]
	world.fleet_registry[blockader_id] = blockader

	var battle := CampaignWorldStateScript.make_naval_battle_record("fl7_dense_naval", "fl7_dense_war", STRAITS_OF_DOVER, world.current_day)
	battle["attacker_fleets"] = ["fl7_dense_000", "fl7_dense_001"]
	battle["defender_fleets"] = ["fl7_dense_003", "fl7_dense_007"]
	battle["attacker_countries"] = ["ENG", "POR"]
	battle["defender_countries"] = ["FRA"]
	world.naval_battle_registry["fl7_dense_naval"] = battle

	fleet_markers.set_selected_fleet(selected_id)
	fleet_markers.debug_force_refresh()
	conflict_markers.debug_force_refresh()
	var baseline_signature := fleet_markers.debug_cluster_signature()
	var samples: Array[float] = []
	for _sample in REBUILD_SAMPLES:
		var started := Time.get_ticks_usec()
		fleet_markers.debug_force_refresh()
		conflict_markers.debug_force_refresh()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		_require(fleet_markers.debug_cluster_signature() == baseline_signature, "repeated dense rebuilds must retain a deterministic cluster signature")
	samples.sort()
	var rebuild_p50 := _percentile(samples, 0.50)
	var rebuild_p95 := _percentile(samples, 0.95)
	var rebuild_max := samples[-1] if not samples.is_empty() else 0.0

	_require(fleet_markers.debug_fleet_count() == FLEET_COUNT, "every authoritative fleet must remain represented logically")
	_require(fleet_markers.debug_cluster_count() <= locations.size() + 1, "co-located dense fleets must collapse to a bounded cluster count")
	_require(fleet_markers.debug_marker_instances() == fleet_markers.debug_cluster_count(), "the fleet batch must use one GPU instance per visible cluster, not per logical fleet")
	_require(fleet_markers.debug_route_style() == "moving" and fleet_markers.debug_route_surface_count() > 0, "selection and route geometry must survive dense marker rebuilds")
	_require(conflict_markers.debug_naval_battle_count() == 1, "the simultaneous naval battle must have a persistent marker")
	_require(conflict_markers.debug_blockade_count() >= 1, "the simultaneous blockade must have a persistent marker")
	_require(conflict_markers.debug_battle_count() == 2 and conflict_markers.debug_siege_count() == 1, "land battle and siege presentation must coexist with dense naval presentation")
	_require(rebuild_p95 <= REBUILD_P95_BUDGET_MS, "dense marker rebuild P95 must stay within the conservative headless smoke budget")

	# Locate the largest fleet cluster, then prove repeated clicks cycle rather
	# than making a dense stack unselectable.
	var largest_position := Vector2.ZERO
	var largest_size := 0
	for cluster_index in fleet_markers.debug_cluster_count():
		var position := fleet_markers.debug_cluster_screen_position(cluster_index)
		var marker := fleet_markers.marker_at_screen_position(position)
		var cluster_size := int(marker.get("cluster_size", 0))
		if cluster_size > largest_size:
			largest_size = cluster_size
			largest_position = position
	var cycled_ids: Dictionary = {}
	for _click in mini(largest_size, 12):
		var cycled := fleet_markers.marker_at_screen_position(largest_position)
		cycled_ids[String(cycled.get("fleet_id", ""))] = true
	_require(largest_size >= 20, "the fixture must actually create a materially dense fleet cluster")
	_require(cycled_ids.size() >= mini(largest_size, 12) - 1, "repeated clicks must cycle through dense cluster members deterministically")

	print("Naval dense-zone presentation stress passed. fleets=%d fleet_clusters=%d largest_cluster=%d conflict_clusters=%d rebuild_p50_ms=%.3f rebuild_p95_ms=%.3f rebuild_max_ms=%.3f static_memory_bytes=%d" % [
		FLEET_COUNT, fleet_markers.debug_cluster_count(), largest_size, conflict_markers.debug_cluster_count(), rebuild_p50, rebuild_p95, rebuild_max, int(Performance.get_monitor(Performance.MEMORY_STATIC)),
	])
	quit(1 if _failed else 0)
