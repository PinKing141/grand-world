class_name CampaignSaveService
extends RefCounted

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")


static func save_world(world: CampaignWorldState, path: String, game_version: String) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return {"ok": false, "message": "Could not create the save directory: %s" % error_string(directory_error)}
	var temporary_path := "%s.tmp" % absolute_path
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Could not open the temporary save file."}
	file.store_string(JSON.stringify(world.to_save_dict(game_version), "\t", false))
	file.flush()
	file.close()
	if FileAccess.file_exists(absolute_path):
		var remove_error := DirAccess.remove_absolute(absolute_path)
		if remove_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return {"ok": false, "message": "Could not replace the existing save: %s" % error_string(remove_error)}
	var rename_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return {"ok": false, "message": "Could not finalize the save: %s" % error_string(rename_error)}
	return {"ok": true, "message": "Campaign saved.", "checksum": world.checksum()}


static func load_world(world: CampaignWorldState, path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "No save exists at %s." % path}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		return {
			"ok": false,
			"message": "The save is not valid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()],
		}
	if not json.data is Dictionary:
		return {"ok": false, "message": "The save root must be an object."}
	var rollback_data := world.to_save_dict("rollback")
	var apply_error := world.apply_save_dict(json.data)
	if not apply_error.is_empty():
		return {"ok": false, "message": apply_error}
	var expected_checksum := String((json.data as Dictionary).get("checksum", ""))
	if expected_checksum.is_empty() or expected_checksum != world.checksum():
		world.apply_save_dict(rollback_data)
		return {"ok": false, "message": "The save checksum does not match its campaign state."}
	return {"ok": true, "message": "Campaign loaded.", "checksum": world.checksum()}
