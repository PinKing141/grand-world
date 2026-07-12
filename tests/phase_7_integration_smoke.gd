extends SceneTree

const ControllerScript = preload("res://scripts/simulation/simulation_controller.gd")
const CharacterHUDScript = preload("res://scripts/ui/character_hud.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const WarHUDScript = preload("res://scripts/ui/war_hud.gd")


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 7 integration smoke failed: %s" % message)
		quit(1)


func _select_character(hud, character_id: String) -> void:
	for index in range(hud.character_option.item_count):
		if String(hud.character_option.get_item_metadata(index)) == character_id:
			hud.character_option.select(index)
			hud._select_character(index)
			return


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var simulation := scene.get_node("SimulationController") as ControllerScript
	var hud := scene.get_node("CharacterHUD") as CharacterHUDScript
	var war_hud := scene.get_node("WarHUD") as WarHUDScript
	_require(simulation.initialized, "campaign must initialize")
	_require(simulation.character_definitions != null and simulation.character_definitions.is_valid(), "character definitions must be packaged and valid")
	_require(simulation.world.character_registry.size() == 12, "main scene must contain the Iberian character roster")
	_require(hud != null and hud.court_button != null, "court HUD must instantiate in the packaged scene")
	_require(hud.country_option.item_count == 5, "court HUD must expose the five character-enabled countries")

	simulation.choose_player_country("CAS")
	simulation.scheduler.process_commands()
	hud.panel.show()
	hud._refresh_all()
	_require(hud.ruler_label.text.contains("Juan II"), "realm header must name the current ruler")
	_require(hud.ruler_label.text.contains("Enrique"), "realm header must name the heir")
	_require(hud.succession_label.text.contains("absolute primogeniture"), "succession screen must explain the active law")
	_require(hud.identity_label.text.contains("Skills") == false and hud.skills_label.text.contains("Diplomacy"), "character sheet must expose skills separately from identity")
	_require(hud.family_label.text.contains("Family tree"), "character sheet must expose family relationships")
	_require(hud.titles_label.text.contains("Kingdom of Castile"), "character sheet must expose titles")
	_require(hud.opinion_label.text.contains("Opinion of"), "character UI must expose an opinion breakdown")

	_select_character(hud, "ch_cas_enrique")
	_require(not hud.marriage_button.disabled and hud.marriage_option.item_count > 0, "the player heir must have valid marriage candidates")
	var spouse_id := String(hud.marriage_option.get_item_metadata(hud.marriage_option.selected))
	hud._arrange_marriage()
	simulation.scheduler.process_commands()
	await process_frame
	_require(String(simulation.world.character_registry["ch_cas_enrique"].get("spouse_id", "")) == spouse_id, "marriage UI must reach authoritative state")
	_require(not hud.claim_button.disabled, "a player-controlled claimant must expose the claim-war action")

	# Other countries retain periodic character AI while the player's court is excluded.
	var history_before_ai := simulation.command_history().size()
	simulation.scheduler.advance_days(35)
	await process_frame
	var aragon_ai := simulation.character_ai_snapshot("ARA")
	_require(not aragon_ai.is_empty() and int(aragon_ai.get("last_review_day", -1)) > 0, "character AI must review non-player courts monthly")
	for record in simulation.command_history().slice(history_before_ai):
		if String(record.get("type", "")) in ["ArrangeMarriageCommand", "AssignCommanderCommand", "DeclareClaimWarCommand"]:
			_require(String(record.get("issuer", "")) != "CAS", "character AI must never issue commands for the player country")

	var checksum_before_save := simulation.world_checksum()
	var save_result := simulation.quick_save()
	_require(bool(save_result.get("ok", false)), "character campaign quick save must succeed")
	var mutated: Dictionary = simulation.world.character_registry["ch_cas_enrique"]
	mutated["name"] = "Corrupted test name"
	simulation.world.character_registry["ch_cas_enrique"] = mutated
	_require(simulation.world_checksum() != checksum_before_save, "character state must participate in campaign checksums")
	var load_result := simulation.quick_load()
	_require(bool(load_result.get("ok", false)) and simulation.world_checksum() == checksum_before_save, "quick load must exactly restore characters, families, titles, and AI")
	_select_character(hud, "ch_cas_enrique")
	hud._refresh_claim_button()
	_require(not hud.claim_button.disabled, "loaded claim state must remain actionable")
	hud._press_claim()
	simulation.scheduler.process_commands()
	await process_frame
	var claim_wars := simulation.country_wars("CAS")
	_require(claim_wars.size() == 1, "claim action must reach the warfare registry")
	war_hud._refresh_all()
	_require(war_hud.war_summary.text.contains("claim on"), "war overview must describe the claimed title")
	_require(war_hud.demand_goal_button.text == "Enforce claim", "peace UI must expose the claim-specific term")
	var claim_war_id := String(claim_wars[0])
	simulation.world.war_registry[claim_war_id]["total_war_score"] = 40
	war_hud._offer_war_goal()
	simulation.scheduler.process_commands()
	var offers: Dictionary = simulation.world.war_registry[claim_war_id].get("peace_offers", {})
	_require(offers.size() == 1 and String((((offers.values()[0] as Dictionary).get("terms", []) as Array)[0] as Dictionary).get("type", "")) == "press_claim", "war UI must create an enforce-claim peace term")

	CharacterSystemScript.kill_character(simulation.world, simulation.event_bus, "ch_cas_juan_ii", "integration test")
	await process_frame
	hud._refresh_all()
	_require(String(simulation.country_ruler("CAS").get("name", "")) == "Enrique", "death event must update the controller's ruler query")
	_require(hud.ruler_label.text.contains("Ruler: Enrique"), "succession notification must refresh the realm UI")

	var save_path := ProjectSettings.globalize_path(ControllerScript.QUICK_SAVE_PATH)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	print("Phase 7 integration smoke passed. characters=%d ruler=%s checksum=%s" % [simulation.world.character_registry.size(), CharacterSystemScript.ruler_id(simulation.world, "CAS"), simulation.world_checksum().left(16)])
	quit(0)
