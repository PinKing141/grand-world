class_name CampaignScenarioDefinition
extends RefCounted

var _scenario_id := ""
var _province_initial_owners: Dictionary = {}
var _country_names: Dictionary = {}
var _error := ""


func initialize_from_country_registry(
		country_data: CountryData,
		country_registry,
		p_scenario_id: String
) -> void:
	_scenario_id = p_scenario_id
	_error = ""
	_province_initial_owners.clear()
	_country_names = country_registry.country_names()
	var province_ids := country_data.province_id_to_owner.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var imported_owner := String(country_data.province_id_to_owner[raw_province_id])
		if imported_owner.is_empty() or imported_owner in ["No Owner", "Ocean"]:
			_province_initial_owners[province_id] = ""
		elif _country_names.has(imported_owner):
			_province_initial_owners[province_id] = imported_owner
		else:
			_error = "Province %d references unknown imported owner %s." % [province_id, imported_owner]
			return


func is_valid() -> bool:
	return _error.is_empty()


func error() -> String:
	return _error


func scenario_id() -> String:
	return _scenario_id


func province_initial_owners() -> Dictionary:
	return _province_initial_owners.duplicate()


func country_names() -> Dictionary:
	return _country_names.duplicate()


func has_province(province_id: int) -> bool:
	return _province_initial_owners.has(province_id)


func has_country(country_tag: String) -> bool:
	return _country_names.has(country_tag)
