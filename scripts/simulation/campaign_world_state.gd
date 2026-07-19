class_name CampaignWorldState
extends RefCounted

const DeterministicRng = preload("res://scripts/simulation/deterministic_rng.gd")

const SAVE_SCHEMA_VERSION := 9
const DEFAULT_SCENARIO_ID := "grand_world_1444"

const ARMY_STATUS_IDLE := "idle"
const ARMY_STATUS_MOVING := "moving"
const ARMY_STATUS_BLOCKED := "blocked"
const ARMY_STATUS_BATTLE := "battle"
const ARMY_STATUS_RETREATING := "retreating"
const ARMY_STATUS_RECOVERING := "recovering"
# Embarking: still land-present (counted by armies_in_province) but locked,
# waiting out the embark-timing formula. Embarked: aboard, absent from land-
# presence queries, following the carrier. See
# docs/roadmap/naval/03_N3_MARITIME_TRANSPORT.md "State Machine".
const ARMY_STATUS_EMBARKING := "embarking"
const ARMY_STATUS_EMBARKED := "embarked"

# N3.1/N3.2 reach four of the full state machine's states - embarking,
# sailing, disembarking, and (implicitly, by record deletion) completed.
# battle_paused is N3.3's job, once combat/interception concepts exist to
# pause for. Cancelling an operation deletes its record rather than
# transitioning it to a terminal state, mirroring CancelShipConstructionCommand.
const TRANSPORT_STATE_EMBARKING := "embarking"
const TRANSPORT_STATE_SAILING := "sailing"
const TRANSPORT_STATE_DISEMBARKING := "disembarking"

# The one authoritative fleet location state, per
# docs/roadmap/naval/00_SCOPE_AND_ARCHITECTURE_LOCK.md "Location".
const FLEET_LOCATION_DOCKED := "docked"
const FLEET_LOCATION_AT_SEA := "at_sea"
const FLEET_LOCATION_MOVING := "moving"
const FLEET_LOCATION_BATTLE := "battle"
const FLEET_LOCATION_RETREATING := "retreating"

# Duplicated from SetFleetMissionCommand.VALID_MISSIONS rather than preloaded
# from it - commands/simulation_command.gd already preloads this very file,
# so preloading a command script back from here would be a cycle. Keep in
# sync with SetFleetMissionCommand.VALID_MISSIONS whenever a mission is
# added or removed (FL2.4 closure audit).
const VALID_FLEET_MISSIONS := [
	"none", "idle", "patrol", "intercept", "protect_transport", "transport",
	"blockade", "protect_coast", "return_to_port", "repair", "trade_protection",
]

var scenario_id := DEFAULT_SCENARIO_ID
var current_day := 0
var player_country := ""
var paused := true
var game_speed := 1
var campaign_seed := 14441111

var province_states: Dictionary = {}
var country_states: Dictionary = {}
var country_to_provinces: Dictionary = {}
var diplomatic_relations: Dictionary = {}
var army_registry: Dictionary = {}
var war_registry: Dictionary = {}
var construction_registry: Dictionary = {}
var recruitment_registry: Dictionary = {}
var loan_registry: Dictionary = {}
var character_registry: Dictionary = {}
var dynasty_registry: Dictionary = {}
var title_registry: Dictionary = {}
var claim_registry: Dictionary = {}
var subject_registry: Dictionary = {}
var country_event_registry: Dictionary = {}
var rebel_faction_registry: Dictionary = {}
var fleet_registry: Dictionary = {}
var ship_registry: Dictionary = {}
var naval_construction_registry: Dictionary = {}
var transport_operation_registry: Dictionary = {}
var naval_battle_registry: Dictionary = {}
var blockaded_provinces: Dictionary = {}
var global_flags: Dictionary = {}
var global_counters: Dictionary = {}
var rng_stream_states: Dictionary = {}


func initialize(
	province_owners: Dictionary,
	country_names: Dictionary,
	p_scenario_id := DEFAULT_SCENARIO_ID,
	p_campaign_seed := 14441111
) -> void:
	scenario_id = p_scenario_id
	campaign_seed = p_campaign_seed
	current_day = 0
	player_country = ""
	paused = true
	game_speed = 1
	province_states.clear()
	country_states.clear()
	diplomatic_relations.clear()
	army_registry.clear()
	war_registry.clear()
	construction_registry.clear()
	recruitment_registry.clear()
	loan_registry.clear()
	character_registry.clear()
	dynasty_registry.clear()
	title_registry.clear()
	claim_registry.clear()
	subject_registry.clear()
	country_event_registry.clear()
	rebel_faction_registry.clear()
	fleet_registry.clear()
	ship_registry.clear()
	naval_construction_registry.clear()
	transport_operation_registry.clear()
	naval_battle_registry.clear()
	blockaded_provinces.clear()
	global_flags.clear()
	global_counters.clear()
	rng_stream_states.clear()

	var country_tags := country_names.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		var tag := String(raw_tag)
		country_states[tag] = {
			"runtime_values": {},
		}

	var province_ids := province_owners.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var imported_owner := String(province_owners[raw_province_id])
		var owner := imported_owner if country_states.has(imported_owner) else ""
		province_states[province_id] = {
			"owner": owner,
			"controller": owner,
		}
	_rebuild_country_index()
	_create_default_armies()


func _create_default_armies() -> void:
	# Phase 3 test setup: every country with territory fields one army at its
	# lowest-ID province. Deterministic: sorted tags, sorted province lists.
	army_registry.clear()
	var country_tags := country_to_provinces.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		var tag := String(raw_tag)
		var provinces: Array = country_to_provinces[raw_tag]
		if provinces.is_empty():
			continue
		var army_id := "a_%s" % tag
		army_registry[army_id] = make_army_record(army_id, tag, int(provinces[0]))


static func make_army_record(army_id: String, owner_tag: String, province_id: int) -> Dictionary:
	return {
		"army_id": army_id,
		"owner_country_id": owner_tag,
		"current_province_id": province_id,
		"destination_province_id": -1,
		"remaining_path": [],
		"path_index": 0,
		"movement_start_day": -1,
		"next_arrival_day": -1,
		"movement_progress": 0.0,
		"movement_locked": false,
		"status": ARMY_STATUS_IDLE,
		"unit_id": "infantry_regiment",
		"regiment_count": 1,
		"strength": 1000,
		"maximum_strength": 1000,
		"morale_bp": 10000,
		"maximum_morale_bp": 10000,
		"attack": 100,
		"defence": 100,
		"commander_id": "",
		"battle_id": "",
		"retreating": false,
		"recovery_until_day": -1,
		"base_monthly_maintenance": 500,
		"transport_operation_id": "",
	}


## N2.1 fleet/ship/construction record shapes. No command yet creates these
## (that is N2.2/N2.3) - this establishes the stable record shape and
## save/checksum/migration wiring per docs/roadmap/naval/02_N2_FLEET_LOGISTICS.md
## "Fleet and Ship Model", matching the existing make_army_record convention.
static func make_fleet_record(fleet_id: String, owner_tag: String, home_port_id: int) -> Dictionary:
	return {
		"fleet_id": fleet_id,
		"owner_country_id": owner_tag,
		"display_name": "",
		"home_port_id": home_port_id,
		"location_status": FLEET_LOCATION_DOCKED,
		"location_id": home_port_id,
		"destination_id": -1,
		"remaining_path": [],
		"path_index": 0,
		"movement_start_day": -1,
		"next_arrival_day": -1,
		"movement_progress": 0.0,
		"movement_locked": false,
		"mission": "idle",
		"mission_target_ids": [],
		"mission_started_day": -1,
		"maintenance_posture_bp": 10000,
		"morale_bp": 10000,
		"supplied": true,
		"supply_reason": "",
		"admiral_id": "",
		"battle_id": "",
		"retreat_destination_id": -1,
		"transport_operation_ids": [],
		"ship_ids": [],
		"aggregate": {
			"ship_count": 0,
			"total_hull": 0,
			"total_maximum_hull": 0,
			"total_attack": 0,
			"total_defence": 0,
			"total_blockade_power": 0,
			"total_transport_capacity": 0,
			"speed": 1,
		},
	}


static func make_ship_record(ship_id: String, owner_tag: String, fleet_id: String, definition_id: String, construction_day: int) -> Dictionary:
	return {
		"ship_id": ship_id,
		"owner_country_id": owner_tag,
		"fleet_id": fleet_id,
		"definition_id": definition_id,
		"name": "",
		"construction_day": construction_day,
		"hull_bp": 10000,
		"crew_bp": 10000,
		"morale_contribution_bp": 10000,
		"captured_from": "",
		"captured_battle_id": "",
		"repairing": false,
		"disabled": false,
	}


static func make_naval_construction_record(
	construction_id: String, country_tag: String, port_id: int, definition_id: String,
	start_day: int, completion_day: int, amount_paid: int
) -> Dictionary:
	return {
		"construction_id": construction_id,
		"country_tag": country_tag,
		"port_id": port_id,
		"definition_id": definition_id,
		"start_day": start_day,
		"completion_day": completion_day,
		"amount_paid": amount_paid,
		"reserved_sailors": 0,
		"status": "in_progress",
	}


## N3A transport operation shape, per
## docs/roadmap/naval/03_N3_MARITIME_TRANSPORT.md "Transport Operation
## Record". Fields belonging to states this slice's commands never reach yet
## (planned_path, battle_pause_reference, accumulated_losses) are still
## present with inert defaults, so N3B/C/D can populate them without another
## schema migration - the same forward-design precedent N2.1's fleet
## "aggregate" sub-dict already established.
static func make_transport_operation_record(
	operation_id: String, country_tag: String, army_id: String, fleet_id: String,
	origin_port_id: int, destination_province_id: int, reserved_capacity: int,
	start_day: int, completion_day: int
) -> Dictionary:
	return {
		"operation_id": operation_id,
		"country_tag": country_tag,
		"army_id": army_id,
		"fleet_id": fleet_id,
		"origin_port_id": origin_port_id,
		"destination_province_id": destination_province_id,
		"reserved_capacity": reserved_capacity,
		"transport_ship_ids": [],
		"state": TRANSPORT_STATE_EMBARKING,
		"state_start_day": start_day,
		"completion_day": completion_day,
		"planned_path": [],
		"current_location_id": origin_port_id,
		"battle_pause_reference": "",
		"accumulated_losses": 0,
		"cancellation_target": origin_port_id,
		"failure_reason": "",
	}


func get_transport_operation(operation_id: String) -> Dictionary:
	return (transport_operation_registry.get(operation_id, {}) as Dictionary).duplicate(true)


## N4A battle record shape, per docs/roadmap/naval/04_N4_NAVAL_COMBAT.md
## "Battle Record". This first slice reaches "active" and "completed" only -
## capture/pursuit/reinforcement fields are deliberately absent rather than
## present-but-unused, since nothing populates or reads them yet (unlike
## N3.1's transport record, which pre-declared fields for a state machine
## that already existed on paper). They will be added when N4C/D build the
## systems that need them, not speculatively now.
static func make_naval_battle_record(battle_id: String, war_id: String, zone_id: int, start_day: int) -> Dictionary:
	return {
		"battle_id": battle_id,
		"war_id": war_id,
		"zone_id": zone_id,
		"start_day": start_day,
		"last_round_day": -1,
		"round": 0,
		"status": "active",
		"attacker_fleets": [],
		"defender_fleets": [],
		"attacker_countries": [],
		"defender_countries": [],
		"attacker_initial_ships": 0,
		"defender_initial_ships": 0,
		"attacker_initial_hull": 0,
		"defender_initial_hull": 0,
		"attacker_positioning_bp": 10000,
		"defender_positioning_bp": 10000,
		"attacker_positioning_breakdown": {},
		"defender_positioning_breakdown": {},
		"attacker_active_ships": [],
		"defender_active_ships": [],
		"attacker_morale_bp": 10000,
		"defender_morale_bp": 10000,
		"attacker_hull_lost": 0,
		"defender_hull_lost": 0,
		"attacker_ships_sunk": 0,
		"defender_ships_sunk": 0,
		"attacker_captured_ship_ids": [],
		"defender_captured_ship_ids": [],
		"attacker_withdrawn_fleet_ids": [],
		"defender_withdrawn_fleet_ids": [],
		"reinforcement_history": [],
		"pursuit_hull_lost": 0,
		"end_reason": "",
		"winner_side": "",
		"end_day": -1,
	}


func get_naval_battle(battle_id: String) -> Dictionary:
	return (naval_battle_registry.get(battle_id, {}) as Dictionary).duplicate(true)


func get_fleet(fleet_id: String) -> Dictionary:
	return (fleet_registry.get(fleet_id, {}) as Dictionary).duplicate(true)


func get_ship(ship_id: String) -> Dictionary:
	return (ship_registry.get(ship_id, {}) as Dictionary).duplicate(true)


func country_fleets(country_tag: String) -> Array[String]:
	var found: Array[String] = []
	var fleet_ids := fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		var fleet: Dictionary = fleet_registry[raw_fleet_id]
		if String(fleet.get("owner_country_id", "")) == country_tag:
			found.append(String(raw_fleet_id))
	return found


func country_ships(country_tag: String) -> Array[String]:
	var found: Array[String] = []
	var ship_ids := ship_registry.keys()
	ship_ids.sort()
	for raw_ship_id in ship_ids:
		var ship: Dictionary = ship_registry[raw_ship_id]
		if String(ship.get("owner_country_id", "")) == country_tag:
			found.append(String(raw_ship_id))
	return found


func fleet_ships(fleet_id: String) -> Array[String]:
	var found: Array[String] = []
	var ship_ids := ship_registry.keys()
	ship_ids.sort()
	for raw_ship_id in ship_ids:
		var ship: Dictionary = ship_registry[raw_ship_id]
		if String(ship.get("fleet_id", "")) == fleet_id:
			found.append(String(raw_ship_id))
	return found


func get_army(army_id: String) -> Dictionary:
	return army_registry.get(army_id, {})


func armies_in_province(province_id: int) -> Array[String]:
	var found: Array[String] = []
	var army_ids := army_registry.keys()
	army_ids.sort()
	for raw_army_id in army_ids:
		var army: Dictionary = army_registry[raw_army_id]
		if String(army.get("status", "")) == ARMY_STATUS_EMBARKED:
			continue
		if int(army.get("current_province_id", -1)) == province_id:
			found.append(String(raw_army_id))
	return found


func country_armies(country_tag: String) -> Array[String]:
	var found: Array[String] = []
	var army_ids := army_registry.keys()
	army_ids.sort()
	for raw_army_id in army_ids:
		var army: Dictionary = army_registry[raw_army_id]
		if String(army.get("owner_country_id", "")) == country_tag:
			found.append(String(raw_army_id))
	return found


static func migrate_save_data(save_data: Dictionary) -> Dictionary:
	var migrated := save_data.duplicate(true)
	var schema := int(migrated.get("schema_version", -1))
	if schema == 1:
		# Phase 2 predates armies. Recreate one deterministic test army for
		# each country represented in the saved ownership.
		var owners: Dictionary = migrated.get("province_owners", {})
		var first_province := {}
		var province_keys := owners.keys()
		province_keys.sort_custom(func(a, b): return int(a) < int(b))
		for key in province_keys:
			var owner := String(owners[key])
			if owner.is_empty() or first_province.has(owner):
				continue
			first_province[owner] = int(key)
		var armies := {}
		var tags := first_province.keys()
		tags.sort()
		for raw_tag in tags:
			var tag := String(raw_tag)
			var army_id := "a_%s" % tag
			armies[army_id] = make_army_record(army_id, tag, int(first_province[raw_tag]))
		migrated["army_registry"] = armies
		schema = 2
	if schema == 2:
		# Phase 4 economy values merge onto the scenario defaults already
		# present in the target world during apply_save_dict.
		migrated["province_economy"] = {}
		migrated["construction_registry"] = {}
		migrated["recruitment_registry"] = {}
		migrated["loan_registry"] = {}
		migrated["migrated_from_schema"] = int(save_data.get("schema_version", 2))
		schema = 3
	if schema == 3:
		# Phase 7 character data is restored from scenario defaults when an old
		# campaign is loaded. New registries remain explicit in schema 4 saves.
		migrated["character_registry"] = {}
		migrated["dynasty_registry"] = {}
		migrated["title_registry"] = {}
		migrated["claim_registry"] = {}
		migrated["migrated_from_schema"] = int(save_data.get("schema_version", 3))
		schema = 4
	if schema == 4:
		migrated["subject_registry"] = {}
		migrated["country_event_registry"] = {}
		migrated["rebel_faction_registry"] = {}
		migrated["migrated_from_schema"] = int(save_data.get("schema_version", 4))
		schema = 5
	if schema == 5:
		# N2.1 naval registries. Pre-naval campaigns simply start with no
		# fleets, no ships, and no naval construction in progress.
		migrated["fleet_registry"] = {}
		migrated["ship_registry"] = {}
		migrated["naval_construction_registry"] = {}
		migrated["migrated_from_schema"] = int(save_data.get("schema_version", 5))
		schema = 6
	if schema == 6:
		# N3A transport registry. Pre-transport campaigns start with no
		# operations in progress - no army can be mid-embarkation in a save
		# that predates the feature.
		migrated["transport_operation_registry"] = {}
		migrated["migrated_from_schema"] = int(save_data.get("schema_version", 6))
		schema = 7
	if schema == 7:
		# N4A naval battle registry. Pre-combat campaigns start with no
		# battles in progress.
		migrated["naval_battle_registry"] = {}
		migrated["migrated_from_schema"] = int(save_data.get("schema_version", 7))
		schema = 8
	if schema == 8:
		# N5 blockade-transition tracking. Pre-blockade campaigns start with
		# no province recorded as currently blockaded - the first post-load
		# BlockadeSystem.process_day() tick establishes the real state and
		# emits blockade_started for anything genuinely blockaded already.
		migrated["blockaded_provinces"] = {}
		migrated["migrated_from_schema"] = int(save_data.get("schema_version", 8))
		schema = 9
	if schema < 1 or schema > SAVE_SCHEMA_VERSION:
		return save_data
	migrated["schema_version"] = SAVE_SCHEMA_VERSION
	return migrated


func country_runtime(country_tag: String) -> Dictionary:
	var country: Dictionary = country_states.get(country_tag, {})
	return (country.get("runtime_values", {}) as Dictionary).duplicate(true)


func set_country_runtime(country_tag: String, runtime: Dictionary) -> void:
	var country: Dictionary = country_states[country_tag]
	country["runtime_values"] = runtime
	country_states[country_tag] = country


func take_counter(counter_name: String) -> int:
	var current := int(global_counters.get(counter_name, 1))
	global_counters[counter_name] = current + 1
	return current


func has_province(province_id: int) -> bool:
	return province_states.has(province_id)


func has_country(country_tag: String) -> bool:
	return country_states.has(country_tag)


func has_character(character_id: String) -> bool:
	return character_registry.has(character_id)


func get_character(character_id: String) -> Dictionary:
	return (character_registry.get(character_id, {}) as Dictionary).duplicate(true)


func set_character(character_id: String, record: Dictionary) -> void:
	character_registry[character_id] = record.duplicate(true)


func living_characters_in_country(country_tag: String) -> Array[String]:
	var result: Array[String] = []
	var ids := character_registry.keys()
	ids.sort()
	for raw_id in ids:
		var record: Dictionary = character_registry[raw_id]
		if bool(record.get("alive", false)) and String(record.get("employer_country", "")) == country_tag:
			result.append(String(raw_id))
	return result


func get_province_owner(province_id: int) -> String:
	var state: Dictionary = province_states.get(province_id, {})
	return String(state.get("owner", ""))


func get_province_controller(province_id: int) -> String:
	var state: Dictionary = province_states.get(province_id, {})
	return String(state.get("controller", ""))


func set_province_owner(province_id: int, new_owner: String) -> String:
	var state: Dictionary = province_states[province_id]
	var old_owner := String(state["owner"])
	if old_owner == new_owner:
		return old_owner
	state["owner"] = new_owner
	province_states[province_id] = state
	if not old_owner.is_empty():
		var old_provinces: Array = country_to_provinces.get(old_owner, [])
		old_provinces.erase(province_id)
	if not new_owner.is_empty():
		var new_provinces: Array = country_to_provinces.get(new_owner, [])
		new_provinces.append(province_id)
		new_provinces.sort()
		country_to_provinces[new_owner] = new_provinces
	return old_owner


func set_province_controller(province_id: int, new_controller: String) -> String:
	var state: Dictionary = province_states[province_id]
	var old_controller := String(state.get("controller", ""))
	state["controller"] = new_controller
	province_states[province_id] = state
	return old_controller


func get_country_provinces(country_tag: String) -> Array:
	return (country_to_provinces.get(country_tag, []) as Array).duplicate()


func next_random_u32(stream_name: String) -> int:
	var state := int(rng_stream_states.get(stream_name, DeterministicRng.stream_seed(campaign_seed, stream_name)))
	state = DeterministicRng.advance(state)
	rng_stream_states[stream_name] = state
	return state


func checksum() -> String:
	var canonical_parts: Array[String] = [
		"schema=%d" % SAVE_SCHEMA_VERSION,
		"scenario=%s" % scenario_id,
		"day=%d" % current_day,
		"player=%s" % player_country,
		"paused=%s" % str(paused),
		"speed=%d" % game_speed,
		"seed=%d" % campaign_seed,
		"flags=%s" % _canonical_variant(global_flags),
		"counters=%s" % _canonical_variant(global_counters),
		"relations=%s" % _canonical_variant(diplomatic_relations),
		"armies=%s" % _canonical_variant(army_registry),
		"wars=%s" % _canonical_variant(war_registry),
		"construction=%s" % _canonical_variant(construction_registry),
		"recruitment=%s" % _canonical_variant(recruitment_registry),
		"loans=%s" % _canonical_variant(loan_registry),
		"characters=%s" % _canonical_variant(character_registry),
		"dynasties=%s" % _canonical_variant(dynasty_registry),
		"titles=%s" % _canonical_variant(title_registry),
		"claims=%s" % _canonical_variant(claim_registry),
		"subjects=%s" % _canonical_variant(subject_registry),
		"country_events=%s" % _canonical_variant(country_event_registry),
		"rebel_factions=%s" % _canonical_variant(rebel_faction_registry),
		"fleets=%s" % _canonical_variant(fleet_registry),
		"ships=%s" % _canonical_variant(ship_registry),
		"naval_construction=%s" % _canonical_variant(naval_construction_registry),
		"transport_operations=%s" % _canonical_variant(transport_operation_registry),
		"naval_battles=%s" % _canonical_variant(naval_battle_registry),
		"blockaded_provinces=%s" % _canonical_variant(blockaded_provinces),
	]
	var stream_names := rng_stream_states.keys()
	stream_names.sort()
	for raw_stream_name in stream_names:
		var stream_name := String(raw_stream_name)
		canonical_parts.append("rng:%s=%d" % [stream_name, int(rng_stream_states[raw_stream_name])])
	var country_tags := country_states.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		var tag := String(raw_tag)
		var country: Dictionary = country_states[raw_tag]
		canonical_parts.append("country:%s=%s" % [tag, _canonical_variant(country.get("runtime_values", {}))])
	var province_ids := province_states.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var state: Dictionary = province_states[raw_province_id]
		canonical_parts.append("province:%d=%s" % [province_id, _canonical_variant(state)])
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update("\n".join(canonical_parts).to_utf8_buffer())
	return hashing.finish().hex_encode()


func to_save_dict(game_version: String) -> Dictionary:
	var owners := {}
	var controllers := {}
	var province_economy := {}
	var province_ids := province_states.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var state: Dictionary = province_states[raw_province_id]
		owners[str(province_id)] = state["owner"]
		controllers[str(province_id)] = state["controller"]
		province_economy[str(province_id)] = (state.get("economy", {}) as Dictionary).duplicate(true)
	var runtime_values := {}
	var country_tags := country_states.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		var tag := String(raw_tag)
		var country: Dictionary = country_states[raw_tag]
		runtime_values[tag] = (country.get("runtime_values", {}) as Dictionary).duplicate(true)
	return {
		"schema_version": SAVE_SCHEMA_VERSION,
		"game_version": game_version,
		"scenario_id": scenario_id,
		"current_day": current_day,
		"player_country": player_country,
		"paused": paused,
		"game_speed": game_speed,
		"campaign_seed": campaign_seed,
		"rng_stream_states": rng_stream_states.duplicate(true),
		"province_owners": owners,
		"province_controllers": controllers,
		"province_economy": province_economy,
		"country_runtime_values": runtime_values,
		"global_flags": global_flags.duplicate(true),
		"global_counters": global_counters.duplicate(true),
		"diplomatic_relations": diplomatic_relations.duplicate(true),
		"army_registry": army_registry.duplicate(true),
		"war_registry": war_registry.duplicate(true),
		"construction_registry": construction_registry.duplicate(true),
		"recruitment_registry": recruitment_registry.duplicate(true),
		"loan_registry": loan_registry.duplicate(true),
		"character_registry": character_registry.duplicate(true),
		"dynasty_registry": dynasty_registry.duplicate(true),
		"title_registry": title_registry.duplicate(true),
		"claim_registry": claim_registry.duplicate(true),
		"subject_registry": subject_registry.duplicate(true),
		"country_event_registry": country_event_registry.duplicate(true),
		"rebel_faction_registry": rebel_faction_registry.duplicate(true),
		"fleet_registry": fleet_registry.duplicate(true),
		"ship_registry": ship_registry.duplicate(true),
		"naval_construction_registry": naval_construction_registry.duplicate(true),
		"transport_operation_registry": transport_operation_registry.duplicate(true),
		"naval_battle_registry": naval_battle_registry.duplicate(true),
		"blockaded_provinces": blockaded_provinces.duplicate(true),
		"checksum": checksum(),
	}


func apply_save_dict(save_data: Dictionary) -> String:
	if int(save_data.get("schema_version", -1)) != SAVE_SCHEMA_VERSION:
		return "Unsupported save schema version."
	if String(save_data.get("scenario_id", "")) != scenario_id:
		return "The save belongs to a different scenario."
	var loaded_day := int(save_data.get("current_day", -1))
	if loaded_day < 0:
		return "The save contains an invalid campaign day."
	var loaded_speed := int(save_data.get("game_speed", 1))
	if loaded_speed < 1 or loaded_speed > 5:
		return "The save contains an invalid game speed."
	var loaded_player := String(save_data.get("player_country", ""))
	if not loaded_player.is_empty() and not country_states.has(loaded_player):
		return "The saved player country is not present in this scenario."
	var owners_variant = save_data.get("province_owners", null)
	var controllers_variant = save_data.get("province_controllers", null)
	if not owners_variant is Dictionary or not controllers_variant is Dictionary:
		return "The save is missing province state."
	var owners: Dictionary = owners_variant
	var controllers: Dictionary = controllers_variant
	var province_economy_variant = save_data.get("province_economy", {})
	if not province_economy_variant is Dictionary:
		return "The save contains invalid province economy state."
	var province_economy: Dictionary = province_economy_variant
	if owners.size() != province_states.size() or controllers.size() != province_states.size():
		return "The save has a different province set."

	var loaded_provinces := {}
	for raw_province_id in province_states.keys():
		var province_id := int(raw_province_id)
		var key := str(province_id)
		if not owners.has(key) or not controllers.has(key):
			return "The save is missing province %d." % province_id
		var owner := String(owners[key])
		var controller := String(controllers[key])
		if not owner.is_empty() and not country_states.has(owner):
			return "Province %d has an unknown owner %s." % [province_id, owner]
		if not controller.is_empty() and not country_states.has(controller):
			return "Province %d has an unknown controller %s." % [province_id, controller]
		var existing_state: Dictionary = province_states[province_id]
		var economy := (existing_state.get("economy", {}) as Dictionary).duplicate(true)
		if province_economy.has(key):
			if not province_economy[key] is Dictionary:
				return "Province %d has invalid economy state." % province_id
			economy.merge((province_economy[key] as Dictionary).duplicate(true), true)
		var loaded_state := {"owner": owner, "controller": controller}
		if existing_state.has("economy") or not economy.is_empty():
			loaded_state["economy"] = economy
		loaded_provinces[province_id] = loaded_state

	var armies_variant = save_data.get("army_registry", {})
	if not armies_variant is Dictionary:
		return "The save contains an invalid army registry."
	var loaded_armies: Dictionary = armies_variant
	for raw_army_id in loaded_armies.keys():
		if not loaded_armies[raw_army_id] is Dictionary:
			return "Army %s has invalid state." % raw_army_id
		var army: Dictionary = loaded_armies[raw_army_id]
		var army_owner := String(army.get("owner_country_id", ""))
		if not army_owner.is_empty() and not country_states.has(army_owner):
			return "Army %s belongs to unknown country %s." % [raw_army_id, army_owner]
		var army_province := int(army.get("current_province_id", -1))
		if not province_states.has(army_province):
			return "Army %s sits in unknown province %d." % [raw_army_id, army_province]

	var loaded_country_states := country_states.duplicate(true)
	var runtime_values_variant = save_data.get("country_runtime_values", {})
	if not runtime_values_variant is Dictionary:
		return "The save contains invalid country runtime values."
	var runtime_values: Dictionary = runtime_values_variant
	for raw_tag in runtime_values.keys():
		var tag := String(raw_tag)
		if not loaded_country_states.has(tag) or not runtime_values[raw_tag] is Dictionary:
			return "The save contains invalid runtime state for %s." % tag
		var merged_runtime := (loaded_country_states[tag].get("runtime_values", {}) as Dictionary).duplicate(true)
		merged_runtime.merge((runtime_values[raw_tag] as Dictionary).duplicate(true), true)
		loaded_country_states[tag]["runtime_values"] = merged_runtime

	for registry_key in ["construction_registry", "recruitment_registry", "loan_registry", "diplomatic_relations", "war_registry"]:
		if not save_data.get(registry_key, {}) is Dictionary:
			return "The save contains an invalid %s." % registry_key.replace("_", " ")
	var loaded_relations: Dictionary = save_data.get("diplomatic_relations", {})
	for raw_relation_key in loaded_relations:
		if not loaded_relations[raw_relation_key] is Dictionary:
			return "Diplomatic relationship %s has invalid state." % raw_relation_key
		var relation_countries: Array = loaded_relations[raw_relation_key].get("countries", [])
		if relation_countries.size() != 2:
			return "Diplomatic relationship %s has invalid participants." % raw_relation_key
		for raw_country in relation_countries:
			if not country_states.has(String(raw_country)):
				return "Diplomatic relationship %s references an unknown country." % raw_relation_key
	var loaded_wars: Dictionary = save_data.get("war_registry", {})
	for raw_war_id in loaded_wars:
		if not loaded_wars[raw_war_id] is Dictionary:
			return "War %s has invalid state." % raw_war_id
		var war: Dictionary = loaded_wars[raw_war_id]
		if String(war.get("status", "")) not in ["active", "ended"]:
			return "War %s has an invalid status." % raw_war_id
		var participants: Array = (war.get("attackers", []) as Array) + (war.get("defenders", []) as Array)
		# An active war always keeps both sides non-empty, but an ended one
		# does not: country-extinction cleanup below strips the extinct
		# tag from whichever side it was on, which can empty that side
		# outright. Same "history snapshot, not a live index" reasoning
		# _validate_naval_battle_data already applies to completed battles.
		if String(war.get("status", "")) == "active" and participants.size() < 2:
			return "War %s is missing participants." % raw_war_id
		var seen_participants := {}
		for raw_country in participants:
			var country := String(raw_country)
			if not country_states.has(country) or seen_participants.has(country):
				return "War %s has an unknown or duplicated participant." % raw_war_id
			seen_participants[country] = true
		var goal = war.get("war_goal", null)
		if not goal is Dictionary or not province_states.has(int((goal as Dictionary).get("province_id", -1))):
			return "War %s has an invalid war goal." % raw_war_id
		if String((goal as Dictionary).get("type", "")) == "press_claim":
			var goal_claim := String((goal as Dictionary).get("claim_id", ""))
			var goal_title := String((goal as Dictionary).get("title_id", ""))
			var goal_claimant := String((goal as Dictionary).get("claimant_id", ""))
			var save_claims = save_data.get("claim_registry", {})
			var save_titles = save_data.get("title_registry", {})
			var save_characters = save_data.get("character_registry", {})
			if not save_claims is Dictionary or not (save_claims as Dictionary).has(goal_claim) or not save_titles is Dictionary or not (save_titles as Dictionary).has(goal_title) or not save_characters is Dictionary or not (save_characters as Dictionary).has(goal_claimant):
				return "War %s has an invalid character claim war goal." % raw_war_id
		if not war.get("battles", {}) is Dictionary or not war.get("occupied_provinces", {}) is Dictionary or not war.get("peace_offers", {}) is Dictionary:
			return "War %s contains an invalid conflict registry." % raw_war_id
		for battle in (war.get("battles", {}) as Dictionary).values():
			if not battle is Dictionary or not province_states.has(int((battle as Dictionary).get("province_id", -1))):
				return "War %s contains an invalid battle." % raw_war_id
		for raw_province in (war.get("occupied_provinces", {}) as Dictionary):
			if not province_states.has(int(raw_province)):
				return "War %s contains an invalid occupation." % raw_war_id

	var loaded_characters_variant = save_data.get("character_registry", {})
	var loaded_dynasties_variant = save_data.get("dynasty_registry", {})
	var loaded_titles_variant = save_data.get("title_registry", {})
	var loaded_claims_variant = save_data.get("claim_registry", {})
	if not loaded_characters_variant is Dictionary or not loaded_dynasties_variant is Dictionary or not loaded_titles_variant is Dictionary or not loaded_claims_variant is Dictionary:
		return "The save contains invalid Phase 7 registries."
	var loaded_characters: Dictionary = loaded_characters_variant
	var loaded_dynasties: Dictionary = loaded_dynasties_variant
	var loaded_titles: Dictionary = loaded_titles_variant
	var loaded_claims: Dictionary = loaded_claims_variant
	if int(save_data.get("migrated_from_schema", SAVE_SCHEMA_VERSION)) < 4 and loaded_characters.is_empty():
		loaded_characters = character_registry.duplicate(true)
		loaded_dynasties = dynasty_registry.duplicate(true)
		loaded_titles = title_registry.duplicate(true)
		loaded_claims = claim_registry.duplicate(true)
	var character_error := _validate_character_data(loaded_characters, loaded_dynasties, loaded_titles, loaded_claims, loaded_country_states, loaded_armies)
	if not character_error.is_empty():
		return character_error
	var loaded_subjects_variant = save_data.get("subject_registry", {})
	var loaded_country_events_variant = save_data.get("country_event_registry", {})
	var loaded_rebels_variant = save_data.get("rebel_faction_registry", {})
	if not loaded_subjects_variant is Dictionary or not loaded_country_events_variant is Dictionary or not loaded_rebels_variant is Dictionary:
		return "The save contains invalid Phase 8 registries."
	var loaded_subjects: Dictionary = loaded_subjects_variant
	var loaded_country_events: Dictionary = loaded_country_events_variant
	var loaded_rebels: Dictionary = loaded_rebels_variant
	var depth_error := _validate_country_depth_data(loaded_subjects, loaded_country_events, loaded_rebels, loaded_country_states, loaded_provinces)
	if not depth_error.is_empty():
		return depth_error

	var loaded_fleets_variant = save_data.get("fleet_registry", {})
	var loaded_ships_variant = save_data.get("ship_registry", {})
	var loaded_naval_construction_variant = save_data.get("naval_construction_registry", {})
	if not loaded_fleets_variant is Dictionary or not loaded_ships_variant is Dictionary or not loaded_naval_construction_variant is Dictionary:
		return "The save contains invalid naval registries."
	var loaded_fleets: Dictionary = loaded_fleets_variant
	var loaded_ships: Dictionary = loaded_ships_variant
	var loaded_naval_construction: Dictionary = loaded_naval_construction_variant
	var naval_error := _validate_naval_data(loaded_fleets, loaded_ships, loaded_naval_construction, loaded_country_states, loaded_provinces, loaded_characters)
	if not naval_error.is_empty():
		return naval_error

	var loaded_transport_operations_variant = save_data.get("transport_operation_registry", {})
	if not loaded_transport_operations_variant is Dictionary:
		return "The save contains an invalid transport operation registry."
	var loaded_transport_operations: Dictionary = loaded_transport_operations_variant
	var transport_error := _validate_transport_data(loaded_transport_operations, loaded_fleets, loaded_armies, loaded_country_states, loaded_provinces)
	if not transport_error.is_empty():
		return transport_error

	var loaded_naval_battles_variant = save_data.get("naval_battle_registry", {})
	if not loaded_naval_battles_variant is Dictionary:
		return "The save contains an invalid naval battle registry."
	var loaded_naval_battles: Dictionary = loaded_naval_battles_variant
	var naval_battle_error := _validate_naval_battle_data(loaded_naval_battles, loaded_fleets, loaded_country_states, loaded_provinces)
	if not naval_battle_error.is_empty():
		return naval_battle_error

	var loaded_blockaded_provinces_variant = save_data.get("blockaded_provinces", {})
	if not loaded_blockaded_provinces_variant is Dictionary:
		return "The save contains an invalid blockaded-provinces record."
	var loaded_blockaded_provinces: Dictionary = loaded_blockaded_provinces_variant
	for raw_province_id in loaded_blockaded_provinces:
		if not loaded_provinces.has(int(raw_province_id)):
			return "The save records an unknown province as blockaded."
		var recorded_bp := int(loaded_blockaded_provinces[raw_province_id])
		if recorded_bp <= 0 or recorded_bp > 10000:
			return "Province %d has an out-of-range recorded blockade level." % int(raw_province_id)

	province_states = loaded_provinces
	country_states = loaded_country_states
	current_day = loaded_day
	player_country = loaded_player
	paused = bool(save_data.get("paused", true))
	game_speed = loaded_speed
	campaign_seed = int(save_data.get("campaign_seed", campaign_seed))
	rng_stream_states = (save_data.get("rng_stream_states", {}) as Dictionary).duplicate(true)
	global_flags = (save_data.get("global_flags", {}) as Dictionary).duplicate(true)
	global_counters = (save_data.get("global_counters", {}) as Dictionary).duplicate(true)
	diplomatic_relations = (save_data.get("diplomatic_relations", {}) as Dictionary).duplicate(true)
	army_registry = (save_data.get("army_registry", {}) as Dictionary).duplicate(true)
	war_registry = (save_data.get("war_registry", {}) as Dictionary).duplicate(true)
	construction_registry = (save_data.get("construction_registry", {}) as Dictionary).duplicate(true)
	recruitment_registry = (save_data.get("recruitment_registry", {}) as Dictionary).duplicate(true)
	loan_registry = (save_data.get("loan_registry", {}) as Dictionary).duplicate(true)
	character_registry = loaded_characters.duplicate(true)
	dynasty_registry = loaded_dynasties.duplicate(true)
	title_registry = loaded_titles.duplicate(true)
	claim_registry = loaded_claims.duplicate(true)
	subject_registry = loaded_subjects.duplicate(true)
	country_event_registry = loaded_country_events.duplicate(true)
	rebel_faction_registry = loaded_rebels.duplicate(true)
	fleet_registry = loaded_fleets.duplicate(true)
	ship_registry = loaded_ships.duplicate(true)
	naval_construction_registry = loaded_naval_construction.duplicate(true)
	transport_operation_registry = loaded_transport_operations.duplicate(true)
	naval_battle_registry = loaded_naval_battles.duplicate(true)
	blockaded_provinces = loaded_blockaded_provinces.duplicate(true)
	_rebuild_country_index()
	return ""


func _validate_naval_data(fleets: Dictionary, ships: Dictionary, naval_construction: Dictionary, loaded_countries: Dictionary, loaded_provinces: Dictionary, characters: Dictionary) -> String:
	for raw_id in fleets:
		var fleet_id := String(raw_id)
		if not fleets[raw_id] is Dictionary:
			return "Fleet %s has invalid state." % fleet_id
		var fleet: Dictionary = fleets[raw_id]
		if not loaded_countries.has(String(fleet.get("owner_country_id", ""))):
			return "Fleet %s belongs to an unknown country." % fleet_id
		if not loaded_provinces.has(int(fleet.get("home_port_id", -1))):
			return "Fleet %s has an unknown home port." % fleet_id
		if not loaded_provinces.has(int(fleet.get("location_id", -1))):
			return "Fleet %s has an unknown location." % fleet_id
		var admiral := String(fleet.get("admiral_id", ""))
		if not admiral.is_empty():
			if not characters.has(admiral) or not bool((characters[admiral] as Dictionary).get("alive", false)):
				return "Fleet %s has an invalid admiral." % fleet_id
			if String((characters[admiral] as Dictionary).get("admiral_fleet_id", "")) != fleet_id:
				return "Fleet %s and its admiral do not agree on assignment." % fleet_id
		if not VALID_FLEET_MISSIONS.has(String(fleet.get("mission", "idle"))):
			return "Fleet %s has an unknown mission." % fleet_id
		var mission_target_ids := (fleet.get("mission_target_ids", []) as Array)
		for raw_target_id in mission_target_ids:
			if not (raw_target_id is int or raw_target_id is float):
				return "Fleet %s has a malformed mission target." % fleet_id
			if not loaded_provinces.has(int(raw_target_id)):
				return "Fleet %s has an unknown mission target." % fleet_id
		var member_ids := (fleet.get("ship_ids", []) as Array)
		var seen_members := {}
		for raw_ship_id in member_ids:
			var member_id := String(raw_ship_id)
			if seen_members.has(member_id):
				return "Fleet %s lists ship %s more than once." % [fleet_id, member_id]
			seen_members[member_id] = true
			if not ships.has(member_id):
				return "Fleet %s references unknown ship %s." % [fleet_id, member_id]
			if String((ships[member_id] as Dictionary).get("fleet_id", "")) != fleet_id:
				return "Fleet %s and ship %s do not agree on membership." % [fleet_id, member_id]
	for raw_id in ships:
		var ship_id := String(raw_id)
		if not ships[raw_id] is Dictionary:
			return "Ship %s has invalid state." % ship_id
		var ship: Dictionary = ships[raw_id]
		if not loaded_countries.has(String(ship.get("owner_country_id", ""))):
			return "Ship %s belongs to an unknown country." % ship_id
		var owning_fleet := String(ship.get("fleet_id", ""))
		if not fleets.has(owning_fleet):
			return "Ship %s references unknown fleet %s." % [ship_id, owning_fleet]
		if not (fleets[owning_fleet] as Dictionary).get("ship_ids", []).has(ship_id):
			return "Ship %s is not listed by its own fleet %s." % [ship_id, owning_fleet]
	for raw_id in naval_construction:
		var construction_id := String(raw_id)
		if not naval_construction[raw_id] is Dictionary:
			return "Naval construction %s has invalid state." % construction_id
		var construction: Dictionary = naval_construction[raw_id]
		if not loaded_countries.has(String(construction.get("country_tag", ""))):
			return "Naval construction %s belongs to an unknown country." % construction_id
		if not loaded_provinces.has(int(construction.get("port_id", -1))):
			return "Naval construction %s references an unknown port." % construction_id
	return ""


## N3A structural/referential checks only, mirroring _validate_naval_data's
## scope - operation<->army<->fleet reverse references must agree, and every
## reference must resolve. Reserved-capacity-vs-live-transports (03_N3
## "Reserved capacity against live transports") needs ShipDefinitions to
## compute, which is a data-layer concern this structural validator
## deliberately does not depend on; that check belongs to TransportSystem.
func _validate_transport_data(operations: Dictionary, fleets: Dictionary, armies: Dictionary, loaded_countries: Dictionary, loaded_provinces: Dictionary) -> String:
	for raw_id in operations:
		var operation_id := String(raw_id)
		if not operations[raw_id] is Dictionary:
			return "Transport operation %s has invalid state." % operation_id
		var operation: Dictionary = operations[raw_id]
		var country_tag := String(operation.get("country_tag", ""))
		if not loaded_countries.has(country_tag):
			return "Transport operation %s belongs to an unknown country." % operation_id
		if not loaded_provinces.has(int(operation.get("origin_port_id", -1))):
			return "Transport operation %s has an unknown origin port." % operation_id
		if not loaded_provinces.has(int(operation.get("destination_province_id", -1))):
			return "Transport operation %s has an unknown destination." % operation_id
		var army_id := String(operation.get("army_id", ""))
		if not armies.has(army_id):
			return "Transport operation %s references an unknown army." % operation_id
		var army: Dictionary = armies[army_id]
		if String(army.get("transport_operation_id", "")) != operation_id:
			return "Transport operation %s and army %s do not agree on assignment." % [operation_id, army_id]
		if String(army.get("owner_country_id", "")) != country_tag:
			return "Transport operation %s and its army disagree on owning country." % operation_id
		var fleet_id := String(operation.get("fleet_id", ""))
		if not fleets.has(fleet_id):
			return "Transport operation %s references an unknown fleet." % operation_id
		var fleet: Dictionary = fleets[fleet_id]
		if not (fleet.get("transport_operation_ids", []) as Array).has(operation_id):
			return "Transport operation %s and fleet %s do not agree on assignment." % [operation_id, fleet_id]
		if String(fleet.get("owner_country_id", "")) != country_tag:
			return "Transport operation %s and its fleet disagree on owning country." % operation_id
	for raw_army_id in armies:
		var army: Dictionary = armies[raw_army_id]
		var operation_id := String(army.get("transport_operation_id", ""))
		if not operation_id.is_empty() and not operations.has(operation_id):
			return "Army %s references an unknown transport operation." % String(raw_army_id)
	for raw_fleet_id in fleets:
		var fleet: Dictionary = fleets[raw_fleet_id]
		for raw_operation_id in (fleet.get("transport_operation_ids", []) as Array):
			if not operations.has(String(raw_operation_id)):
				return "Fleet %s references an unknown transport operation." % String(raw_fleet_id)
	return ""


## N4A structural/referential checks, mirroring _validate_naval_data and
## _validate_transport_data's scope: battle<->fleet reverse references must
## agree, every reference must resolve, and no fleet may belong to more than
## one active battle - "One fleet cannot enter two battles"
## (04_N4_NAVAL_COMBAT.md "Engagement Start"). Completed battles are kept in
## the registry as history (the "final report" 04_N4 asks for), so their
## fleet lists are a snapshot, not a live index - a fleet a completed battle
## names may have since left battle status, retreated, or been destroyed and
## erased entirely; only *active* battles require live reciprocity.
func _validate_naval_battle_data(battles: Dictionary, fleets: Dictionary, loaded_countries: Dictionary, loaded_provinces: Dictionary) -> String:
	var fleet_claimed_by := {}
	for raw_id in battles:
		var battle_id := String(raw_id)
		if not battles[raw_id] is Dictionary:
			return "Naval battle %s has invalid state." % battle_id
		var battle: Dictionary = battles[raw_id]
		if not loaded_provinces.has(int(battle.get("zone_id", -1))):
			return "Naval battle %s has an unknown sea zone." % battle_id
		var attacker_fleets := (battle.get("attacker_fleets", []) as Array)
		var defender_fleets := (battle.get("defender_fleets", []) as Array)
		if String(battle.get("status", "")) != "active":
			continue
		if attacker_fleets.is_empty() or defender_fleets.is_empty():
			return "Naval battle %s must have at least one fleet on each side." % battle_id
		for raw_fleet_id in attacker_fleets + defender_fleets:
			var fleet_id := String(raw_fleet_id)
			if not fleets.has(fleet_id):
				return "Naval battle %s references unknown fleet %s." % [battle_id, fleet_id]
			if String((fleets[fleet_id] as Dictionary).get("battle_id", "")) != battle_id:
				return "Naval battle %s and fleet %s do not agree on membership." % [battle_id, fleet_id]
			if fleet_claimed_by.has(fleet_id):
				return "Fleet %s belongs to more than one active naval battle." % fleet_id
			fleet_claimed_by[fleet_id] = battle_id
	for raw_fleet_id in fleets:
		var fleet: Dictionary = fleets[raw_fleet_id]
		var battle_id := String(fleet.get("battle_id", ""))
		if not battle_id.is_empty() and not battles.has(battle_id):
			return "Fleet %s references an unknown naval battle." % String(raw_fleet_id)
	return ""


func _validate_country_depth_data(subjects: Dictionary, country_events: Dictionary, rebels: Dictionary, loaded_countries: Dictionary, loaded_provinces: Dictionary) -> String:
	var subject_of := {}
	for raw_id in subjects:
		if not subjects[raw_id] is Dictionary:
			return "Subject relationship %s has invalid state." % String(raw_id)
		var subject: Dictionary = subjects[raw_id]
		var overlord := String(subject.get("overlord", ""))
		var subject_tag := String(subject.get("subject", ""))
		if overlord == subject_tag or not loaded_countries.has(overlord) or not loaded_countries.has(subject_tag):
			return "Subject relationship %s has invalid countries." % String(raw_id)
		if subject_of.has(subject_tag):
			return "%s has more than one direct overlord." % subject_tag
		subject_of[subject_tag] = overlord
	for raw_subject in subject_of:
		var current := String(raw_subject)
		var seen := {}
		while subject_of.has(current):
			if seen.has(current):
				return "Subject hierarchy contains a cycle."
			seen[current] = true
			current = String(subject_of[current])
	for raw_id in country_events:
		if not country_events[raw_id] is Dictionary or not loaded_countries.has(String((country_events[raw_id] as Dictionary).get("country_tag", ""))):
			return "Country event %s has invalid state or country." % String(raw_id)
	for raw_id in rebels:
		if not rebels[raw_id] is Dictionary:
			return "Rebel faction %s has invalid state." % String(raw_id)
		var rebel: Dictionary = rebels[raw_id]
		if not loaded_countries.has(String(rebel.get("country_tag", ""))) or not loaded_provinces.has(int(rebel.get("province_id", -1))):
			return "Rebel faction %s has invalid country or province." % String(raw_id)
	return ""


func _validate_character_data(
	characters: Dictionary,
	dynasties: Dictionary,
	titles: Dictionary,
	claims: Dictionary,
	loaded_countries: Dictionary,
	loaded_armies: Dictionary
) -> String:
	for raw_id in characters:
		var character_id := String(raw_id)
		if not characters[raw_id] is Dictionary:
			return "Character %s has invalid state." % character_id
		var character: Dictionary = characters[raw_id]
		if String(character.get("character_id", character_id)) != character_id:
			return "Character %s has a mismatched stable ID." % character_id
		if not character.get("birth", {}) is Dictionary or not character.get("skills", {}) is Dictionary or not character.get("traits", []) is Array:
			return "Character %s has malformed core data." % character_id
		if not dynasties.has(String(character.get("dynasty_id", ""))):
			return "Character %s references an unknown dynasty." % character_id
		for field in ["father_id", "mother_id", "spouse_id"]:
			var reference := String(character.get(field, ""))
			if reference == character_id or (not reference.is_empty() and not characters.has(reference)):
				return "Character %s has an invalid %s reference." % [character_id, field]
		for raw_child in character.get("children", []):
			var child_id := String(raw_child)
			if not characters.has(child_id):
				return "Character %s references an unknown child." % character_id
			var child: Dictionary = characters[child_id]
			if String(child.get("father_id", "")) != character_id and String(child.get("mother_id", "")) != character_id:
				return "Character %s has a non-reciprocal child reference." % character_id
		var spouse := String(character.get("spouse_id", ""))
		if not spouse.is_empty() and String((characters[spouse] as Dictionary).get("spouse_id", "")) != character_id:
			return "Marriage references are not symmetric for %s." % character_id
		var employer := String(character.get("employer_country", ""))
		if not employer.is_empty() and not loaded_countries.has(employer):
			return "Character %s has an unknown employer." % character_id
	if _has_character_ancestry_cycle(characters):
		return "The saved character ancestry contains a cycle."
	for raw_id in dynasties:
		if not dynasties[raw_id] is Dictionary:
			return "Dynasty %s has invalid state." % String(raw_id)
		for raw_member in (dynasties[raw_id] as Dictionary).get("living_members", []):
			if not characters.has(String(raw_member)) or not bool((characters[String(raw_member)] as Dictionary).get("alive", false)):
				return "Dynasty %s has an invalid living member." % String(raw_id)
	for raw_id in titles:
		if not titles[raw_id] is Dictionary:
			return "Title %s has invalid state." % String(raw_id)
		var title: Dictionary = titles[raw_id]
		var holder := String(title.get("holder_id", ""))
		if not characters.has(holder) or not bool((characters[holder] as Dictionary).get("alive", false)):
			return "Title %s has no valid living holder." % String(raw_id)
		var country := String(title.get("country_tag", ""))
		if not country.is_empty() and not loaded_countries.has(country):
			return "Title %s references an unknown country." % String(raw_id)
		var liege := String(title.get("liege_title_id", ""))
		if not liege.is_empty() and not titles.has(liege):
			return "Title %s references an unknown liege." % String(raw_id)
	if _has_title_hierarchy_cycle(titles):
		return "The saved title hierarchy contains a cycle."
	for raw_id in claims:
		if not claims[raw_id] is Dictionary:
			return "Claim %s has invalid state." % String(raw_id)
		var claim: Dictionary = claims[raw_id]
		if not characters.has(String(claim.get("claimant_id", ""))) or not titles.has(String(claim.get("title_id", ""))):
			return "Claim %s has an invalid character or title reference." % String(raw_id)
	for raw_tag in loaded_countries:
		var runtime: Dictionary = (loaded_countries[raw_tag] as Dictionary).get("runtime_values", {})
		for field in ["ruler_character_id", "heir_character_id"]:
			var character_id := String(runtime.get(field, ""))
			if not character_id.is_empty() and (not characters.has(character_id) or not bool((characters[character_id] as Dictionary).get("alive", false))):
				return "Country %s has an invalid %s." % [String(raw_tag), field]
		var primary_title := String(runtime.get("primary_title_id", ""))
		if not primary_title.is_empty() and not titles.has(primary_title):
			return "Country %s has an invalid primary title." % String(raw_tag)
	for raw_army_id in loaded_armies:
		var commander := String((loaded_armies[raw_army_id] as Dictionary).get("commander_id", ""))
		if not commander.is_empty() and (not characters.has(commander) or not bool((characters[commander] as Dictionary).get("alive", false))):
			return "Army %s has an invalid commander." % String(raw_army_id)
	return ""


func _has_character_ancestry_cycle(characters: Dictionary) -> bool:
	var fully_visited := {}
	var ids := characters.keys()
	ids.sort()
	for raw_id in ids:
		if _visit_character_ancestry(String(raw_id), characters, {}, fully_visited):
			return true
	return false


func _visit_character_ancestry(character_id: String, characters: Dictionary, visiting: Dictionary, fully_visited: Dictionary) -> bool:
	if visiting.has(character_id):
		return true
	if fully_visited.has(character_id):
		return false
	visiting[character_id] = true
	var character: Dictionary = characters[character_id]
	for field in ["father_id", "mother_id"]:
		var parent := String(character.get(field, ""))
		if not parent.is_empty() and _visit_character_ancestry(parent, characters, visiting, fully_visited):
			return true
	visiting.erase(character_id)
	fully_visited[character_id] = true
	return false


func _has_title_hierarchy_cycle(titles: Dictionary) -> bool:
	for raw_id in titles:
		var current := String(raw_id)
		var seen := {}
		while not current.is_empty():
			if seen.has(current):
				return true
			seen[current] = true
			current = String((titles[current] as Dictionary).get("liege_title_id", ""))
	return false


func _rebuild_country_index() -> void:
	country_to_provinces.clear()
	var country_tags := country_states.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		country_to_provinces[String(raw_tag)] = []
	var province_ids := province_states.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var owner := get_province_owner(province_id)
		if owner.is_empty() or not country_to_provinces.has(owner):
			continue
		(country_to_provinces[owner] as Array).append(province_id)


func _canonical_variant(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value
		var keys := dictionary.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var parts: Array[String] = []
		for key in keys:
			parts.append("%s:%s" % [str(key), _canonical_variant(dictionary[key])])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var parts: Array[String] = []
		for item in value:
			parts.append(_canonical_variant(item))
		return "[%s]" % ",".join(parts)
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	return str(value)
