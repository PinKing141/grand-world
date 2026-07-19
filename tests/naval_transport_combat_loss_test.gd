extends SceneTree

## N3.3 "Fleet retreat/destruction": a carrier fleet a naval battle destroys
## outright (sunk to zero ships, or no legal retreat) used to leave its
## transport operation dangling forever - TransportSystem's "settled
## somewhere other than the destination" recovery check only recognises
## FLEET_LOCATION_DOCKED/AT_SEA, and an erased fleet's location_status reads
## as "" (neither), so the operation was silently orphaned rather than
## recovered or destroyed.
##
## This is tested by directly erasing the carrier fleet rather than driving
## a full multi-day battle to a one-shot kill: gradual ship damage always
## crosses TransportSystem's own pre-existing 50%-hull capacity threshold on
## its way to zero, so a scripted multi-round fight would exercise the
## already-working capacity-shortfall sweep (N4.3's "Transport casualty
## handoff", already closed) instead of this fix's actual target - a fleet
## that still had perfectly good capacity right up until the instant combat
## erased it outright (the "no legal retreat" branch, which can strand a
## fleet with undamaged surviving ships). Reproducing that specific branch
## through real geography needs the entire map under hostile control, the
## same reachability limit naval_combat_test.gd and
## naval_transport_recovery_test.gd already documented for its sibling
## cases - so, like naval_transport_recovery_test.gd's own
## `_destroy_stranded_operation` case, this drives the exact post-erasure
## state directly instead.

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const FleetSystemScript = preload("res://scripts/simulation/fleet_system.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")

const CALAIS := 87
const KENT := 235
const PICARDIE := 89


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Naval transport combat loss test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldStateScript.new()
	world.initialize({CALAIS: "ENG", KENT: "ENG", PICARDIE: "BUR"}, {"ENG": "England", "BUR": "Burgundy"})
	return world


func _run() -> void:
	var world := _make_world()
	var events := SimulationEventBusScript.new()
	root.add_child(events)

	# Burgundy's army is mid-crossing, embarked and sailing aboard fleet_bur -
	# a fleet naval combat has, this instant, erased outright (undamaged
	# surviving ships, but no legal port to retreat to).
	world.army_registry["bur_army"] = CampaignWorldStateScript.make_army_record("bur_army", "BUR", PICARDIE)
	world.army_registry["bur_army"]["status"] = CampaignWorldStateScript.ARMY_STATUS_EMBARKED
	world.army_registry["bur_army"]["transport_operation_id"] = "transport_1"
	world.army_registry["bur_army"]["movement_locked"] = true

	world.transport_operation_registry["transport_1"] = CampaignWorldStateScript.make_transport_operation_record(
		"transport_1", "BUR", "bur_army", "fleet_bur", PICARDIE, CALAIS, 5, 0, 5
	)
	world.transport_operation_registry["transport_1"]["state"] = CampaignWorldState.TRANSPORT_STATE_SAILING
	world.transport_operation_registry["transport_1"]["current_location_id"] = PICARDIE

	# An unrelated, healthy fleet stays in the world so the fixture isn't
	# trivially empty - fleet_bur itself is deliberately never added to
	# fleet_registry, standing in for "naval combat already erased it".
	world.fleet_registry["fleet_eng"] = CampaignWorldStateScript.make_fleet_record("fleet_eng", "ENG", CALAIS)
	world.ship_registry["fleet_eng_s0"] = CampaignWorldStateScript.make_ship_record("fleet_eng_s0", "ENG", "fleet_eng", "war_galley", 0)
	world.fleet_registry["fleet_eng"]["ship_ids"] = ["fleet_eng_s0"]
	FleetSystemScript.recompute_aggregate(world, "fleet_eng")

	var army_lost_signals: Array = []
	events.transport_operation_army_lost.connect(func(operation_id, army_id, reason): army_lost_signals.append([operation_id, army_id, reason]))

	TransportSystemScript.process_day(world, events)

	_require(not world.transport_operation_registry.has("transport_1"), "the operation naming a fleet combat already erased must be cleaned up")
	_require(not world.army_registry.has("bur_army"), "the embarked army must be lost along with its erased carrier, not left as an orphaned EMBARKED record")
	_require(army_lost_signals.size() == 1 and String(army_lost_signals[0][2]) == "The fleet carrying the army was destroyed in battle.", "the loss must be reported with a battle-specific reason: %s" % [army_lost_signals])

	# The save must round-trip cleanly - before the fix, the orphaned
	# operation record (still referencing a fleet that no longer exists)
	# would have failed _validate_transport_data on the very next load.
	var saved := world.to_save_dict("test")
	var reloaded := _make_world()
	var load_error := reloaded.apply_save_dict(saved)
	_require(load_error.is_empty(), "the post-battle save must load cleanly: %s" % load_error)

	print("Naval transport combat loss test passed.")
	quit(0)
