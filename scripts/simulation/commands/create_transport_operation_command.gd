class_name CreateTransportOperationCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const TransportSystemScript = preload("res://scripts/simulation/transport_system.gd")

var country_tag := ""
var army_id := ""
var fleet_id := ""
var destination_province_id := -1


func _init(p_country_tag: String, p_army_id: String, p_fleet_id: String, p_destination_province_id: int, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	army_id = p_army_id
	fleet_id = p_fleet_id
	destination_province_id = p_destination_province_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s embarks %s onto %s bound for province %d" % [country_tag, army_id, fleet_id, destination_province_id]


func command_type() -> String:
	return "CreateTransportOperationCommand"


## N3.2 requires the destination to be a real, currently dockable port with a
## legal port-to-port sea route - tighter than N3.1's "any coastal province"
## placeholder, now that TransportSystem.process_day() actually sails the
## fleet there and disembarks at that exact node. Amphibious landing onto a
## non-port coastal province remains out of scope (see the N3.1/N3.2 evidence
## docs "Deliberately simple / deferred").
func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country: %s" % country_tag
	var army := world.get_army(army_id)
	if army.is_empty():
		return "The army does not exist."
	if String(army.get("owner_country_id", "")) != country_tag:
		return "%s does not control this army." % country_tag
	if String(army.get("status", "")) in [CampaignWorldState.ARMY_STATUS_BATTLE, CampaignWorldState.ARMY_STATUS_RETREATING, CampaignWorldState.ARMY_STATUS_RECOVERING, CampaignWorldState.ARMY_STATUS_EMBARKING, CampaignWorldState.ARMY_STATUS_EMBARKED]:
		return "The army cannot be transported in its current state."
	if bool(army.get("movement_locked", false)):
		return "The army is movement-locked."
	var fleet := world.get_fleet(fleet_id)
	if fleet.is_empty():
		return "The fleet does not exist."
	if String(fleet.get("owner_country_id", "")) != country_tag:
		return "%s does not control this fleet." % country_tag
	if String(fleet.get("location_status", "")) in [CampaignWorldState.FLEET_LOCATION_BATTLE, CampaignWorldState.FLEET_LOCATION_RETREATING]:
		return "The fleet cannot accept a transport mission in its current state."
	var origin_port_id := int(army.get("current_province_id", -1))
	if String(fleet.get("location_status", "")) != CampaignWorldState.FLEET_LOCATION_DOCKED or int(fleet.get("location_id", -1)) != origin_port_id:
		return "The fleet must be docked in the army's current province."
	var graph := MaritimeGraphScript.load_default()
	if not graph.is_port_province(origin_port_id):
		return "The army's province is not a naval port."
	if destination_province_id == origin_port_id:
		return "The army is already there."
	if not graph.is_port_province(destination_province_id):
		return "The destination is not a naval port."
	if not bool(NavalAccessPolicyScript.find_legal_route(graph, world, country_tag, origin_port_id, destination_province_id)["exists"]):
		return "No legal sea route reaches the destination."
	var required := TransportSystemScript.required_capacity(world, army_id)
	var available := TransportSystemScript.available_capacity(world, fleet_id)
	if required > available:
		return "The fleet lacks sufficient transport capacity (%d required, %d available)." % [required, available]
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var army := world.get_army(army_id)
	var origin_port_id := int(army.get("current_province_id", -1))
	var required := TransportSystemScript.required_capacity(world, army_id)
	var embark_days := TransportSystemScript.embark_days(world, army_id, fleet_id)
	var operation_id := "transport_%d" % world.take_counter("next_transport_operation_id")
	world.transport_operation_registry[operation_id] = CampaignWorldState.make_transport_operation_record(
		operation_id, country_tag, army_id, fleet_id, origin_port_id, destination_province_id,
		required, world.current_day, world.current_day + embark_days
	)
	army["transport_operation_id"] = operation_id
	army["status"] = CampaignWorldState.ARMY_STATUS_EMBARKING
	army["movement_locked"] = true
	world.army_registry[army_id] = army
	var fleet := world.get_fleet(fleet_id)
	var operation_ids: Array = fleet.get("transport_operation_ids", [])
	operation_ids.append(operation_id)
	operation_ids.sort()
	fleet["transport_operation_ids"] = operation_ids
	world.fleet_registry[fleet_id] = fleet
	events.transport_operation_created.emit(operation_id, army_id, fleet_id, destination_province_id)
