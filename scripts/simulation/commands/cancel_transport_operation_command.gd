class_name CancelTransportOperationCommand
extends "res://scripts/simulation/commands/simulation_command.gd"

var country_tag := ""
var operation_id := ""


func _init(p_country_tag: String, p_operation_id: String, p_scheduled_day := -1) -> void:
	country_tag = p_country_tag
	operation_id = p_operation_id
	issuer = p_country_tag
	scheduled_day = p_scheduled_day
	description = "Cancel transport operation %s" % operation_id


func command_type() -> String:
	return "CancelTransportOperationCommand"


## Cancellation is safe while embarking or once the carrier is docked and
## disembarking. Sailing cancellation still requires a retreat/reroute order;
## it cannot teleport an army from an at-sea fleet.
func validate(world: CampaignWorldState) -> String:
	var operation := world.get_transport_operation(operation_id)
	if operation.is_empty():
		return "The transport operation no longer exists."
	if String(operation.get("country_tag", "")) != country_tag:
		return "%s does not control this transport operation." % country_tag
	if String(operation.get("state", "")) not in [CampaignWorldState.TRANSPORT_STATE_EMBARKING, CampaignWorldState.TRANSPORT_STATE_DISEMBARKING]:
		return "This transport operation cannot be cancelled in its current state."
	return ""


func apply(world: CampaignWorldState, events: SimulationEventBus) -> void:
	var operation := world.get_transport_operation(operation_id)
	var army_id := String(operation.get("army_id", ""))
	var fleet_id := String(operation.get("fleet_id", ""))
	var army := world.get_army(army_id)
	if String(operation.get("state", "")) == CampaignWorldState.TRANSPORT_STATE_DISEMBARKING and world.fleet_registry.has(fleet_id):
		army["current_province_id"] = int(world.get_fleet(fleet_id).get("location_id", operation.get("destination_province_id", operation.get("origin_port_id", -1))))
	army["transport_operation_id"] = ""
	army["status"] = CampaignWorldState.ARMY_STATUS_IDLE
	army["movement_locked"] = false
	world.army_registry[army_id] = army
	var fleet := world.get_fleet(fleet_id)
	var operation_ids: Array = fleet.get("transport_operation_ids", [])
	operation_ids.erase(operation_id)
	fleet["transport_operation_ids"] = operation_ids
	world.fleet_registry[fleet_id] = fleet
	world.transport_operation_registry.erase(operation_id)
	events.transport_operation_cancelled.emit(operation_id, army_id, fleet_id)
