class_name ProvincePathfinder
extends RefCounted

## Deterministic land pathfinding over the canonical province graph.
##
## Dijkstra with integer day costs and a binary heap whose entries pack
## (cost, province_id) into one integer, so equal-cost ties always resolve to
## the lowest province ID on every machine. No floats, no wall-clock time, no
## dictionary iteration order, no randomness.

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")

# Foreign territory currently allows passage: wars, access treaties, and
# hostility arrive with the diplomacy phase. The rule lives here so every
# future restriction changes exactly one function.
static func can_enter(graph: ProvinceGraph, _world: CampaignWorldState, _country: String, province_id: int) -> bool:
	return graph.is_land(province_id)


static func entry_failure_reason(graph: ProvinceGraph, _world: CampaignWorldState, _country: String, province_id: int) -> String:
	if not graph.has_province(province_id):
		return "Unknown destination province."
	if graph.classification(province_id) == "water":
		return "Naval transport required."
	if graph.is_impassable(province_id):
		return "Destination is impassable."
	return ""


static func find_route(
	graph: ProvinceGraph,
	world: CampaignWorldState,
	country: String,
	from_id: int,
	to_id: int
) -> Dictionary:
	var result := {
		"exists": false,
		"path": PackedInt32Array(),
		"total_cost_days": 0,
		"uses_strait": false,
		"permissions": [],
		"failure_reason": "",
	}
	if not graph.has_province(from_id) or not graph.is_land(from_id):
		result["failure_reason"] = "The army is not on valid land."
		return result
	var destination_failure := entry_failure_reason(graph, world, country, to_id)
	if not destination_failure.is_empty():
		result["failure_reason"] = destination_failure
		return result
	if from_id == to_id:
		result["exists"] = true
		result["path"] = PackedInt32Array([from_id])
		return result

	# Heap entries pack cost and province: (cost << 13) | id. IDs stay under
	# 8192, so ordering by the packed value orders by cost then lowest ID.
	var heap := PackedInt64Array()
	var best_cost := {}
	var came_from := {}
	best_cost[from_id] = 0
	_heap_push(heap, from_id)
	while heap.size() > 0:
		var packed := _heap_pop(heap)
		var cost := int(packed >> 13)
		var current := int(packed & 0x1FFF)
		if cost > int(best_cost.get(current, 0x7FFFFFFF)):
			continue
		if current == to_id:
			break
		for neighbor in graph.land_neighbors(current):
			if not can_enter(graph, world, country, neighbor):
				continue
			var step_cost := graph.entry_cost_days(neighbor)
			if graph.is_strait(current, neighbor):
				step_cost += graph.strait_cost_days()
			var new_cost := cost + step_cost
			var known := int(best_cost.get(neighbor, 0x7FFFFFFF))
			if new_cost < known or (new_cost == known and current < int(came_from.get(neighbor, 0x7FFFFFFF))):
				best_cost[neighbor] = new_cost
				came_from[neighbor] = current
				heap.append((new_cost << 13) | neighbor)
				_sift_up(heap, heap.size() - 1)

	if not best_cost.has(to_id):
		result["failure_reason"] = "No land route to the destination."
		return result

	var path := PackedInt32Array()
	var walk := to_id
	while walk != from_id:
		path.append(walk)
		walk = int(came_from[walk])
	path.append(from_id)
	path.reverse()
	var uses_strait := false
	for index in range(path.size() - 1):
		if graph.is_strait(path[index], path[index + 1]):
			uses_strait = true
			break
	result["exists"] = true
	result["path"] = path
	result["total_cost_days"] = int(best_cost[to_id])
	result["uses_strait"] = uses_strait
	return result


static func leg_cost_days(graph: ProvinceGraph, from_id: int, to_id: int) -> int:
	var cost := graph.entry_cost_days(to_id)
	if graph.is_strait(from_id, to_id):
		cost += graph.strait_cost_days()
	return cost


static func _heap_push(heap: PackedInt64Array, value: int) -> void:
	heap.append(value)
	_sift_up(heap, heap.size() - 1)


static func _heap_pop(heap: PackedInt64Array) -> int:
	var top := heap[0]
	var last := heap[heap.size() - 1]
	heap.remove_at(heap.size() - 1)
	if heap.size() > 0:
		heap[0] = last
		_sift_down(heap, 0)
	return top


static func _sift_up(heap: PackedInt64Array, index: int) -> void:
	while index > 0:
		var parent := (index - 1) >> 1
		if heap[index] >= heap[parent]:
			break
		var swap := heap[index]
		heap[index] = heap[parent]
		heap[parent] = swap
		index = parent


static func _sift_down(heap: PackedInt64Array, index: int) -> void:
	var size := heap.size()
	while true:
		var smallest := index
		var left := index * 2 + 1
		var right := index * 2 + 2
		if left < size and heap[left] < heap[smallest]:
			smallest = left
		if right < size and heap[right] < heap[smallest]:
			smallest = right
		if smallest == index:
			return
		var swap := heap[index]
		heap[index] = heap[smallest]
		heap[smallest] = swap
		index = smallest
