class_name EconomyDefinitions
extends RefCounted

const DEFAULT_PATH := "res://assets/economy_definitions.json"

static var _cached

var version := 0
var money_scale := 1000
var basis_points := 10000
var trade_goods: Dictionary = {}
var buildings: Dictionary = {}
var units: Dictionary = {}
var provinces: Dictionary = {}


static func load_default():
	if _cached == null:
		_cached = load_from_path(DEFAULT_PATH)
	return _cached


static func load_from_path(path: String):
	var script := load("res://scripts/simulation/economy_definitions.gd") as Script
	var result = script.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Economy definitions are missing: %s" % path)
		return result
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Economy definitions are not valid JSON: %s" % path)
		return result
	var data: Dictionary = parsed
	result.version = int(data.get("version", 0))
	result.money_scale = int(data.get("money_scale", 1000))
	result.basis_points = int(data.get("basis_points", 10000))
	result.trade_goods = (data.get("trade_goods", {}) as Dictionary).duplicate(true)
	result.buildings = (data.get("buildings", {}) as Dictionary).duplicate(true)
	result.units = (data.get("units", {}) as Dictionary).duplicate(true)
	var raw_provinces: Dictionary = data.get("provinces", {})
	for raw_id in raw_provinces:
		result.provinces[int(raw_id)] = (raw_provinces[raw_id] as Dictionary).duplicate(true)
	return result


func province(province_id: int) -> Dictionary:
	return provinces.get(province_id, {})


func building(building_id: String) -> Dictionary:
	return buildings.get(building_id, {})


func unit(unit_id: String) -> Dictionary:
	return units.get(unit_id, {})


func trade_good(trade_good_id: String) -> Dictionary:
	return trade_goods.get(trade_good_id, trade_goods.get("unknown", {}))


func is_valid() -> bool:
	return version > 0 and not provinces.is_empty() and not buildings.is_empty() and not units.is_empty()
