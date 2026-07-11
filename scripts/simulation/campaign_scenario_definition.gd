class_name CampaignScenarioDefinition
extends RefCounted

var _scenario_id := ""
var _province_initial_owners: Dictionary = {}
var _country_names: Dictionary = {}


func initialize_from_country_data(
	country_data: CountryData,
	scenario_id: String
) -> void:
	_scenario_id = scenario_id
	var country_tags := country_data.country_id_to_country_name.keys()
	country_tags.sort()
	for raw_tag in country_tags:
		_country_names[String(raw_tag)] = String(country_data.country_id_to_country_name[raw_tag])
	var province_ids := country_data.province_id_to_owner.keys()
	province_ids.sort()
	for raw_province_id in province_ids:
		var province_id := int(raw_province_id)
		var imported_owner := String(country_data.province_id_to_owner[raw_province_id])
		_province_initial_owners[province_id] = (
			imported_owner if _country_names.has(imported_owner) else ""
		)


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
