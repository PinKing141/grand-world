class_name ConstructShipCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

const ShipDefinitionsScript = preload("res://scripts/simulation/ship_definitions.gd")
const NavalDefinitionsScript = preload("res://scripts/simulation/naval_definitions.gd")
const MaritimeGraphScript = preload("res://scripts/simulation/maritime_graph.gd")
const NavalAccessPolicyScript = preload("res://scripts/simulation/naval_access_policy.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")

# N2.2 placeholder queue policy: one naval construction project per port at a
# time. Not an approved N0 budget - a simple, testable first-slice rule per
# 02_N2_FLEET_LOGISTICS.md "Queue/capacity limit is not exceeded."
const MAX_CONCURRENT_CONSTRUCTIONS_PER_PORT := 1

var country_tag := ""
var port_id := -1
var definition_id := ""


func _init(p_country_tag: String, p_port_id: int, p_definition_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	port_id = p_port_id
	definition_id = p_definition_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "%s constructs %s at port %d" % [country_tag, definition_id, port_id]


func command_type() -> String:
	return "ConstructShipCommand"


func validate(world: CampaignWorldState) -> String:
	if not world.has_country(country_tag):
		return "Unknown country: %s" % country_tag
	if not world.has_province(port_id):
		return "Unknown province ID: %d" % port_id
	var graph := MaritimeGraphScript.load_default()
	if not graph.is_port_province(port_id):
		return "%d is not a naval port." % port_id
	if not graph.is_port_enabled(port_id):
		return "This port is disabled."
	if not NavalAccessPolicyScript.can_base(graph, world, country_tag, port_id):
		return NavalAccessPolicyScript.dock_failure_reason(graph, world, country_tag, port_id)
	var naval_definitions := NavalDefinitionsScript.load_default()
	var port_record := naval_definitions.port(port_id)
	var ship_definitions := ShipDefinitionsScript.load_default()
	if not ship_definitions.has_ship(definition_id):
		return "Unknown ship definition: %s" % definition_id
	var definition := ship_definitions.ship(definition_id)
	if int(port_record.get("harbour_level", 0)) < int(definition.get("required_harbour_level", 0)):
		return "This port's harbour is too small for %s." % definition_id
	if bool(definition.get("required_shipyard", false)) and not bool(port_record.get("shipyard", false)):
		return "%s requires a shipyard that this port does not have." % definition_id
	var current_date := SimulationDateScript.day_to_date(world.current_day)
	if not ship_definitions.unlocked_ship_ids(current_date).has(definition_id):
		return "%s is not unlocked yet." % definition_id
	var runtime := world.country_runtime(country_tag)
	if int(runtime.get("treasury", 0)) < int(definition.get("cost", 0)):
		return "Insufficient treasury."
	if int(runtime.get("sailors", 0)) < int(definition.get("sailor_cost", 0)):
		return "Insufficient sailors."
	var active := 0
	for raw_id in world.naval_construction_registry:
		var record: Dictionary = world.naval_construction_registry[raw_id]
		if int(record.get("port_id", -1)) == port_id:
			active += 1
	if active >= MAX_CONCURRENT_CONSTRUCTIONS_PER_PORT:
		return "This port's construction queue is full."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var ship_definitions := ShipDefinitionsScript.load_default()
	var definition := ship_definitions.ship(definition_id)
	var cost := int(definition.get("cost", 0))
	var sailor_cost := int(definition.get("sailor_cost", 0))
	var runtime := world.country_runtime(country_tag)
	runtime["treasury"] = int(runtime.get("treasury", 0)) - cost
	runtime["sailors"] = int(runtime.get("sailors", 0)) - sailor_cost
	world.set_country_runtime(country_tag, runtime)
	var construction_id := "naval_construction_%d" % world.take_counter("next_naval_construction_id")
	world.naval_construction_registry[construction_id] = CampaignWorldState.make_naval_construction_record(
		construction_id, country_tag, port_id, definition_id,
		world.current_day, world.current_day + int(definition.get("construction_days", 1)), cost
	)
	var record: Dictionary = world.naval_construction_registry[construction_id]
	record["reserved_sailors"] = sailor_cost
	world.naval_construction_registry[construction_id] = record
	EconomySystemScript.recalculate_country(world, country_tag)
	events.naval_construction_started.emit(construction_id, port_id, definition_id)
