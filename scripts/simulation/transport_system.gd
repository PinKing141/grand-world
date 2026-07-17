class_name TransportSystem
extends RefCounted

## N3.1/N3.2/N3.3: capacity accounting, the reachable slice of the transport
## state machine (embarking -> sailing -> disembarking -> completed), and the
## failure-recovery paths reachable without combat (capacity shortfall from
## attrition, and recovery/destruction for a fleet FleetMovementSystem has
## already halted mid-route). See
## docs/roadmap/naval/03_N3_MARITIME_TRANSPORT.md "Capacity Model", "State
## Machine", and "Loss and Recovery Policy". battle_paused and combat-driven
## losses remain out of scope until N4 exists to trigger them.

const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const MoveFleetCommandScript = preload("res://scripts/simulation/commands/move_fleet_command.gd")

# Placeholder first-slice rule, not an approved N0 budget: a ship at or below
# half hull contributes zero transport capacity rather than a scaled
# fraction - the simplest rule that is genuinely "explicit" and "cannot
# fluctuate unpredictably from presentation values" (03_N3 "Capacity Model").
const DAMAGED_CAPACITY_THRESHOLD_BP := 5000

# Placeholder first-slice embark/disembark timing constants, not approved N0
# budgets - 03_N3 "Completion day is explicit and modified by port, army
# size, damage, and commander only through bounded integer rules." Bounded:
# every modifier is a small flat integer, and the total never drops below
# MIN_EMBARK_DAYS.
const EMBARK_BASE_DAYS := 3
const EMBARK_DAYS_PER_5_REGIMENTS := 1
const EMBARK_DAMAGE_PENALTY_DAYS := 2
const EMBARK_COMMANDER_BONUS_DAYS := 1
const MIN_EMBARK_DAYS := 1
const DISEMBARK_DAYS := 1


static func usable_capacity(world: CampaignWorldState, fleet_id: String, ship_definitions = null) -> int:
	if ship_definitions == null:
		ship_definitions = ShipDefinitionsScript.load_default()
	var total := 0
	for ship_id in world.fleet_ships(fleet_id):
		var ship := world.get_ship(ship_id)
		if bool(ship.get("disabled", false)) or int(ship.get("hull_bp", 10000)) < DAMAGED_CAPACITY_THRESHOLD_BP:
			continue
		var definition_id := String(ship.get("definition_id", ""))
		if not ship_definitions.has_ship(definition_id):
			continue
		total += int(ship_definitions.ship(definition_id).get("transport_capacity", 0))
	return total


static func reserved_capacity(world: CampaignWorldState, fleet_id: String) -> int:
	var total := 0
	for raw_operation_id in (world.get_fleet(fleet_id).get("transport_operation_ids", []) as Array):
		total += int(world.get_transport_operation(String(raw_operation_id)).get("reserved_capacity", 0))
	return total


static func available_capacity(world: CampaignWorldState, fleet_id: String, ship_definitions = null) -> int:
	return usable_capacity(world, fleet_id, ship_definitions) - reserved_capacity(world, fleet_id)


## "Required capacity uses authoritative regiment count, not displayed
## strength" (03_N3 "Capacity Model").
static func required_capacity(world: CampaignWorldState, army_id: String) -> int:
	return int(world.get_army(army_id).get("regiment_count", 0))


static func embark_days(world: CampaignWorldState, army_id: String, fleet_id: String) -> int:
	var regiments := int(world.get_army(army_id).get("regiment_count", 1))
	var days := EMBARK_BASE_DAYS + (regiments / 5) * EMBARK_DAYS_PER_5_REGIMENTS
	if not String(world.get_army(army_id).get("commander_id", "")).is_empty():
		days -= EMBARK_COMMANDER_BONUS_DAYS
	if _fleet_has_damaged_ship(world, fleet_id):
		days += EMBARK_DAMAGE_PENALTY_DAYS
	return maxi(MIN_EMBARK_DAYS, days)


static func _fleet_has_damaged_ship(world: CampaignWorldState, fleet_id: String) -> bool:
	for ship_id in world.fleet_ships(fleet_id):
		if int(world.get_ship(ship_id).get("hull_bp", 10000)) < DAMAGED_CAPACITY_THRESHOLD_BP:
			return true
	return false


## Walks every transport operation once a day, in stable ID order. Registered
## as a start_of_day_system (after FleetMovementSystem's daily_systems entry
## has already moved fleets for the day), mirroring EconomySystem's
## completion-day pattern: "current_day >= completion_day" checked after the
## day counter has advanced, not before (see _complete_constructions).
static func process_day(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var graph := MaritimeGraphScript.load_default()
	_resolve_capacity_shortfalls(world, events)
	var operation_ids := world.transport_operation_registry.keys()
	operation_ids.sort()
	for raw_operation_id in operation_ids:
		var operation_id := String(raw_operation_id)
		if not world.transport_operation_registry.has(operation_id):
			continue
		var operation: Dictionary = world.transport_operation_registry[operation_id]
		var state := String(operation.get("state", ""))
		if state == CampaignWorldState.TRANSPORT_STATE_EMBARKING:
			_advance_embarking(world, events, graph, operation_id, operation)
		elif state == CampaignWorldState.TRANSPORT_STATE_SAILING:
			_advance_sailing(world, events, graph, operation_id, operation)
		elif state == CampaignWorldState.TRANSPORT_STATE_DISEMBARKING:
			_advance_disembarking(world, events, operation_id, operation)


## N3.3: "If usable capacity falls below reserved capacity, affected armies
## take deterministic regiment/strength losses using stable operation and
## army ordering" (03_N3 "Loss and Recovery Policy"). Runs every day for
## every fleet carrying at least one operation, so it catches a capacity drop
## from any cause - today that is only FleetLogisticsSystem's attrition
## pushing a ship below the damaged-capacity threshold, but the check itself
## does not care why usable_capacity fell, only that it did.
static func _resolve_capacity_shortfalls(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var ship_definitions := ShipDefinitionsScript.load_default()
	var fleet_ids := world.fleet_registry.keys()
	fleet_ids.sort()
	for raw_fleet_id in fleet_ids:
		var fleet_id := String(raw_fleet_id)
		var operation_ids := (world.get_fleet(fleet_id).get("transport_operation_ids", []) as Array)
		if operation_ids.is_empty():
			continue
		var deficit := reserved_capacity(world, fleet_id) - usable_capacity(world, fleet_id, ship_definitions)
		if deficit <= 0:
			continue
		var sorted_operation_ids: Array = operation_ids.duplicate()
		sorted_operation_ids.sort()
		for raw_operation_id in sorted_operation_ids:
			if deficit <= 0:
				break
			deficit -= _apply_capacity_loss(world, events, String(raw_operation_id), deficit)


## Reduces one operation's army by up to `deficit` regiments (never more than
## the operation's own reserved_capacity - "surviving capacity remains
## reserved; reservations cannot become negative"), scaling strength down
## proportionally with integer math, and returns how much of the deficit was
## absorbed. An army reduced to zero regiments is destroyed outright, mirroring
## DisbandArmyCommand's registry-erase pattern but without a manpower refund -
## this is a real loss, not a voluntary disbandment.
static func _apply_capacity_loss(world: CampaignWorldState, events: SimulationEventBus, operation_id: String, deficit: int) -> int:
	var operation := world.get_transport_operation(operation_id)
	if operation.is_empty():
		return 0
	var reserved := int(operation.get("reserved_capacity", 0))
	var loss := mini(deficit, reserved)
	if loss <= 0:
		return 0
	var army_id := String(operation.get("army_id", ""))
	var army := world.get_army(army_id)
	if army.is_empty():
		return loss
	var old_regiments := int(army.get("regiment_count", 0))
	var new_regiments := maxi(0, old_regiments - loss)
	var lost_regiments := old_regiments - new_regiments
	if lost_regiments <= 0:
		return loss
	var strength_per_regiment := int(army.get("strength", 0)) / maxi(1, old_regiments)
	army["regiment_count"] = new_regiments
	army["strength"] = maxi(0, int(army.get("strength", 0)) - strength_per_regiment * lost_regiments)
	army["maximum_strength"] = maxi(0, int(army.get("maximum_strength", 0)) - strength_per_regiment * lost_regiments)
	world.army_registry[army_id] = army
	operation["reserved_capacity"] = reserved - lost_regiments
	world.transport_operation_registry[operation_id] = operation
	events.transport_capacity_shortfall.emit(operation_id, army_id, lost_regiments)
	if new_regiments <= 0:
		_destroy_stranded_operation(world, events, operation_id, "The army was lost when its transport's capacity was destroyed.")
	return loss


## Bounded recovery, per 03_N3 "If the carrier fleet retreats, the operation
## follows it and targets the retreat port" / "survivors attempt the nearest
## legal friendly/accessible coast according to one bounded recovery rule."
## There is no fleet "retreat" mechanic yet (N4), so the closest analogue
## available today is a fleet FleetMovementSystem has already halted safely
## after an access/ownership change mid-route (N2.3's per-leg revalidation).
## Recovery tries the operation's original destination again first (access
## may have been restored), then the nearest port the fleet can legally dock
## at from where it is now. If neither exists, the army is explicitly
## destroyed rather than left attached to a fleet going nowhere - "it never
## remains in an unqueryable state" (03_N3 Objective).
static func _attempt_recovery(world: CampaignWorldState, events: SimulationEventBus, graph: MaritimeGraph, operation_id: String, operation: Dictionary) -> void:
	var fleet_id := String(operation.get("fleet_id", ""))
	var fleet := world.get_fleet(fleet_id)
	var current_location_id := int(fleet.get("location_id", -1))
	var country_tag := String(operation.get("country_tag", ""))
	var destination_province_id := int(operation.get("destination_province_id", -1))
	var route := NavalAccessPolicyScript.find_legal_route(graph, world, country_tag, current_location_id, destination_province_id)
	if not bool(route["exists"]) and NavalAccessPolicyScript.can_dock(graph, world, country_tag, current_location_id):
		# nearest_matching excludes the origin from its own search (by
		# design - see maritime_graph.gd's doc comment); a fleet already
		# halted at a perfectly legal port must be checked directly first.
		destination_province_id = current_location_id
		operation["destination_province_id"] = destination_province_id
		events.transport_operation_rerouted.emit(operation_id, destination_province_id)
	elif not bool(route["exists"]):
		var nearest := graph.nearest_matching(
			current_location_id,
			func(candidate_id): return NavalAccessPolicyScript.can_dock(graph, world, country_tag, candidate_id)
		)
		if not bool(nearest["found"]):
			_destroy_stranded_operation(world, events, operation_id, "No legal port was reachable; the army was lost at sea.")
			return
		destination_province_id = int(nearest["id"])
		operation["destination_province_id"] = destination_province_id
		events.transport_operation_rerouted.emit(operation_id, destination_province_id)
	if String(fleet.get("location_status", "")) == CampaignWorldState.FLEET_LOCATION_DOCKED and current_location_id == destination_province_id:
		operation["state"] = CampaignWorldState.TRANSPORT_STATE_DISEMBARKING
		operation["state_start_day"] = world.current_day
		operation["completion_day"] = world.current_day + DISEMBARK_DAYS
	else:
		MoveFleetCommandScript.new(fleet_id, destination_province_id, country_tag).apply(world, events)
	operation["current_location_id"] = current_location_id
	world.transport_operation_registry[operation_id] = operation


static func _destroy_stranded_operation(world: CampaignWorldState, events: SimulationEventBus, operation_id: String, reason: String) -> void:
	var operation := world.get_transport_operation(operation_id)
	var army_id := String(operation.get("army_id", ""))
	var fleet_id := String(operation.get("fleet_id", ""))
	world.army_registry.erase(army_id)
	_detach_from_fleet(world, fleet_id, operation_id)
	world.transport_operation_registry.erase(operation_id)
	events.transport_operation_army_lost.emit(operation_id, army_id, reason)


## Embark timer expires -> the army goes aboard (no longer land-present) and
## the operation orders the fleet to sail. Routes from the fleet's *live*
## location, not the operation's recorded origin: a fleet carrying more than
## one staggered embark (multiple armies, multiple completion days) may have
## already sailed for a different operation by the time this one's timer
## expires. If the fleet isn't currently docked, this operation simply waits
## another day rather than routing from a stale position - a known
## simplification for multi-destination convoys (see the evidence doc's
## "Deliberately simple / deferred"), not a crash risk. If the route has
## stopped being legal since validate() ran (access/ownership changed during
## the embark window), the operation fails safely rather than committing the
## fleet to an illegal order - "no army may be... permanently stranded"
## (03_N3 Objective) - even though the richer follow-the-fleet recovery rules
## are N3.3's job.
static func _advance_embarking(world: CampaignWorldState, events: SimulationEventBus, graph: MaritimeGraph, operation_id: String, operation: Dictionary) -> void:
	if int(operation.get("completion_day", 0)) > world.current_day:
		return
	var fleet_id := String(operation.get("fleet_id", ""))
	var fleet := world.get_fleet(fleet_id)
	if String(fleet.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_DOCKED:
		return
	var current_location_id := int(fleet.get("location_id", -1))
	var country_tag := String(operation.get("country_tag", ""))
	var destination_province_id := int(operation.get("destination_province_id", -1))
	var route := NavalAccessPolicyScript.find_legal_route(graph, world, country_tag, current_location_id, destination_province_id)
	if not bool(route["exists"]):
		_fail_operation(world, events, operation_id, operation, "No legal sea route reaches the destination.")
		return
	var army_id := String(operation.get("army_id", ""))
	var army := world.get_army(army_id)
	army["status"] = CampaignWorldState.ARMY_STATUS_EMBARKED
	world.army_registry[army_id] = army
	MoveFleetCommandScript.new(fleet_id, destination_province_id, country_tag).apply(world, events)
	operation["state"] = CampaignWorldState.TRANSPORT_STATE_SAILING
	operation["state_start_day"] = world.current_day
	operation["completion_day"] = -1
	operation["planned_path"] = route["path"]
	operation["current_location_id"] = current_location_id
	world.transport_operation_registry[operation_id] = operation
	events.transport_operation_state_changed.emit(operation_id, CampaignWorldState.TRANSPORT_STATE_SAILING)


## Sailing has no day-count completion - it ends when the fleet actually
## docks at the destination (FleetMovementSystem, ticking separately, is the
## single authority for fleet position; this only watches it). A fleet
## carrying a transport operation can never receive an independent move
## order (MoveFleetCommand.validate()), so if it has stopped moving anywhere
## other than this operation's destination, FleetMovementSystem must have
## blocked it (an access/ownership change mid-route, 02_N2/N2.3's per-leg
## revalidation) - the N3.3 recovery path.
static func _advance_sailing(world: CampaignWorldState, events: SimulationEventBus, graph: MaritimeGraph, operation_id: String, operation: Dictionary) -> void:
	var fleet_id := String(operation.get("fleet_id", ""))
	var fleet := world.get_fleet(fleet_id)
	var destination_province_id := int(operation.get("destination_province_id", -1))
	var location_status := String(fleet.get("location_status", ""))
	var location_id := int(fleet.get("location_id", -1))
	if location_status == CampaignWorldState.FLEET_LOCATION_DOCKED and location_id == destination_province_id:
		operation["state"] = CampaignWorldState.TRANSPORT_STATE_DISEMBARKING
		operation["state_start_day"] = world.current_day
		operation["completion_day"] = world.current_day + DISEMBARK_DAYS
		operation["current_location_id"] = destination_province_id
		world.transport_operation_registry[operation_id] = operation
		events.transport_operation_state_changed.emit(operation_id, CampaignWorldState.TRANSPORT_STATE_DISEMBARKING)
		return
	var settled := location_status in [CampaignWorldState.FLEET_LOCATION_DOCKED, CampaignWorldState.FLEET_LOCATION_AT_SEA] \
		and (fleet.get("remaining_path", []) as Array).is_empty() and int(fleet.get("destination_id", -1)) < 0
	if settled and location_id != destination_province_id:
		_attempt_recovery(world, events, graph, operation_id, operation)


## Destination access is revalidated at the moment of landing, per 03_N3
## Disembarking - "Destination access, control, coast adjacency, and capacity
## state are revalidated." A hostile landing is not rejected outright (that
## is a real, permitted outcome per 03_N3), only an outright-illegal one
## (destination no longer a usable port) fails the operation; the landing-
## battle/penalty handoff itself is N3.3/N4, once land warfare can be
## triggered from here.
static func _advance_disembarking(world: CampaignWorldState, events: SimulationEventBus, operation_id: String, operation: Dictionary) -> void:
	if int(operation.get("completion_day", 0)) > world.current_day:
		return
	var graph := MaritimeGraphScript.load_default()
	var destination_province_id := int(operation.get("destination_province_id", -1))
	if not graph.is_port_province(destination_province_id) or not graph.is_port_enabled(destination_province_id):
		_fail_operation(world, events, operation_id, operation, "The destination is no longer a usable port.")
		return
	_complete_operation(world, events, operation_id, operation)


static func _complete_operation(world: CampaignWorldState, events: SimulationEventBus, operation_id: String, operation: Dictionary) -> void:
	var army_id := String(operation.get("army_id", ""))
	var fleet_id := String(operation.get("fleet_id", ""))
	var destination_province_id := int(operation.get("destination_province_id", -1))
	var army := world.get_army(army_id)
	army["current_province_id"] = destination_province_id
	army["status"] = CampaignWorldState.ARMY_STATUS_IDLE
	army["movement_locked"] = false
	army["transport_operation_id"] = ""
	world.army_registry[army_id] = army
	_detach_from_fleet(world, fleet_id, operation_id)
	world.transport_operation_registry.erase(operation_id)
	events.transport_operation_completed.emit(operation_id, army_id, destination_province_id)


## A safety valve, not the full loss/recovery policy 03_N3 describes (that
## needs combat/interception concepts N4 has not built - N3.3's job). This
## only fires when the destination itself has become illegal, and always
## resolves the army safely: it disembarks wherever the fleet currently is,
## rather than vanishing or reappearing at a stale location.
static func _fail_operation(world: CampaignWorldState, events: SimulationEventBus, operation_id: String, operation: Dictionary, reason: String) -> void:
	var army_id := String(operation.get("army_id", ""))
	var fleet_id := String(operation.get("fleet_id", ""))
	var fleet := world.get_fleet(fleet_id)
	var landing_province_id := int(fleet.get("location_id", operation.get("origin_port_id", -1)))
	var army := world.get_army(army_id)
	army["current_province_id"] = landing_province_id
	army["status"] = CampaignWorldState.ARMY_STATUS_IDLE
	army["movement_locked"] = false
	army["transport_operation_id"] = ""
	world.army_registry[army_id] = army
	_detach_from_fleet(world, fleet_id, operation_id)
	world.transport_operation_registry.erase(operation_id)
	events.transport_operation_failed.emit(operation_id, army_id, landing_province_id, reason)


static func _detach_from_fleet(world: CampaignWorldState, fleet_id: String, operation_id: String) -> void:
	if not world.fleet_registry.has(fleet_id):
		return
	var fleet := world.get_fleet(fleet_id)
	var operation_ids: Array = fleet.get("transport_operation_ids", [])
	operation_ids.erase(operation_id)
	fleet["transport_operation_ids"] = operation_ids
	world.fleet_registry[fleet_id] = fleet
